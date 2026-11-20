# QA & Test Strategy — ThingsBoard PE Mobile App

> **Governing Rules & Inputs:**
> - [`docs/ai/api-rules.md`](../api-rules.md)
> - [`docs/ai/ui-rules.md`](../ui-rules.md)
> - [`docs/research/api-controller-matrix.md`](../../research/api-controller-matrix.md)
> - [`.agents/skills/tdd/SKILL.md`](../../../.agents/skills/tdd/SKILL.md) (seams at system boundaries only; vertical Red -> Green slices; independent literal expectations)
> - [`.agents/skills/flutter-ui/scripts/flutter_ui_audit.py`](../../../.agents/skills/flutter-ui/scripts/flutter_ui_audit.py)

---

## 1. Testing Philosophy & Seams

Following `.agents/skills/tdd/SKILL.md` (`tests.md`, `mocking.md`), tests verify **observable behavior through public seams** and **mock only at external system boundaries**:

| System Boundary (Mocked / Faked) | What Real Code Runs Above It | What This Seam Catches |
| :--- | :--- | :--- |
| `MockDioAdapter` (`HttpClientAdapter`) | `Dio` + `TbAuthInterceptor` + `TbErrorMapper` + `Rest*Repository` + Riverpod `AsyncNotifier` | Real URL paths, `X-Authorization` headers, JSON parsing, single-flight 401 refresh, `404`-only compatibility fallbacks, `403` RBAC handling, `TbFailure` mapping |
| `FakeSecureStorage` (in-memory `Map`) | `TbSecureStorage` + `AuthController` | Token persistence across cold restarts, logout clearing, corrupt/malformed refresh recovery |
| `FakeAppPreferences` (in-memory `Map`) | `TbAppPreferences` + `ServerConfigController` | Server URL & `SessionMode` (`live` / `demo`) persistence without touching secure storage |
| `FakeWebSocketChannel` (`StreamChannel` pair) | `TbWebSocketService` + live telemetry/alarm/notification `StreamProvider`s | `authCmd` framing, `cmdId` generation scoping, 30s heartbeat (`<90s` timeout), reconnect re-subscribe, offline disposal, partial updates |
| `ProviderContainer` + `SessionMode.demo` | Demo repositories + all Riverpod controllers & widgets | Full end-to-end mutations (alarm ack/clear/assign/unassign/comment, notifications read/delete, profile edit) without network |
| `WidgetTester` + `GoRouter` | Real `MaterialApp.router` (`theme` + `darkTheme`) + all routeable screens + `TbIcons` | Redirect guards, cold-start OAuth deep links, adaptive `NavigationBar`/`NavigationRail`/2-pane layouts, `Semantics`, `48dp` targets, `2.0x` text scaling, `disableAnimations` |

**Anti-patterns prohibited in this suite:**
- Do **not** mock internal Riverpod notifiers/repositories when testing a screen if the repository can be backed by `MockDioAdapter` or `Demo*Repository`.
- Do **not** assert internal method call counts when observable state/UI/HTTP output can be verified directly.
- Do **not** skip or relax assertions (`skip: true`, loosened matchers) to force green builds.

---

## 2. Unit Test Harness (`test/helpers/`)

### 2.1 Reusable Boundary Fakes
1. **`test/helpers/mock_dio_adapter.dart`**
   - Implements `HttpClientAdapter` (`fetch(RequestOptions, Stream<Uint8List>?, Future<void>?)`).
   - Supports route handlers by `(method, path)`, controllable `Completer`-gated delayed responses (to test concurrency, cancellation, and stale-response races), FIFO response queues, and simulated `DioException` network/timeout errors.
   - Records captured `RequestOptions` (headers, query parameters, decoded request bodies) so tests verify `X-Authorization: Bearer ...` and `pageSize`/`page` without coupling to internal client methods.
2. **`test/helpers/fake_secure_storage.dart`**
   - Implements `TbSecureStorage` backed by an in-memory `Map<String, String>` (with optional read/write error injection).
3. **`test/helpers/fake_app_preferences.dart`**
   - Implements `TbAppPreferences` (`baseUrl`, `SessionMode`, `ThemeMode`) backed by an in-memory `Map<String, Object>`.
4. **`test/helpers/fake_websocket_channel.dart`**
   - Implements `WebSocketChannel` using paired `StreamController<dynamic>` (outgoing client frames inspected as decoded JSON, incoming server frames pushed synchronously/async in tests) and tracks `sink.closeCode` / `sink.closeReason`.
