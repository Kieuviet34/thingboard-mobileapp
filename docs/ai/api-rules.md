# API, State, WebSocket & QA Rules

> Grounded in [thingsboard-pe-api.md](../research/thingsboard-pe-api.md), `.agents/skills/api-designer/SKILL.md`, and `.agents/skills/tdd/SKILL.md`.
> All API, repository, provider, and test work MUST follow these rules.

---

## 1. Layering & State Management
- **Single State Stack:** Keep `hooks_riverpod` (`^2.6.1`) + `flutter_hooks` + `dio` (`^5.8.0+1`) + `go_router` (`^17.0.0`). Never introduce Bloc, Provider, GetX, or a second HTTP client.
- **Strict Boundaries:**
  - **UI (`lib/modules/*/view`, `lib/widgets/`):** Watches Riverpod state, triggers controller actions, handles navigation/toasts. Zero raw URLs, JSON parsing, or `Dio` calls.
  - **Controllers (`AsyncNotifier` / `Notifier` / `StateNotifier`):** Own screen/session state, pagination, search/debounce, optimistic mutations with rollback, and error mapping.
  - **Repositories / Services (`lib/core/api/`):** Typed ThingsBoard PE REST calls (via `Dio` / `thingsboard_pe_client` facade) and `TbWebSocketService`. Return immutable domain models (`const` classes with `copyWith`, value equality).
- **Secrets & Storage:**
  - Store `jwtToken`, `refreshToken`, and optional API keys ONLY in `flutter_secure_storage` (never `SharedPreferences`, never committed in code, never logged via `print`/`debugPrint`/`pretty_dio_logger` in release builds).

---

## 2. Authentication & `X-Authorization` Lifecycle
- **Header Name:** ThingsBoard requires `X-Authorization: Bearer <jwt>` (or `X-Authorization: ApiKey <key>`). NEVER send `Authorization: Bearer ...`.
- **Single-Flight Refresh & `sessionGeneration` Guard:**
  - Attach `X-Authorization: Bearer <token>` in a `QueuedInterceptor` (skip `/api/auth/login`, `/api/auth/token`, `/api/noauth/**`).
  - Proactive `exp` check (`jwt_decoder`) and reactive HTTP `401` (`errorCode == 11`, `JWT_TOKEN_EXPIRED`) MUST share the **same** single-flight refresh lock calling `POST /api/auth/token` with `{"refreshToken": ...}`, persisting the new `JwtPair`, and replaying queued requests.
  - Maintain a monotonic `sessionGeneration` counter incremented on `logout()`, server host switch, and `SessionMode` toggle (`live` <-> `demo`). Any refresh response or REST/WS callback from an older `sessionGeneration` MUST be discarded so stale responses cannot revive a logged-out or switched session.
  - If refresh fails (`401`, timeout, or invalid payload), clear secure storage, increment `sessionGeneration`, set `isAuthenticated = false`, and let `GoRouter` (`refreshListenable`) redirect to `/login`.
- **2FA, OAuth2 & QR Login:**
  - Handle `LoginResponse.scope == 'PRE_VERIFICATION_TOKEN'` (2FA OTP verification via `/api/auth/2fa/providers`, `/verification/send`, `/verification/check`) and `LoginResponse.scope == 'MFA_CONFIGURATION_TOKEN'` (mandatory 2FA setup flow) as distinct auth states.
  - OAuth2 clients fetched via `POST /api/noauth/oauth2Clients?pkgName=...&platform=ANDROID|IOS` returning to `ThingsboardAppConstants.thingsboardOAuth2CallbackUrlScheme` (`org.thingsboard.pe.app.auth`).
  - QR scan handles both login secrets (`GET /api/noauth/qr/{secret}`) and device claiming (`POST /api/customer/device/{deviceName}/claim`).
- **GoRouter Auth Guard:** Protect all authenticated routes (`/home`, `/dashboards`, `/alarms`, `/devices`, `/assets`, `/customers`, `/notifications`, `/auditLogs`, `/more`, `/profile`, `/settings`) via `GoRouter.redirect`; allow `/login`, `/login/resetPasswordRequest`, `/qrCodeScan` unauthenticated.

