import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/config/themes/tb_text_styles.dart';
import 'package:thingsboard_democloud_app/core/auth/login/provider/auth_provider.dart';

class LoginFooter extends ConsumerWidget {
  const LoginFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selfRegistrationEnabled = ref.watch(
      authProvider.select((s) => s.selfRegistrationEnabled),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selfRegistrationEnabled)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('New User?', style: TbTextStyles.bodyMedium),
              TextButton(
                onPressed: () {},
                child: Text('Create Account', style: TbTextStyles.bodyMedium),
              ),
            ],
          ),
        const SizedBox(width: double.infinity),
      ],
    );
  }
}
