import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/auth/login/provider/auth_provider.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_empty_state.dart';
import 'package:thingsboard_democloud_app/widgets/tb_progress_indicator.dart';

/// Deep-link callback receiver for `org.thingsboard.pe.app.auth://...` or
/// `/oauth2/callback?accessToken=...&refreshToken=...`.
class OAuthCallbackPage extends ConsumerStatefulWidget {
  const OAuthCallbackPage({super.key, this.accessToken, this.refreshToken});

  final String? accessToken;
  final String? refreshToken;

  @override
  ConsumerState<OAuthCallbackPage> createState() => _OAuthCallbackPageState();
}

class _OAuthCallbackPageState extends ConsumerState<OAuthCallbackPage> {
  bool _started = false;
  String? _localError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final token = widget.accessToken?.trim() ?? '';
    if (token.isEmpty) {
      _localError = 'Missing OAuth2 access token';
      return;
    }
    Future<void>.microtask(() async {
      await ref
          .read(authSessionProvider.notifier)
          .completeOAuth2(
            accessToken: token,
            refreshToken: widget.refreshToken,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authSessionProvider);
    final authError = authAsync.error;
    final errorMessage =
        _localError ??
        (authAsync.hasError
            ? (authError is TbFailure
                  ? authError.message
                  : authError.toString())
            : null);

    if (errorMessage != null) {
      return Scaffold(
        appBar: TbAppBar(title: const Text('OAuth2 Sign-In'), canGoBack: false),
        body: TbEmptyState(
          icon: TbIconKind.severityCritical,
          title: 'Sign-in failed',
          subtitle: errorMessage,
          isError: true,
          actionLabel: 'Back to login',
          onAction: () {
            ref.read(authSessionProvider.notifier).cancelMfa();
            context.go('/login');
          },
        ),
      );
    }

    return const Scaffold(body: Center(child: TbProgressIndicator(size: 56)));
  }
}