5. **`test/helpers/pump_app.dart`** (`ProviderContainer` + Widget test helpers)
   - `createTestContainer({MockDioAdapter? dioAdapter, FakeSecureStorage? storage, FakeAppPreferences? prefs, FakeWebSocketChannel? wsChannel, SessionMode mode = SessionMode.live, ...})` with automatic `addTearDown(container.dispose)`.
   - `pumpTbApp(WidgetTester tester, {Brightness brightness = Brightness.light, Size size = const Size(390, 844), double textScale = 1.0, bool disableAnimations = false, String? initialLocation, ...})` wrapping `ProviderScope` + `MediaQuery` + `ThingsboardDemoCloudApp` (or isolated `GoRouter`).

### 2.2 Core Infrastructure Unit Tests (`test/core/api/`)

#### A. `TbAuthInterceptor` & Session Lifecycle (`test/core/api/tb_auth_interceptor_test.dart`)
- Attaches `X-Authorization: Bearer <jwt>` (never `Authorization`) to authenticated requests.
- Skips `X-Authorization` header on `/api/auth/login`, `/api/auth/token`, and `/api/noauth/**`.
- **Single-flight concurrent reactive refresh:** Firing 3 parallel requests that all receive `401` with `errorCode: 11` (`JWT_TOKEN_EXPIRED`) sends **exactly 1** `POST /api/auth/token` with `{"refreshToken": "..."}`, persists the new token pair in `FakeSecureStorage`, and replays all 3 original requests with the new Bearer token.
- **Proactive + reactive refresh race:** A proactive `exp`-skew check and a reactive `401` (`errorCode: 11`) arriving simultaneously share the **same** single-flight refresh lock -> **exactly 1** `POST /api/auth/token` is sent.
- **Refresh failure / timeout / malformed response:** Any `401`, network timeout, or malformed JSON from `POST /api/auth/token` clears `FakeSecureStorage`, sets `authProvider` to unauthenticated, and fails pending requests with `TbFailure(tokenExpired/unauthorized)`.
- **Non-expired `401` (`errorCode: 10`):** Does not attempt refresh; propagates `TbFailure(invalidCredentials)`.
- **`sessionGeneration` guard (logout / host switch / mode switch during in-flight refresh):**
  - Calling `logout()` while `POST /api/auth/token` or another request is in flight increments `sessionGeneration`; when the late response resolves, tokens are **not** restored and requests are **not** replayed into the logged-out session.
  - Switching `baseUrl` or toggling `SessionMode.live` <-> `SessionMode.demo` increments `sessionGeneration`, cancels in-flight tokens/requests, closes/recreates `TbWebSocketService`, invalidates host-scoped caches, and drops late responses from the previous host/mode.

#### B. `TbErrorMapper` (`test/core/api/tb_error_mapper_test.dart`)
- Maps every `ThingsboardErrorResponse` `errorCode` integer to its canonical `TbFailureType`:
  - `2` (`GENERAL`), `10` (`AUTHENTICATION`), `11` (`JWT_TOKEN_EXPIRED`), `12` (`TENANT_TRIAL_EXPIRED`), `15` (`CREDENTIALS_EXPIRED`), `20` (`PERMISSION_DENIED`), `30` (`INVALID_ARGUMENTS`), `31` (`BAD_REQUEST_PARAMS`), `32` (`ITEM_NOT_FOUND`), `33` (`TOO_MANY_REQUESTS`), `34` (`TOO_MANY_UPDATES`), `35` (`VERSION_CONFLICT`), `40` (`SUBSCRIPTION_VIOLATION` + `subscriptionErrorCode` `1..7`), `41` (`ENTITIES_LIMIT_EXCEEDED`), `45` (`PASSWORD_VIOLATION`), `46` (`DATABASE`), `47` (`SETUP_INCOMPLETE`), `50` (PE-specific restriction).
- Maps HTTP `504` (empty body from RPC) -> `deviceOfflineOrTimeout`, HTTP `406` -> `invalidDeviceRpcReply`, `DioExceptionType.connectionError`/`receiveTimeout` -> `networkUnavailable`.
- Verifies `40` is NOT misclassified as `versionConflict(35)` (guarding against the upstream `thingsboard_pe_client` enum bug).

