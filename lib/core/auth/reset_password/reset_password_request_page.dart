import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/core/auth/login/provider/auth_provider.dart';
import 'package:thingsboard_democloud_app/core/auth/login/widgets/full_screen_loader.dart';
import 'package:thingsboard_democloud_app/core/auth/login/widgets/text_field.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/utils/ui/visibility_widget.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';
import 'package:toastification/toastification.dart';

class ResetPasswordRequestPage extends HookConsumerWidget {
  const ResetPasswordRequestPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final form = useMemoized(
      () => FormGroup({
        'email': FormControl<String>(
          validators: [Validators.required, Validators.email],
        ),
      }),
    );
    final isLoading = useState(false);
    final sent = useState(false);
    final errorText = useState<String?>(null);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: TbAppBar(title: const Text('Reset password')),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: DesignTokens.paddingLarge,
              child: ReactiveForm(
                formGroup: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: DesignTokens.spacing16,
                  children: [
                    Text(
                      'Send a password reset link to your account email',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (errorText.value != null)
                      Container(
                        padding: DesignTokens.paddingSmall,
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: DesignTokens.borderRadiusMedium,
                        ),
                        child: Text(
                          errorText.value!,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onErrorContainer,
                          ),
                        ),
                      ),
                    if (sent.value)
                      Container(
                        key: const Key('reset-password-sent-banner'),
                        padding: DesignTokens.paddingMedium,
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: DesignTokens.borderRadiusLarge,
                        ),
                        child: Row(
                          children: [
                            TbIcon(
                              TbIconKind.statusCleared,
                              size: DesignTokens.iconMedium,
                              color: scheme.onSecondaryContainer,
                            ),
                            const SizedBox(width: DesignTokens.spacing12),
                            Expanded(
                              child: Text(
                                'Reset link sent',
                                style: textTheme.titleSmall?.copyWith(
                                  color: scheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const TbTextField(
                      formControlName: 'email',
                      hint: 'Email',
                      label: 'Email',
                      type: TextInputType.emailAddress,
                    ),
                    ReactiveFormConsumer(
                      builder: (context, form, _) {
                        return FilledButton(
                          key: const Key('request-reset-submit-button'),
                          onPressed:
                              (form.invalid && form.touched) || isLoading.value
                              ? null
                              : () => _requestPasswordReset(
                                  context,
                                  form,
                                  ref,
                                  isLoading,
                                  sent,
                                  errorText,
                                ),
                          child: const Text('Request password reset'),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedVisibilityWidget(
            show: isLoading.value,
            child: const FullScreenLoader(),
          ),
        ],
      ),
    );
  }

  Future<void> _requestPasswordReset(
    BuildContext context,
    FormGroup form,
    WidgetRef ref,
    ValueNotifier<bool> isLoading,
    ValueNotifier<bool> sent,
    ValueNotifier<String?> errorText,
  ) async {
    FocusScope.of(context).unfocus();
    form.markAllAsTouched();
    if (form.invalid) {
      return;
    }
    isLoading.value = true;
    errorText.value = null;
    final formValue = form.control('email').value.toString();
    try {
      await ref
          .read(authSessionProvider.notifier)
          .requestPasswordReset(formValue);
      sent.value = true;
      if (context.mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.success,
          style: ToastificationStyle.fillColored,
          title: const Text('Password reset link was successfully sent!'),
          autoCloseDuration: const Duration(seconds: 3),
        );
      }
    } catch (e) {
      errorText.value = e is TbFailure ? e.message : e.toString();
    } finally {
      if (context.mounted) {
        isLoading.value = false;
      }
    }
  }
}
