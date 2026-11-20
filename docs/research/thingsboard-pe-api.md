# ThingsBoard PE API & Dart SDK Research Reference

> **Target Workspace:** `thingboard-mobileapp` (`dio: ^5.8.0+1`, `hooks_riverpod: ^2.6.1`, `go_router: ^17.0.0`, `collection: ^1.19.1`)
> **Primary Sources:**
> - ThingsBoard PE Docs Hub: `https://thingsboard.io/docs/pe/apis-and-sdks/`
> - REST API Reference: `https://thingsboard.io/docs/pe/reference/rest-api/`
> - WebSocket API Reference: `https://thingsboard.io/docs/pe/reference/websocket-api/`
> - Entity Data Query API: `https://thingsboard.io/docs/pe/reference/data-query-api/`
> - Alarm Query API: `https://thingsboard.io/docs/pe/reference/alarm-query-api/`
> - Dart API Client Docs: `https://thingsboard.io/docs/pe/reference/dart-client/`
> - Mobile App Reference: `https://thingsboard.io/docs/pe/reference/mobile-app/`
> - Live OpenAPI 3.1.0 Spec (PE `4.4.1PAAS`, 745 paths): `https://thingsboard.cloud/v3/api-docs` (`https://thingsboard.cloud/swagger-ui/index.html`)

---

## 1. Official Dart / Flutter SDK & OpenAPI Findings

### 1.1 Official Dart Packages (`pub.dev`)
ThingsBoard officially publishes **auto-generated** OpenAPI Dart clients (built on `dio` + `built_value` + `web_socket_channel`) with a handwritten runtime facade for JWT auth/refresh, API key auth, WebSocket `TelemetrySubscriber`, and typed error normalization:

| Package | Target Platform | Latest Version | Min Server Version | Status |
| :--- | :--- | :--- | :--- | :--- |
| **`thingsboard_pe_client`** | ThingsBoard PE & ThingsBoard Cloud | **`4.4.1`** | `4.4.0` | **Recommended** (used by official `flutter_thingsboard_pe_app` >= 1.9.0) |
| `thingsboard_ce_client` | ThingsBoard Community Edition | `4.3.0` | `4.3.0` | CE only |
| `thingsboard_client` / legacy `thingsboard_pe_client` (<= 4.2.1) | Legacy CE/PE (`>= 3.6.3`) | `4.2.1` | `3.6.3` | Deprecated handwritten client (`dart_thingsboard_client`) |

**Key technical details of `thingsboard_pe_client: ^4.4.1`:**
- **Dependencies (`pub.dev`):** `dio: ^5.7.0`, `web_socket_channel: ^3.0.3`, `built_value: >=8.4.0 <9.0.0`, `built_collection: >=5.1.1 <6.0.0`, `one_of: >=1.5.0 <2.0.0`, `one_of_serializer: >=1.5.0 <2.0.0`, `jwt_decoder: ^2.0.1`, `collection: >=1.15.0 <2.0.0`, `pretty_dio_logger: ^1.4.0`.
- **Compatibility with this repo (`pubspec.yaml`):** Repo already has `sdk: ^3.7.0`, `dio: ^5.8.0+1`, and `collection: ^1.19.1` — **no dependency conflicts** with `thingsboard_pe_client: ^4.4.1`.
- **Important Import Caveat:** The main barrel exports both generated OpenAPI models and facade types, causing name collisions on `LoginRequest`, `EntityId`, and `EntityType`. Import as:
  ```dart
  import 'package:thingsboard_pe_client/thingsboard_pe_client.dart'
      hide LoginRequest, EntityId, EntityType;
  import 'package:thingsboard_pe_client/src/model/login_models.dart'
      show LoginRequest;
  import 'package:thingsboard_pe_client/src/model/id/entity_id.dart'
      show EntityId;
  import 'package:thingsboard_pe_client/src/model/id/entity_type_models.dart'
      show EntityType;
  ```
- **API Style:** One generated controller class per Swagger tag (`tbClient.getDeviceControllerApi()`, `getAlarmControllerApi()`, `getEntityQueryControllerApi()`, etc.) returning `Future<Response<T>>`, immutable `built_value` models, and `TelemetrySubscriber` over `tbClient.getTelemetryService()`.
- **Storage & Lifecycle:** `ThingsboardClient(endpoint, storage: ..., apiKey: ..., onUserLoaded: ..., onMfaAuth: ..., onMfaForce: ..., onError: ...)` — default storage is `InMemoryStorage` (also bundles `LocalFileStorage`; mobile apps should implement `TbStorage` backed by `flutter_secure_storage`).