---

## 3. REST Compatibility & Graceful Degradation
- **Pagination Standard:** Every collection endpoint uses `PageData<T>` (`pageSize`, `page` zero-based, `textSearch`, `sortProperty`, `sortOrder`: `ASC`/`DESC`). Support pull-to-refresh and incremental `loadNextPage` when `hasNext == true`. Guard against search/filter/pagination race conditions (discard stale page/search responses when query or generation changes).
- **Preferred PE Endpoints:**
  - Devices: `GET /api/deviceInfos/all`, `GET /api/device/info/{id}`, `GET /api/deviceProfileInfos`.
  - Alarms: `GET /api/v2/alarms` (multi-filter `statusList`, `severityList`), `POST /api/alarm/{id}/ack|clear|assign/{userId}`, `GET/POST /api/alarm/{id}/comment`, `GET /api/users/assign/{alarmId}`.
  - Dashboards: `GET /api/dashboard/home/info`, `GET /api/user/dashboards?mobile=true`, `GET /api/user/lastVisitedDashboards`, `GET /api/user/dashboards/{id}/{VISIT|STAR|UNSTAR}`.
  - Assets & Customers: `GET /api/assetInfos/all`, `GET /api/customerInfos/all`, `GET /api/relations/info/from/{type}/{id}`.
  - Telemetry & RPC: `GET /api/plugins/telemetry/{type}/{id}/values/timeseries` (latest; pass `useStrictDataTypes=true` when numeric values are needed), `GET .../values/timeseries/history` (`startTs`, `endTs`, `agg`, `interval`, `limit`, `useStrictDataTypes=true`) for charts; `POST /api/rpc/twoway/{deviceId}` & `oneway` (timeout >= `5000`ms).
  - Notifications, Audit & Profile: `GET /api/notifications`, `GET /api/notifications/unread/count`, `PUT /api/notification/{id}/read`, `GET /api/audit/logs`, `GET /api/auth/user`, `POST /api/auth/changePassword` (persist returned `JwtPair`), `GET/PUT /api/user/settings/general`.
- **`404` vs `403` Fallback Rules:**
  - **Never silently mask `403 PERMISSION_DENIED`:** Do NOT swallow `403` on Dashboards, Customers, or other role-restricted endpoints by silently falling back to a broader endpoint; map `403` to `TbFailure` (`permissionDenied`) and show an explicit permission state.
  - **Pre-4.4 Telemetry Fallback (`404` only):** If `GET /api/plugins/telemetry/{type}/{id}/values/timeseries/history` returns HTTP `404`, fall back to `GET .../values/timeseries` with `startTs` & `endTs` (do NOT fall back on `400` or `403`).
  - **Graceful `404` Startup Fallbacks:** Because `https://thingsboard.democloud.xyz/` returns `404` for `/api/noauth/mobile`, `/api/noauth/whiteLabel/loginWhiteLabelParams`, `/api/noauth/selfRegistration/signUpSelfRegistrationParams`, and `/v3/api-docs`, wrap optional metadata/white-label/mobile-bundle probes in `try/catch`, treating `404` as feature-unavailable and falling back cleanly to local defaults.

---

