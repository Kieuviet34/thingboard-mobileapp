import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/constants/assets_path.dart';
import 'package:thingsboard_democloud_app/core/auth/login/provider/auth_provider.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';

/// Two-factor OTP verification screen for [AuthMfaVerificationRequired]
/// (`PRE_VERIFICATION_TOKEN`).
class TwoFactorAuthPage extends ConsumerStatefulWidget {
  const TwoFactorAuthPage({super.key});

  @override
  ConsumerState<TwoFactorAuthPage> createState() => _TwoFactorAuthPageState();
}

class _TwoFactorAuthPageState extends ConsumerState<TwoFactorAuthPage> {
  final TextEditingController _codeController = TextEditingController();
  String? _selectedProvider;
  bool _submitting = false;
  String? _errorMessage;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  List<TwoFaProviderInfo> _resolveProviders(AuthState? state) {
    if (state is AuthMfaVerificationRequired && state.providers.isNotEmpty) {
      return state.providers;
    }
    return const [TwoFaProviderInfo(type: 'TOTP', isDefault: true)];
  }

  String _activeProvider(List<TwoFaProviderInfo> providers) {
    if (_selectedProvider != null &&
        providers.any((p) => p.type == _selectedProvider)) {
      return _selectedProvider!;
    }
    final defaultProvider = providers.where((p) => p.isDefault).firstOrNull;
    return (defaultProvider ?? providers.first).type;
  }

  Future<void> _submitOtp(String providerType) async {
    final code = _codeController.text.trim();
    if (code.length < 6) {
      setState(() {
        _errorMessage = 'Enter the 6-digit verification code';
      });
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(authSessionProvider.notifier)
          .verifyTwoFa(providerType: providerType, verificationCode: code);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e is TbFailure ? e.message : e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _resendCode(String providerType) async {
    if (_resendCooldown > 0) return;
    setState(() {
      _errorMessage = null;
      _resendCooldown = 30;
    });
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_resendCooldown > 1) {
          _resendCooldown--;
        } else {
          _resendCooldown = 0;
          timer.cancel();
        }
      });
    });

    try {
      await ref.read(authSessionProvider.notifier).sendTwoFaCode(providerType);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e is TbFailure ? e.message : e.toString();
      });
    }
  }

  void _cancelAndReturnToLogin() {
    ref.read(authSessionProvider.notifier).cancelMfa();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authSessionProvider).valueOrNull;
    final providers = _resolveProviders(authState);
    final activeProvider = _activeProvider(providers);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _cancelAndReturnToLogin();
        }
      },
      child: Scaffold(
        appBar: TbAppBar(
          title: const Text('Two-Factor Verification'),
          showLoadingIndicator: _submitting,
          leading: IconButton(
            tooltip: 'Back to login',
            constraints: const BoxConstraints(
              minWidth: DesignTokens.minTouchTarget,
              minHeight: DesignTokens.minTouchTarget,
            ),
            icon: const Icon(Icons.arrow_back),
            onPressed: _cancelAndReturnToLogin,
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                padding: DesignTokens.paddingLarge,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: DesignTokens.spacing16,
                  children: [
                    ExcludeSemantics(
                      child: SizedBox(
                        height: 88,
                        child: SvgPicture.asset(ThingsboardImage.twoFaSetup),
                      ),
                    ),
                    Text(
                      'Enter verification code',
                      textAlign: TextAlign.center,
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (providers.length > 1)
                      Wrap(
                        spacing: DesignTokens.spacing8,
                        runSpacing: DesignTokens.spacing8,
                        alignment: WrapAlignment.center,
                        children: [
                          for (final provider in providers)
                            ChoiceChip(
                              key: Key('two-fa-provider-${provider.type}'),
                              label: Text(provider.type),
                              selected: provider.type == activeProvider,
                              onSelected: (_) {
                                setState(() {
                                  _selectedProvider = provider.type;
                                  _errorMessage = null;
                                });
                              },
                            ),
                        ],
                      ),
                    if (_errorMessage != null)
                      Container(
                        key: const Key('two-fa-error-banner'),
                        padding: DesignTokens.paddingSmall,
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: DesignTokens.borderRadiusMedium,
                        ),
                        child: Row(
                          children: [
                            TbIcon(
                              TbIconKind.severityCritical,
                              size: DesignTokens.iconSmall,
                              color: scheme.onErrorContainer,
                            ),
                            const SizedBox(width: DesignTokens.spacing8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: textTheme.bodySmall?.copyWith(
                                  color: scheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    TextField(
                      key: const Key('two-fa-code-input'),
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      onSubmitted: (_) => _submitOtp(activeProvider),
                      decoration: InputDecoration(
                        labelText: '$activeProvider code',
                        hintText: '000000',
                      ),
                    ),
                    FilledButton(
                      key: const Key('two-fa-verify-button'),
                      onPressed: _submitting
                          ? null
                          : () => _submitOtp(activeProvider),
                      child: const Text('Verify'),
                    ),
                    if (activeProvider != 'TOTP' &&
                        activeProvider != 'BACKUP_CODE')
                      TextButton(
                        key: const Key('two-fa-resend-button'),
                        onPressed: _resendCooldown > 0
                            ? null
                            : () => _resendCode(activeProvider),
                        child: Text(
                          _resendCooldown > 0
                              ? 'Resend code (${_resendCooldown}s)'
                              : 'Resend code',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
