import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/auth/login/widgets/login_widget.dart';

class LoginPage extends ConsumerWidget {
  const LoginPage({super.key, this.redirectUrl});

  final String? redirectUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(body: LoginWidget(redirectUrl: redirectUrl));
  }
}