#### C. `TbWebSocketService` (`test/core/api/telemetry_ws_service_test.dart`)
- Sends `{"authCmd": {"cmdId": 0, "token": "<jwt>"}}` as the first frame upon connect.
- Allocates unique monotonically increasing `cmdId`s across concurrent `ENTITY_DATA`, `ALARM_COUNT`, and `NOTIFICATIONS_COUNT` subscriptions.
- **Socket generation scoping:** Stale frames from an old socket generation or closed `cmdId` cannot be delivered to newly allocated subscriptions after reconnect.
- **App-level heartbeat (`30s` < `90s` server idle timeout):** Verified using `fake_async` that a keepalive frame/ping is emitted every `30s` when no other command is sent.
- **Reconnect & replay:** On unexpected disconnect or `AppLifecycleState.resumed`, reconnects with fresh JWT and re-subscribes all currently active commands (and only once — no duplicate replay).
- **Disposal while disconnected / per-command cleanup:** Disposing a subscription while disconnected removes its local subscription intent immediately so subsequent reconnect does **not** replay it. Disposing `ENTITY_DATA`/`ALARM_DATA`/`ALARM_COUNT`/`NOTIFICATIONS` sends `*_UNSUBSCRIBE`; disposing v1 `ATTRIBUTES`/`TIMESERIES` sends `"unsubscribe": true`; disposing `NOTIFICATIONS_COUNT` removes the local listener **without** sending an unsupported server unsubscribe frame.
- **Partial `ENTITY_DATA` update merge:** Verifies incremental `update` frames merge into cached entity rows without wiping unmentioned keys, ignore out-of-order older `ts` values, and handle deleted/null fields cleanly.
- **Errors:** Emits `TbFailure` on `errorCode != 0` (`3` `UNAUTHORIZED`, `4` `ACCESS_DENIED`), and closes cleanly on logout / `SessionMode.demo` switch.

### 2.3 Demo Model Regression Tests (`test/core/mock/mock_data_test.dart`)
- **`MockAlarm.copyWith` nullable clear:** Unassigning an alarm (`copyWith(clearAssignee: true)` / `assigneeName: null`) clears `assigneeName` to `null` instead of retaining the previous assignee via `??`.
- **`MockDeviceProfile` count parity:** `activeCount` and `inactiveCount` on every `MockDeviceProfile` (or Demo repository calculation) exactly match the seeded `MockDevice` records per profile type.

### 2.4 Controller & Repository Unit Tests (All 13 Controllers, Live + Demo)

