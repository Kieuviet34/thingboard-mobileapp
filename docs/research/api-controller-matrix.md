# API Controller & Riverpod State Provider Architecture Matrix

> **Target Codebase:** `thingboard-mobileapp` (`hooks_riverpod: ^2.6.1`, `dio: ^5.8.0+1`, `go_router: ^17.0.0`)
> **Companion Reference:** [`docs/research/thingsboard-pe-api.md`](./thingsboard-pe-api.md)
> **Scope:** Complete mapping from `lib/core/mock/mock_data.dart` and `lib/core/auth/login/provider/auth_provider.dart` to production `lib/core/api/` repositories, immutable Dart domain/DTO models, Riverpod providers, pagination/caching, `ThingsboardErrorCode` mapping, and Live vs. Demo/Offline mode support.

---

## 1. Cross-Cutting Infrastructure (`lib/core/api/` & `lib/core/models/`)

### 1.1 Recommended Layering
Keep UI widgets decoupled from transport details (and from `built_value` if `thingsboard_pe_client` is used, or direct JSON if custom `Dio` is used) via a 3-layer boundary:

```text
lib/modules/<feature>/*          -> Riverpod Notifiers/AsyncNotifiers + UI screens
lib/core/api/controllers/*       -> Typed Repository / Controller classes (1 per domain)
lib/core/api/client/*            -> Dio + AuthInterceptor + TelemetryWsService + TbErrorMapper
lib/core/mock/*                  -> Seeded Demo/Offline fixtures behind the same repository interfaces
```

### 1.2 Shared Core Types

#### `PageData<T>` & `PageQuery`
```dart
@immutable
class PageQuery {
  const PageQuery({
    this.page = 0,
    this.pageSize = 20,
    this.textSearch,
    this.sortProperty = 'createdTime',
    this.sortOrder = SortOrder.desc,
  });
  final int page;
  final int pageSize;
  final String? textSearch;
  final String sortProperty;
  final SortOrder sortOrder;
}

@immutable
class PageData<T> {
  const PageData({
    required this.data,
    required this.totalPages,
    required this.totalElements,
    required this.hasNext,
  });
  final List<T> data;
  final int totalPages;
  final int totalElements;
  final bool hasNext;
}

@immutable
class PagedListState<T> {
  const PagedListState({
    this.items = const [],
    this.page = 0,
    this.hasNext = false,
    this.totalElements = 0,
    this.isLoadingMore = false,
    this.loadMoreError,
  });
  final List<T> items;
  final int page;
  final bool hasNext;
  final int totalElements;
  final bool isLoadingMore;
  final TbFailure? loadMoreError;
}
```

