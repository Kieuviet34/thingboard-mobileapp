import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/auth/login/view/login_page.dart';
import 'package:thingsboard_democloud_app/core/auth/reset_password/reset_password_request_page.dart';
import 'package:thingsboard_democloud_app/modules/home/home_placeholder_page.dart';
import 'package:thingsboard_democloud_app/utils/ui/qr_code_scanner/qr_code_scanner_page.dart';

final GlobalKey<NavigatorState> globalNavigatorKey = GlobalKey();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: globalNavigatorKey,
    initialLocation: '/login',
    routes: [
      GoRoute(
        path: '/',
        redirect: (_, _) => '/login',
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
        routes: [
          GoRoute(
            path: 'resetPasswordRequest',
            builder: (context, state) => const ResetPasswordRequestPage(),
          ),
        ],
      ),
      GoRoute(
        path: '/qrCodeScan',
        builder: (context, state) => const QrCodeScannerPage(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomePlaceholderPage(),
      ),
    ],
  );
});