| Test File | Controller / Repo | Required Live (`MockDioAdapter`) & Demo Assertions |
| :--- | :--- | :--- |
| `server_config_controller_test.dart` | `ServerConfigController` | Parses `GET /api/noauth/userPasswordPolicy` & `POST /api/noauth/oauth2Clients`; **treats `404` on `/api/noauth/mobile` & `/api/noauth/whiteLabel/loginWhiteLabelParams` as null/disabled**; probes `GET /api/system/info` after auth to detect server version/capabilities; switching `baseUrl` or `SessionMode` clears host-scoped caches & increments `sessionGeneration`. |
| `auth_controller_test.dart` | `AuthController` | `login` -> `authenticated`; `scope == PRE_VERIFICATION_TOKEN` -> `mfaVerificationRequired` -> `/verification/send` & `/check` -> `authenticated`; **`scope == MFA_CONFIGURATION_TOKEN` -> `mfaConfigurationRequired` -> `/api/auth/2fa/login` -> `authenticated`**; `loginWithQrSecret` (`GET /api/noauth/qr/{secret}`); OAuth2 callback token persistence; `requestPasswordReset`; `logout` clears tokens; `loginDemo()` activates `SessionMode.demo`. |
| `dashboard_controller_test.dart` | `DashboardController` | `GET /api/user/dashboards?mobile=true` pagination (`hasNext` -> `loadNextPage`), `404`-only fallback (if endpoint absent on older server) to `/api/tenant/dashboards` or `/api/customer/{id}/dashboards`; **real `403 PERMISSION_DENIED` surfaces `TbFailure(permissionDenied)` without masking**; `GET /api/dashboard/home/info`, `STAR`/`UNSTAR`/`VISIT`; overlapping search/refresh race drops stale page; Demo mode returns seeded dashboards & preserves star state. |
| `alarm_controller_test.dart` | `AlarmController` | `GET /api/v2/alarms` query serialization (`statusList`, `severityList`), `ack`/`clear`/`assign`/`unassign` optimistic update + **ordering & rollback on `403`/`404`**, stale-page refresh race (older response discarded), `GET/POST /api/alarm/{id}/comment`, `GET /api/users/assign/{id}`; Demo mode mutates `MockAlarm` & clears `assigneeName` on unassign. |
| `device_controller_test.dart` | `DeviceController` | `GET /api/deviceInfos/all` + `deviceProfileInfos`, **asserts exact `POST /api/entitiesQuery/count` request body (`deviceType` + `active` key filter)**, `GET /api/device/{id}/credentials` (`403`/`20` permission error handled), `POST /api/customer/device/{name}/claim`, overlapping search/pagination race; Demo profile counts match `MockDevice` active states. |
| `asset_controller_test.dart` | `AssetController` | `GET /api/assetInfos/all` pagination + search + stale-response guard, `GET /api/asset/info/{id}`, `GET /api/relations/info/from/ASSET/{id}`; Demo mode returns `MockAsset` + synthetic relations. |
| `customer_controller_test.dart` | `CustomerController` | `GET /api/customerInfos/all` with **`404`-only** fallback to `GET /api/customers`; **real `403 PERMISSION_DENIED` (`errorCode: 20`) surfaces `TbFailure(permissionDenied)` for `CUSTOMER_USER`**; `GET /api/customer/info/{id}`; Demo mode returns `MockCustomer`. |
| `telemetry_controller_test.dart` | `TelemetryController` | `GET .../values/attributes/{scope}`, `POST .../attributes/SHARED_SCOPE`, `GET .../values/timeseries?useStrictDataTypes=true` (latest), `GET .../values/timeseries/history` (`startTs`, `endTs`, `agg`, `interval`) **with `404`-only fallback to `/values/timeseries?startTs=...` (while `400` propagates `TbFailure(validation)`)**; string-to-double numeric parsing safety; overlapping time-range request race discards stale series; Demo telemetry & synthetic history. |
| `rpc_controller_test.dart` | `RpcController` | `POST /api/rpc/oneway/{id}` & `twoway/{id}`, `504` -> `deviceOfflineOrTimeout`, `406` -> `invalidDeviceRpcReply`, `GET/DELETE /api/rpc/persistent/...`, cancellation / late response ignored after switching device or disposing provider; Demo mode echoes active device & times out offline device. |
| `notification_controller_test.dart` | `NotificationController` | `GET /api/notifications`, `GET /api/notifications/unread/count`, `PUT /api/notification/{id}/read`, `PUT /api/notifications/read`, `DELETE /api/notification/{id}`, **`GET/POST /api/notification/settings/user`**, `POST/DELETE /api/user/mobile/session` (`X-Mobile-Token`), WS `NOTIFICATIONS_COUNT` updates without emitting unsubscribe frame; Demo mode mutations update badge count. |
| `audit_log_controller_test.dart` | `AuditLogController` | `GET /api/audit/logs` + entity/user scoped logs, `actionTypes` & time range params, `403`/`20` permission error surfaced cleanly, large `actionData` payload parsing; Demo mode filtering by search/type. |
| `user_profile_controller_test.dart` | `UserProfileController` | `GET /api/auth/user`, `POST /api/user` update, `GET/PUT /api/user/settings/general`, **`POST /api/auth/changePassword` persists returned `JwtPair` in `FakeSecureStorage`**; Demo mode profile updates persist in session. |

---

## 3. Widget & UI/UX Test Suite (`test/modules/` & `test/widgets/`)

### 3.1 Routing, Auth Guard & Cold-Start Deep Links (`test/config/router_test.dart`)
- Unauthenticated user visiting `/home`, `/dashboards`, `/alarms`, `/devices`, `/assets`, `/customers`, `/notifications`, `/auditLogs`, `/more`, `/profile`, or `/settings` is redirected to `/login`.
- Unauthenticated user can access `/login`, `/login/resetPasswordRequest`, `/login/2fa`, `/qrCodeScan`, and OAuth callback route.
- `routerProvider` `refreshListenable` triggers redirect to `/login` immediately when `AuthController` transitions to unauthenticated (e.g., refresh failure), and redirects to `/home` on login (Live or Demo).
- **2FA back navigation & retention:** Pressing back from `PRE_VERIFICATION_TOKEN` / `MFA_CONFIGURATION_TOKEN` screen clears or retains pre-auth state per design without leaving an invalid authenticated session.
- **Cold-start OAuth2 deep link:** Pumping `GoRouter` with initial callback URI (`org.thingsboard.pe.app.auth://...` / `/oauth2/callback?accessToken=...&refreshToken=...`) persists tokens and lands on `/home` (and handles missing/invalid callback params safely).
- `StatefulShellRoute.indexedStack` preserves tab state and scroll position when switching between Home, Alarms, Devices, and More.

