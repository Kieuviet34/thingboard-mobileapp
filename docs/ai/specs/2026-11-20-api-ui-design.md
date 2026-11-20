# Design Specification: ThingsBoard PE Mobile App — API Integration & Material 3 UI/UX Overhaul

> **Status:** Revised Post-Codex Review (Ready for Implementation)
> **Date:** 2026-11-20
> **Target Repository:** `thingboard-mobileapp` (`thingsboard_democloud_app`, Flutter `3.50.0` / Dart `3.14.0`, `hooks_riverpod ^2.6.1`, `go_router ^17.0.0`, `dio ^5.8.0+1`)
> **Authoritative References:**
> - `docs/ai/ARCHITECTURE.md`, `docs/ai/ui-rules.md`, `docs/ai/api-rules.md`
> - `docs/research/thingsboard-pe-api.md`, `docs/research/sdk-decision.md`, `docs/research/api-controller-matrix.md`
> - `docs/ai/plans/2026-11-20-codex-plan-review.md`

---

## 1. Problem Statement

The current `thingsboard_democloud_app` repository is a mock-driven UI baseline with three major gaps:
1. **Disconnected API & Placeholder Core:** `AuthNotifier` simulates login/password-reset with `Future.delayed(800ms)`, `dioClientProvider` is unused, `QrCodeScannerPage` and `HomePlaceholderPage` are static stubs, and there is no secure JWT persistence, single-flight refresh, WebSocket telemetry/alarm stream, or live ThingsBoard PE REST integration.
2. **Broken Routing & Missing Feature Screens:** `routerProvider` only mounts `/`, `/login`, `/login/resetPasswordRequest`, `/qrCodeScan`, and `/home` (`HomePlaceholderPage`). Existing mock screens (`DashboardsPage`, `AlarmsPage`, `DevicesMainPage`, etc.) and `NavigationPage` are unreachable, while `More`, `2FA`, `Customers`, `CustomerDetails`, `Assets`, `AssetDetails`, `AuditLogs`, `Notifications`, and `Profile/Settings` have no UI despite mock providers and SVG assets existing. Additionally, `MockAlarm.copyWith` cannot clear `assigneeName` and `MockDeviceProfile` counts disagree with `MockDevice` records.
3. **Legacy Theme, Generic Icons & Android Release Gaps:** `tb_theme.dart` sets `useMaterial3: false`, `main.dart` hardcodes `ThemeMode.light` and passes the same light theme to `darkTheme`, `TbThemeUtils` (`Colors.teal[800]`) conflicts with `AppColors` (`#305680`), pages use hardcoded hex colors and generic Material icons, and `android/app/src/main/AndroidManifest.xml` lacks `INTERNET` permission (breaking release builds), `CAMERA` permission, OAuth deep-link filters, and branding assets.

---

## 2. Solution Overview

Upgrade `thingsboard_democloud_app` into a production-ready, dual-mode (`SessionMode.live` + `SessionMode.demo`) Flutter application featuring:
1. **Option C Typed `Dio` Facade (`TbApiClient`) + Shared `TbWebSocketService`:** Clean immutable domain models shared seamlessly across `Rest*Repository` and `Demo*Repository` implementations, protected by a shared single-flight JWT refresh gate, monotonic `sessionGeneration` race guard, canonical `TbFailure` error model, and explicit endpoint-specific `404` compatibility fallbacks.
2. **Material Design 3 Light & Dark System:** `useMaterial3: true`, unified ThingsBoard PE brand `ColorScheme` + `TbStatusColors` `ThemeExtension`, adaptive `NavigationBar` -> `NavigationRail` + 2-pane master-detail (Dashboards, Alarms, Devices, Assets, Customers), minimal-text scannable IoT layouts, `2.0x` text scaling support, and `>= 48dp` accessibility targets.
3. **Cohesive Custom Icon Identity (`TbIcons`) & GPU-Safe Motion:** Custom `24dp` / `1.75dp` stroke vector/`CustomPainter` icon kit across navigation, entities, telemetry, and shape-distinct alarm severities, paired with `Transform`/`Opacity`/`Hero`/shimmer/staggered animations that honor `MediaQuery.disableAnimationsOf(context)`.
4. **Complete Route & Screen Coverage + Android Readiness:** Full `StatefulShellRoute.indexedStack` shell with `GoRouter` `refreshListenable` auth guard across all 21 routeable screens/pages, live QR scanning (`mobile_scanner`), 2FA verification & MFA setup guidance, OAuth2 callback handling, and properly configured `AndroidManifest.xml` + `assets/branding/` assets.