### 1.2 OpenAPI / Swagger Endpoints
- Interactive Swagger UI: `<BASE_URL>/swagger-ui.html` or `<BASE_URL>/swagger-ui/index.html`
- OpenAPI 3.1.0 JSON spec: `<BASE_URL>/v3/api-docs` (verified `200 OK` on `https://thingsboard.cloud/v3/api-docs`, `1,852,962` bytes, `745` paths, version `4.4.1PAAS`).
- **Live probe on `https://thingsboard.democloud.xyz/` (repo's `defaultApiEndpoint`):**
  - `GET /api/noauth/userPasswordPolicy` -> `200 OK` (`{"minimumLength":6,...,"allowWhitespaces":true}`)
  - `POST /api/noauth/oauth2Clients?pkgName=org.thingsboard.pe.app&platform=ANDROID` -> `200 OK` (`[]`)
  - `GET /api/noauth/mobile` -> `404 Not Found`
  - `GET /api/noauth/whiteLabel/loginWhiteLabelParams` -> `404 Not Found`
  - `GET /v3/api-docs` -> `404 Not Found`
  - *Implication:* `thingsboard.democloud.xyz` either disables Swagger/noauth mobile-bundle/white-label endpoints or runs an earlier/locked-down server version. Mobile client startup calls to `/api/noauth/mobile` or `/api/noauth/whiteLabel/...` **must fail gracefully** and fall back to local defaults.

---

## 2. Authentication, Headers & Security Flows

### 2.1 Authorization Header (`X-Authorization`)
ThingsBoard does **not** use the standard `Authorization` header for REST calls; it uses **`X-Authorization`**:

1. **JWT Bearer Token (User Sessions — standard for mobile login):**
   ```http
   X-Authorization: Bearer <JWT_TOKEN>
   ```
   - Access token lifetime: **2.5 hours** (9,000s default).
   - Refresh token lifetime: **1 week** (604,800s default).
2. **API Key (Recommended for server/headless integrations; TB >= 4.3):**
   ```http
   X-Authorization: ApiKey <YOUR_API_KEY_VALUE>
   ```
   - Long-lived, inherits owner permissions, revocable in UI or via `/api/apiKey`.
   - If both JWT and API key are sent, **JWT takes priority**.

### 2.2 Auth, 2FA, OAuth2 & QR Code Endpoints

| Method | Endpoint | Auth | Request Body / Query | Response | Notes |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `POST` | `/api/auth/login` | None | `{"username": "...", "password": "..."}` (`LoginRequest`) | `LoginResponse` (`token`, `refreshToken`, `scope`) | `scope` is `Authority` (may be `PRE_VERIFICATION_TOKEN` or `MFA_CONFIGURATION_TOKEN` if 2FA is active) |
| `POST` | `/api/auth/token` | None | `{"refreshToken": "..."}` | `LoginResponse` (`token`, `refreshToken`, `scope`) | Exchange refresh token for new JWT pair |
| `POST` | `/api/auth/logout` | JWT | — | `200 OK` | Invalidates current user session |
| `GET` | `/api/auth/user` | JWT/Key | — | `User` | Fetch currently authenticated user |
| `POST` | `/api/auth/changePassword` | JWT | `{"currentPassword": "...", "newPassword": "..."}` | `JwtPair` | Returns fresh JWT pair on success |
| `POST` | `/api/noauth/resetPasswordByEmail` | None | `{"email": "..."}` | `200 OK` | Triggers password reset email |
| `GET` | `/api/noauth/resetPassword?resetToken=...` | None | `resetToken` (query) | `200 OK` | Validate reset token |
| `POST` | `/api/noauth/resetPassword` | None | `{"resetToken": "...", "password": "..."}` | `200 OK` | Complete password reset |
| `GET` | `/api/noauth/userPasswordPolicy` | None | — | `UserPasswordPolicy` | Min length, uppercase/lowercase/digit/special rules |
| `GET` | `/api/auth/2fa/providers` | Pre-auth JWT | — | `List<TwoFaProviderInfo>` | Available 2FA providers |
| `POST` | `/api/auth/2fa/verification/send?providerType=...` | Pre-auth JWT | `providerType` (query) | `200 OK` | Send OTP code (SMS/Email) |
| `POST` | `/api/auth/2fa/verification/check?providerType=...&verificationCode=...` | Pre-auth JWT | `providerType`, `verificationCode` (query) | `JwtPair` | Upgrades pre-verification token to full `JwtPair` |
| `POST` | `/api/noauth/oauth2Clients` | None | Query: `pkgName`, `platform` (`WEB`/`ANDROID`/`IOS`) | `List<OAuth2ClientLoginInfo>` | `[{name, icon, url}]`; launch `BASE_URL + url` in WebView/CustomTabs |
| `GET` | `/api/noauth/qr/{secret}` | None | `secret` (path) | `JwtPair` | Mobile QR-code login exchange |
| `GET` | `/api/noauth/mobile` | None | Query: `pkgName`, `platform` (`ANDROID`/`IOS`) | `LoginMobileInfo` | OAuth2 clients, self-reg, store/version info (PE 4.x mobile bundle) |

#### JWT Login + Refresh State Machine
```text
1. POST /api/auth/login -> { token, refreshToken, scope }
   ├─ scope == "PRE_VERIFICATION_TOKEN" -> run /api/auth/2fa/verification/send & /check -> full JwtPair
   ├─ scope == "MFA_CONFIGURATION_TOKEN" -> configure 2FA -> POST /api/auth/2fa/login -> full JwtPair
   └─ normal Authority (TENANT_ADMIN / CUSTOMER_USER / SYS_ADMIN) -> authenticated
2. All REST calls attach header: X-Authorization: Bearer <token>
3. On HTTP 401 with errorCode == 11 (JWT_TOKEN_EXPIRED) OR proactive JWT exp check:
   └─ Single-flight POST /api/auth/token {"refreshToken": <refreshToken>}
      ├─ 200 OK -> persist new { token, refreshToken }, retry queued requests
      └─ 401 / failure -> clear secure storage, emit unauthenticated state -> GoRouter redirects to /login
```

---

## 3. Pagination, Sorting & Common Entity Models

### 3.1 Standard Pagination (`PageData<T>`)
Most list `GET` endpoints accept query parameters:
- `pageSize` (**required**, `int32`): items per page
- `page` (**required**, `int32`): zero-based page index (`0`, `1`, ...)
- `textSearch` (optional, `string`): case-insensitive search substring
- `sortProperty` (optional, `string`): entity field name (e.g., `createdTime`, `name`, `title`, `type`, `severity`)
- `sortOrder` (optional, `enum`): `ASC` or `DESC`

**Response envelope (`PageData<T>`):**
```json
{
  "data": [ /* T[] */ ],
  "totalPages": 5,
  "totalElements": 42,
  "hasNext": true
}
```

### 3.2 `EntityId` & `EntityType`
Every ThingsBoard entity uses a typed UUID reference:
```json
{
  "entityType": "DEVICE",
  "id": "784f394c-42b6-435a-983c-b7beff2784f9"
}
```
Common `EntityType` values: `TENANT`, `CUSTOMER`, `USER`, `DASHBOARD`, `ASSET`, `DEVICE`, `ALARM`, `ENTITY_GROUP`, `ENTITY_VIEW`, `DEVICE_PROFILE`, `ASSET_PROFILE`, `EDGE`, `OTA_PACKAGE`, `NOTIFICATION`, `RPC`, `API_KEY`.

Common `Authority` values: `SYS_ADMIN`, `TENANT_ADMIN`, `CUSTOMER_USER` (plus PE/billing/auth token scopes: `BILLING_ADMIN`, `BILLING_SERVICE`, `REFRESH_TOKEN`, `PRE_VERIFICATION_TOKEN`, `MFA_CONFIGURATION_TOKEN`).

---

## 4. Core PE REST API Reference

### 4.1 Devices & Device Profiles (`device-controller`, `device-profile-controller`)

| Method | Endpoint | Key Params / Body | Response | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `GET` | `/api/tenant/devices` | `pageSize`, `page`, `type`, `textSearch`, `sortProperty`, `sortOrder` | `PageData<Device>` | Tenant admin device list |
| `GET` | `/api/customer/{customerId}/devices` | `customerId`, pagination, `type` | `PageData<Device>` | Devices assigned to customer |
| `GET` | `/api/deviceInfos/all` | `pageSize`, `page`, `includeCustomers`, `deviceProfileId`, `active`, `textSearch`, `sortProperty`, `sortOrder` | `PageData<DeviceInfo>` | **Best for mobile UI:** includes `active` boolean, `ownerName`, `groups` |
| `GET` | `/api/customer/{customerId}/deviceInfos` | `customerId`, `pageSize`, `page`, `includeCustomers`, `deviceProfileId`, `active`, `textSearch` | `PageData<DeviceInfo>` | Customer-scoped `DeviceInfo` list |
| `GET` | `/api/user/devices` | `pageSize`, `page`, `type`, `textSearch` | `PageData<Device>` | PE owner/user-group scoped devices |
| `GET` | `/api/entityGroup/{entityGroupId}/devices` | `entityGroupId`, pagination | `PageData<Device>` | PE Entity Group devices |
| `GET` | `/api/device/{deviceId}` | `deviceId` (path) | `Device` | Full device entity |
| `GET` | `/api/device/info/{deviceId}` | `deviceId` (path) | `DeviceInfo` | Device + `active`, `ownerName`, `groups` |
| `POST` | `/api/device` | Body: `Device`; optional query `accessToken`, `entityGroupId`, `entityGroupIds` | `Device` | Create or update device |
| `DELETE` | `/api/device/{deviceId}` | `deviceId` (path) | `200 OK` | Delete device |
| `GET` | `/api/device/{deviceId}/credentials` | `deviceId` (path) | `DeviceCredentials` | `credentialsType`: `ACCESS_TOKEN`, `X509_CERTIFICATE`, `MQTT_BASIC`, `LWM2M_CREDENTIALS` |
| `POST` | `/api/device/credentials` | Body: `DeviceCredentials` | `DeviceCredentials` | Update credentials |
| `POST` | `/api/customer/device/{deviceName}/claim` | Body: `ClaimRequest` (`secretKey`, `durationMs`) | `ClaimResult` | QR-code device claiming |
| `GET` | `/api/deviceProfileInfos` | `pageSize`, `page`, `textSearch`, `transportType` | `PageData<DeviceProfileInfo>` | Device profiles (`id`, `name`, `image`, `defaultDashboardId`, `transportType`) |
| `GET` | `/api/deviceProfile/names` | `activeOnly` (bool) | `List<EntityInfo>` | Lightweight profile name/id pairs |

**`DeviceInfo` key fields:** `id`, `createdTime`, `tenantId`, `customerId`, `ownerId`, `ownerName`, `name`, `type`, `label`, `deviceProfileId`, `firmwareId`, `softwareId`, `active` (`bool`), `groups`, `additionalInfo`, `deviceData`, `version`.

---

### 4.2 Assets & Asset Profiles (`asset-controller`, `asset-profile-controller`)

| Method | Endpoint | Key Params / Body | Response | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `GET` | `/api/tenant/assets` | `pageSize`, `page`, `type`, `textSearch`, `sortProperty`, `sortOrder` | `PageData<Asset>` | Tenant assets |
| `GET` | `/api/customer/{customerId}/assets` | `customerId`, pagination, `type` | `PageData<Asset>` | Customer assets |
| `GET` | `/api/assetInfos/all` | `pageSize`, `page`, `includeCustomers`, `assetProfileId`, `textSearch`, `sortProperty`, `sortOrder` | `PageData<AssetInfo>` | **Best for mobile UI:** includes `ownerName`, `groups` |
| `GET` | `/api/customer/{customerId}/assetInfos` | `customerId`, pagination, `includeCustomers`, `assetProfileId` | `PageData<AssetInfo>` | Customer `AssetInfo` list |
| `GET` | `/api/user/assets` | `pageSize`, `page`, `type`, `assetProfileId`, `textSearch` | `PageData<Asset>` | PE user-scoped assets |
| `GET` | `/api/asset/{assetId}` / `/api/asset/info/{assetId}` | `assetId` (path) | `Asset` / `AssetInfo` | Single asset details |
| `POST` | `/api/asset` | Body: `Asset` (`name` required); optional `entityGroupId(s)` | `Asset` | Create or update asset |
| `DELETE` | `/api/asset/{assetId}` | `assetId` (path) | `200 OK` | Delete asset |
| `GET` | `/api/assetProfileInfos` | Pagination | `PageData<AssetProfileInfo>` | Asset profiles |

---

### 4.3 Customers (`customer-controller`)

| Method | Endpoint | Key Params / Body | Response | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `GET` | `/api/customers` | `pageSize`, `page`, `textSearch`, `sortProperty`, `sortOrder` | `PageData<Customer>` | Tenant customers |
| `GET` | `/api/customerInfos/all` | `pageSize`, `page`, `includeCustomers`, `textSearch` | `PageData<CustomerInfo>` | PE customer infos (hierarchy-aware) |
| `GET` | `/api/customer/{customerId}/customerInfos` | `customerId`, pagination | `PageData<CustomerInfo>` | Sub-customers (PE hierarchy) |
| `GET` | `/api/user/customers` | Pagination | `PageData<Customer>` | PE user-accessible customers |
| `GET` | `/api/customer/{customerId}` / `/api/customer/info/{customerId}` | `customerId` (path) | `Customer` / `CustomerInfo` | Customer details (`title`, `country`, `city`, `state`, `zip`, `address`, `address2`, `phone`, `email`) |
| `POST` | `/api/customer` | Body: `Customer` (`title` required) | `Customer` | Create or update customer |
| `DELETE` | `/api/customer/{customerId}` | `customerId` (path) | `200 OK` | Delete customer |

---

### 4.4 Alarms & Alarm Comments (`alarm-controller`, `alarm-comment-controller`)

| Method | Endpoint | Key Params / Body | Response | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `GET` | `/api/v2/alarms` | `pageSize`, `page`, `statusList` (`ANY`,`ACTIVE`,`CLEARED`,`ACK`,`UNACK`), `severityList` (`CRITICAL`,`MAJOR`,`MINOR`,`WARNING`,`INDETERMINATE`), `typeList`, `assigneeId`, `startTime`, `endTime`, `textSearch`, `sortProperty` (`createdTime`,`startTs`,`endTs`,`type`,`ackTs`,`clearTs`,`severity`,`status`), `sortOrder` | `PageData<AlarmInfo>` | **Preferred v2 multi-filter list** |
| `GET` | `/api/v2/alarm/{entityType}/{entityId}` | Same filters as `/api/v2/alarms`, scoped to originator entity | `PageData<AlarmInfo>` | Device/asset-specific alarms |
| `GET` | `/api/alarms` | Legacy single `searchStatus` / `status` (`ACTIVE_UNACK`, etc.), `fetchOriginator` | `PageData<AlarmInfo>` | Legacy v1 endpoint |
| `GET` | `/api/alarm/info/{alarmId}` | `alarmId` (path) | `AlarmInfo` | Includes `originatorName`, `originatorLabel`, `originatorDisplayName`, `assignee` |
| `POST` | `/api/alarm` | Body: `Alarm` | `Alarm` | Create or update alarm |
| `POST` | `/api/alarm/{alarmId}/ack` | `alarmId` (path) | `AlarmInfo` | Acknowledge alarm |
| `POST` | `/api/alarm/{alarmId}/clear` | `alarmId` (path) | `AlarmInfo` | Clear alarm |
| `POST` | `/api/alarm/{alarmId}/assign/{assigneeId}` | `alarmId`, `assigneeId` (path) | `AlarmInfo` | Assign alarm to user |
| `DELETE` | `/api/alarm/{alarmId}/assign` | `alarmId` (path) | `AlarmInfo` | Unassign alarm |
| `DELETE` | `/api/alarm/{alarmId}` | `alarmId` (path) | `boolean` | Delete alarm |
| `GET` | `/api/alarm/types` | `pageSize`, `page`, `textSearch`, `sortOrder` | `PageData<EntitySubtype>` | Distinct alarm types |
| `GET` | `/api/alarm/{alarmId}/comment` | `alarmId`, `pageSize`, `page`, `sortProperty` (`createdTime`,`id`), `sortOrder` | `PageData<AlarmCommentInfo>` | Includes `firstName`, `lastName`, `email`, `type` (`SYSTEM` \| `OTHER`) |
| `POST` | `/api/alarm/{alarmId}/comment` | Body: `AlarmComment` (`{"comment": {"text": "..."}}`) | `AlarmComment` | Add or update comment |
| `DELETE` | `/api/alarm/{alarmId}/comment/{commentId}` | `alarmId`, `commentId` (path) | `200 OK` | Delete comment |
| `GET` | `/api/users/assign/{alarmId}` | `alarmId`, pagination | `PageData<UserEmailInfo>` | Users eligible for alarm assignment |

---

### 4.5 Dashboards (`dashboard-controller`)

| Method | Endpoint | Key Params / Body | Response | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `GET` | `/api/tenant/dashboards` | `pageSize`, `page`, `mobile` (bool), `textSearch`, `sortProperty`, `sortOrder` | `PageData<DashboardInfo>` | Tenant dashboards (`mobile=true` filters out `mobileHide: true`) |
| `GET` | `/api/customer/{customerId}/dashboards` | `customerId`, pagination | `PageData<DashboardInfo>` | Customer dashboards |
| `GET` | `/api/dashboards/all` | `pageSize`, `page`, `includeCustomers`, `textSearch`, `sortProperty`, `sortOrder` | `PageData<DashboardInfo>` | All accessible dashboards (PE) |
| `GET` | `/api/user/dashboards` | `pageSize`, `page`, `mobile` (bool), `textSearch`, `operation`, `userId` | `PageData<DashboardInfo>` | Current user dashboards |
| `GET` | `/api/dashboard/home` | — | `HomeDashboard` | Full home dashboard + `hideDashboardToolbar` |
| `GET` | `/api/dashboard/home/info` | — | `HomeDashboardInfo` | `{dashboardId, hideDashboardToolbar}` |
| `GET` | `/api/dashboard/{dashboardId}` | `dashboardId` (path), `includeResources` (bool) | `Dashboard` | Full dashboard JSON (`configuration` widgets/states/filters) |
| `GET` | `/api/dashboard/info/{dashboardId}` | `dashboardId` (path) | `DashboardInfo` | Lightweight metadata (`title`, `image`, `mobileHide`, `mobileOrder`) |
| `GET` | `/api/user/lastVisitedDashboards` | — | `UserDashboardsInfo` | `{last: [...], starred: [...]}` |
| `GET` | `/api/user/dashboards/{dashboardId}/{action}` | `dashboardId`, `action` (`VISIT`, `STAR`, `UNSTAR`) | `UserDashboardsInfo` | Record visit or toggle favorite |

---

### 4.6 Telemetry & Attributes (`telemetry-controller`)

Works for any entity (`DEVICE`, `ASSET`, `CUSTOMER`, `ENTITY_VIEW`, etc.).

**Attribute Scopes:**
- `SERVER_SCOPE` — server-side writable via REST
- `SHARED_SCOPE` — server-side writable via REST, readable by devices
- `CLIENT_SCOPE` — reported by devices (**not** writable via REST)

| Method | Endpoint | Key Params / Body | Response |
| :--- | :--- | :--- | :--- |
| `GET` | `/api/plugins/telemetry/{entityType}/{entityId}/keys/attributes` | — | `List<string>` (all scopes) |
| `GET` | `/api/plugins/telemetry/{entityType}/{entityId}/keys/attributes/{scope}` | `scope` | `List<string>` |
| `GET` | `/api/plugins/telemetry/{entityType}/{entityId}/values/attributes` | `keys` (comma-sep) or `key` (array) | `List<{lastUpdateTs, key, value}>` |
| `GET` | `/api/plugins/telemetry/{entityType}/{entityId}/values/attributes/{scope}` | `scope`, `keys` | `List<{lastUpdateTs, key, value}>` |
| `POST` | `/api/plugins/telemetry/{entityType}/{entityId}/attributes/{scope}` | JSON object `{"k": v}` | `200 OK` |
| `DELETE` | `/api/plugins/telemetry/{entityType}/{entityId}/{scope}` | `keys` (comma-sep) | `200 OK` |
| `GET` | `/api/plugins/telemetry/{entityType}/{entityId}/keys/timeseries` | — | `List<string>` |
| `GET` | `/api/plugins/telemetry/{entityType}/{entityId}/values/timeseries` | `keys`, `useStrictDataTypes` (bool, default `false`) | `Map<String, List<{ts, value}>>` (latest values) |
| `GET` | `/api/plugins/telemetry/{entityType}/{entityId}/values/timeseries/history` | **Required:** `startTs`, `endTs`; Optional: `keys`, `agg` (`NONE`,`MIN`,`MAX`,`AVG`,`SUM`,`COUNT`), `interval`, `intervalType`, `limit` (default 100), `orderBy` (`ASC`\|`DESC`), `useStrictDataTypes` | `Map<String, List<{ts, value}>>` |
| `POST` | `/api/plugins/telemetry/{entityType}/{entityId}/values/timeseries` | Body: `List<ReadTsKvQuery>` | `List<TsKvData>` |
| `POST` | `/api/plugins/telemetry/{entityType}/{entityId}/timeseries/{scope}` | `scope` (use `ANY`); Body: `{"k": v}` or `{"ts": ms, "values": {...}}` or array | `200 OK` |
| `DELETE` | `/api/plugins/telemetry/{entityType}/{entityId}/timeseries/delete` | `keys`, `deleteAllDataForKeys`, `startTs`, `endTs`, `deleteLatest`, `rewriteLatestIfDeleted` | `200 OK` |

> **Note on `/values/timeseries` vs `/values/timeseries/history`:** In ThingsBoard `4.4.1` OpenAPI, `GET .../values/timeseries` returns **latest** values only, while historical range queries moved to `GET .../values/timeseries/history` (though the REST docs prose still shows `?startTs=...&endTs=...` on `/values/timeseries` for compatibility). Use `/values/timeseries` without `startTs` for latest, and `/values/timeseries/history` (or WebSocket `TIMESERIES_HISTORY` / `EntityDataCmd.historyCmd`) for charts on TB 4.4+. Also note `value` is returned as a **string** unless `useStrictDataTypes=true`.

---

### 4.7 Entity Data Query & Alarm Data Query (`entity-query-controller`)

Powers dashboard tables, dynamic device/asset filtering, and live WebSocket subscriptions.

| Method | Endpoint | Body | Response |
| :--- | :--- | :--- | :--- |
| `POST` | `/api/entitiesQuery/find` | `EntityDataQuery` | `PageData<EntityData>` |
| `POST` | `/api/entitiesQuery/count` | `EntityCountQuery` (`entityFilter`, `keyFilters`) | `integer` |
| `POST` | `/api/v2/entitiesQuery/find/keys` | `EntityDataQuery` + query `includeTimeseries`, `includeAttributes`, `scopes`, `includeSamples` | `AvailableEntityKeysV2` |
| `POST` | `/api/alarmsQuery/find` | `AlarmDataQuery` | `PageData<AlarmData>` |
| `POST` | `/api/alarmsQuery/count` | `AlarmCountQuery` | `integer` |

**`EntityDataQuery` structure:**
```json
{
  "entityFilter": { "type": "entityType", "entityType": "DEVICE" },
  "pageLink": {
    "pageSize": 20,
    "page": 0,
    "textSearch": "",
    "dynamic": false,
    "sortOrder": { "key": { "type": "ENTITY_FIELD", "key": "createdTime" }, "direction": "DESC" }
  },
  "entityFields": [
    { "type": "ENTITY_FIELD", "key": "name" },
    { "type": "ENTITY_FIELD", "key": "type" },
    { "type": "ENTITY_FIELD", "key": "label" }
  ],
  "latestValues": [
    { "type": "ATTRIBUTE", "key": "active" },
    { "type": "TIME_SERIES", "key": "temperature" }
  ],
  "keyFilters": [
    {
      "key": { "type": "TIME_SERIES", "key": "temperature" },
      "valueType": "NUMERIC",
      "predicate": { "type": "NUMERIC", "operation": "GREATER", "value": { "defaultValue": 30.0 } }
    }
  ]
}
```
- **Entity Filter `type` values:** `entityType`, `singleEntity`, `entityList`, `entityName`, `deviceType`, `assetType`, `edgeType`, `entityViewType`, `relationsQuery` (supports `multiRoot`), `deviceSearchQuery`, `assetSearchQuery`, `edgeSearchQuery`, `entityViewSearchQuery`, `apiUsageState`.
- **Key `type` values:** `ENTITY_FIELD`, `ATTRIBUTE`, `CLIENT_ATTRIBUTE`, `SHARED_ATTRIBUTE`, `SERVER_ATTRIBUTE`, `TIME_SERIES`, plus `ALARM_FIELD` in `AlarmDataQuery` (`createdTime`, `type`, `severity`, `status`, `assignee`, `startTs`, `endTs`, `ackTs`, `clearTs`).
- **`AlarmDataQuery.pageLink` extra fields:** `severityList`, `statusList` (`ANY`, `ACTIVE`, `CLEARED`, `ACK`, `UNACK`), `typeList`, `searchPropagatedAlarms` (default `true`), `assigneeId`, `startTs`, `endTs`, `timeWindow`.
- **Predicate `valueType`:** `STRING` (`EQUAL`, `NOT_EQUAL`, `STARTS_WITH`, `ENDS_WITH`, `CONTAINS`, `NOT_CONTAINS`, `IN`, `NOT_IN`), `NUMERIC`/`DATE_TIME` (`EQUAL`, `NOT_EQUAL`, `GREATER`, `LESS`, `GREATER_OR_EQUAL`, `LESS_OR_EQUAL`), `BOOLEAN` (`EQUAL`, `NOT_EQUAL`), `COMPLEX` (`AND`, `OR` combining nested predicates). Supports `dynamicValue` (`CURRENT_TENANT`, `CURRENT_CUSTOMER`, `CURRENT_USER`, `CURRENT_DEVICE`).

---

### 4.8 Entity Relations (`entity-relation-controller`)

| Method | Endpoint | Key Params / Body | Response |
| :--- | :--- | :--- | :--- |
| `POST` | `/api/v2/relation` | Body: `EntityRelation` (`from`, `to`, `type`, `typeGroup`) | `EntityRelation` |
| `DELETE` | `/api/v2/relation` | Query: `fromId`, `fromType`, `relationType`, `toId`, `toType`, optional `relationTypeGroup` | `EntityRelation` |
| `GET` | `/api/relations/from/{fromType}/{fromId}` | Optional `relationTypeGroup` (default `COMMON`) | `List<EntityRelation>` |
| `GET` | `/api/relations/to/{toType}/{toId}` | Optional `relationTypeGroup` | `List<EntityRelation>` |
| `GET` | `/api/relations/info/from/{fromType}/{fromId}` | Optional `relationTypeGroup` | `List<EntityRelationInfo>` (includes `fromName`, `toName`) |
| `GET` | `/api/relations/info/to/{toType}/{toId}` | Optional `relationTypeGroup` | `List<EntityRelationInfo>` |
| `POST` | `/api/relations` / `/api/relations/info` | Body: `EntityRelationsQuery` (`parameters`, `filters`) | `List<EntityRelation>` / `List<EntityRelationInfo>` |

---

### 4.9 RPC v2 (`rpc-v-2-controller`)

| Method | Endpoint | Body / Params | Response | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `POST` | `/api/rpc/oneway/{deviceId}` | `{"method": "...", "params": {...}, "timeout": 10000, "persistent": false, "retries": 0}` | Empty (`200`) or `{"rpcId": "..."}` if persistent | Min timeout `5000` ms. `504` if device offline & non-persistent |
| `POST` | `/api/rpc/twoway/{deviceId}` | Same as above | Device JSON reply (`200`) or `{"rpcId": "..."}` if persistent | `406` if device returned invalid JSON; `504` on timeout |
| `GET` | `/api/rpc/persistent/device/{deviceId}` | Pagination + `rpcStatus` (`QUEUED`, `SENT`, `DELIVERED`, `SUCCESSFUL`, `TIMEOUT`, `EXPIRED`, `FAILED`, `DELETED`) | `PageData<Rpc>` | Monitor queued/delivered commands |
| `GET` | `/api/rpc/persistent/{rpcId}` | `rpcId` (path) | `Rpc` | Check status of a single persistent RPC |
| `DELETE` | `/api/rpc/persistent/{rpcId}` | `rpcId` (path) | `200 OK` | Cancel/delete persistent RPC |

---

### 4.10 Notifications (`notification-controller`)

| Method | Endpoint | Key Params / Body | Response | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `GET` | `/api/notifications` | `pageSize`, `page`, `unreadOnly` (bool), `deliveryMethod` (`WEB`, `MOBILE_APP`, etc.), `textSearch`, `sortProperty`, `sortOrder` | `PageData<Notification>` | User notification inbox (`subject`, `text`, `type`, `status`: `SENT`\|`READ`, `info`) |
| `GET` | `/api/notifications/unread/count` | Optional `deliveryMethod` | `integer` | Badge counter |
| `PUT` | `/api/notification/{id}/read` | `id` (path) | `200 OK` | Mark single notification read |
| `PUT` | `/api/notifications/read` | Optional `deliveryMethod` (query) | `200 OK` | Mark all notifications read |
| `DELETE` | `/api/notification/{id}` | `id` (path) | `200 OK` | Delete notification |
| `GET` | `/api/notification/settings/user` | — | `UserNotificationSettings` (`{prefs: {...}}`) | Per-user notification preferences |
| `POST` | `/api/notification/settings/user` | Body: `UserNotificationSettings` | `UserNotificationSettings` | Save user notification preferences |
| `GET`/`POST`/`DELETE` | `/api/user/mobile/session` | Header `X-Mobile-Token` (FCM token); Body `{"fcmTokenTimestamp": ms}` | `MobileSessionInfo` | Register/refresh/remove FCM push token |

---

### 4.11 User, Settings, Audit Logs & Mobile/White-Label (`user-controller`, `audit-log-controller`, `mobile-app-controller`, `white-labeling-controller`)

| Method | Endpoint | Key Params / Body | Response | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `GET` | `/api/user/{userId}` / `/api/user/info/{userId}` | `userId` (path) | `User` / `UserInfo` | Profile fields (`email`, `firstName`, `lastName`, `phone`, `authority`, `additionalInfo`) |
| `POST` | `/api/user` | Body: `User`; optional `sendActivationMail` | `User` | Update user profile (note: `authority`/`email` edits depend on permissions) |
| `GET` | `/api/user/settings/general` | — | `JsonNode` | General user preferences JSON |
| `PUT` | `/api/user/settings/general` | Body: `JsonNode` | `200 OK` | Partial/general settings update |
| `GET` / `PUT` | `/api/user/settings/{type}` | `type` (path, e.g. `GENERAL`, `MOBILE`) | `JsonNode` | Typed user settings |
| `POST` | `/api/user/settings` | Body: `JsonNode` | `JsonNode` | Save user settings |
| `GET` | `/api/audit/logs` | `pageSize`, `page`, `startTime`, `endTime`, `actionTypes`, `textSearch`, `sortProperty`, `sortOrder` | `PageData<AuditLog>` | Tenant-wide audit logs (`actionType`, `actionStatus`: `SUCCESS`\|`FAILURE`, `actionData`, `actionFailureDetails`) |
| `GET` | `/api/audit/logs/entity/{entityType}/{entityId}` | Same pagination/time filters | `PageData<AuditLog>` | Entity-specific audit history |
| `GET` | `/api/audit/logs/user/{userId}` | Same pagination/time filters | `PageData<AuditLog>` | User-specific audit history |
| `GET` | `/api/audit/logs/customer/{customerId}` | Same pagination/time filters | `PageData<AuditLog>` | Customer-specific audit history |
| `GET` | `/api/mobile` | Query: `pkgName`, `platform` (`ANDROID`/`IOS`) | `UserMobileInfo` | Authenticated mobile config (`user`, `storeInfo`, `versionInfo`, `homeDashboardInfo`, `pages`) |
| `GET` | `/api/whiteLabel/currentWhiteLabelParams` | Optional `customerId` | `WhiteLabelingParams` | PE white-labeling palette, logos, app title |

---

## 5. WebSocket Telemetry & Subscriptions API

### 5.1 Connection & Authentication
- **Endpoint:** `wss://<HOST>/api/ws` (or `ws://<HOST>/api/ws` for local HTTP).
- **Inactivity Timeout:** **90 seconds** — client must send periodic pings or commands to keep the socket alive.
- **Auth (`authCmd`)** — send as the first message (can be combined with initial `cmds` array):
  ```json
  {
    "authCmd": { "cmdId": 0, "token": "YOUR_JWT_TOKEN" },
    "cmds": [ ... ]
  }
  ```
  - **API key auth (TB >= 4.4):** `{ "authCmd": { "cmdId": 0, "apiKey": "RAW_API_KEY" } }` (no `ApiKey ` prefix; TB <= 4.3 closes the socket if `apiKey` is used).
  - If `authCmd` fails (expired/invalid), the server closes the WebSocket (e.g., status `1007` with reason `"API key is expired"`).

### 5.2 Command Types & Lifecycle
Every command carries a client-chosen integer `cmdId`; server initial responses and real-time updates echo `cmdId`, `errorCode`, `errorMsg`, and `cmdUpdateType`.

| Category | Subscribe `type` | `cmdUpdateType` | Unsubscribe `type` |
| :--- | :--- | :--- | :--- |
| Entity query + live values | `ENTITY_DATA` | `ENTITY_DATA` | `ENTITY_DATA_UNSUBSCRIBE` |
| Live entity count | `ENTITY_COUNT` | `COUNT_DATA` | `ENTITY_COUNT_UNSUBSCRIBE` |
| Alarm query + live updates | `ALARM_DATA` | `ALARM_DATA` | `ALARM_DATA_UNSUBSCRIBE` |
| Live alarm count | `ALARM_COUNT` | `ALARM_COUNT_DATA` | `ALARM_COUNT_UNSUBSCRIBE` |
| Entity active alarm flag | `ALARM_STATUS` | `ALARM_STATUS` | `ALARM_STATUS_UNSUBSCRIBE` |
| User notifications feed | `NOTIFICATIONS` | `NOTIFICATIONS` | `NOTIFICATIONS_UNSUBSCRIBE` |
| Unread notification count | `NOTIFICATIONS_COUNT` | `NOTIFICATIONS_COUNT` | — |
| Mark notifications read | `MARK_NOTIFICATIONS_AS_READ` | — | — |
| Mark all notifications read | `MARK_ALL_NOTIFICATIONS_AS_READ` | — | — |
| v1 Attributes (single entity) | `ATTRIBUTES` (`scope`: `SERVER_SCOPE`\|`SHARED_SCOPE`\|`CLIENT_SCOPE`) | `ATTRIBUTE_DATA` | Resend same cmd with `"unsubscribe": true` |
| v1 Time series (single entity) | `TIMESERIES` (`startTs`, `timeWindow`, `interval`, `limit`, `agg`) | `TIMESERIES_DATA` | Resend same cmd with `"unsubscribe": true` |
| v1 Time series history (one-shot) | `TIMESERIES_HISTORY` (`startTs`, `endTs`, `interval`, `limit`, `agg`) | `TIMESERIES_DATA` | One-shot (no subscription) |

**v2 `ENTITY_DATA` sub-commands:**
- `latestCmd`: `{ "keys": [{ "type": "TIME_SERIES", "key": "temperature" }] }`
- `tsCmd` (rolling window): `{ "keys": ["temperature"], "startTs": 1704067200000, "timeWindow": 3600000 }`
- `historyCmd` (one-time fetch): `{ "keys": ["temperature"], "startTs": ..., "endTs": ..., "interval": 60000, "limit": 100, "agg": "AVG" }`

### 5.3 WebSocket Error Codes
| Code | Name | Meaning |
| :--- | :--- | :--- |
| `0` | `NO_ERROR` | Success |
| `1` | `INTERNAL_ERROR` | Internal server error |
| `2` | `BAD_REQUEST` | Invalid command/parameters |
| `3` | `UNAUTHORIZED` | Unauthorized |
| `4` | `ACCESS_DENIED` | No permission for requested data (TB >= 4.4) |

---

## 6. REST Error Model & Platform Error Codes

### 6.1 `ThingsboardErrorResponse` Payload
```json
{
  "message": "Token has expired",
  "errorCode": 11,
  "status": 401,
  "subscriptionErrorCode": null,
  "subscriptionEntry": null,
  "subscriptionValue": null,
  "timestamp": 1609459200000
}
```

### 6.2 `ThingsboardErrorCode` Table
Verified against OpenAPI 3.1.0 (`4.4.1PAAS`) and ThingsBoard server `ThingsboardErrorCode.java`:

| `errorCode` | Enum Name | Typical HTTP Status | Meaning / Client Handling |
| :--- | :--- | :--- | :--- |
| `2` | `GENERAL` | `500` | Unexpected server error |
| `10` | `AUTHENTICATION` | `401` | Bad username/password, disabled account, invalid token |
| `11` | `JWT_TOKEN_EXPIRED` | `401` | Access token expired -> trigger `/api/auth/token` refresh |
| `15` | `CREDENTIALS_EXPIRED` | `401` | User password expired -> prompt password change |
| `20` | `PERMISSION_DENIED` | `403` | RBAC / group permission denied |
| `30` | `INVALID_ARGUMENTS` | `400` | Validation error on request payload |
| `31` | `BAD_REQUEST_PARAMS` | `400` | Invalid query/path params or unsupported HTTP method |
| `32` | `ITEM_NOT_FOUND` | `404` | Entity UUID does not exist or is inaccessible |
| `33` | `TOO_MANY_REQUESTS` | `429` | Rate limit exceeded -> exponential backoff |
| `34` | `TOO_MANY_UPDATES` | WS | WebSocket update rate limit exceeded |
| `35` | `VERSION_CONFLICT` | `409` | Optimistic lock `version` mismatch -> refetch & retry |
| `40` | `SUBSCRIPTION_VIOLATION` | `403` | PE/Cloud plan feature or subscription inactive |
| `41` | `ENTITIES_LIMIT_EXCEEDED` | `403` | Tenant entity quota reached |
| `45` | `PASSWORD_VIOLATION` | `400` | Password violates `UserPasswordPolicy` |
| `46` | `DATABASE` | `500` | Persistence error |
| `47` / `50` | `SETUP_INCOMPLETE` / PE code `50` | `400`/`500` | Incomplete platform/SMTP setup or PE-specific restriction |

**`subscriptionErrorCode` (PE/Cloud when `errorCode == 40`):** `1` = Entities limit reached, `2` = Feature disabled, `3` = Subscription not active, `4` = Billing error, `5` = Permission denied, `6` = Plan downgrade overflow, `7` = Solution template level mismatch.

---

## 7. Mobile App Recommendations (Aligned with Repo Stack)

### 7.1 Current Repo Alignment Check
Inspecting `pubspec.yaml` and `lib/`:
- **HTTP & State & Routing:** `dio: ^5.8.0+1`, `hooks_riverpod: ^2.6.1`, `flutter_hooks: ^0.21.2`, `go_router: ^17.0.0`, `reactive_forms: ^18.2.2`, `toastification: ^2.3.0`.
- **Current stubs:**
  - `lib/constants/app_constants.dart`: `defaultApiEndpoint = 'https://thingsboard.democloud.xyz/'`, `thingsboardOAuth2CallbackUrlScheme = 'org.thingsboard.pe.app.auth'`.
  - `lib/core/auth/login/provider/auth_provider.dart`: defines `dioClientProvider` and `AuthNotifier` (currently simulated with 800ms delays).
  - `lib/config/routes/router.dart`: defines `/login`, `/login/resetPasswordRequest`, `/qrCodeScan`, `/home` (missing auth redirect guard and sub-routes for alarms/devices/assets/customers/dashboards/notifications/audit-logs/settings).
  - `lib/core/mock/mock_data.dart`: already mirrors ThingsBoard PE domain entities (`MockDashboard`, `MockAlarm` + `MockAlarmComment`, `MockDeviceProfile`, `MockDevice`, `MockCustomer`, `MockAsset`, `MockAuditLog`, `MockNotificationItem`, `MockUserProfile`).

### 7.2 SDK vs. Custom Dio Client Decision
- **Option A — Official `thingsboard_pe_client: ^4.4.1` (Recommended if targeting TB PE >= 4.4):**
  - Gives all 745+ typed REST endpoints, built-in `TelemetrySubscriber` WebSocket reconnection, JWT auto-refresh, and `toThingsboardError()` normalization out of the box.
  - Note: Check target server version! `thingsboard_pe_client: 4.4.1` targets TB >= `4.4.0` (e.g., `/api/plugins/telemetry/.../values/timeseries/history`). Against `thingsboard.democloud.xyz`, verify server version via `GET /api/system/info` (once authenticated) or test `/api/auth/login` + `/api/deviceInfos/all` early.
- **Option B — Custom `Dio` + `web_socket_channel` Layer (Best if keeping lightweight models without `built_value` codegen or supporting mixed TB 3.x/4.x servers):**
  - Reuses existing `dioClientProvider` (`dio ^5.8.0+1`) with Riverpod repositories (`AuthRepository`, `DeviceRepository`, `AlarmRepository`, etc.), Freezed/manual immutable Dart models mapping directly from the existing `Mock*` classes, and a single shared `TbWebSocketService` using `web_socket_channel`.

### 7.3 Concrete Implementation Blueprint

1. **Auth & Secure Token Persistence:**
   - Add `flutter_secure_storage` for `jwtToken` and `refreshToken` (plus `jwt_decoder` to inspect `exp`, `userId`, `authority`, `tenantId`, `customerId` locally).
   - Implement a `QueuedInterceptor` on `Dio`:
     - `onRequest`: attach `X-Authorization: Bearer <token>` (skip for `/api/auth/login`, `/api/auth/token`, `/api/noauth/**`).
     - `onError`: if `statusCode == 401` and `errorCode == 11` (`JWT_TOKEN_EXPIRED`), acquire a single-flight lock, call `POST /api/auth/token`, update storage, and replay failed requests; on refresh failure, call `authProvider.notifier.logout()` and let `GoRouter` redirect to `/login`.
   - **2FA & OAuth2 & QR Login:**
     - Handle `LoginResponse.scope == 'PRE_VERIFICATION_TOKEN'` by routing to a 2FA OTP screen calling `/api/auth/2fa/verification/send` and `/check`.
     - Populate `AuthUiState.oauthClients` via `POST /api/noauth/oauth2Clients?pkgName=...&platform=ANDROID|IOS` (already works on `democloud.xyz`), launching OAuth URLs via `flutter_appauth` or Custom Tabs / `ASWebAuthenticationSession` returning to `ThingsboardAppConstants.thingsboardOAuth2CallbackUrlScheme` (`org.thingsboard.pe.app.auth`).
     - Wire `/qrCodeScan` to `GET /api/noauth/qr/{secret}` (if QR contains login secret) or `POST /api/customer/device/{deviceName}/claim` (if QR contains device claim payload).

2. **GoRouter Guard (`routerProvider`):**
   - Pass a `Listenable` / Riverpod `ref.listen(authProvider, ...)` as `refreshListenable` to `GoRouter`, redirecting unauthenticated users to `/login` (except `/login`, `/login/resetPasswordRequest`, `/qrCodeScan`) and authenticated users away from `/login` to `/home`.

3. **Mapping Existing `mock_data.dart` Providers to Real Endpoints:**
   - **Home / Dashboards:** `GET /api/dashboard/home/info` + `GET /api/user/dashboards?pageSize=20&page=0&mobile=true` + `GET /api/user/lastVisitedDashboards`. Render dashboards in `webview_flutter` (pointing to `<BASE_URL>/dashboards/<id>?accessToken=<jwt>&...`) or native telemetry cards using `ENTITY_DATA` WebSocket queries.
   - **Alarms & Comments:** `GET /api/v2/alarms` (or `ALARM_DATA` WebSocket for live updates), actions `POST /api/alarm/{id}/ack`, `POST /api/alarm/{id}/clear`, `POST /api/alarm/{id}/assign/{userId}`, `GET /api/users/assign/{alarmId}`, and `GET/POST /api/alarm/{id}/comment`.
   - **Devices & Device Profiles:** `GET /api/deviceInfos/all` (or `POST /api/entitiesQuery/find` with `latestValues` for live card telemetry), `GET /api/deviceProfileInfos`, and `TelemetrySubscriber` (`ENTITY_DATA` or `ATTRIBUTES` + `TIMESERIES`) on `DeviceDetailsPage`.
   - **Assets & Customers:** `GET /api/assetInfos/all`, `GET /api/customerInfos/all` (fall back to `GET /api/customers` if customer hierarchy endpoints are disabled for role), and `GET /api/relations/info/from/{type}/{id}` for asset/device drill-down.
   - **Notifications & Badge:** Single WebSocket subscription `NOTIFICATIONS_COUNT` / `NOTIFICATIONS` + REST `GET /api/notifications`, `PUT /api/notification/{id}/read`, `PUT /api/notifications/read`. Register FCM token via `POST /api/user/mobile/session` (`X-Mobile-Token` header).
   - **Audit Logs & Profile/Settings:** `GET /api/audit/logs`, `GET /api/auth/user`, `POST /api/user`, `GET/PUT /api/user/settings/general`, `POST /api/auth/changePassword`.

4. **Mobile Performance & Resilience:**
   - Share **one** WebSocket connection (`wss://<host>/api/ws`) managed by a Riverpod `keepAlive` service; multiplex subscriptions by incrementing `cmdId`, always send unsubscribe commands on screen `dispose`, and reconnect with exponential backoff + heartbeat ping (< 90s) when `AppLifecycleState.resumed` fires.
   - Guard optional PE/4.4+ startup endpoints (`/api/noauth/mobile`, `/api/noauth/whiteLabel/loginWhiteLabelParams`, `/api/noauth/selfRegistration/signUpSelfRegistrationParams`) with `try/catch` treating `404` as feature-unavailable, since `thingsboard.democloud.xyz` returns `404` for those paths.
