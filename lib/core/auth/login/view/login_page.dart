import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/auth/login/provider/auth_provider.dart';
import 'package:thingsboard_democloud_app/core/auth/login/widgets/login_widget.dart';

class LoginPage extends HookConsumerWidget {
  const LoginPage({super.key, this.redirectUrl});

  final String? redirectUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final darkForeground = authState.darkForeground;

    return Theme(
      data: authState.loginTheme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value:
            darkForeground
                ? SystemUiOverlayStyle.dark
                : SystemUiOverlayStyle.light,
        child: const Scaffold(
          body: Stack(
            children: [
              LoginWidget(),
            ],
          ),
        ),
      ),
    );
  }
}