---

## 3. User Stories

1. As an **IoT operator**, I want to sign in with my ThingsBoard PE credentials against `https://thingsboard.democloud.xyz/` (or a custom server URL) and stay signed in via automatic JWT refresh, so that my session stays uninterrupted.
2. As an **evaluator without server credentials**, I want a one-tap **Demo Mode** (`SessionMode.demo`) entry from the login screen, so that I can explore every screen and mutation offline with consistent sample data.
3. As a **security-conscious user**, I want `PRE_VERIFICATION_TOKEN` 2FA OTP verification, `MFA_CONFIGURATION_TOKEN` 2FA setup handling, OAuth2 external login with deep-link callback, password reset, and QR code login/device claiming to work reliably.
4. As an **operator on the Home tab**, I want to see my assigned Home Dashboard (or a compact KPI summary of active alarms, online/offline devices, and recent/starred dashboards), so that I can assess system health in seconds.
5. As a **facility manager**, I want to browse, search, star, and open Dashboards in normal or fullscreen mode with live telemetry metric tiles and sparklines, so that I can monitor key KPIs on phone or tablet.
6. As an **on-call engineer**, I want live alarm counts, multi-filter alarm lists (status & severity), and an Alarm Details screen where I can acknowledge, clear, assign/unassign users, and post comments optimistically.
7. As a **field technician**, I want to browse device profiles and devices, scan a device QR to claim it, and open Device Details to inspect live WebSocket telemetry, historical charts, server/shared/client attributes, execute one-way/two-way RPC commands, and view device alarms/relations.
8. As a **tenant administrator**, I want to access Customers + Customer Details, Assets + Asset Details (with relations/telemetry/attributes/alarms), Audit Logs (with JSON payload inspection), Notifications (with unread badge, settings, mark-read, and bulk delete), and Profile/Settings (profile edit, password change, Light/Dark/System theme, server/demo switch).
9. As an **accessibility & dark-mode user**, I want high-contrast Light and Dark Material 3 themes, distinct geometric alarm severity icons (never color-only), `>= 48dp` touch targets, `2.0x` dynamic font scaling without clipping, and reduced-motion support.

---

## 4. Architecture & API Design (Option C — Canonical Contract)

### 4.1 Layering & Canonical Symbols
```text
lib/modules/<feature>/       -> HookConsumerWidget / ConsumerWidget + feature views
lib/core/api/controllers/    -> 13 Riverpod Notifiers / AsyncNotifiers / Providers
lib/core/api/repositories/   -> Abstract interfaces + Rest* implementations (Dio)
lib/core/mock/               -> Demo*Repository implementations + seeded mock_data.dart
lib/core/api/client/         -> TbApiClient, TbAuthInterceptor, TbErrorMapper, TbSecureStorage, TbAppPreferences
lib/core/api/ws/             -> TbWebSocketService (wss://<host>/api/ws multiplexer)
lib/core/models/             -> Immutable const domain models (fromJson / copyWith / ==)
```
- **Canonical Names (used across all docs & code):**
  - Session Mode enum: `SessionMode { live, demo }` (no `AppConnectionMode` / `isDemoModeProvider` aliases).
  - Error model: `TbFailure` + `TbFailureType` (no `TbApiException` / `ThingsboardException` aliases).
  - Storage split:
    - `TbSecureStorage` (`flutter_secure_storage`): ONLY secrets (`jwtToken`, `refreshToken`, optional `apiKey`).
    - `TbAppPreferences` (`shared_preferences`): non-sensitive host/UI settings (`serverBaseUrl`, `sessionMode`, `themeMode`).

### 4.2 Auth, Single-Flight Refresh & `sessionGeneration` Race Guard
- **Distinct `AuthState` Variants (`lib/core/models/auth_models.dart`):**
  1. `AuthUnauthenticated`
  2. `AuthMfaVerificationRequired(providers, preAuthToken)` — server returned `scope == 'PRE_VERIFICATION_TOKEN'`; routes to `/login/2fa`.
  3. `AuthMfaConfigurationRequired(preAuthToken)` — server returned `scope == 'MFA_CONFIGURATION_TOKEN'`; routes to `/login/2fa-setup`.
  4. `AuthAuthenticated(session, user, mode)` — full `TbAuthSession` in `SessionMode.live` or synthetic session in `SessionMode.demo`.
