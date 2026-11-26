import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:thingsboard_democloud_app/core/auth/login/provider/auth_provider.dart';
import 'package:thingsboard_democloud_app/core/auth/login/view/login_page.dart';
import 'package:thingsboard_democloud_app/core/auth/oauth/oauth_callback_page.dart';
import 'package:thingsboard_democloud_app/core/auth/reset_password/reset_password_request_page.dart';
import 'package:thingsboard_democloud_app/core/auth/two_factor/mfa_setup_page.dart';
import 'package:thingsboard_democloud_app/core/auth/two_factor/two_factor_auth_page.dart';
import 'package:thingsboard_democloud_app/core/models/auth_models.dart';
import 'package:thingsboard_democloud_app/modules/alarm/alarm_details_page.dart';
import 'package:thingsboard_democloud_app/modules/alarm/alarms_page.dart';
import 'package:thingsboard_democloud_app/modules/asset/asset_details_page.dart';
import 'package:thingsboard_democloud_app/modules/asset/assets_page.dart';
import 'package:thingsboard_democloud_app/modules/audit_log/audit_logs_page.dart';
import 'package:thingsboard_democloud_app/modules/customer/customer_details_page.dart';
import 'package:thingsboard_democloud_app/modules/customer/customers_page.dart';
import 'package:thingsboard_democloud_app/modules/dashboard/dashboard_details_page.dart';
import 'package:thingsboard_democloud_app/modules/dashboard/dashboards_page.dart';
import 'package:thingsboard_democloud_app/modules/device/device_details_page.dart';
import 'package:thingsboard_democloud_app/modules/device/devices_list_page.dart';
import 'package:thingsboard_democloud_app/modules/device/devices_main_page.dart';
import 'package:thingsboard_democloud_app/modules/home/home_page.dart';
import 'package:thingsboard_democloud_app/modules/main/navigation_page.dart';
import 'package:thingsboard_democloud_app/modules/more/more_page.dart';
import 'package:thingsboard_democloud_app/modules/notification/notifications_page.dart';
import 'package:thingsboard_democloud_app/modules/profile/profile_settings_page.dart';
import 'package:thingsboard_democloud_app/utils/transition/page_transitions.dart';
import 'package:thingsboard_democloud_app/utils/ui/qr_code_scanner/qr_code_scanner_page.dart';
import 'package:thingsboard_democloud_app/widgets/icons/tb_icons.dart';

final GlobalKey<NavigatorState> globalNavigatorKey = GlobalKey();

/// Canonical route paths shared by the router, shell, and feature screens.
abstract final class AppRoutes {
  // Auth & session
  static const splash = '/splash';
  static const login = '/login';
  static const resetPassword = '/login/resetPasswordRequest';
  static const twoFactor = '/login/2fa';
  static const mfaSetup = '/login/2fa-setup';
  static const oauthCallback = '/oauth2/callback';
  static const qrScan = '/qrCodeScan';

  // Shell branch 0 — Home
  static const home = '/home';
  static const dashboards = '/home/dashboards';
  static const dashboardDetails = '/dashboard/:id';

  // Shell branch 1 — Alarms
  static const alarms = '/alarms';
  static const alarmsSearch = '/alarms/search';
  static const alarmDetails = '/alarms/alarmDetails/:id';

  // Shell branch 2 — Devices
  static const devices = '/devices';
  static const deviceList = '/devices/deviceList';
  static const deviceDetails = '/devices/deviceDetails/:id';

  // Shell branch 3 — More
  static const more = '/more';
  static const customers = '/customers';
  static const customerDetails = '/customers/customerDetails/:id';
  static const assets = '/assets';
  static const assetDetails = '/assets/assetDetails/:id';
  static const auditLogs = '/auditLogs';
  static const notifications = '/notifications';
  static const profile = '/profile';

  static String dashboardDetailsPath(String id) => '/dashboard/$id';
  static String alarmDetailsPath(String id) => '/alarms/alarmDetails/$id';
  static String deviceDetailsPath(String id) => '/devices/deviceDetails/$id';
  static String customerDetailsPath(String id) =>
      '/customers/customerDetails/$id';
  static String assetDetailsPath(String id) => '/assets/assetDetails/$id';

  /// Routes reachable without an authenticated session.
  static const publicPaths = <String>{
    login,
    resetPassword,
    qrScan,
    oauthCallback,
  };