## 4. WebSocket (`wss://<host>/api/ws`) Rules
- **Single Shared Connection:** Maintain ONE `keepAlive` `TbWebSocketService` per authenticated `SessionMode.live` session (`wss://<host>/api/ws`). Never open per-widget WebSocket connections. Close and clear all subscriptions atomically on `logout()`, host change, or `SessionMode.demo` switch (`sessionGeneration` bump).
- **Auth & Multiplexing:** Send `authCmd` (`{ "authCmd": { "cmdId": 0, "token": "<jwt>" } }`) as the first frame; allocate monotonically increasing integer `cmdId`s per subscription (`ENTITY_DATA`, `ENTITY_COUNT`, `ALARM_DATA`, `ALARM_COUNT`, `NOTIFICATIONS`, `NOTIFICATIONS_COUNT`, `ATTRIBUTES`, `TIMESERIES`). Ignore stale frames from closed socket generations.
- **Heartbeat & Lifecycle:** ThingsBoard closes idle sockets after **90 seconds**. Send a **`30s` app-level heartbeat** (`< 90s` server timeout). On `AppLifecycleState.resumed` or socket disconnect, reconnect with exponential backoff + jitter and re-register active subscriptions with clean `cmdId` mapping.
- **Clean Unsubscribe:** Every Riverpod provider / screen subscribing to a `cmdId` MUST remove local subscription intent in `ref.onDispose` / `dispose()` (even when the socket is currently disconnected so it does not replay on reconnect), and send the corresponding `*_UNSUBSCRIBE` (or `"unsubscribe": true` for v1) when connected — **except `NOTIFICATIONS_COUNT`**, which has **no** server unsubscribe command (cancel locally without sending an unsupported frame).

---

## 5. Demo / Offline Mode Support
- Support two explicit runtime session modes via `SessionMode`: `SessionMode.live` (real ThingsBoard PE server) and `SessionMode.demo` (offline/preview mode backed by `lib/core/mock/mock_data.dart` datasets).
- All repositories/controllers share the same domain models and `TbFailure` contracts across `SessionMode.live` and `SessionMode.demo` so every screen works identically without a live server, while displaying a subtle `DEMO` indicator pill in the shell/header when in `SessionMode.demo`.
- Mutations in `SessionMode.demo` (ack/clear/assign/unassign alarm, add comment, mark notification read, edit profile) MUST update in-memory provider state immediately so QA/UI flows work end-to-end.

---

## 6. Error Handling, QA & Testing Rules
- **Typed Error Normalization (`TbFailure`):** Parse `ThingsboardErrorResponse` (`status`, `errorCode`, `message`, `subscriptionErrorCode`) into canonical **`TbFailure`**:
  - Handle all `ThingsboardErrorCode` values: `2` (`GENERAL`), `10` (`AUTHENTICATION`), `11` (`JWT_TOKEN_EXPIRED`), `12` (`JWT_TOKEN_NOT_VALID` / token invalid), `15` (`CREDENTIALS_EXPIRED`), `20` (`PERMISSION_DENIED`), `30` (`INVALID_ARGUMENTS`), `31` (`BAD_REQUEST_PARAMS`), `32` (`ITEM_NOT_FOUND`), `33` (`TOO_MANY_REQUESTS`), `34` (`TOO_MANY_UPDATES`), `35` (`VERSION_CONFLICT`), `40` (`SUBSCRIPTION_VIOLATION`), `41` (`ENTITIES_LIMIT_EXCEEDED`), `45` (`PASSWORD_VIOLATION`), `46` (`DATABASE`), `47` (`SETUP_INCOMPLETE`), `50` (PE-specific restriction), plus HTTP `504` (device offline / RPC timeout), HTTP `406` (invalid RPC device JSON response), and network offline/timeout.
  - Never expose raw stack traces or raw Dio errors in UI; show concise actionable messages and preserve form inputs.
- **TDD & Automated Verification:**
  - Write unit tests for interceptors, token refresh single-flight, error mapping, JSON/DTO parsing, WebSocket subscription manager, and Riverpod notifiers using mocked `Dio` (`HttpClientAdapter`) and `ProviderContainer` overrides.
  - Write widget tests for every screen covering loading, data, empty, error-retry, accessibility semantics, and `demo` mode interactions.
  - Never skip or weaken assertions to make tests pass.
  - Mandatory verification after code changes:
    1. `flutter analyze` (zero errors/warnings)
    2. `flutter test` (all tests pass)
    3. `dart format --output=none --set-exit-if-changed .` (or `dart format .`)
    4. `flutter build apk --debug` (for Android/manifest/plugin/release-affecting changes)