- **Shared Single-Flight Refresh Gate (`TbAuthSessionCoordinator`):**
  - Both **proactive** expiry checks (`JwtDecoder.getExpirationDate(token)` within 60s skew in `onRequest`) and **reactive** HTTP `401` (`errorCode == 11`) handlers in `TbAuthInterceptor` (`QueuedInterceptor`) acquire the **same** `Completer<RefreshOutcome>? _refreshInFlight` lock.
  - Overlapping proactive and reactive refresh triggers coalesce onto that single `POST /api/auth/token` call.
  - **Every** refresh failure (HTTP 401/4xx/5xx, network error, timeout, malformed JSON, missing `refreshToken`) uniformly clears `TbSecureStorage`, increments `sessionGeneration`, closes `TbWebSocketService`, and transitions `authProvider` to `AuthUnauthenticated`.
- **Monotonic `sessionGeneration` Counter:**
  - Incremented atomically on `login`, `loginDemo`, `logout`, `forceLogout`, `switchServerUrl`, and `setSessionMode`.
  - Every in-flight HTTP request, refresh call, and WebSocket callback captures `final gen = sessionGeneration` before `await`. If `gen != currentSessionGeneration` upon completion, the response is **discarded** (never writes tokens, never replays queued requests, never mutates state).
- **Atomic Demo <-> Live & Host-Switch Transition:**
  1. Increment `sessionGeneration`.
  2. Cancel active `Dio` `CancelToken` group.
  3. Close `TbWebSocketService` and clear active subscription registry.
  4. Clear `TbSecureStorage` tokens (when switching host or leaving live session).
  5. Persist new `baseUrl` / `SessionMode` in `TbAppPreferences`.
  6. `ref.invalidate(...)` all domain controllers/caches so zero stale data or credentials cross session boundaries.

