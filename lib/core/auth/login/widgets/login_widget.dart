import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_text_styles.dart';
import 'package:thingsboard_democloud_app/core/auth/login/provider/auth_provider.dart';
import 'package:thingsboard_democloud_app/core/auth/login/widgets/footer/login_footer.dart';
import 'package:thingsboard_democloud_app/core/auth/login/widgets/full_screen_loader.dart';
import 'package:thingsboard_democloud_app/core/auth/login/widgets/header/login_header.dart';
import 'package:thingsboard_democloud_app/core/auth/login/widgets/o_auth_buttons.dart';
import 'package:thingsboard_democloud_app/core/auth/login/widgets/text_divider.dart';
import 'package:thingsboard_democloud_app/core/auth/login/widgets/text_field.dart';
import 'package:thingsboard_democloud_app/utils/ui/visibility_widget.dart';
import 'package:toastification/toastification.dart';

class LoginWidget extends HookConsumerWidget {
  const LoginWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loading = useState(false);
    final oauthClients = ref.watch(authProvider.select((s) => s.oauthClients));
    final form = useMemoized(
      () => FormGroup({
        'email': FormControl<String>(
          validators: [Validators.required, Validators.email],
        ),
        'password': FormControl<String>(validators: [Validators.required]),
      }),
    );

    final mediaQuery = MediaQuery.of(context);
    return Stack(
      children: [
        ReactiveForm(
          formGroup: form,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: SingleChildScrollView(
                child: SizedBox(
                  height:
                      mediaQuery.size.height -
                      mediaQuery.padding.top -
                      mediaQuery.padding.bottom -
                      kToolbarHeight,
                  child: Column(
                    spacing: 16,
                    children: [
                      const LoginHeader(),
                      Text(
                        'Login to your account',
                        style: TbTextStyles.titleMedium,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 32),
                        child: AutofillGroup(
                          child: Column(
                            spacing: 12,
                            children: [
                              Text(
                                'LOGIN WITH',
                                style: TbTextStyles.labelMedium.copyWith(
                                  fontWeight: FontWeight.w400,
                                  fontFamily: 'Roboto',
                                  letterSpacing: 0.4,
                                ),
                              ),
                              OAuthButtons(
                                onButtonPressed:
                                    (client) => onOauth2ButtonPressed(
                                      client,
                                      context,
                                      loading,
                                      ref,
                                    ),
                                clients: oauthClients,
                              ),
                              const TextDivider(text: 'OR'),
                              const Column(
                                spacing: 24,
                                children: [
                                  TbTextField(
                                    formControlName: 'email',
                                    label: 'Email',
                                    hint: 'Email',
                                    type: TextInputType.emailAddress,
                                    autoFillHints: [AutofillHints.email],
                                  ),
                                  TbTextField(
                                    formControlName: 'password',
                                    label: 'Password',
                                    hint: 'Password',
                                    obscureText: true,
                                    autoFillHints: [AutofillHints.password],
                                  ),
                                ],
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => onForgotPassword(context),
                                  child: Text(
                                    'Forgot Password?',
                                    style: TbTextStyles.labelSmall,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: ReactiveFormConsumer(
                          builder: (context, formGroup, child) {
                            return Column(
                              mainAxisSize: MainAxisSize.min,
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
                                        formGroup.invalid && formGroup.touched
                                            ? null
                                            : () async {
                                              await onLoginPressed(
                                                context,
                                                form,
                                                ref,
                                                loading,
                                              );
                                            },
                                    child: Text(
                                      'Log In',
                                      style: TbTextStyles.labelMedium,
                                    ),
                                  ),
                                ),
                                const LoginFooter(),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        AnimatedVisibilityWidget(
          show: loading.value,
          child: const FullScreenLoader(),
        ),
      ],
    );
  }
}

Future<void> onLoginPressed(
  BuildContext context,
  FormGroup form,
  WidgetRef ref,
  ValueNotifier<bool> loading,
) async {
  FocusScope.of(context).unfocus();
  form.markAllAsTouched();
  if (form.invalid) {
    return;
  }
  final String username = form.control('email').value.toString();
  final String password = form.control('password').value.toString();
  try {
    loading.value = true;
    await ref.read(authProvider.notifier).login(username, password);
    if (context.mounted) {
      context.go('/home');
    }
  } catch (e) {
    form.setErrors({'err': {}});
  } finally {
    loading.value = false;
  }
}

Future<void> onOauth2ButtonPressed(
  OAuth2ClientInfo client,
  BuildContext context,
  ValueNotifier<bool> loading,
  WidgetRef ref,
) async {
  FocusScope.of(context).unfocus();
  if (client.name == 'qr') {
    await context.push('/qrCodeScan');
    return;
  }
  toastification.show(
    context: context,
    type: ToastificationType.info,
    style: ToastificationStyle.fillColored,
    title: Text('OAuth2 (${client.name}) will connect in backend phase'),
    autoCloseDuration: const Duration(seconds: 2),
  );
}

Future<void> onForgotPassword(BuildContext context) async {
  await context.push('/login/resetPasswordRequest');
}
