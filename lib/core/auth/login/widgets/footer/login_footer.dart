import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/auth/login/provider/auth_provider.dart';

class LoginFooter extends ConsumerWidget {
  const LoginFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selfRegistrationEnabled = ref.watch(
      serverConfigProvider.select(
        (s) => s.mobileInfo?.selfRegistrationEnabled ?? false,
      ),
    );
    if (!selfRegistrationEnabled) {
      return const SizedBox.shrink();
    }
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('New User?', style: textTheme.bodyMedium),
        TextButton(
          onPressed: () {},
          child: Text('Create Account', style: textTheme.labelLarge),
        ),
      ],
    );
  }
}
