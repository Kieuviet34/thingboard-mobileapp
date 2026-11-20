## Review verdict

The spec is broad and the TDD intent is clear, but **the plan is not ready to execute as written**. The main blockers are the Wave 2 route graph, an Android Kotlin Gradle configuration conflict, underspecified authentication/session lifecycle rules, and fallback behavior that treats some permission denials like missing endpoints.

The repository is still a mock-driven UI baseline: login is simulated, the router only mounts five paths, Material 3 is disabled, and there is no API/repository/WebSocket implementation. The only test file is a login smoke test. See [auth_provider.dart](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/lib/core/auth/login/provider/auth_provider.dart:61), [router.dart](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/lib/config/routes/router.dart:11), [tb_theme.dart](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/lib/config/themes/tb_theme.dart:17), and [widget_test.dart](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/test/widget_test.dart:1).

I cross-checked the requested [API/UI spec](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/ai/specs/2026-11-20-api-ui-design.md), [implementation plan](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/ai/plans/2026-11-20-api-ui-implementation-plan.md), [QA strategy](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/ai/plans/2026-11-20-qa-test-strategy.md), [UI rules](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/ai/ui-rules.md), [API rules](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/ai/api-rules.md), [architecture guide](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/ai/ARCHITECTURE.md), and the three research documents. No code was changed and no tests or builds were run in this read-only review.

I found no confirmed **[CRITICAL]** exploitable defect: most risks concern proposed work that has not been implemented. The following **[HIGH]** items are readiness blockers.

## [HIGH] Blockers

### 1. Wave 2 cannot satisfy its own route/build gate

Wave 2 worker 2B is assigned the router and “all 18 routes,” while the page implementations are assigned to Wave 3 workers 3A–3C. If 2B imports those pages directly, Wave 2 has unresolved imports; if it does not, the routes are not actually wired. The plan requires wave gates, so this is a predictable intermediate failure, not just a final integration concern. See [Wave 2 ownership](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/ai/plans/2026-11-20-api-ui-implementation-plan.md:99) and [Wave 3 ownership](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/ai/plans/2026-11-20-api-ui-implementation-plan.md:150).

There are further ownership ambiguities:

- 2A owns auth API/controller work while 2B owns `auth_provider.dart` and may bridge or remove the existing stub. That requires a stable provider contract before parallel work starts.
- 3A may delete or redirect `home_placeholder_page.dart`; Wave 4 also owns placeholder cleanup. The router may be left importing a file that 3A removed.
- Wave 4’s “update app widgets/router as needed” is broad enough to overlap all feature workers’ integration points.

**Before implementation:** give one owner the final router integration after Wave 3, or define compiling placeholder destinations for Wave 2. Freeze the auth provider export/contract and assign cleanup of `home_placeholder_page.dart` once.

### 2. Android Kotlin configuration is internally inconsistent

The project already declares AGP 9.3.1 and Kotlin Gradle plugin 2.4.20 in [settings.gradle.kts](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/android/settings.gradle.kts:21), and Gradle 9.5 in [gradle-wrapper.properties](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/android/gradle/wrapper/gradle-wrapper.properties:5). Those versions align with the spec’s Flutter 3.50 target. The concern is how the app module is configured:

- [gradle.properties](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/android/gradle.properties:3) sets `android.builtInKotlin=false`.
- [app/build.gradle.kts](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/android/app/build.gradle.kts:1) applies the Android and Flutter plugins, but not `org.jetbrains.kotlin.android`.
- The same module has a `kotlin { compilerOptions ... }` block at [app/build.gradle.kts](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/android/app/build.gradle.kts:41).

With built-in Kotlin disabled and no Kotlin Gradle plugin applied to that module, the source of the `kotlin {}` DSL is unclear. This is a **likely build-configuration failure**, not a verified one; the build was not run. Reconcile it against the [Flutter Kotlin migration guidance](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers) before relying on the APK gate.