  static bool isPublic(String path) => publicPaths.contains(path);
}

/// Pure auth redirect matrix used by [routerProvider] (and unit tests).
///
/// Returns `null` when [uri] may stay, otherwise the location to redirect to.
String? tbAuthRedirect({
  required AsyncValue<AuthState> auth,
  required Uri uri,
}) {
  final path = uri.path.isEmpty ? '/' : uri.path;
  final isBootPath = path == '/' || path == AppRoutes.splash;

  // Custom-scheme OAuth2 deep links arrive as `<scheme>://callback?accessToken=...`
  // and are normalized onto the dedicated callback route.
  if (uri.queryParameters.containsKey('accessToken') &&
      path != AppRoutes.oauthCallback) {
    return Uri(
      path: AppRoutes.oauthCallback,
      queryParameters: uri.queryParameters,
    ).toString();
  }

  final state = auth.valueOrNull;

  if (state == null) {
    if (auth.isLoading) {
      return (AppRoutes.isPublic(path) || isBootPath) ? null : AppRoutes.splash;
    }
    // Error / no value is treated as unauthenticated.
    return _unauthenticatedRedirect(path, uri);
  }

  return switch (state) {
    AuthAuthenticated() => _authenticatedRedirect(path, uri),
    AuthMfaVerificationRequired() =>
      path == AppRoutes.twoFactor ? null : AppRoutes.twoFactor,
    AuthMfaConfigurationRequired() =>
      path == AppRoutes.mfaSetup ? null : AppRoutes.mfaSetup,
    AuthUnauthenticated() => _unauthenticatedRedirect(path, uri),
  };
}

String? _unauthenticatedRedirect(String path, Uri uri) {
  if (AppRoutes.isPublic(path)) return null;
  if (path == '/' ||
      path == AppRoutes.splash ||
      path == AppRoutes.home ||
      path == AppRoutes.twoFactor ||
      path == AppRoutes.mfaSetup) {
    return AppRoutes.login;
  }
  final from = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
  return Uri(path: AppRoutes.login, queryParameters: {'from': from}).toString();
}

String? _authenticatedRedirect(String path, Uri uri) {
  final leavingAuthArea =
      path == '/' ||
      path == AppRoutes.splash ||
      path == AppRoutes.login ||
      path == AppRoutes.resetPassword ||
      path == AppRoutes.twoFactor ||
      path == AppRoutes.mfaSetup ||
      path == AppRoutes.oauthCallback;
  if (!leavingAuthArea) return null;
  return _safeFrom(uri.queryParameters['from']) ?? AppRoutes.home;
}

/// Accepts only in-app absolute paths that are not part of the auth flow.
String? _safeFrom(String? from) {
  if (from == null || from.isEmpty) return null;
  if (!from.startsWith('/') || from.startsWith('//')) return null;
  final parsed = Uri.tryParse(from);
  if (parsed == null || parsed.hasScheme || parsed.hasAuthority) return null;
  final path = parsed.path;
  if (path == '/' ||
      path == AppRoutes.splash ||
      path.startsWith(AppRoutes.login) ||
      path == AppRoutes.oauthCallback) {
    return null;
  }
  return from;
}

/// Bridges [authSessionProvider] changes into [GoRouter.refreshListenable].
class RouterRefreshNotifier extends ChangeNotifier {
  RouterRefreshNotifier(Ref ref) {
    ref.listen<AsyncValue<AuthState>>(authSessionProvider, (previous, next) {
      if (!_disposed) notifyListeners();
    });
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final routerRefreshProvider = Provider<RouterRefreshNotifier>((ref) {
  final notifier = RouterRefreshNotifier(ref);
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// Minimal boot screen shown while the persisted session is restored.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: TbIcon(TbIconKind.sensorNode, size: 48)),
    );
  }
}

Page<void> _page(GoRouterState state, Widget child) =>
    tbFadeThroughTransitionPage<void>(key: state.pageKey, child: child);

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(routerRefreshProvider);

