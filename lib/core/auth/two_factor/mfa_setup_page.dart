import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/constants/assets_path.dart';
import 'package:thingsboard_democloud_app/core/auth/login/provider/auth_provider.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';

/// Mandatory MFA configuration screen for `MFA_CONFIGURATION_TOKEN`.
class MfaSetupPage extends ConsumerStatefulWidget {
  const MfaSetupPage({super.key});

  @override
  ConsumerState<MfaSetupPage> createState() => _MfaSetupPageState();
}

class _MfaSetupPageState extends ConsumerState<MfaSetupPage> {
  bool _submitting = false;
  String? _errorMessage;

  Future<void> _completeSetup() async {
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authSessionProvider.notifier).completeMfaConfiguration();
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

  void _cancelSetup() {
    ref.read(authSessionProvider.notifier).cancelMfa();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _cancelSetup();
        }
      },
      child: Scaffold(
        appBar: TbAppBar(
          title: const Text('2FA Setup'),
          showLoadingIndicator: _submitting,
          leading: IconButton(
            tooltip: 'Back to login',
            constraints: const BoxConstraints(
              minWidth: DesignTokens.minTouchTarget,
              minHeight: DesignTokens.minTouchTarget,
            ),
            icon: const Icon(Icons.arrow_back),
            onPressed: _cancelSetup,
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
                        child: SvgPicture.asset(
                          ThingsboardImage.twoFaConfigured,
                        ),
                      ),
                    ),
                    Text(
                      '2FA setup required',
                      textAlign: TextAlign.center,
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Configure two-factor authentication for your account',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (_errorMessage != null)
                      Container(
                        key: const Key('mfa-setup-error-banner'),
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
                    FilledButton(
                      key: const Key('mfa-setup-continue-button'),
                      onPressed: _submitting ? null : _completeSetup,
                      child: const Text('Continue'),
                    ),
                    OutlinedButton(
                      key: const Key('mfa-setup-cancel-button'),
                      onPressed: _submitting ? null : _cancelSetup,
                      child: const Text('Back to login'),
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