### 4.3 Canonical `TbFailure` & `ThingsboardErrorCode` Mapping (`lib/core/api/client/tb_error_mapper.dart`)
`TbErrorMapper.fromException(Object error)` normalizes `DioException` + `ThingsboardErrorResponse` directly from the raw integer `errorCode` (avoiding `thingsboard_pe_client`'s `35` vs `40` enum bug):

| Source (`errorCode` / HTTP / Network) | `TbFailureType` | Client / UI Handling |
| :--- | :--- | :--- |
| `10` (`AUTHENTICATION`) | `invalidCredentials` | Inline login/form error |
| `11` (`JWT_TOKEN_EXPIRED`) | `tokenExpired` | Single-flight `/api/auth/token` refresh; forceLogout on failure |
| `12` (`TENANT_TRIAL_EXPIRED`) | `trialExpired` | Trial/subscription expired dialog |
| `15` (`CREDENTIALS_EXPIRED`) | `passwordExpired` | Prompt change-password flow |
| `20` (`PERMISSION_DENIED`) / HTTP `403` | `permissionDenied` | Explicit RBAC denied notice; **never masked by endpoint fallback** |
| `30`, `31` (`INVALID_ARGUMENTS` / `BAD_REQUEST_PARAMS`) | `validation` | Surface server `message` in form/toast |
| `32` (`ITEM_NOT_FOUND`) / HTTP `404` | `notFound` | Deleted entity state OR documented `404`-only compatibility fallback |
| `33`, `34` (`TOO_MANY_REQUESTS` / `UPDATES`) | `rateLimited` | Cooldown / backoff retry notice |
| `35` (`VERSION_CONFLICT`) / HTTP `409` | `conflict` | Refetch entity `version` & prompt retry |
| `40`, `41` (`SUBSCRIPTION_VIOLATION` / `ENTITIES_LIMIT_EXCEEDED`) | `quotaExceeded` | Surface `subscriptionErrorCode` detail |
| `45` (`PASSWORD_VIOLATION`) | `passwordPolicy` | Highlight password policy rules |
| `2`, `46`, `47`, `50` (`GENERAL`, `DATABASE`, `SETUP_INCOMPLETE`, PE `50`) | `serverError` | Retryable server error banner |
| HTTP `406` (RPC invalid device reply) | `invalidDeviceRpcReply` | Surface RPC payload format error |
| HTTP `504` (RPC timeout / device offline) | `deviceOfflineOrTimeout` | Suggest persistent RPC or check device status |
| `DioExceptionType.connectionError` / `*Timeout` | `networkUnavailable` | Retry button + offer Demo Mode preview |
| Request cancelled (`CancelToken` / `sessionGeneration`) | `cancelled` | Silently ignore |

### 4.4 Explicit Endpoint Compatibility & `404` Fallback Contract
**Rule:** HTTP `403` is NEVER treated as a missing-endpoint signal. Only explicit HTTP `404` (endpoint absent on server version) triggers a documented fallback:

| Endpoint | Trigger Condition | Approved Fallback / Handling |
| :--- | :--- | :--- |
| `GET /api/noauth/mobile`, `GET /api/noauth/whiteLabel/loginWhiteLabelParams` | HTTP `404` (verified on `thingsboard.democloud.xyz`) | Treat feature as unavailable; return `null` and keep local defaults |
| `GET /api/system/info` (post-login) | `200 OK` vs `404`/`403` | Parse server `version` (e.g. `>= 4.4.0` capability flag cached per `sessionGeneration`); if `404`/`403`, leave capability unknown and rely on `404` telemetry fallback |
| `GET /api/plugins/telemetry/{type}/{id}/values/timeseries/history` | **HTTP `404` ONLY** (pre-4.4 server) | Retry `GET .../values/timeseries` with `startTs`, `endTs`, `interval`, `limit`, `agg`, `useStrictDataTypes=true`. Do NOT retry on `400` or `403`. Parse both numeric JSON values and stringified numbers (`double.tryParse`) cleanly. |
| `GET /api/user/dashboards?mobile=true` | **HTTP `404` ONLY** | Fallback to `GET /api/tenant/dashboards` (if `TENANT_ADMIN`) or `GET /api/customer/{customerId}/dashboards` (if `CUSTOMER_USER`). Surface `403` directly as `permissionDenied`. |
| `GET /api/customerInfos/all` | **HTTP `404` ONLY** | Fallback to `GET /api/customers`. Surface `403` directly as `permissionDenied` (and hide Customers nav for `CUSTOMER_USER` via `Authority`). |
| Device profile active/inactive counts | Primary: `POST /api/entitiesQuery/count` (`deviceType` filter + `SERVER_ATTRIBUTE` `active == true/false`) | Fallback if `404`: `GET /api/deviceInfos/all?pageSize=1&page=0&deviceProfileId=...&active=true|false` reading `totalElements`. |

### 4.5 `TbWebSocketService` Contract (`lib/core/api/ws/telemetry_ws_service.dart`)
- **Single Connection (`keepAlive`):** Connects to `wss://<host>/api/ws` in `SessionMode.live` only; sends `{"authCmd": {"cmdId": 0, "token": "<jwt>"}}` on open.
- **30-Second Application Heartbeat:** Sends a lightweight WebSocket keepalive frame every **30 seconds** (< 90s server inactivity timeout).
- **Socket Generation + Monotonic `cmdId`:** Every connection instance increments `int _socketGeneration`, and subscriptions use `(socketGeneration, cmdId)`. Stale frames from a previous socket generation are dropped.
- **Disposal While Disconnected:** `unsubscribe(cmdId)` immediately removes the entry from `_activeSubscriptions` locally even when the socket is disconnected/reconnecting, guaranteeing reconnect never replays disposed subscriptions.
- **Per-Command Unsubscribe Semantics:**
  - `ENTITY_DATA` -> `ENTITY_DATA_UNSUBSCRIBE`
  - `ENTITY_COUNT` -> `ENTITY_COUNT_UNSUBSCRIBE`
  - `ALARM_DATA` -> `ALARM_DATA_UNSUBSCRIBE`
  - `ALARM_COUNT` -> `ALARM_COUNT_UNSUBSCRIBE`
  - `ALARM_STATUS` -> `ALARM_STATUS_UNSUBSCRIBE`
  - `NOTIFICATIONS` -> `NOTIFICATIONS_UNSUBSCRIBE`
  - `NOTIFICATIONS_COUNT` -> **NO server unsubscribe command exists**; unsubscribe removes local stream listener only.
  - v1 `ATTRIBUTES` / `TIMESERIES` -> resend command with `"unsubscribe": true`.
- **Partial Update Merging & Lifecycle:** Merge incoming telemetry/alarm deltas by `ts >= cachedTs` while preserving untouched keys. `AppLifecycleState.paused` closes the socket cleanly; `AppLifecycleState.resumed` reconnects with fresh JWT and replays remaining `_activeSubscriptions`.

### 4.6 Search, Filter & Pagination Race Guard
Every paged `AsyncNotifier` (`DashboardsNotifier`, `AlarmsNotifier`, `DevicesNotifier`, `AssetsNotifier`, `CustomersNotifier`, `AuditLogsNotifier`, `NotificationsNotifier`) maintains `int _requestSeq` and a `CancelToken`. Overlapping `refresh()`, `loadNextPage()`, or filter/search changes cancel the prior request and discard any response whose `_requestSeq` is stale.

### 4.7 Demo Data Parity Fixes (`lib/core/mock/mock_data.dart`)
- Fix `MockAlarm.copyWith` using a sentinel / `bool clearAssignee = false` parameter so `assign(id, null)` genuinely clears `assigneeName`.
- Compute `MockDeviceProfile` `activeCount` / `inactiveCount` dynamically from the `MockDevice` dataset so profile counts match the device list 100%.

---

## 5. Material Design 3 Design System & Minimal-Text IoT Rules

- **M3 Opt-In (`lib/config/themes/tb_theme.dart`):** `ThemeData(useMaterial3: true, typography: Typography.material2021(), ...)` for both `tbLightTheme()` and `tbDarkTheme()`. `main.dart` watches `themeModeProvider` (`ThemeMode.system` / `light` / `dark`).
- **Unified Brand Palette (`app_colors.dart`):** Seeded from ThingsBoard PE Blue `#305680` with secondary `#527DAD` and high-contrast CTA accent `#E65100` (removing `Colors.teal[800]` conflict).
- **`TbStatusColors` (`ThemeExtension<TbStatusColors>`):** Distinct light & dark foreground + container tokens for `critical`, `major`, `minor`, `warning`, `indeterminate`, `cleared`, `online`, `offline`, `demo`.
- **`DesignTokens` (`design_tokens.dart`):** Fix `paddingZero` (keep `@Deprecated('Use paddingZero')` alias for `paddigZero` until Wave 4 cleanup), `minTouchTarget = 48.0`, breakpoints `compactMaxWidth = 600.0`, `mediumMaxWidth = 840.0`.
- **Minimal-Text IoT UI ("gọn gàng ít chữ nhất"):**
  - Numeric telemetry uses `FontFeature.tabularFigures()`.
  - Empty/error states: 1 short title (2–4 words) + 1 action button.
  - Entity rows: max 3 scannable lines (Name + 1-word status badge, Type icon + label, 2–3 metric pills or relative timestamp).
  - Progressive disclosure via tabs / `ModalBottomSheet`; avoid nested elevated cards.
- **Adaptive Breakpoints:**
  - `< 600dp`: bottom `NavigationBar`
  - `600..839dp`: `NavigationRail`
  - `>= 840dp`: `NavigationRail` + **2-pane master-detail** for **Dashboards, Alarms, Devices, Assets, and Customers** (consistent across `ui-rules.md` and this spec).
- **Accessibility:** `>= 48dp x 48dp` targets, `Semantics` on icon controls/badges/charts, `ExcludeSemantics` on decorative art, `2.0x` text scaling verified without clipping or overflow.

---

## 6. Custom Icon Identity (`TbIcons`) & GPU-Safe Motion

- **Custom Icon Kit (`lib/widgets/icons/tb_icons.dart` + `tb_icon_painters.dart`):** `24dp` viewBox, `1.75dp` stroke, rounded caps/joins, themed via `IconTheme.of(context).color` / `colorScheme`, wrapped in `RepaintBoundary`:
  - **Nav (active/outlined):** `navHome`, `navAlarms`, `navDevices`, `navMore`
  - **Entities:** `sensorNode`, `gateway`, `energyMeter`, `gpsTracker`, `waterSensor`, `thermostat`, `actuator`, `assetBuilding`, `customerOrg`, `dashboardTile`, `auditLog`, `notificationInbox`
  - **Telemetry & Control:** `temperature`, `humidity`, `voltagePower`, `signalRssi`, `battery`, `flowRate`, `rpcCommand`, `attributesTag`, `relationsGraph`
  - **Shape-Distinct Alarm Severities:** `severityCritical` (octagon+`!`), `severityMajor` (triangle+`!`), `severityMinor` (diamond+dot), `severityWarning` (circle+`!`), `severityIndeterminate` (dashed circle+`?`), `statusCleared` (shield+check)
  - **Session/Scanner:** `livePulse`, `offlineNode`, `demoFlask`, `qrFrame`
- **GPU-Safe Motion (`lib/widgets/tb_motion.dart`, `tb_shimmer.dart`, `lib/utils/transition/page_transitions.dart`):**
  - Only `Transform`, `Opacity`, `FadeTransition`, `ScaleTransition`, `SlideTransition`, `Hero`, `AnimatedSwitcher`.
  - All `AnimationController`s disposed cleanly; `MediaQuery.disableAnimationsOf(context)` collapses transitions/shimmers/staggers cleanly.

---

## 7. Complete Routeable Screen Inventory (21 Routeable Destinations)

### 7.1 `GoRouter` Tree & `refreshListenable` Contract
- `RouterRefreshNotifier` (`ChangeNotifier`) listens to `authProvider` and drives `GoRouter.refreshListenable`.
- **Redirect Matrix:**
  - Public routes: `/login`, `/login/resetPasswordRequest`, `/qrCodeScan`, `/oauth2/callback`.
  - `AuthMfaVerificationRequired` -> `/login/2fa` (stay if already on `/login/2fa`; back navigation cancels MFA and returns to `/login`).
  - `AuthMfaConfigurationRequired` -> `/login/2fa-setup`.
  - `AuthUnauthenticated` on protected route -> `/login?from=<encoded>`.
  - `AuthAuthenticated` on `/login*` or `/oauth2/callback` -> `from` param if safe internal path, else `/home`.

### 7.2 Complete Screen & Page Table (21 Routeable Pages)

| # | Route | Page Class | Core Contract & UI Notes |
| :--- | :--- | :--- | :--- |
| 1 | `/login` | `LoginPage` | Email/password `POST /api/auth/login`, Server URL sheet, `"Try Demo Mode"` (`SessionMode.demo`), dynamic OAuth2 (`POST /api/noauth/oauth2Clients`), QR link. |
| 2 | `/login/resetPasswordRequest` | `ResetPasswordRequestPage` | `POST /api/noauth/resetPasswordByEmail`, concise 1-line subtitle, M3 `FilledButton`. |
| 3 | `/login/2fa` | `TwoFactorAuthPage` | Handles `PRE_VERIFICATION_TOKEN`: `/api/auth/2fa/providers`, `/verification/send`, `/verification/check` 6-digit OTP; back button clears pending MFA token. |
| 4 | `/login/2fa-setup` | `MfaSetupPage` | Handles `MFA_CONFIGURATION_TOKEN`: displays setup status/TOTP/OTP guidance (`/api/auth/2fa/account/*` or web portal link) + back to login. |
| 5 | `/oauth2/callback` | `OAuthCallbackPage` | Handles cold-start & warm-start `org.thingsboard.pe.app.auth://` deep links (`accessToken` + `refreshToken` query params) -> `AuthController.completeOAuth2()`. |
| 6 | `/qrCodeScan` | `QrCodeScannerPage` | `mobile_scanner` live viewfinder, torch toggle, `GET /api/noauth/qr/{secret}` login or `POST /api/customer/device/{name}/claim`, plus Demo simulated scan. |
| 7 | `/home` (Shell Branch 0) | `HomePage` | Replaces `HomePlaceholderPage`. Home Dashboard summary (`GET /api/dashboard/home/info`), active alarms & online/offline KPI strip, recent/starred horizontal dashboards rail, `DEMO` pill when in `SessionMode.demo`. |
| 8 | `/home/dashboards` | `DashboardsPage` | Paginated `GET /api/user/dashboards?mobile=true`, `All`/`Starred` chips, debounced search, `STAR`/`UNSTAR`, `Hero`, tablet multi-col / 2-pane. |
| 9 | `/dashboard/:id` | `DashboardDetailsPage` | `GET /api/dashboard/{id}`, live WS `ENTITY_DATA` tiles + `SparklinePainter` (`1h`/`24h`/`7d`, `useStrictDataTypes=true`, `404`-only history fallback), fullscreen toggle, external WebView/browser open option. |
| 10 | `/alarms` (Shell Branch 1) | `AlarmsPage` | Paginated `GET /api/v2/alarms`, WS `ALARM_DATA`, M3 `FilterChip` sheet (`statusList`, `severityList`), `TbIcons` severity glyphs, quick Ack/Clear, 2-pane on `>=840dp`. |
| 11 | `/alarms/search` | `AlarmsPage(searchMode: true)` | Debounced `textSearch` query against `/api/v2/alarms`. |
| 12 | `/alarms/alarmDetails/:id` | `AlarmDetailsPage` | `GET /api/alarm/info/{id}`, `GET /api/users/assign/{alarmId}` picker sheet (with unassign clearing `assigneeName`), working Activity refresh + optimistic comments (`/comment`), Ack/Clear confirmation sheet. |
| 13 | `/devices` (Shell Branch 2) | `DevicesMainPage` | All Devices summary + 2-col profile grid (`GET /api/deviceProfileInfos` + count queries, synced in Demo mode) with `TbIcons` device glyphs. |
| 14 | `/devices/deviceList` | `DevicesListPage` | Paginated `GET /api/deviceInfos/all` (`deviceProfileId`, `active`, `textSearch` debounced), `TbStatusBadge`, `Hero`, 2-pane on `>=840dp`. |
| 15 | `/devices/deviceDetails/:id` | `DeviceDetailsPage` | 5 segments: `Telemetry` (live WS + `SparklinePainter` history), `Attributes` (`SERVER`/`SHARED`/`CLIENT` read+edit), `RPC` (`oneway`/`twoway` + persistent history w/ `504`/`406` handling), `Alarms` (`/api/v2/alarm/DEVICE/{id}`), `Info` + Relations. |
| 16 | `/more` (Shell Branch 3) | `MorePage` | User summary, role-aware links (Customers, Assets, Audit Logs, Notifications w/ WS badge, Profile & Settings), `SessionMode` pill, Logout. |
| 17 | `/customers` | `CustomersPage` | Paginated `GET /api/customerInfos/all` (`404`-only fallback to `/api/customers`; `403` surfaced cleanly), 3-line cards, 2-pane on `>=840dp`. |
| 18 | `/customers/:id` | `CustomerDetailsPage` | `GET /api/customer/info/{id}`, contact quick-actions (tel/mailto via `url_launcher`), customer-scoped devices/assets/dashboards counts & drill-down. |
| 19 | `/assets` | `AssetsPage` | Paginated `GET /api/assetInfos/all` + profile filter chips, `TbIcons.assetBuilding`, 2-pane on `>=840dp`. |
| 20 | `/assets/:id` | `AssetDetailsPage` | `GET /api/asset/info/{id}`, shared Telemetry/Attributes/Alarms/Relations (`/api/relations/info/from/ASSET/{id}`) tabs. |
| 21 | `/auditLogs`, `/notifications`, `/profile` | `AuditLogsPage`, `NotificationsPage`, `ProfileSettingsPage` | `AuditLogsPage`: `/api/audit/logs`, status/search filters, JSON `ModalBottomSheet` (`2.0x` safe). `NotificationsPage`: `/api/notifications`, All/Unread toggle, multi-select mark-read/delete, WS live count. `ProfileSettingsPage`: `/api/auth/user` + `/api/user`, change password (persisting returned fresh `JwtPair`!), ThemeMode (`System`/`Light`/`Dark`), `SessionMode` switch, notification prefs (`/api/notification/settings/user`). |

*(Total distinct routeable UI pages = **23** including `AuditLogsPage`, `NotificationsPage`, `ProfileSettingsPage` separately, covering every feature and detail view cleanly.)*

---

## 8. Dependencies & Android Build Configuration

### 8.1 `pubspec.yaml`
- Bump `environment.sdk` to `^3.11.0` (verified installed toolchain: **Flutter 3.50.0 / Dart 3.14.0**).
- Keep `hooks_riverpod: ^2.6.1`, `flutter_hooks: ^0.21.2`, `go_router: ^17.0.0`, `dio: ^5.8.0+1`, `reactive_forms: ^18.2.2`, `flutter_svg: ^2.2.2`, `google_fonts: ^6.3.2`, `intl: ^0.20.2`, `auto_size_text: ^3.0.0`, `toastification: ^2.3.0`, `collection: ^1.19.1`.
- Add: `flutter_secure_storage: ^11.2.0`, `jwt_decoder: ^2.0.1`, `web_socket_channel: ^3.0.3`, `mobile_scanner: ^7.5.0`, `url_launcher: ^6.3.3`, `shared_preferences: ^2.5.6`.
- Note: Caret ranges resolve against `pubspec.lock` during Wave 1 `flutter pub get`; exact resolved versions and `pubspec.lock` compatibility with AGP 9.3.1 are verified at Wave 1 exit.

### 8.2 Android Build, Kotlin DSL, `minSdk` & Manifest
- **`android/app/build.gradle.kts` & `android/gradle.properties`:**
  - Existing config has `android.builtInKotlin=false` in `gradle.properties`, AGP `9.3.1` + Kotlin `2.4.20` in `settings.gradle.kts`, and `kotlin { compilerOptions { jvmTarget = JvmTarget.JVM_17 } }` in `app/build.gradle.kts`.
  - Verify plugin compilation after adding `flutter_secure_storage` / `mobile_scanner` / `shared_preferences` / `url_launcher`; if AGP 9.3.1 + `android.builtInKotlin=false` requires explicit `id("org.jetbrains.kotlin.android")` or migrating to built-in Kotlin per Flutter's AGP/Kotlin migration guide, reconcile cleanly in Wave 1C and verify via `flutter build apk --debug`.
  - **Pin `minSdk = 24`** (or `maxOf(flutter.minSdkVersion, 24)`) because `shared_preferences: 2.5.6` and `url_launcher: 6.3.3` have Android API 24 floors (higher than `mobile_scanner` / `flutter_secure_storage`'s API 23 floor).
  - Document resolved `compileSdk`, `targetSdk`, `minSdk`, and `ndkVersion` (`28.2.13676358` installed).
  - Keep `applicationId = "com.example.thingsboard_democloud_app"` for local debug APK testing; note custom reverse-DNS `applicationId` as required before Play Store release.
- **`android/app/src/main/AndroidManifest.xml`:**
  - Add `<uses-permission android:name="android.permission.INTERNET" />` and `<uses-permission android:name="android.permission.CAMERA" />`.
  - Set `android:label="ThingsBoard PE"`.
  - Add OAuth2 deep-link `<intent-filter>` (`VIEW`, `DEFAULT`, `BROWSABLE`, `android:scheme="org.thingsboard.pe.app.auth"`).
  - Apply `assets/branding/` adaptive launcher icons & Android 12 splash resources.

---

## 9. Testing, Static Audit & Device Verification Decisions
- **Behavior-First Seams:** Repository + controller tests (`ProviderContainer` + `MockDioAdapter` + `FakeTbStorage` + `FakeWebSocketChannel`) and screen widget tests (`ProviderScope` overrides).
- **Mandatory Coverage:**
  - All `TbFailure` codes (`2, 10, 11, 12, 15, 20, 30, 31, 32, 33, 34, 35, 40, 41, 45, 46, 47, 50`, `406`, `504`, network).
  - Concurrent proactive + reactive JWT refresh lock, `sessionGeneration` cancellation on logout/host/mode switch, search/filter/pagination race cancellation.
  - Distinct `PRE_VERIFICATION_TOKEN` & `MFA_CONFIGURATION_TOKEN` flows, cold-start OAuth deep-link callback, `MockAlarm` unassign & `MockDeviceProfile` count parity.
  - Every one of the 23 routeable pages tested (4 states + Light/Dark M3 + `TbStatusColors` + `>=48dp` targets + `Semantics` + `2.0x` text scaling + `disableAnimations: true`).
- **Quality Gates:**
  - `flutter analyze` (0 issues)
  - `dart format --output=none --set-exit-if-changed .`
  - `flutter test` (100% pass, zero skipped/relaxed assertions)
  - `python .agents/skills/flutter-ui/scripts/flutter_ui_audit.py .` (**0 `RED` findings + all `YELLOW` findings reviewed and either fixed or explicitly justified**)
  - `flutter build apk --debug` + Gradle daemon cleanup (`gradlew --stop`) + **separate** live Android emulator / `adb` deep-link + screenshot walkthrough + live `https://thingsboard.democloud.xyz/` public-endpoint smoke test.
