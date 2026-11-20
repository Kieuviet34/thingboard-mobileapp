# Architecture

> Authoritative architecture summary for `thingsboard_democloud_app` (Flutter, Dart `^3.7.0`).
> Detailed design & coding rules live in [ui-rules.md](ui-rules.md) and [api-rules.md](api-rules.md).

## Stack & Key Packages
- **UI & Framework:** Flutter (`uses-material-design: true`), `flutter_svg`, `google_fonts`, `auto_size_text`, `toastification`.
- **State & Hooks:** `hooks_riverpod: ^2.6.1`, `flutter_hooks: ^0.21.2` (single state-management system; do not introduce Bloc/Provider/GetX).
- **Navigation:** `go_router: ^17.0.0` (`routerProvider`, `globalNavigatorKey`).
- **Networking & Forms:** `dio: ^5.8.0+1`, `reactive_forms: ^18.2.2`, `intl: ^0.20.2`, `collection: ^1.19.1`.
- **Target API & SDK:** ThingsBoard PE 4.4.x REST + WebSocket (`wss://<host>/api/ws`). See [thingsboard-pe-api.md](../research/thingsboard-pe-api.md).

## Modules / Layers
Feature-first + clean separation between UI, Riverpod state controllers, and API/storage infrastructure:

- `lib/main.dart` — `ProviderScope` -> `ThingsboardDemoCloudApp` (`ToastificationWrapper` + `MaterialApp.router`).
- `lib/constants/` — `ThingsboardAppConstants` (`app_constants.dart`), `ThingsboardImage` (`assets_path.dart`).
- `lib/config/themes/` — M3 themes (`tb_theme.dart`, `tb_theme_utils.dart`), `AppColors`, `DesignTokens`, `TbTextStyles`, status `ThemeExtension`.
- `lib/config/routes/` — `router.dart` (`GoRouter` routes, `ShellRoute`/`StatefulShellRoute` for main tabs, auth `redirect` + `refreshListenable`).
- `lib/core/`
  - `auth/` — `AuthNotifier` / `AuthUiState`, login, 2FA, password reset, OAuth2, QR login, secure JWT token storage.
  - `api/` — `Dio` client (`dioClientProvider`), `X-Authorization` interceptor & single-flight refresh, typed repositories/controllers (`Device`, `Alarm`, `Dashboard`, `Asset`, `Customer`, `Telemetry`, `Rpc`, `Notification`, `AuditLog`, `UserProfile`), `TbWebSocketService`.
  - `mock/` — `mock_data.dart` and demo repositories for Demo/Offline preview mode.
- `lib/modules/` — Feature screens (`login`, `main`, `home`/`dashboards`, `alarms`, `devices`, `assets`, `customers`, `notifications`, `audit_logs`, `more`, `profile`, `settings`).
- `lib/widgets/` — Reusable M3 UI components, `TbIcons` custom icon kit, metric pills, status badges, shimmer loaders, `TbAppBar`, `TbAppSearchBar`.
- `lib/utils/` — Transition builders, UI helpers, QR scanner.

## Data Flow
1. **UI Widgets (`ConsumerWidget` / `HookConsumerWidget`)** watch Riverpod providers (`AsyncNotifierProvider`, `NotifierProvider`, `StateNotifierProvider`) and render states (`loading` shimmer, `data`, `empty`, `error` with retry). No direct `Dio` calls or business logic in widgets.
2. **Controllers / Notifiers** coordinate pagination (`PageData<T>`), search/filter state, optimistic updates, and dispatch calls to repositories according to `SessionMode` (`live` vs `demo`).
3. **Repositories / API Services** call ThingsBoard PE REST endpoints via `Dio` (attaching `X-Authorization: Bearer <jwt>`) and subscribe to real-time updates via the single shared `TbWebSocketService` (`wss://<host>/api/ws`, multiplexed by `cmdId`).
4. **Demo / Offline Mode:** When `SessionMode.demo` is active, repositories return deterministic mock datasets backed by `lib/core/mock/mock_data.dart` without requiring live server credentials.

## External Services & Secrets (names only, never values)
- **ThingsBoard PE Server:** `ThingsboardAppConstants.thingsBoardApiEndpoint` (default `https://thingsboard.democloud.xyz/`, configurable via `--dart-define` or server selector).
- **JWT Credentials:** `jwtToken` and `refreshToken` stored exclusively in secure platform keystore/keychain (`flutter_secure_storage`), never in `SharedPreferences` or logs.
- **OAuth2 Callback Scheme:** `org.thingsboard.pe.app.auth` (`thingsboardOAuth2CallbackUrlScheme`), optional client secrets passed via `--dart-define`.
- **Push Notifications (optional):** FCM device token sent via `X-Mobile-Token` header to `/api/user/mobile/session`.

## Known Pitfalls (Verified in Repo)
- **Legacy Theme Defaults:** `lib/config/themes/tb_theme.dart` currently sets `useMaterial3: false` and `lib/main.dart` hardcodes `themeMode: ThemeMode.light` with `darkTheme: authState.appTheme`; must migrate to true M3 light/dark `ColorScheme`s.
- **Palette Mismatch:** `AppColors` defines CE Blue (`0xFF305680`), while `TbThemeUtils.defaultTheme` uses `Colors.teal[800]` / `Colors.deepOrange`. Consolidate into intentional M3 brand tokens.
- **Router Incomplete:** `lib/config/routes/router.dart` lacks an auth redirect guard and only mounts `/`, `/login`, `/login/resetPasswordRequest`, `/qrCodeScan`, `/home` (`HomePlaceholderPage`); `NavigationPage` and feature modules are not yet wired.
- **Android Manifest `INTERNET`:** `android/app/src/main/AndroidManifest.xml` is missing `android.permission.INTERNET` (currently only in `debug/` and `profile/` manifests), which breaks release/non-debug builds.
- **ThingsBoard Header & Endpoint Quirks:**
  - REST uses `X-Authorization: Bearer <jwt>`, NOT `Authorization`.
  - `https://thingsboard.democloud.xyz/` returns `404` on `/api/noauth/mobile`, `/api/noauth/whiteLabel/loginWhiteLabelParams`, and `/v3/api-docs` — optional startup calls must degrade gracefully.
  - ThingsBoard 4.4+ separates latest telemetry (`GET .../values/timeseries`) from historical range queries (`GET .../values/timeseries/history`).