The spec’s `maxOf(flutter.minSdkVersion, 23)` proposal also needs tightening. `mobile_scanner 7.5.0` and `flutter_secure_storage 11.2.0` have Android API 23 floors, but `shared_preferences 2.5.6` and `url_launcher 6.3.3` have API 24 floors. The effective app floor must be at least 24 when those dependencies are used; explicitly pin or verify it instead of only guarding for 23. See the package [mobile_scanner changelog](https://pub.dev/packages/mobile_scanner/changelog), [flutter_secure_storage changelog](https://pub.dev/packages/flutter_secure_storage/changelog), [shared_preferences](https://pub.dev/packages/shared_preferences), and [url_launcher changelog](https://pub.dev/packages/url_launcher/changelog).

`compileSdk` and `ndkVersion` are inherited from Flutter in [app/build.gradle.kts](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/android/app/build.gradle.kts:9). The repository does not pin the requested NDK `28.2.13676358`; the plan should state the resolved SDK/NDK values and verify them in the chosen Flutter environment. The main [AndroidManifest.xml](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/android/app/src/main/AndroidManifest.xml:1) currently lacks `INTERNET`, `CAMERA`, and an OAuth callback filter; adding these is necessary, but a debug APK build alone will not prove callback routing works.

The app’s `applicationId` is still `com.example.thingsboard_democloud_app` at [app/build.gradle.kts](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/android/app/build.gradle.kts:19). That is acceptable for a local debug build, but not a release identity. Also, the QA build step should include the repository’s JVM-on-demand/daemon cleanup procedure, since `flutter build apk` invokes Gradle.

### 3. Authentication and session lifecycle races are underspecified

The design combines proactive expiry checks with reactive 401 handling: [API rules](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/ai/api-rules.md:23) calls for JWT expiry checks and single-flight refresh; the spec describes a `QueuedInterceptor` and refresh behavior at [API/UI spec](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/ai/specs/2026-11-20-api-ui-design.md:59). The QA plan tests three concurrent expired-token 401s, but does not specify or test:

- A proactive refresh and a reactive 401 arriving together. Both paths need to share the same refresh gate.
- Logout while refresh is in flight. A late refresh response must not restore tokens or replay requests into a logged-out session.
- Switching server while old-host requests or refreshes are in flight.
- Refresh-token expiry and whether every refresh error, timeout, and malformed response clears the session consistently.
- A session-generation guard for old responses that arrive after logout or a mode/server switch.

The router/auth contract also needs definition: the plan uses `authProvider` while the router requires a `refreshListenable`. State transitions, listener ownership, and redirect behavior during `mfaRequired` and refresh failure are not specified well enough to rule out redirect loops or transient access to protected routes.

There is a direct 2FA contract mismatch. The spec and QA cover `PRE_VERIFICATION_TOKEN`, but [API rules](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/ai/api-rules.md:26) and the research material also identify `MFA_CONFIGURATION_TOKEN`. These should be modeled as distinct states if the server uses them for different flows; one generic “2FA required” branch is not sufficient.

### 4. 404/403 fallbacks can mask permission failures

The fallback policy needs to be endpoint-specific and distinguish “endpoint unavailable” from “user cannot access this resource.”

- The QA plan explicitly tests Dashboard fallback on 403/404 and Customer fallback on 403/404 at [QA strategy](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/ai/plans/2026-11-20-qa-test-strategy.md:75) and [line 79](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/ai/plans/2026-11-20-qa-test-strategy.md:79). A 403 is normally an authorization result, so silently retrying a broader or different endpoint can hide a real denial or produce confusing data.
- The research matrix includes `GET /api/system/info` for server version detection ([matrix](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/research/api-controller-matrix.md:125)), but the plan’s compatibility tests focus on optional metadata 404s and do not define a capability/version strategy. “Pre-4.4 fallback” is therefore more a collection of endpoint retries than a controlled compatibility contract.
- Telemetry fallback differs across documents: the SDK decision proposes fallback on `404` **or** `400` ([SDK decision](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/research/sdk-decision.md:40)); the spec and QA describe `404` only. A broad fallback can turn malformed requests or missing entities into misleading success/failure behavior.
- ThingsBoard’s telemetry response typing needs an explicit contract. The API research notes string-valued telemetry unless strict typing is requested; the plan should specify `useStrictDataTypes` and test numeric parsing before using values in charts.

For every fallback, document the exact endpoint, the exact status/error that proves the feature is unsupported, and whether the retry is safe for each role. Do not use 403 as a generic compatibility signal.

## Service coverage and contract gaps

The plan intends 12 controllers plus a shared WebSocket service. None exists in the current `lib/` implementation, so the plan represents a substantial new API layer, not a migration of working repositories. The following gaps remain even in the proposed contract.

| Service | Review |
|---|---|
| **ServerConfig** | QA covers password policy, OAuth clients, and optional metadata 404s. Add the matrix’s `/api/system/info` version/capability probe and define whether server switching clears host-scoped state. |
| **Auth** | Login, reset, QR, demo, and refresh are covered broadly. `MFA_CONFIGURATION_TOKEN`, OAuth callback processing, refresh/logout races, and callback token persistence are not adequately covered. |
| **Dashboard** | Pagination and star/visit actions are specified. The 403 fallback is unsafe without a proven role/capability rule. |
| **Alarm** | Listing and ack/clear/assign/unassign/comments are specified. Test stale-page refresh and optimistic update ordering, not just rollback for a failed action. |
| **Device** | The active/inactive count query lacks an asserted request shape. The matrix describes an `active` attribute filter; verify that this matches the server’s meaning of device activity before treating it as online status. Demo profile counts currently disagree with the mock device records. |
| **Asset** | Repository behavior is described, but the QA strategy lacks a dedicated `AssetDetailsPage` test despite the route and detail UI requirements. |
| **Customer** | The 403 fallback needs role-safe semantics. The QA screen tests cover Customers, but not the `CustomerDetailsPage` route/view. |
| **Telemetry** | Resolve the 400-versus-404 fallback discrepancy, specify strict data typing, and test that older history responses cannot overwrite a newer range/filter request. |
| **RPC** | The 504 and 406 mapping is good coverage. Add cancellation, request timeout, and late-response behavior when navigating away or switching devices. |
| **Notification** | The matrix has `GET/POST /api/notification/settings/user`, but the QA notification test lists notification/session endpoints and omits settings ([matrix](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/research/api-controller-matrix.md:366), [QA strategy](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/ai/plans/2026-11-20-qa-test-strategy.md:82)). Also, the matrix lists `NOTIFICATIONS_COUNT` without an unsubscribe command; generic unsubscribe rules must not invent an unsupported frame. |
| **AuditLog** | Listing/filtering is specified, but the plan does not clearly test role restrictions, large `actionData` payloads, or detail rendering at large text scale. |
| **UserProfile** | The matrix says `changePassword` returns a fresh JWT pair that must be persisted ([matrix](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/research/api-controller-matrix.md:405)). Make that part of the test contract, along with settings and notification preferences. |
| **WebSocket service** | Reconnect and replay are specified, but command IDs, stale frames, cancellation while offline, and partial-update merge behavior need stronger contracts, described below. |

The typed failure contract is inconsistent too: the matrix uses `TbFailure`, API rules use `TbApiException`, and the SDK decision uses `ThingsboardException`. The design spec’s error test list omits codes `2`, `46`, `47`, and `50`, while the QA plan includes them. Pick one error model and one canonical mapping table before generating controllers or UI states.

## [HIGH] Mode, server, and cache transitions need one owner

The documents refer to `SessionMode`, `AppConnectionMode`, and `isDemoModeProvider`. They also disagree on whether server URL and demo mode belong in secure storage: the SDK decision groups them with secure tokens, while the spec separates `TbSecureStorage` from `TbAppPreferences`. See [SDK decision](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/research/sdk-decision.md:31) and [spec storage design](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/ai/specs/2026-11-20-api-ui-design.md:59).

The plan needs an atomic transition contract for Demo ↔ Live and host changes: clear or namespace auth state, cancel old requests, close/recreate the socket, invalidate providers/caches, and prevent old responses from appearing in the new session. Tests currently establish that the mode can toggle, but not that data and credentials are isolated through the transition.

## [MEDIUM] WebSocket lifecycle details are inconsistent

The docs disagree about the keepalive interval: API rules call for a 30–45 second ping and a 90 second inactivity threshold; the SDK decision says 90-second keepalive; the spec/QA focus on a 45-second heartbeat. Align the intervals and specify whether this is a ThingsBoard application frame or a transport-level ping before testing it. See [API rules](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/ai/api-rules.md:46), [SDK decision](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/research/sdk-decision.md:38), and [QA strategy](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/ai/plans/2026-11-20-qa-test-strategy.md:61).

Also define:

- Whether `cmdId` is global or per socket generation; old frames must not be delivered to newly allocated subscriptions after reconnect.
- How disposal works while disconnected: remove local subscription intent so reconnect does not replay it, even when an unsubscribe frame cannot be sent.
- How partial entity updates merge with cached state, including out-of-order timestamps and deleted/missing fields.
- What happens to subscriptions across pause/resume and logout.

The API matrix specifically lists no unsubscribe for `NOTIFICATIONS_COUNT` ([matrix](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/research/api-controller-matrix.md:325)), so generic cleanup language needs per-command behavior.

## [MEDIUM] UI requirements are stronger than the planned acceptance tests

The requirements are sound, but the acceptance evidence does not match their breadth:

- The project currently has `useMaterial3: false` and supplies the same auth theme for light and dark in [tb_theme.dart](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/lib/config/themes/tb_theme.dart:17) and [main.dart](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/lib/main.dart:26). Replacing that requires tests for both real schemes and the `TbStatusColors` extension.
- UI rules require two-pane layouts for Devices, Alarms, and Dashboards; the spec adds Assets and Customers. Resolve this difference between [UI rules](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/ai/ui-rules.md:68) and [spec](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/ai/specs/2026-11-20-api-ui-design.md:132).
- The “18 screens” count is ambiguous. The spec combines Customers with Customer Details and Assets with Asset Details; its route tree therefore contains more distinct page classes than the feature-row count. QA plans Customers and Assets page tests but not detail-page tests. Define the route/page inventory and test each routeable page, including OAuth callback.
- Touch-target tests cover selected screens; semantics and text scaling test only selected widgets. The spec requires at least 48dp targets, semantics, and scaling to 2.0; QA tests 1.8 scaling on a small subset. See [QA accessibility tests](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/docs/ai/plans/2026-11-20-qa-test-strategy.md:120).
- The audit script is heuristic. It scans Dart files under `lib/` and does not check M3, the theme extension, adaptive breakpoints, Semantics, hit targets, or reduced-motion requirements. Its pass/fail behavior therefore cannot serve as evidence for those requirements. The QA plan says to review yellow results, while Wave 4 says to fix critical/red findings only; reconcile those gates.

Current source also has compatibility points that need explicit ownership during the theme migration: `TbThemeUtils`, `AppColors`, `DesignTokens.paddigZero`, and `TbValicationMessages` (the latter is used by the login text field). The typo in `paddigZero` appears unused, but changing/removing shared theme APIs while feature workers build against them could cause avoidable breakage.

Two existing Demo-mode model issues undermine parity: mock device-profile active counts do not match the mock devices, and `MockAlarm.copyWith` uses `assigneeName ?? this.assigneeName`, so it cannot clear an assignee for unassign. See [mock_data.dart](/D:/DMHoang/Project_GitHub/thingboard-mobileapp/lib/core/mock/mock_data.dart:103) and the profile/device data in the same file. Add regression tests for both before building the new Demo repositories.

## [MEDIUM] QA is broad in intent, incomplete in evidence

TDD is explicitly planned from Wave 1, but the test strategy still needs to cover:

- Search/filter/page races: issue overlapping requests, refresh page 0 while `loadNextPage` is running, clear filters, and verify an older response cannot replace the latest state.
- `PRE_VERIFICATION_TOKEN` and `MFA_CONFIGURATION_TOKEN` back navigation and token retention; OAuth deep-link parsing and callback delivery from a cold app start.
- Demo ↔ Live and server URL switching with in-flight REST and WebSocket work.
- WebSocket disposal during reconnect, duplicate replay prevention, stale frames, and partial updates.
- All routeable detail screens, not only feature list pages.
- The exact Android release manifest and OAuth callback on-device, not just a successful debug APK build.
- A live PE smoke path for auth and the known `thingsboard.democloud.xyz` 404 behavior. MockDio tests verify client logic, but they cannot verify that the server still behaves as recorded in the research document.

`flutter analyze` and the UI audit will not validate Gradle DSL, merged manifest permissions, or deep-link handling. Keep the APK/device gate, but make it explicit that those are separate checks. Also align QA’s “review yellow” rule with Wave 4’s “fix red only” rule.

## Recommended pre-work decisions

1. Publish one contract sheet for mode/auth state, router paths, provider exports, failure type, endpoint fallback matrix, and WebSocket command semantics.
2. Resolve the Gradle Kotlin setup and effective Android API floor before Wave 1’s APK check.
3. Move route wiring to a post-Wave-3 integration owner or provide compiling placeholders.
4. Add a single-flight refresh/session-generation design covering proactive refresh, logout, and host changes.
5. Restrict compatibility retries to confirmed unsupported-endpoint responses; keep permission denials visible.
6. Make the QA inventory enumerate actual pages/routes and add tests for the state transitions and detail screens above.

The dependency constraints in the spec are caret ranges, not exact pins. The current lockfile resolves different versions for existing packages and does not yet include the proposed packages; `pub get` will change it. Confirm the resolved lockfile and Android plugin requirements at implementation time rather than treating `pubspec.yaml` constraints alone as a compatibility check.