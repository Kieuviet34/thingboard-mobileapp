import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';
import 'package:thingsboard_democloud_app/constants/app_constants.dart';
import 'package:thingsboard_democloud_app/core/auth/login/provider/auth_provider.dart';
import 'package:thingsboard_democloud_app/core/auth/login/widgets/footer/login_footer.dart';
import 'package:thingsboard_democloud_app/core/auth/login/widgets/full_screen_loader.dart';
import 'package:thingsboard_democloud_app/core/auth/login/widgets/header/login_header.dart';
import 'package:thingsboard_democloud_app/core/auth/login/widgets/o_auth_buttons.dart';
import 'package:thingsboard_democloud_app/core/auth/login/widgets/text_divider.dart';
import 'package:thingsboard_democloud_app/core/auth/login/widgets/text_field.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/utils/ui/visibility_widget.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:toastification/toastification.dart';
import 'package:url_launcher/url_launcher.dart';

class LoginWidget extends HookConsumerWidget {
  const LoginWidget({super.key, this.redirectUrl});

  final String? redirectUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final submitting = useState(false);
    final serverConfig = ref.watch(serverConfigProvider);
    final authAsync = ref.watch(authSessionProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final form = useMemoized(
      () => FormGroup({
        'email': FormControl<String>(
          validators: [Validators.required, Validators.email],
        ),
        'password': FormControl<String>(validators: [Validators.required]),
      }),
    );

    final oauthClients = <OAuth2ClientInfo>[
      for (final c in serverConfig.oauthClients) OAuth2ClientInfo.fromModel(c),
      const OAuth2ClientInfo(name: 'qr', icon: 'qr-code-logo'),
    ];

    final hostLabel =
        Uri.tryParse(serverConfig.baseUrl)?.host.isNotEmpty == true
        ? Uri.parse(serverConfig.baseUrl).host
        : serverConfig.baseUrl;

    String? errorMessage;
    if (authAsync.hasError) {
      final err = authAsync.error;
      errorMessage = err is TbFailure ? err.message : err.toString();
    }

    return Stack(
      children: [
        ReactiveForm(
          formGroup: form,
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    vertical: DesignTokens.spacing16,
                    horizontal: DesignTokens.spacing20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: DesignTokens.spacing16,
                    children: [
                      LoginHeader(
                        trailing: Semantics(
                          button: true,
                          label: 'Server $hostLabel',
                          child: ActionChip(
                            key: const Key('server-url-pill'),
                            avatar: TbIcon(
                              TbIconKind.gateway,
                              size: DesignTokens.iconXs,
                              color: scheme.primary,
                            ),
                            label: Text(
                              hostLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onPressed: () => _showServerUrlSheet(
                              context,
                              ref,
                              serverConfig.baseUrl,
                            ),
                          ),
                        ),
                      ),
                      Text(
                        'Login to your account',
                        textAlign: TextAlign.center,
                        style: textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      if (errorMessage != null && errorMessage.isNotEmpty)
                        Container(
                          key: const Key('login-error-banner'),
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
                                  errorMessage,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: scheme.onErrorContainer,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: DesignTokens.spacing12,
                          children: [
                            Text(
                              'LOGIN WITH',
                              textAlign: TextAlign.center,
                              style: textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                letterSpacing: 0.6,
                              ),
                            ),
                            OAuthButtons(
                              onButtonPressed: (client) =>
                                  onOauth2ButtonPressed(
                                    client,
                                    context,
                                    submitting,
                                    ref,
                                  ),
                              clients: oauthClients,
                            ),
                            const TextDivider(text: 'OR'),
                            const TbTextField(
                              formControlName: 'email',
                              label: 'Email',
                              hint: 'Email',
                              type: TextInputType.emailAddress,
                              autoFillHints: [AutofillHints.email],
                            ),
                            const TbTextField(
                              formControlName: 'password',
                              label: 'Password',
                              hint: 'Password',
                              obscureText: true,
                              autoFillHints: [AutofillHints.password],
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => onForgotPassword(context),
                                child: const Text('Forgot Password?'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ReactiveFormConsumer(
                        builder: (context, formGroup, child) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: DesignTokens.spacing12,
                            children: [
                              FilledButton(
                                key: const Key('login-submit-button'),
                                onPressed:
                                    (formGroup.invalid && formGroup.touched) ||
                                        submitting.value
                                    ? null
                                    : () async {
                                        await onLoginPressed(
                                          context,
                                          form,
                                          ref,
                                          submitting,
                                        );
                                      },
                                child: const Text('Log In'),
                              ),
                              FilledButton.tonalIcon(
                                key: const Key('try-demo-mode-button'),
                                onPressed: submitting.value
                                    ? null
                                    : () async {
                                        submitting.value = true;
                                        try {
                                          await ref
                                              .read(
                                                authSessionProvider.notifier,
                                              )
                                              .loginDemo();
                                        } finally {
                                          if (context.mounted) {
                                            submitting.value = false;
                                          }
                                        }
                                      },
                                icon: TbIcon(
                                  TbIconKind.demoFlask,
                                  size: DesignTokens.iconSmall,
                                  color: scheme.onSecondaryContainer,
                                ),
                                label: const Text('Try Demo Mode'),
                              ),
                              const LoginFooter(),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        AnimatedVisibilityWidget(
          show: submitting.value,
          child: const FullScreenLoader(),
        ),
      ],
    );
  }

  Future<void> _showServerUrlSheet(
    BuildContext context,
    WidgetRef ref,
    String currentUrl,
  ) async {
    final controller = TextEditingController(text: currentUrl);
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final bottomInset = MediaQuery.viewInsetsOf(sheetCtx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            DesignTokens.spacing20,
            DesignTokens.spacing20,
            DesignTokens.spacing20,
            bottomInset + DesignTokens.spacing20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignTokens.spacing12,
            children: [
              Text(
                'ThingsBoard Server',
                style: Theme.of(
                  sheetCtx,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              TextField(
                key: const Key('server-url-input'),
                controller: controller,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://thingsboard.democloud.xyz/',
                  suffixIcon: IconButton(
                    tooltip: 'Paste from clipboard',
                    icon: const Icon(Icons.content_paste_rounded),
                    onPressed: () async {
                      final clip = await Clipboard.getData(
                        Clipboard.kTextPlain,
                      );
                      final text = clip?.text?.trim() ?? '';
                      if (text.isNotEmpty) {
                        controller.text = text;
                      }
                    },
                  ),
                ),
              ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: DesignTokens.spacing8,
                runSpacing: DesignTokens.spacing8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.paste_rounded, size: 16),
                    label: const Text('Paste link'),
                    onPressed: () async {
                      final clip = await Clipboard.getData(
                        Clipboard.kTextPlain,
                      );
                      final text = clip?.text?.trim() ?? '';
                      if (text.isNotEmpty) {
                        controller.text = text;
                      }
                    },
                  ),
                  TextButton(
                    onPressed: () {
                      controller.text =
                          ThingsboardAppConstants.defaultApiEndpoint;
                    },
                    child: const Text('Reset default'),
                  ),
                  FilledButton(
                    key: const Key('save-server-url-button'),
                    onPressed: () async {
                      final nextUrl = controller.text.trim();
                      Navigator.of(sheetCtx).pop();
                      await ref
                          .read(serverConfigProvider.notifier)
                          .switchServerUrl(nextUrl);
                    },
                    child: const Text('Save server'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
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
  loading.value = true;
  try {
    await ref.read(authSessionProvider.notifier).login(username, password);
  } finally {
    if (context.mounted) {
      loading.value = false;
    }
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
  final baseUrl = ref.read(serverConfigProvider).baseUrl;
  final rawUrl = client.url ?? '';
  if (rawUrl.isNotEmpty) {
    final resolved = rawUrl.startsWith('http')
        ? Uri.tryParse(rawUrl)
        : Uri.tryParse(baseUrl)?.resolve(rawUrl);
    if (resolved != null) {
      final launched = await launchUrl(
        resolved,
        mode: LaunchMode.externalApplication,
      );
      if (launched) return;
    }
  }
  if (context.mounted) {
    toastification.show(
      context: context,
      type: ToastificationType.info,
      style: ToastificationStyle.fillColored,
      title: Text('OAuth2 (${client.name}) unavailable'),
      autoCloseDuration: const Duration(seconds: 2),
    );
  }
}

Future<void> onForgotPassword(BuildContext context) async {
  await context.push('/login/resetPasswordRequest');
}