### 3.2 Complete Routeable Page & Feature Widget Tests
Every routeable page and detail screen is tested across **4 states** (`loading` shimmer, `data`, `empty` 2–4 word title + action, `error` + retry button) in **Demo mode** and mocked **Live mode**:
1. **Auth Flow (`test/core/auth/`):**
   - `LoginPage`: validation errors, Live login -> `/home`, "Try Demo Mode" -> `/home` with `DEMO` badge, server URL editor, OAuth buttons rendered from `/api/noauth/oauth2Clients` without crashing when empty/`404`.
   - `ResetPasswordRequestPage`: submits email and shows confirmation feedback.
   - `TwoFactorAuthPage`: handles both `PRE_VERIFICATION_TOKEN` (provider selector + OTP submit + invalid-code error) and `MFA_CONFIGURATION_TOKEN` setup flow.
   - `QrCodeScannerPage`: handles scanned login secret and device-claim QR payload via injected scanner callback.
2. **Adaptive Shell (`test/modules/main/navigation_page_test.dart`):**
   - `390x844` (Compact): renders bottom `NavigationBar` with custom `TbIcons` + unread notification/alarm badges; no `NavigationRail`.
   - `720x1024` (Medium): renders `NavigationRail` instead of bottom `NavigationBar`.
   - `1024x768` (Expanded): renders `NavigationRail` + 2-pane master-detail across all 5 master-detail modules (**Devices**, **Alarms**, **Dashboards**, **Assets**, **Customers**) without single-column stretching or overflow.
3. **Home & Dashboards (`test/modules/dashboard/`):**
   - `HomePage`: home dashboard summary + recent/starred quick access + `DEMO` pill when in Demo mode.
   - `DashboardsPage`: search filter, star toggle, pull-to-refresh, `Hero` transition to `DashboardDetailsPage`.
   - `DashboardDetailsPage`: live metric pills (`tabularFigures`), WebView/native widget fallback, toolbar visibility (`hideDashboardToolbar`).
4. **Alarms (`test/modules/alarm/`):**
   - `AlarmsPage`: multi-filter (`ACTIVE`/`CLEARED`, `CRITICAL`..`INDETERMINATE`), search, distinct severity glyphs rendered.
   - `AlarmDetailsPage`: Ack / Clear / Assign / Unassign user sheet / Add comment updates UI immediately and rolls back with toast on `403`/`404`.
5. **Devices (`test/modules/device/`):**
   - `DevicesMainPage`: profile list shows accurate active/inactive counts; tapping profile opens `DevicesListPage` filtered by profile.
   - `DevicesListPage`: search, active filter, pagination `loadNextPage`, empty/error states.
   - `DeviceDetailsPage`: tabs for Telemetry (metric pills + chart + WS live updates), Attributes (`SERVER_SCOPE`/`SHARED_SCOPE` edit), RPC (command form + `504`/`406` feedback), and Alarms.
6. **Assets & Customers (`test/modules/asset/`, `test/modules/customer/`):**
   - `AssetsPage`: search, type filter, pagination, empty/error states.
   - `AssetDetailsPage`: asset metadata, attributes/telemetry preview, `Contains` entity relations drill-down to related Devices.
   - `CustomersPage`: search, pagination, `403` role notice vs `404` fallback.
   - `CustomerDetailsPage`: contact/address fields (`title`, `email`, `phone`, `city`/`country`), customer devices/assets/dashboards tabs.
7. **More Hub, Audit Logs, Notifications, Profile & Settings (`test/modules/more/`, `audit_log/`, `notification/`, `profile/`):**
   - `MorePage`: shows Customers/Assets/Audit Logs/Notifications/Profile/Settings; hides Tenant-only entries when `authority == CUSTOMER_USER`.
   - `AuditLogsPage`: filter by action type, `403` role-restricted view, expandable `actionData` JSON rendering.
   - `NotificationsPage`: mark read, mark all read, delete, multi-select delete, notification settings sheet (`/api/notification/settings/user`).
   - `ProfilePage` / `SettingsPage`: edit user profile, theme mode switch (`Light` / `Dark` / `System`), unit system, change password (persisting new tokens), mode/host switch isolation.