  final router = GoRouter(
    navigatorKey: globalNavigatorKey,
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) =>
        tbAuthRedirect(auth: ref.read(authSessionProvider), uri: state.uri),
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => _page(state, const SplashPage()),
      ),
      GoRoute(
        path: AppRoutes.splash,
        pageBuilder: (context, state) => _page(state, const SplashPage()),
      ),
      GoRoute(
        path: AppRoutes.login,
        pageBuilder: (context, state) => _page(
          state,
          LoginPage(redirectUrl: state.uri.queryParameters['from']),
        ),
        routes: [
          GoRoute(
            path: 'resetPasswordRequest',
            pageBuilder: (context, state) =>
                _page(state, const ResetPasswordRequestPage()),
          ),
          GoRoute(
            path: '2fa',
            pageBuilder: (context, state) =>
                _page(state, const TwoFactorAuthPage()),
          ),
          GoRoute(
            path: '2fa-setup',
            pageBuilder: (context, state) => _page(state, const MfaSetupPage()),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.oauthCallback,
        pageBuilder: (context, state) => _page(
          state,
          OAuthCallbackPage(
            accessToken: state.uri.queryParameters['accessToken'],
            refreshToken: state.uri.queryParameters['refreshToken'],
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.qrScan,
        pageBuilder: (context, state) =>
            _page(state, const QrCodeScannerPage()),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            NavigationPage(navigationShell: navigationShell),
        branches: [
          // 0 — Home
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                pageBuilder: (context, state) => _page(state, const HomePage()),
                routes: [
                  GoRoute(
                    path: 'dashboards',
                    pageBuilder: (context, state) =>
                        _page(state, const DashboardsPage()),
                  ),
                ],
              ),
              GoRoute(
                path: AppRoutes.dashboardDetails,
                pageBuilder: (context, state) => _page(
                  state,
                  DashboardDetailsPage(
                    dashboardId: state.pathParameters['id']!,
                  ),
                ),
              ),
            ],
          ),
          // 1 — Alarms
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.alarms,
                pageBuilder: (context, state) =>
                    _page(state, const AlarmsPage()),
                routes: [
                  GoRoute(
                    path: 'search',
                    pageBuilder: (context, state) =>
                        _page(state, const AlarmsPage(searchMode: true)),
                  ),
                  GoRoute(
                    path: 'alarmDetails/:id',
                    pageBuilder: (context, state) => _page(
                      state,
                      AlarmDetailsPage(id: state.pathParameters['id']!),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // 2 — Devices
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.devices,
                pageBuilder: (context, state) =>
                    _page(state, const DevicesMainPage()),
                routes: [
                  GoRoute(
                    path: 'deviceList',
                    pageBuilder: (context, state) {
                      final q = state.uri.queryParameters;
                      final activeStr = q['active'];
                      final bool? active = activeStr == null
                          ? null
                          : (activeStr == 'true');
                      return _page(
                        state,
                        DevicesListPage(
                          deviceProfileId:
                              q['deviceProfileId'] ?? q['profileId'],
                          deviceType: q['deviceType'] ?? q['title'],
                          active: active,
                          searchMode: q['search'] == 'true',
                        ),
                      );
                    },
                  ),
                  GoRoute(
                    path: 'deviceDetails/:id',
                    pageBuilder: (context, state) => _page(
                      state,
                      DeviceDetailsPage(deviceId: state.pathParameters['id']!),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // 3 — More (+ customers, assets, audit logs, notifications, profile)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.more,
                pageBuilder: (context, state) => _page(state, const MorePage()),
              ),
              GoRoute(
                path: AppRoutes.customers,
                pageBuilder: (context, state) =>
                    _page(state, const CustomersPage()),
                routes: [
                  GoRoute(
                    path: 'customerDetails/:id',
                    pageBuilder: (context, state) => _page(
                      state,
                      CustomerDetailsPage(
                        customerId: state.pathParameters['id']!,
                      ),
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: AppRoutes.assets,
                pageBuilder: (context, state) =>
                    _page(state, const AssetsPage()),
                routes: [
                  GoRoute(
                    path: 'assetDetails/:id',
                    pageBuilder: (context, state) => _page(
                      state,
                      AssetDetailsPage(assetId: state.pathParameters['id']!),
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: AppRoutes.auditLogs,
                pageBuilder: (context, state) =>
                    _page(state, const AuditLogsPage()),
              ),
              GoRoute(
                path: AppRoutes.notifications,
                pageBuilder: (context, state) =>
                    _page(state, const NotificationsPage()),
              ),
              GoRoute(
                path: AppRoutes.profile,
                pageBuilder: (context, state) =>
                    _page(state, const ProfileSettingsPage()),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  ref.onDispose(router.dispose);
  return router;
});