#### `TbFailure` & `ThingsboardErrorCode` Mapping
Raw `errorCode` integers from `ThingsboardErrorResponse` should be mapped directly in `TbErrorMapper.fromDioException(Object e)` (note: `thingsboard_pe_client: 4.4.1`'s built-in `ThingsBoardErrorCode` enum maps `subscriptionViolation(35)` instead of `40` and omits `41`/`47`/`50`, so always normalize from the raw JSON `errorCode` integer):

| `errorCode` | Meaning | HTTP | `TbFailureType` | UI / App Action |
| :--- | :--- | :--- | :--- | :--- |
| `10` | `AUTHENTICATION` | `401` | `invalidCredentials` | Show inline credential error |
| `11` | `JWT_TOKEN_EXPIRED` | `401` | `tokenExpired` | Intercept & single-flight refresh; logout if refresh fails |
| `12` | `TENANT_TRIAL_EXPIRED` | `401`/`403` | `trialExpired` | Show subscription/trial expired dialog |
| `15` | `CREDENTIALS_EXPIRED` | `401` | `passwordExpired` | Route to change-password flow |
| `20` | `PERMISSION_DENIED` | `403` | `permissionDenied` | Show non-blocking permission notice |
| `30`, `31` | `INVALID_ARGUMENTS` / `BAD_REQUEST_PARAMS` | `400` | `validation` | Surface server `message` in form/toast |
| `32` | `ITEM_NOT_FOUND` | `404` | `notFound` | Handle deleted entity or optional-endpoint `404` fallback |
| `33`, `34` | `TOO_MANY_REQUESTS` / `TOO_MANY_UPDATES` | `429`/WS | `rateLimited` | Exponential backoff + retry toast |
| `35` | `VERSION_CONFLICT` | `409` | `conflict` | Refetch entity `version` and prompt user |
| `40`, `41` | `SUBSCRIPTION_VIOLATION` / `ENTITIES_LIMIT_EXCEEDED` | `403` | `quotaExceeded` | Show `subscriptionErrorCode` detail |
| `45` | `PASSWORD_VIOLATION` | `400` | `passwordPolicy` | Highlight password policy rules |
| `2`, `46`, `47`, `50` | `GENERAL` / `DATABASE` / `SETUP_INCOMPLETE` / PE `50` | `500`/`400` | `serverError` | Generic retryable error |
| Network/Timeout | `DioExceptionType.connectionError` / `*Timeout` | — | `networkUnavailable` | Offer Retry or Switch to Demo/Offline Preview |

---

## 2. Controller & Provider Inventory (13 Controllers)

| # | Controller / Service | Location (`lib/core/api/`) | Primary Riverpod Providers |
| :--- | :--- | :--- | :--- |
| 1 | `ServerConfigController` | `controllers/server_config_controller.dart` | `serverConfigProvider` (`NotifierProvider`, `keepAlive`) |
| 2 | `AuthController` | `controllers/auth_controller.dart` | `authProvider` (`AsyncNotifierProvider<AuthController, AuthState>`) |
| 3 | `DashboardController` | `controllers/dashboard_controller.dart` | `dashboardsProvider`, `homeDashboardProvider`, `dashboardDetailsProvider(id)` |
| 4 | `AlarmController` | `controllers/alarm_controller.dart` | `alarmsProvider`, `alarmDetailsProvider(id)`, `alarmCommentsProvider(id)`, `alarmAssigneesProvider(id)` |
| 5 | `DeviceController` | `controllers/device_controller.dart` | `deviceProfilesProvider`, `devicesProvider`, `deviceDetailsProvider(id)`, `deviceCredentialsProvider(id)` |
| 6 | `AssetController` | `controllers/asset_controller.dart` | `assetProfilesProvider`, `assetsProvider`, `assetDetailsProvider(id)`, `entityRelationsProvider(key)` |
| 7 | `CustomerController` | `controllers/customer_controller.dart` | `customersProvider`, `customerDetailsProvider(id)` |
| 8 | `TelemetryController` | `controllers/telemetry_controller.dart` | `entityAttributesProvider(key)`, `entityLatestTelemetryProvider(key)`, `entityTelemetryHistoryProvider(query)` |
| 9 | `TelemetryWsService` | `ws/telemetry_ws_service.dart` | `telemetryWsServiceProvider` (`Provider`, `keepAlive`), `wsConnectionStateProvider` |
| 10 | `RpcController` | `controllers/rpc_controller.dart` | `rpcControllerProvider`, `persistentRpcsProvider(deviceId)` |
| 11 | `NotificationController` | `controllers/notification_controller.dart` | `notificationsProvider`, `unreadNotificationsCountProvider`, `notificationSettingsProvider` |
| 12 | `AuditLogController` | `controllers/audit_log_controller.dart` | `auditLogsProvider(filter)` |
| 13 | `UserProfileController` | `controllers/user_profile_controller.dart` | `userProfileProvider`, `userSettingsProvider(type)` |

---

## 3. Detailed Controller Matrix

### 3.1 `ServerConfigController`
Manages target ThingsBoard base URL (`https://thingsboard.democloud.xyz/` default), **Live vs. Demo Mode** toggle, and server capability probing.

- **Endpoints:**
  - `GET /api/noauth/userPasswordPolicy` (public; verified `200 OK` on `democloud.xyz`)
  - `POST /api/noauth/oauth2Clients?pkgName=<pkg>&platform=<ANDROID|IOS>` (public; verified `200 OK` on `democloud.xyz`)
  - `GET /api/noauth/mobile?pkgName=<pkg>&platform=<ANDROID|IOS>` (optional PE 4.x; **404 on `democloud.xyz`** — treat `404` as unavailable)
  - `GET /api/noauth/whiteLabel/loginWhiteLabelParams` (optional PE; **404 on `democloud.xyz`** — treat `404` as unavailable)
  - `GET /api/system/info` (authenticated; returns platform `version` / `type` to detect TB 4.4+ vs older)
- **Models:**
  - `AppConnectionMode` enum: `live`, `demo`
  - `ServerConfigState`: `{baseUrl, mode, passwordPolicy, oauthClients, mobileInfo?, whiteLabel?, serverVersion?}`
- **Riverpod Signatures:**
  - `final serverConfigProvider = NotifierProvider<ServerConfigController, ServerConfigState>(ServerConfigController.new);`
  - `final dioClientProvider = Provider<Dio>(...);` (watches `serverConfigProvider.select((s) => s.baseUrl)`, attaches `TbAuthInterceptor`)
- **Demo / Offline Fallback:** Switching to `AppConnectionMode.demo` bypasses network auth/REST calls across all controllers and serves deterministic mutable in-memory copies of `mock_data.dart` fixtures; persisted in `SharedPreferences` (non-sensitive URL & mode only).

---

### 3.2 `AuthController`
Replaces simulated `AuthNotifier` in `lib/core/auth/login/provider/auth_provider.dart` and backs `GoRouter` redirect guards.

- **Endpoints:**
  - `POST /api/auth/login` -> `{"username", "password"}` -> `LoginResponse {token, refreshToken, scope}`
  - `POST /api/auth/token` -> `{"refreshToken"}` -> `LoginResponse {token, refreshToken, scope}`
  - `POST /api/auth/logout` (authenticated) -> `200 OK`
  - `GET /api/auth/user` -> `User`
  - `POST /api/noauth/resetPasswordByEmail` -> `{"email"}`
  - `POST /api/auth/changePassword` -> `{"currentPassword", "newPassword"}` -> `JwtPair`
  - `GET /api/auth/2fa/providers`, `POST /api/auth/2fa/verification/send`, `POST /api/auth/2fa/verification/check` -> `JwtPair`
  - `GET /api/noauth/qr/{secret}` -> `JwtPair`
- **Models:**
  - `TbAuthSession`: `{accessToken, refreshToken, userId, email, authority (Authority), tenantId, customerId, expiresAt}`
  - `AuthState` sealed/union: `unauthenticated`, `loading`, `mfaRequired(providers, preAuthToken)`, `authenticated(session, user, isDemo)`
- **Riverpod Signatures:**
  - `final authProvider = AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);`
  - Methods: `login(email, password)`, `loginDemo()`, `loginWithQrSecret(secret)`, `completeOAuth2(token, refreshToken)`, `verify2fa(provider, code)`, `requestPasswordReset(email)`, `logout()`.
- **Caching / Refresh:**
  - Store `accessToken` + `refreshToken` in `FlutterSecureStorage`.
  - On app launch (`build()`), restore tokens -> decode JWT `exp` -> if expired or within 60s skew, run `POST /api/auth/token` -> fetch `GET /api/auth/user`.
  - `TbAuthInterceptor` (`QueuedInterceptor`) uses a `Completer<void>` single-flight gate on HTTP `401` (`errorCode == 11`) so concurrent requests trigger only one refresh call.
- **Error Mapping:** `10` -> invalid email/password; `15` -> route to change password; `33` -> rate-limited cooldown notice; `45` -> password policy failure.
- **Demo / Offline Fallback:** `loginDemo()` creates a synthetic `TbAuthSession` (`TENANT_ADMIN`, `tenant@thingsboard.org`, `isDemo: true`) without network calls; `logout()` resets demo state.

---

### 3.3 `DashboardController`
Powers `Home` (home dashboard + recent/starred) and `DashboardsPage` / `DashboardDetailsPage`.

- **Endpoints:**
  - `GET /api/user/dashboards` (`pageSize`, `page`, `mobile=true`, `textSearch`, `sortProperty`, `sortOrder`) -> `PageData<DashboardInfo>`
  - Fallback if `403`/`404` on older server: `GET /api/tenant/dashboards` or `GET /api/customer/{customerId}/dashboards`
  - `GET /api/dashboard/home/info` -> `HomeDashboardInfo {dashboardId, hideDashboardToolbar}`
  - `GET /api/dashboard/home` -> `HomeDashboard`
  - `GET /api/dashboard/{dashboardId}` (`includeResources=true`) -> `Dashboard`
  - `GET /api/user/lastVisitedDashboards` -> `UserDashboardsInfo {last, starred}`
  - `GET /api/user/dashboards/{dashboardId}/{action}` (`VISIT` | `STAR` | `UNSTAR`) -> `UserDashboardsInfo`
- **Models:**
  - `TbDashboardInfo`: `{id, title, image, mobileHide, mobileOrder, assignedCustomers, createdTime}`
  - `TbDashboard`: extends info with `configuration` JSON (for extracting entity aliases/widgets or rendering via WebView)
  - `TbHomeDashboardInfo`: `{dashboardId, hideToolbar}`
- **Riverpod Signatures:**
  - `final dashboardsProvider = AsyncNotifierProvider.autoDispose.family<DashboardsNotifier, PagedListState<TbDashboardInfo>, String?>(DashboardsNotifier.new);` (arg = search query)
  - `final homeDashboardProvider = FutureProvider.autoDispose<TbHomeDashboardInfo?>(...);`
  - `final userDashboardsInfoProvider = AsyncNotifierProvider.autoDispose<UserDashboardsInfoNotifier, UserDashboardsInfo>(...);`
  - `final dashboardDetailsProvider = FutureProvider.autoDispose.family<TbDashboard, String>(...);`
- **Caching / Pagination:** Page size `20`, pull-to-refresh invalidates page 0; `keepAlive` cache for `homeDashboardProvider` invalidated on logout.
- **Demo / Offline Fallback:** Maps `MockDashboard` list (`dash-1`..`dash-6`), marks `dash-1` as `HomeDashboard`, and stores `lastVisited` / `starred` in memory.

---

### 3.4 `AlarmController`
Powers `AlarmsPage`, `AlarmDetailsPage`, and home alarm summary badges.

- **Endpoints:**
  - `GET /api/v2/alarms` (`pageSize`, `page`, `statusList`, `severityList`, `typeList`, `assigneeId`, `startTime`, `endTime`, `textSearch`, `sortProperty`, `sortOrder`) -> `PageData<AlarmInfo>`
  - `GET /api/v2/alarm/{entityType}/{entityId}` -> `PageData<AlarmInfo>` (for `DeviceDetailsPage` / `AssetDetailsPage` Alarms tab)
  - `POST /api/alarmsQuery/find` & `POST /api/alarmsQuery/count` -> `PageData<AlarmData>` / `int`
  - `GET /api/alarm/info/{alarmId}` -> `AlarmInfo`
  - `POST /api/alarm/{alarmId}/ack` -> `AlarmInfo`
  - `POST /api/alarm/{alarmId}/clear` -> `AlarmInfo`
  - `POST /api/alarm/{alarmId}/assign/{assigneeId}` & `DELETE /api/alarm/{alarmId}/assign` -> `AlarmInfo`
  - `DELETE /api/alarm/{alarmId}` -> `bool`
  - `GET /api/alarm/types` (`pageSize`, `page`, `textSearch`) -> `PageData<EntitySubtype>`
  - `GET /api/users/assign/{alarmId}` (`pageSize`, `page`, `textSearch`) -> `PageData<UserEmailInfo>`
  - `GET /api/alarm/{alarmId}/comment` (`pageSize`, `page`, `sortProperty=createdTime`, `sortOrder=DESC`) -> `PageData<AlarmCommentInfo>`
  - `POST /api/alarm/{alarmId}/comment` -> `{"comment": {"text": "..."}}` -> `AlarmComment`
  - `DELETE /api/alarm/{alarmId}/comment/{commentId}` -> `200 OK`
- **Models:**
  - `TbAlarmFilter`: `{textSearch, statusList (Set<AlarmSearchStatus>), severityList (Set<AlarmSeverity>), typeList, assigneeId, startTime, endTime, originatorId?}`
  - `TbAlarmInfo`: `{id, type, severity, status, acknowledged, cleared, createdTime, startTs, ackTs, clearTs, originator (EntityId), originatorName, originatorDisplayName, assigneeId, assignee (Email/Name), details}`
  - `TbAlarmComment`: `{id, alarmId, userId, type (SYSTEM|OTHER), text, authorName, authorEmail, createdTime}`
- **Riverpod Signatures:**
  - `final alarmFilterProvider = StateProvider.autoDispose<TbAlarmFilter>((ref) => const TbAlarmFilter());`
  - `final alarmsProvider = AsyncNotifierProvider.autoDispose.family<AlarmsNotifier, PagedListState<TbAlarmInfo>, EntityId?>(AlarmsNotifier.new);` (null = all alarms, non-null = entity alarms)
  - `final alarmDetailsProvider = AsyncNotifierProvider.autoDispose.family<AlarmDetailsNotifier, TbAlarmInfo, String>(AlarmDetailsNotifier.new);`
  - `final alarmCommentsProvider = AsyncNotifierProvider.autoDispose.family<AlarmCommentsNotifier, PagedListState<TbAlarmComment>, String>(AlarmCommentsNotifier.new);`
  - `final alarmAssigneesProvider = FutureProvider.autoDispose.family<List<TbUserEmailInfo>, ({String alarmId, String search})>(...);`
- **Real-Time & Optimistic Updates:** Subscribe to `ALARM_COUNT` / `ALARM_DATA` via `TelemetryWsService`; `acknowledge`, `clear`, `assign` update local state optimistically and rollback on `TbFailure` (`32` not found / `20` permission denied).
- **Demo / Offline Fallback:** Uses `MockAlarm` + `MockAlarmComment` in-memory store with client-side filtering matching `statusList` (`ACTIVE`, `CLEARED`, `ACK`, `UNACK`) and `severityList`.

---

### 3.5 `DeviceController`
Powers `DevicesMainPage` (profiles + active/inactive counts), `DevicesListPage`, and `DeviceDetailsPage`.

- **Endpoints:**
  - `GET /api/deviceInfos/all` (`pageSize`, `page`, `includeCustomers=true`, `deviceProfileId`, `active`, `textSearch`, `sortProperty`, `sortOrder`) -> `PageData<DeviceInfo>`
  - `GET /api/customer/{customerId}/deviceInfos` -> `PageData<DeviceInfo>` (fallback if customer user)
  - `POST /api/entitiesQuery/count` (using `deviceType` filter + `active` `ATTRIBUTE` `KeyFilter` to compute per-profile active/inactive counts accurately without downloading all devices)
  - `GET /api/deviceProfileInfos` (`pageSize`, `page`, `textSearch`) -> `PageData<DeviceProfileInfo>`
  - `GET /api/device/info/{deviceId}` -> `DeviceInfo`
  - `POST /api/device` & `DELETE /api/device/{deviceId}`
  - `GET /api/device/{deviceId}/credentials` -> `DeviceCredentials`
  - `POST /api/customer/device/{deviceName}/claim` -> `ClaimRequest` -> `ClaimResult`
- **Models:**
  - `TbDeviceProfileSummary`: `{id, name, image, defaultDashboardId, transportType, activeCount, inactiveCount}`
  - `TbDeviceInfo`: `{id, name, label, type, deviceProfileId, active, customerId, ownerName, createdTime, additionalInfo, latestTelemetry}`
  - `TbDeviceCredentials`: `{id, deviceId, credentialsType, credentialsId, credentialsValue}`
- **Riverpod Signatures:**
  - `final deviceProfilesProvider = AsyncNotifierProvider.autoDispose<DeviceProfilesNotifier, PagedListState<TbDeviceProfileSummary>>(DeviceProfilesNotifier.new);`
  - `final devicesProvider = AsyncNotifierProvider.autoDispose.family<DevicesNotifier, PagedListState<TbDeviceInfo>, TbDeviceQuery>(DevicesNotifier.new);`
  - `final deviceDetailsProvider = FutureProvider.autoDispose.family<TbDeviceInfo, String>(...);`
  - `final deviceCredentialsProvider = FutureProvider.autoDispose.family<TbDeviceCredentials, String>(...);`
- **Error Mapping:** `32` (`ITEM_NOT_FOUND`) on deleted device; `41` (`ENTITIES_LIMIT_EXCEEDED`) on device creation; `20` (`PERMISSION_DENIED`) when `CUSTOMER_USER` requests credentials.
- **Demo / Offline Fallback:** Serves `MockDeviceProfile` (with dynamically computed counts from `MockDevice` list so profile counts never drift!) and `MockDevice`.

---

### 3.6 `AssetController`
Powers `AssetsPage`, `AssetDetailsPage`, and Entity Relations drill-down (e.g., Building Asset -> Contained Devices).

- **Endpoints:**
  - `GET /api/assetInfos/all` (`pageSize`, `page`, `includeCustomers=true`, `assetProfileId`, `textSearch`, `sortProperty`, `sortOrder`) -> `PageData<AssetInfo>`
  - `GET /api/customer/{customerId}/assetInfos` -> `PageData<AssetInfo>`
  - `GET /api/asset/info/{assetId}` -> `AssetInfo`
  - `POST /api/asset` & `DELETE /api/asset/{assetId}`
  - `GET /api/assetProfileInfos` (`pageSize`, `page`, `textSearch`) -> `PageData<AssetProfileInfo>`
  - `GET /api/relations/info/from/{fromType}/{fromId}` & `GET /api/relations/info/to/{toType}/{toId}` -> `List<EntityRelationInfo>`
- **Models:**
  - `TbAssetInfo`: `{id, name, type, label, assetProfileId, customerId, ownerName, createdTime, additionalInfo}`
  - `TbEntityRelationInfo`: `{from (EntityId), to (EntityId), type, typeGroup, fromName, toName}`
- **Riverpod Signatures:**
  - `final assetsProvider = AsyncNotifierProvider.autoDispose.family<AssetsNotifier, PagedListState<TbAssetInfo>, TbAssetQuery>(AssetsNotifier.new);`
  - `final assetDetailsProvider = FutureProvider.autoDispose.family<TbAssetInfo, String>(...);`
  - `final entityRelationsProvider = FutureProvider.autoDispose.family<List<TbEntityRelationInfo>, ({EntityId entity, bool outgoing})>(...);`
- **Demo / Offline Fallback:** Serves `MockAsset` list and synthetic `Contains` relations linking `asset-1..4` to `dev-1..6`.

---

### 3.7 `CustomerController`
Powers `CustomersPage` and `CustomerDetailsPage` (including customer's devices/assets/dashboards).

- **Endpoints:**
  - `GET /api/customerInfos/all` (`pageSize`, `page`, `includeCustomers=true`, `textSearch`, `sortProperty`, `sortOrder`) -> `PageData<CustomerInfo>`
  - Fallback for CE/non-PE-hierarchy: `GET /api/customers` (`pageSize`, `page`, `textSearch`, `sortProperty`, `sortOrder`) -> `PageData<Customer>`
  - `GET /api/customer/info/{customerId}` (or `GET /api/customer/{customerId}`) -> `CustomerInfo`
  - `POST /api/customer` & `DELETE /api/customer/{customerId}`
- **Models:**
  - `TbCustomerInfo`: `{id, title, country, state, city, address, address2, zip, phone, email, parentCustomerId, createdTime}`
- **Riverpod Signatures:**
  - `final customersProvider = AsyncNotifierProvider.autoDispose.family<CustomersNotifier, PagedListState<TbCustomerInfo>, String?>(CustomersNotifier.new);`
  - `final customerDetailsProvider = FutureProvider.autoDispose.family<TbCustomerInfo, String>(...);`
- **Error Mapping:** `20` (`PERMISSION_DENIED`) when logged in as `CUSTOMER_USER` without customer-list permissions -> hide Customers entry from `MorePage` based on `Authority` + `user-permissions-controller` (`GET /api/permissions/allowedPermissions`).
- **Demo / Offline Fallback:** Serves `MockCustomer` list.

---

### 3.8 `TelemetryController` (REST Attributes & Time Series)
Handles one-shot reads/writes/history for Device/Asset details (Attributes tab, Telemetry history charts, Shared attribute editing).

- **Endpoints:**
  - `GET /api/plugins/telemetry/{entityType}/{entityId}/keys/attributes` & `.../keys/attributes/{scope}` -> `List<String>`
  - `GET /api/plugins/telemetry/{entityType}/{entityId}/values/attributes/{scope}` (`keys`) -> `List<AttributeKvEntry>`
  - `POST /api/plugins/telemetry/{entityType}/{entityId}/attributes/{scope}` (`SERVER_SCOPE` | `SHARED_SCOPE`) -> `200 OK`
  - `DELETE /api/plugins/telemetry/{entityType}/{entityId}/{scope}?keys=...` -> `200 OK`
  - `GET /api/plugins/telemetry/{entityType}/{entityId}/keys/timeseries` -> `List<String>`
  - `GET /api/plugins/telemetry/{entityType}/{entityId}/values/timeseries` (`keys`, `useStrictDataTypes=true`) -> `Map<String, List<TsKvEntry>>`
  - `GET /api/plugins/telemetry/{entityType}/{entityId}/values/timeseries/history` (`keys`, `startTs`, `endTs`, `interval`, `limit`, `agg`, `orderBy`, `useStrictDataTypes=true`) -> `Map<String, List<TsKvEntry>>`
    - *Compatibility note:* If server < 4.4 returns `404` on `/values/timeseries/history`, retry `GET .../values/timeseries` with `startTs`/`endTs` query params.
- **Models:**
  - `TbAttributeScope`: `serverScope`, `sharedScope`, `clientScope`
  - `TbAttributeEntry`: `{key, value, lastUpdateTs, scope}`
  - `TbTsPoint`: `{ts, rawValue, numericValue?}`
  - `TbTsHistoryQuery`: `{entityId, keys, startTs, endTs, intervalMs, limit, agg (NONE|MIN|MAX|AVG|SUM|COUNT)}`
- **Riverpod Signatures:**
  - `final entityAttributesProvider = AsyncNotifierProvider.autoDispose.family<EntityAttributesNotifier, List<TbAttributeEntry>, ({EntityId id, TbAttributeScope scope})>(...);`
  - `final entityLatestTelemetryProvider = FutureProvider.autoDispose.family<Map<String, TbTsPoint>, EntityId>(...);`
  - `final entityTelemetryHistoryProvider = FutureProvider.autoDispose.family<Map<String, List<TbTsPoint>>, TbTsHistoryQuery>(...);`
- **Demo / Offline Fallback:** Maps `MockDevice.telemetry` to `TbTsPoint` entries and simulates 24h sine/step history points for chart preview.

---

### 3.9 `TelemetryWsService` (Shared WebSocket Multiplexer)
Single `keepAlive` WebSocket connection to `wss://<host>/api/ws` multiplexing all real-time streams.

- **Protocol & Lifecycle:**
  1. Connect on `authProvider` becoming `authenticated` (Live mode only).
  2. Immediately send `{"authCmd": {"cmdId": 0, "token": "<JWT>"}}` (re-authenticate with fresh JWT on reconnect).
  3. Maintain monotonic `int _nextCmdId` (`1, 2, ...`) and an active subscription registry `Map<int, WsCommand>` so **on reconnect** (network switch or app resume from background), all active subscriptions are automatically re-sent.
  4. Send lightweight keepalive / ping every **45 seconds** (< 90s server inactivity timeout).
  5. Close socket cleanly on `logout()` or `AppLifecycleState.paused` (with automatic resume-reconnect).
- **Supported Commands & Streams:**
  - `ENTITY_DATA` / `ENTITY_DATA_UNSUBSCRIBE` (`latestCmd`, `tsCmd`, `historyCmd`) -> `Stream<EntityDataUpdate>`
  - `ENTITY_COUNT` / `ENTITY_COUNT_UNSUBSCRIBE` -> `Stream<int>`
  - `ALARM_DATA` / `ALARM_DATA_UNSUBSCRIBE` -> `Stream<AlarmDataUpdate>`
  - `ALARM_COUNT` / `ALARM_COUNT_UNSUBSCRIBE` -> `Stream<int>`
  - `ALARM_STATUS` / `ALARM_STATUS_UNSUBSCRIBE` -> `Stream<bool>`
  - `NOTIFICATIONS` / `NOTIFICATIONS_UNSUBSCRIBE` -> `Stream<NotificationsUpdate>`
  - `NOTIFICATIONS_COUNT` -> `Stream<int>`
  - Legacy v1 `ATTRIBUTES` & `TIMESERIES` (`"unsubscribe": true`) -> `Stream<SubscriptionDataUpdate>`
- **Riverpod Signatures:**
  - `final telemetryWsServiceProvider = Provider<TelemetryWsService>(...);` (`ref.keepAlive()`, `ref.onDispose(...)`)
  - `final wsConnectionStateProvider = StreamProvider<WsConnectionState>(...);` (`disconnected`, `connecting`, `authenticated`, `reconnecting`)
  - `final liveEntityTelemetryProvider = StreamProvider.autoDispose.family<Map<String, TbTsPoint>, ({EntityId id, List<String> keys})>(...);`
- **Error Mapping:** `errorCode == 3` (`UNAUTHORIZED`) -> refresh JWT & reconnect; `errorCode == 4` (`ACCESS_DENIED`) -> surface permission failure on stream; WS close `1007` -> auth rejected.
- **Demo / Offline Fallback:** Never opens a socket in Demo mode; `liveEntityTelemetryProvider` emits initial `MockDevice.telemetry` plus optional periodic simulated jitter if previewing live charts.

---

### 3.10 `RpcController`
Powers Device RPC command execution & persistent command history on `DeviceDetailsPage`.

- **Endpoints:**
  - `POST /api/rpc/oneway/{deviceId}` -> `{"method", "params", "timeout", "persistent", "retries"}`
  - `POST /api/rpc/twoway/{deviceId}` -> returns device JSON response
  - `GET /api/rpc/persistent/device/{deviceId}` (`pageSize`, `page`, `rpcStatus`, `sortProperty`, `sortOrder`) -> `PageData<Rpc>`
  - `GET /api/rpc/persistent/{rpcId}` -> `Rpc`
  - `DELETE /api/rpc/persistent/{rpcId}` -> `200 OK`
- **Models:**
  - `TbRpcRequest`: `{method, params (Map<String, dynamic>), timeoutMs (default 10000, min 5000), persistent (false), retries (0)}`
  - `TbPersistentRpc`: `{id, deviceId, createdTime, expirationTime, request, response, status (RpcStatus)}`
- **Riverpod Signatures:**
  - `final rpcControllerProvider = AsyncNotifierProvider.autoDispose<RpcNotifier, AsyncValue<Map<String, dynamic>?>>(RpcNotifier.new);`
  - `final persistentRpcsProvider = AsyncNotifierProvider.autoDispose.family<PersistentRpcsNotifier, PagedListState<TbPersistentRpc>, String>(PersistentRpcsNotifier.new);`
- **Error Mapping:** HTTP `504` (no body) -> `TbFailure.deviceOfflineOrTimeout` (guide UI to suggest `persistent: true` or check `lastConnectTime`/`lastDisconnectTime`); HTTP `406` -> `TbFailure.invalidDeviceRpcReply`.
- **Demo / Offline Fallback:** Returns simulated echo response for active `MockDevice`, `504`-equivalent timeout failure for offline `MockDevice` (matching `MockAuditLog` `log-3` behavior!).

---

### 3.11 `NotificationController`
Powers `NotificationsPage`, app bar unread badge, and FCM push token registration.

- **Endpoints:**
  - `GET /api/notifications` (`pageSize`, `page`, `unreadOnly`, `deliveryMethod`, `textSearch`, `sortProperty`, `sortOrder`) -> `PageData<Notification>`
  - `GET /api/notifications/unread/count` (`deliveryMethod`) -> `int`
  - `PUT /api/notification/{id}/read` -> `200 OK`
  - `PUT /api/notifications/read` (`deliveryMethod`) -> `200 OK`
  - `DELETE /api/notification/{id}` -> `200 OK`
  - `GET` / `POST /api/notification/settings/user` -> `UserNotificationSettings`
  - `POST` / `DELETE /api/user/mobile/session` (header `X-Mobile-Token: <fcmToken>`, body `{"fcmTokenTimestamp": ms}`)
  - WebSocket: `NOTIFICATIONS`, `NOTIFICATIONS_COUNT`, `MARK_NOTIFICATIONS_AS_READ`, `MARK_ALL_NOTIFICATIONS_AS_READ`.
- **Models:**
  - `TbNotification`: `{id, requestId, type (NotificationType), deliveryMethod, subject, text, isRead (status == READ), createdTime, info}`
- **Riverpod Signatures:**
  - `final notificationsProvider = AsyncNotifierProvider.autoDispose.family<NotificationsNotifier, PagedListState<TbNotification>, bool>(NotificationsNotifier.new);` (arg = `unreadOnly`)
  - `final unreadNotificationsCountProvider = StreamProvider.autoDispose<int>(...);` (WS `NOTIFICATIONS_COUNT` in Live mode, derived from `notificationsProvider` in Demo mode)
- **Demo / Offline Fallback:** Uses `NotificationsStateNotifier` / `MockNotificationItem` fixtures with full mark-read / mark-all-read / delete / bulk-delete support.

---

### 3.12 `AuditLogController`
Powers `AuditLogsPage` (tenant-wide) and entity/user audit history tabs.

- **Endpoints:**
  - `GET /api/audit/logs` (`pageSize`, `page`, `startTime`, `endTime`, `actionTypes`, `textSearch`, `sortProperty`, `sortOrder`) -> `PageData<AuditLog>`
  - `GET /api/audit/logs/entity/{entityType}/{entityId}` -> `PageData<AuditLog>`
  - `GET /api/audit/logs/user/{userId}` -> `PageData<AuditLog>`
  - `GET /api/audit/logs/customer/{customerId}` -> `PageData<AuditLog>`
- **Models:**
  - `TbAuditLogQuery`: `{scope (tenant|entity|user|customer), targetId?, entityType?, textSearch, startTime, endTime, actionTypes}`
  - `TbAuditLog`: `{id, entityId, entityName, userId, userName, actionType (ActionType), actionStatus (SUCCESS|FAILURE), actionData, actionFailureDetails, createdTime}`
- **Riverpod Signatures:**
  - `final auditLogsProvider = AsyncNotifierProvider.autoDispose.family<AuditLogsNotifier, PagedListState<TbAuditLog>, TbAuditLogQuery>(AuditLogsNotifier.new);`
- **Error Mapping:** `20` (`PERMISSION_DENIED`) when `CUSTOMER_USER` opens tenant audit logs -> show role-restricted empty state.
- **Demo / Offline Fallback:** Serves `MockAuditLog` list filtered by `textSearch` and `actionType`.

---

### 3.13 `UserProfileController`
Powers `ProfilePage`, `SettingsPage`, and user avatar/initials across the app.

- **Endpoints:**
  - `GET /api/auth/user` -> `User`
  - `GET /api/user/info/{userId}` -> `UserInfo`
  - `POST /api/user` -> `User` (update `firstName`, `lastName`, `phone`, `additionalInfo`)
  - `GET /api/user/settings/general` & `PUT /api/user/settings/general` -> `JsonNode`
  - `GET /api/user/settings/MOBILE` & `PUT /api/user/settings/MOBILE` -> `JsonNode` (unit system, language, mobile prefs)
  - `POST /api/auth/changePassword` -> `ChangePasswordRequest` -> `JwtPair` (persist refreshed tokens!)
- **Models:**
  - `TbUserProfile`: `{id, email, firstName, lastName, phone, authority, tenantId, customerId, ownerName, language, unitSystem, homeDashboardId, hideHomeDashboardToolbar}`
- **Riverpod Signatures:**
  - `final userProfileProvider = AsyncNotifierProvider<UserProfileController, TbUserProfile>(UserProfileController.new);`
- **Demo / Offline Fallback:** Maps `MockUserProfile` (`John Doe`, `tenant@thingsboard.org`), persisting edits in memory during the Demo session.

---

## 4. Migration Mapping from Existing `lib/core/mock/mock_data.dart`

| Current `mock_data.dart` Symbol | Target Production Provider | Notes for Migration |
| :--- | :--- | :--- |
| `authProvider` (`auth_provider.dart`) | `authProvider` (`AuthController`) | Keep provider name; upgrade `StateNotifier<AuthUiState>` to `AsyncNotifier<AuthState>` + `FlutterSecureStorage` + Demo mode branch |
| `dashboardsProvider` | `dashboardsProvider(null)` | Replace `List<MockDashboard>` with `PagedListState<TbDashboardInfo>` |
| `alarmsProvider` | `alarmsProvider(null)` + `alarmDetailsProvider(id)` | Preserve optimistic `acknowledge`/`clear`/`assign`/`addComment` UX |
| `deviceProfilesProvider` | `deviceProfilesProvider` | Compute live `activeCount`/`inactiveCount` via `entitiesQuery/count` |
| `devicesProvider` | `devicesProvider(query)` + `deviceDetailsProvider(id)` | Combine `deviceInfos/all` with `TelemetryWsService` on details screen |
| `customersProvider` | `customersProvider(search)` | Role-guard visibility for `CUSTOMER_USER` |
| `assetsProvider` | `assetsProvider(query)` | Add `entityRelationsProvider` for Asset -> Device hierarchy |
| `auditLogsProvider` | `auditLogsProvider(query)` | Add `actionTypes` + time-range filtering & pagination |
| `notificationsProvider` | `notificationsProvider(unreadOnly)` + `unreadNotificationsCountProvider` | Wire WS unread badge + mark-read/delete actions |
| `userProfileProvider` | `userProfileProvider` | Sync `GET /api/auth/user` + `GET /api/user/settings/*` + `GET /api/dashboard/home/info` |
