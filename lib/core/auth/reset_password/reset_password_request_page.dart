import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:thingsboard_democloud_app/config/themes/app_colors.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_text_styles.dart';
import 'package:thingsboard_democloud_app/core/auth/login/provider/auth_provider.dart';
import 'package:thingsboard_democloud_app/core/auth/login/widgets/full_screen_loader.dart';
import 'package:thingsboard_democloud_app/core/auth/login/widgets/text_field.dart';
import 'package:thingsboard_democloud_app/utils/ui/visibility_widget.dart';
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

    return Scaffold(
      appBar: TbAppBar(title: const Text('Reset password')),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: ReactiveForm(
              formGroup: form,
              child: Column(
                spacing: 20,
                children: [
                  Text(
                    "Enter the email associated with your account and we'll send an email with password reset link",
                    textAlign: TextAlign.center,
                    style: TbTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
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
                      return Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                onPressed:
                                    form.invalid && form.touched
                                        ? null
                                        : () {
                                          _requestPasswordReset(
                                            context,
                                            form,
                                            ref,
                                            isLoading,
                                          );
                                        },
                                child: const Text('Request password reset'),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
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
  ) async {
    FocusScope.of(context).unfocus();
    form.markAllAsTouched();
    if (form.invalid) {
      return;
    }
    isLoading.value = true;
    final formValue = form.control('email').value.toString();
    try {
      await ref.read(authProvider.notifier).requestPasswordReset(formValue);
      if (context.mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.success,
          style: ToastificationStyle.fillColored,
          title: const Text('Password reset link was successfully sent!'),
          autoCloseDuration: const Duration(seconds: 3),
        );
      }
    } finally {
      isLoading.value = false;
    }
  }
}
