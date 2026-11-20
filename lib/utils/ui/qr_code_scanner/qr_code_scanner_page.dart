import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/core/api/controllers/device_controller.dart';
import 'package:thingsboard_democloud_app/core/auth/login/provider/auth_provider.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';

/// Live QR code scanner for ThingsBoard PE QR login (`GET /api/noauth/qr/{secret}`)
/// and device claiming (`POST /api/customer/device/{name}/claim`), with
/// GPU-safe laser scan animation and Demo/test simulation actions.
class QrCodeScannerPage extends ConsumerStatefulWidget {
  const QrCodeScannerPage({
    super.key,
    this.enableCamera = true,
    this.onCodeScanned,
  });

  final bool enableCamera;
  final Future<void> Function(String rawCode)? onCodeScanned;

  @override
  ConsumerState<QrCodeScannerPage> createState() => _QrCodeScannerPageState();
}

class _QrCodeScannerPageState extends ConsumerState<QrCodeScannerPage>
    with SingleTickerProviderStateMixin {
  MobileScannerController? _scannerController;
  late final AnimationController _laserController;
  late final Animation<Offset> _laserSlide;
  bool _processing = false;
  bool _torchOn = false;
  String? _statusMessage;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    if (widget.enableCamera) {
      _scannerController = MobileScannerController();
    }
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _laserSlide =
        Tween<Offset>(
          begin: const Offset(0, -0.42),
          end: const Offset(0, 0.42),
        ).animate(
          CurvedAnimation(parent: _laserController, curve: Curves.easeInOut),
        );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _laserController.stop();
    } else if (!_laserController.isAnimating) {
      _laserController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _laserController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  Future<void> handleScannedPayload(String rawCode) async {
    final trimmed = rawCode.trim();
    if (_processing || trimmed.isEmpty) return;

    setState(() {
      _processing = true;
      _statusMessage = null;
      _isError = false;
    });

    try {
      if (widget.onCodeScanned != null) {
        await widget.onCodeScanned!(trimmed);
        return;
      }

      final claimTarget = _tryParseClaimPayload(trimmed);
      if (claimTarget != null) {
        final result = await ref
            .read(deviceRepositoryProvider)
            .claimDevice(claimTarget.$1, secretKey: claimTarget.$2);
        if (!mounted) return;
        setState(() {
          _statusMessage = 'Device claimed (${result.response})';
          _isError = false;
        });
        return;
      }

      await ref.read(authSessionProvider.notifier).loginWithQrSecret(trimmed);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = e is TbFailure ? e.message : e.toString();
        _isError = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
        });
      }
    }
  }

  (String, String?)? _tryParseClaimPayload(String raw) {
    if (raw.startsWith('claim:')) {
      final parts = raw.substring('claim:'.length).split(':');
      final name = parts.first.trim();
      final secret = parts.length > 1 ? parts[1].trim() : null;
      if (name.isNotEmpty) return (name, secret);
    }
    if (raw.startsWith('{') && raw.endsWith('}')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final name = decoded['deviceName'] as String?;
          final secret = decoded['secretKey'] as String?;
          if (name != null && name.isNotEmpty) {
            return (name, secret);
          }
        }
      } catch (_) {
        // Not a JSON claim payload; treat as QR login secret.
      }
    }
    return null;
  }

  Future<void> _toggleTorch() async {
    final controller = _scannerController;
    if (controller == null) return;
    try {
      await controller.toggleTorch();
      if (mounted) {
        setState(() {
          _torchOn = !_torchOn;
        });
      }
    } catch (_) {
      // Torch unavailable on simulator/device.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close scanner',
          constraints: const BoxConstraints(
            minWidth: DesignTokens.minTouchTarget,
            minHeight: DesignTokens.minTouchTarget,
          ),
          icon: const Icon(Icons.close),
          onPressed: () {
            final router = GoRouter.maybeOf(context);
            if (router != null && router.canPop()) {
              router.pop();
            } else if (router != null) {
              router.go('/login');
            }
          },
        ),
        title: const Text('Scan QR code'),
        actions: [
          IconButton(
            tooltip: _torchOn ? 'Turn off torch' : 'Turn on torch',
            constraints: const BoxConstraints(
              minWidth: DesignTokens.minTouchTarget,
              minHeight: DesignTokens.minTouchTarget,
            ),
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
            onPressed: _toggleTorch,
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            if (widget.enableCamera && _scannerController != null)
              Positioned.fill(
                child: MobileScanner(
                  controller: _scannerController,
                  onDetect: (capture) {
                    for (final barcode in capture.barcodes) {
                      final raw = barcode.rawValue;
                      if (raw != null && raw.isNotEmpty) {
                        handleScannedPayload(raw);
                        break;
                      }
                    }
                  },
                  errorBuilder: (context, error) {
                    return ColoredBox(color: scheme.surfaceContainerLowest);
                  },
                ),
              ),
            Center(
              child: SingleChildScrollView(
                padding: DesignTokens.paddingLarge,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 220,
                      height: 220,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerLow.withValues(
                                alpha: 0.72,
                              ),
                              border: Border.all(
                                color: scheme.primary,
                                width: 2.5,
                              ),
                              borderRadius: DesignTokens.borderRadiusXl,
                            ),
                            child: Center(
                              child: TbIcon(
                                TbIconKind.qrFrame,
                                size: 64,
                                color: scheme.primary,
                                semanticLabel: 'QR frame',
                              ),
                            ),
                          ),
                          if (!disableAnimations)
                            SlideTransition(
                              position: _laserSlide,
                              child: Container(
                                width: 184,
                                height: 2.5,
                                decoration: BoxDecoration(
                                  color: scheme.tertiary,
                                  borderRadius: DesignTokens.borderRadiusRound,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: DesignTokens.spacing16),
                    Text(
                      'Align QR code to sign in or claim device',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (_statusMessage != null) ...[
                      const SizedBox(height: DesignTokens.spacing12),
                      Container(
                        key: const Key('qr-status-banner'),
                        padding: DesignTokens.paddingSmall,
                        decoration: BoxDecoration(
                          color: _isError
                              ? scheme.errorContainer
                              : scheme.secondaryContainer,
                          borderRadius: DesignTokens.borderRadiusMedium,
                        ),
                        child: Text(
                          _statusMessage!,
                          textAlign: TextAlign.center,
                          style: textTheme.bodySmall?.copyWith(
                            color: _isError
                                ? scheme.onErrorContainer
                                : scheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: DesignTokens.spacing20),
                    Wrap(
                      spacing: DesignTokens.spacing8,
                      runSpacing: DesignTokens.spacing8,
                      alignment: WrapAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          key: const Key('qr-paste-code-button'),
                          onPressed: _processing
                              ? null
                              : () async {
                                  final clip = await Clipboard.getData(
                                    Clipboard.kTextPlain,
                                  );
                                  final text = clip?.text?.trim() ?? '';
                                  if (text.isNotEmpty) {
                                    handleScannedPayload(text);
                                  } else {
                                    setState(() {
                                      _statusMessage = 'Clipboard is empty';
                                      _isError = true;
                                    });
                                  }
                                },
                          icon: const Icon(Icons.paste_rounded, size: 16),
                          label: const Text('Paste link / code'),
                        ),
                        FilledButton.tonalIcon(
                          key: const Key('qr-simulate-login-button'),
                          onPressed: _processing
                              ? null
                              : () => handleScannedPayload(
                                  'demo-qr-login-secret',
                                ),
                          icon: TbIcon(
                            TbIconKind.qrFrame,
                            size: DesignTokens.iconSmall,
                            color: scheme.onSecondaryContainer,
                          ),
                          label: const Text('Simulate QR login'),
                        ),
                        OutlinedButton.icon(
                          key: const Key('qr-simulate-claim-button'),
                          onPressed: _processing
                              ? null
                              : () => handleScannedPayload(
                                  'claim:SN-001:secret-key',
                                ),
                          icon: TbIcon(
                            TbIconKind.sensorNode,
                            size: DesignTokens.iconSmall,
                            color: scheme.primary,
                          ),
                          label: const Text('Claim demo device'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