### 3.3 Theme, Custom Icons, Accessibility & Reduced-Motion Tests (`test/widgets/ui_standards_test.dart`)
- **Light & Dark Theme Parity:** Pump root shell + primary screens under both `Brightness.light` and `Brightness.dark` with `useMaterial3: true`; assert `Theme.of(context).colorScheme.brightness` matches, `TbStatusColors` extension is non-null, and zero `FlutterError` / overflow exceptions occur.
- **`TbIcons` Rendering & Tinting:** Render every `TbIcons` category (nav, device types, telemetry channels, all 5 alarm severities + cleared) inside Light and Dark themes; verify `RepaintBoundary` wrapping and non-empty paint bounds.
- **Minimum Touch Targets (`>= 48dp`):** Walk `find.byType(IconButton)`, `InkWell`, `NavigationBar`/`NavigationRail` destinations, and interactive status/action chips across Login, Shell, Dashboards, Alarms, Devices, Assets, Customers, Notifications, AuditLogs, and Profile/Settings; assert `tester.getSize(widget).width >= 48.0 && height >= 48.0`.
- **Semantics & `2.0x` Text Scaling:** Verify `Semantics` labels exist on icon-only buttons (`tooltip` / `SemanticsProperties.label`) and non-decorative `TbIcons`; pump key list & detail rows (`AlarmCard`, `DeviceCard`, `MetricPill`, `AssetDetailsPage`, `CustomerDetailsPage`, `AuditLogsPage`) with **`TextScaler.linear(2.0)`** and assert zero `RenderFlex overflow` or clipped-text errors.
- **Reduced Motion (`disableAnimations`):** Pump `NavigationPage`, `AlarmsPage`, and `DeviceDetailsPage` with `MediaQuery(data: MediaQueryData(disableAnimations: true), ...)` and assert `pumpAndSettle()` completes cleanly with no stuck infinite tickers (`shimmer` / pulse disabled or bounded).

---

## 4. Static, Audit, Build & Live Emulator/Server QA Gates

Run these gates in order after every implementation wave and before final handoff. Note that `flutter_ui_audit.py` is a **heuristic static scanner** — it does **not** verify M3 `useMaterial3: true`, `TbStatusColors`, adaptive breakpoints, `Semantics`, `48dp` hit targets, or `disableAnimations`; those requirements are verified by `test/widgets/ui_standards_test.dart`.

| Gate | Command | Pass Criteria |
| :--- | :--- | :--- |
| 1. Static Analysis | `flutter analyze` | `No issues found!` (0 errors, 0 warnings, 0 infos) |
| 2. Formatting | `dart format --output=none --set-exit-if-changed .` | Exit code `0` (all Dart files formatted) |
| 3. Unit & Widget Tests | `flutter test` | 100% tests pass; zero skipped/relaxed assertions |
| 4. Flutter UI Audit (Heuristic) | `python .agents/skills/flutter-ui/scripts/flutter_ui_audit.py .` | **0 `RED` (CRITICAL)** findings AND **every `YELLOW` finding resolved or explicitly justified** in the wave report (e.g., central `TbTheme`/`TbStatusColors` palette definitions only) |
| 5. Android Debug APK & Manifest | `flutter build apk --debug` (with JDK 17 `JAVA_HOME`, followed by Gradle daemon cleanup if needed) | `app-debug.apk` builds cleanly; inspect merged manifest (`INTERNET`, `CAMERA`, `org.thingsboard.pe.app.auth` deep-link intent filter) |
| 6. Live `democloud.xyz` Public Endpoint Smoke Check | Scripted HTTP check against `https://thingsboard.democloud.xyz/` | Confirm live server still matches documented contract (`/api/noauth/userPasswordPolicy` `200`, `POST /api/noauth/oauth2Clients` `200`, `/api/system/info` `401` `errorCode: 10`, `/api/noauth/mobile` `404`) |
| 7. Live Emulator Visual & Deep-Link QA | `adb install -r build/app/outputs/flutter-apk/app-debug.apk`, `adb shell am start -a android.intent.action.VIEW -d "org.thingsboard.pe.app.auth://..."`, `adb exec-out screencap -p`, `adb logcat` | Verify OAuth/deep-link intent routing on-device, inspect Light & Dark screenshots across Login, Demo Home, Dashboards, Alarms + Details, Devices + Details, Assets/Customers Details, More/Notifications/Settings, and confirm `logcat` has zero uncaught exceptions |
