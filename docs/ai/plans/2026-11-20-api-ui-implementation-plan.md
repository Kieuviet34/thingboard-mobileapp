# Implementation Plan: ThingsBoard PE Mobile App — API & M3 UI/UX

> **Status:** Revised Post-Codex Review (Ready for Execution)
> **Spec:** `docs/ai/specs/2026-11-20-api-ui-design.md`
> **API Matrix:** `docs/research/api-controller-matrix.md`
> **QA Strategy:** `docs/ai/plans/2026-11-20-qa-test-strategy.md`
> **Rules:** `AGENTS.md`, `docs/ai/ui-rules.md`, `docs/ai/api-rules.md`, `docs/ai/ARCHITECTURE.md`
> **Toolchain:** Flutter `3.50.0` (`D:\DMHoang\Tools\flutter\bin\flutter.bat`), Dart `3.14.0`, `JAVA_HOME="C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot"`, Android NDK `28.2.13676358`

---

## Execution Rules
1. **TDD First:** In every wave, write failing unit/widget tests *before* implementing production code, then verify tests turn green.
2. **Strict Disjoint File Ownership:** Each worker edits ONLY its listed files. No two concurrent workers ever share a file, and cross-wave integration edits are assigned to one explicit owner.
3. **Every Wave Gate Compiles & Passes:** At the end of each wave:
   - `flutter analyze` -> `No issues found!`
   - `flutter test` -> 100% pass (zero skipped/weakened tests)
   - `dart format --output=none --set-exit-if-changed .`

---

## Wave 1 — Foundation: Pubspec, Core Models/Client/WS, M3 Design System & `TbIcons`, Android Setup

> **Step 1.0 (Before Wave 1 parallel split):** Worker `1A` updates `pubspec.yaml` and runs `flutter pub get` (verifying `pubspec.lock` resolves cleanly on Dart `3.14.0`). Then `1A`, `1B`, and `1C` run in parallel on strictly disjoint directories.

### Worker 1A (`core-infra`): Dependencies, Domain Models, `TbApiClient`, `TbWebSocketService`
- **Owned Files:**
  - `pubspec.yaml`, `pubspec.lock`
  - `lib/core/models/`:
    - `pagination.dart` (`SortOrder`, `PageQuery`, `PageData<T>`, `PagedListState<T>`)
    - `tb_failure.dart` (`TbFailureType`, `TbFailure`)
    - `entity_id.dart` (`EntityType`, `EntityId`, `Authority`)
    - `auth_models.dart` (`LoginResponse`, `TbAuthSession`, `AuthState` sealed variants incl. `AuthMfaVerificationRequired` & `AuthMfaConfigurationRequired`, `TwoFaProviderInfo`, `OAuth2ClientInfo`, `ServerConfigState`, `SessionMode`)
    - `dashboard_models.dart`, `alarm_models.dart`, `device_models.dart`, `asset_models.dart`, `customer_models.dart`, `telemetry_models.dart`, `notification_models.dart`, `audit_log_models.dart`, `user_models.dart`, `models.dart`
  - `lib/core/api/client/`:
    - `tb_secure_storage.dart` (`TbStorage` interface + `FlutterSecureStorageImpl` for secrets only)
    - `tb_app_preferences.dart` (`TbAppPreferences` wrapping `SharedPreferences` for `serverBaseUrl`, `sessionMode`, `themeMode`)
    - `tb_error_mapper.dart` (`TbErrorMapper` mapping raw integer `errorCode` `2, 10, 11, 12, 15, 20, 30, 31, 32, 33, 34, 35, 40, 41, 45, 46, 47, 50` + HTTP `406`/`504` + network/cancellation into `TbFailure`)
    - `tb_auth_interceptor.dart` (`TbAuthSessionCoordinator` + `QueuedInterceptor` sharing one `Completer` lock for proactive `exp` + reactive `401` refresh, `sessionGeneration` cancellation guard, `X-Authorization: Bearer`)
    - `tb_api_client.dart` (`TbApiClient` + host-scoped `CancelToken` group)
  - `lib/core/api/ws/`:
    - `telemetry_ws_service.dart` (`TbWebSocketService`, `WsConnectionState`, `authCmd`, **30s** application heartbeat, `socketGeneration` + monotonic `cmdId`, local intent removal on dispose while disconnected, `NOTIFICATIONS_COUNT` local-only cleanup, partial update merge by `ts`, `AppLifecycleState` reconnect)
  - `test/helpers/`:
    - `mock_dio_adapter.dart`, `fake_secure_storage.dart`, `fake_app_preferences.dart`, `fake_ws_channel.dart`, `test_container.dart`
  - `test/core/api/`:
    - `tb_error_mapper_test.dart`, `tb_auth_interceptor_test.dart` (incl. proactive+reactive overlap, logout mid-refresh, host-switch cancellation), `telemetry_ws_service_test.dart`, `models_parsing_test.dart`

### Worker 1B (`design-system`): M3 Light/Dark Themes, `TbStatusColors`, `TbIcons`, Shared UI & Motion
- **Owned Files:**
  - `lib/config/themes/`:
    - `app_colors.dart`, `tb_status_colors.dart` (`TbStatusColors` `ThemeExtension` `.light()` & `.dark()`), `design_tokens.dart` (`paddingZero` + `@Deprecated` `paddigZero` compatibility alias, `minTouchTarget = 48.0`, breakpoints `600`/`840`), `tb_text_styles.dart` (`tabularFigures` helper), `tb_theme.dart` (`useMaterial3: true`, `tbLightTheme()`, `tbDarkTheme()`, `Typography.material2021()`), `tb_theme_utils.dart` (`themeModeProvider` + light/dark getters)
  - `lib/widgets/icons/`:
    - `tb_icon_painters.dart` (`24dp` / `1.75dp` stroke painters, `RepaintBoundary`), `tb_icons.dart` (nav, entity, telemetry, shape-distinct alarm severities, statuses)
  - `lib/widgets/`:
    - `tb_status_badge.dart`, `tb_metric_pill.dart`, `tb_shimmer.dart`, `tb_empty_state.dart`, `tb_motion.dart` (`StaggeredEntry`, `TbPressScale`, `LivePulseDot`, `SparklineChart`), `tb_app_bar.dart`, `tb_app_search_bar.dart` (300ms debounce)
  - `lib/utils/transition/page_transitions.dart` (M3 fade-through/shared-axis `CustomTransitionPage` + `disableAnimationsOf` guard)
  - `test/widgets/`:
    - `tb_theme_test.dart` (M3 enabled, distinct light/dark schemes, `TbStatusColors`), `tb_icons_test.dart`, `tb_motion_widgets_test.dart` (incl. `disableAnimations: true`, `>=48dp` targets, `2.0x` text scale)

### Worker 1C (`android-setup`): Android Gradle, `minSdk 24`, Manifest & Branding Assets
- **Owned Files:**
  - `android/app/build.gradle.kts`, `android/gradle.properties` (only if Kotlin/builtInKotlin reconciliation is required by AGP 9.3.1 + added plugins), `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/res/**`
- **Tasks:**
  1. Pin `minSdk = maxOf(flutter.minSdkVersion, 24)` (required by `shared_preferences: 2.5.6` & `url_launcher: 6.3.3`) and verify Kotlin plugin / `android.builtInKotlin=false` compatibility with added plugins.
  2. Add `INTERNET` and `CAMERA` permissions, `android:label="ThingsBoard PE"`, and OAuth2 `<intent-filter>` (`android:scheme="org.thingsboard.pe.app.auth"`) to `main/AndroidManifest.xml`.
  3. Apply `assets/branding/icon_*.png` adaptive launcher icons and `splash*.png` launch screens to `android/app/src/main/res/`.
  4. Verify `flutter build apk --debug` succeeds (recording resolved `compileSdk`, `minSdk`, `targetSdk`, `ndkVersion`), then stop Gradle daemon (`cd android && .\gradlew --stop`).

---

## Wave 2 — Repositories, Controllers, Demo Parity, Auth UI & Compiling Shell Router

> **Prerequisite:** Wave 1 gate passes (`flutter analyze`, `flutter test`, `flutter build apk --debug`).
> **Frozen Auth Provider Contract (before Wave 2 starts):**
> - `lib/core/auth/login/provider/auth_provider.dart` re-exports `authProvider` (`AsyncNotifierProvider<AuthController, AuthState>`), `serverConfigProvider`, and `dioClientProvider` from `lib/core/api/controllers/`.
> - **Owner of `auth_provider.dart`:** Worker `2A` ONLY (Worker `2B` imports `auth_controller.dart` / `auth_provider.dart` read-only).

### Worker 2A (`api-repositories`): Repositories, Demo Parity Fixes & 13 Controllers
- **Owned Files:**
  - `lib/core/mock/mock_data.dart` (fix `MockAlarm.copyWith` `clearAssignee` flag + compute `MockDeviceProfile` counts dynamically from `MockDevice` list; add seeded demo datasets for relations, telemetry history, RPC, notifications, user settings)
  - `lib/core/api/repositories/`:
    - `server_config_repository.dart`, `auth_repository.dart`, `dashboard_repository.dart`, `alarm_repository.dart`, `device_repository.dart`, `asset_repository.dart`, `customer_repository.dart`, `telemetry_repository.dart`, `rpc_repository.dart`, `notification_repository.dart`, `audit_log_repository.dart`, `user_profile_repository.dart` (each with `Rest*` + `Demo*` implementations and exact `404`-only compatibility fallbacks; `403` surfaced cleanly as `TbFailureType.permissionDenied`)
  - `lib/core/api/controllers/`:
    - `server_config_controller.dart`, `auth_controller.dart`, `dashboard_controller.dart`, `alarm_controller.dart`, `device_controller.dart`, `asset_controller.dart`, `customer_controller.dart`, `telemetry_controller.dart`, `rpc_controller.dart`, `notification_controller.dart`, `audit_log_controller.dart`, `user_profile_controller.dart` (with `sessionGeneration` checks, `_requestSeq` + `CancelToken` race guards, atomic Demo<->Live & host-switch invalidation)
  - `lib/core/auth/login/provider/auth_provider.dart` (clean bridge exporting `authProvider`, `serverConfigProvider`, `dioClientProvider`)
  - `test/core/mock/mock_data_parity_test.dart`
  - `test/core/api/repositories/*_test.dart` and `test/core/api/controllers/*_test.dart`

### Worker 2B (`auth-and-shell`): Auth Flows (`Login`, `ResetPassword`, `2FA`, `MFA Setup`, `OAuthCallback`, `QrCodeScan`), Shell & Compiling Router
- **Owned Files:**
  - `lib/core/auth/login/` (`login_theme.dart`, `view/login_page.dart`, `widgets/login_widget.dart`, `widgets/text_field.dart` [fix `TbValidationMessages` + deprecated alias], `widgets/o_auth_buttons.dart`, `widgets/footer/login_footer.dart`, `widgets/header/login_header.dart`)
  - `lib/core/auth/reset_password/reset_password_request_page.dart`
  - `lib/core/auth/two_factor/two_factor_auth_page.dart` (`PRE_VERIFICATION_TOKEN` OTP flow)
  - `lib/core/auth/two_factor/mfa_setup_page.dart` (`MFA_CONFIGURATION_TOKEN` flow)
  - `lib/core/auth/oauth/oauth_callback_page.dart` (`/oauth2/callback` deep-link handler)
  - `lib/utils/ui/qr_code_scanner/qr_code_scanner_page.dart` (`mobile_scanner` + Demo simulated scan)
  - `lib/modules/main/navigation_page.dart` (adaptive `NavigationBar`/`NavigationRail` + `TbIcons` + live unread badges + `PopScope`)
  - `lib/config/routes/wave3_placeholders.dart` (temporary compiling stubs ONLY for Wave 3 destinations so Wave 2 compiles & passes all tests cleanly!)
  - `lib/config/routes/router.dart` (full `StatefulShellRoute.indexedStack` + `RouterRefreshNotifier` `refreshListenable` + `redirect` guard + M3 `CustomTransitionPage`, pointing Wave 3 destinations at `wave3_placeholders.dart`)
  - `lib/main.dart` (initializes `TbAppPreferences`, watches `themeModeProvider`, wires `tbLightTheme()` & `tbDarkTheme()`)
  - `test/core/auth/*_test.dart`, `test/modules/main/navigation_page_test.dart`, `test/config/router_guard_test.dart` (tests `unauthenticated`, `PRE_VERIFICATION_TOKEN`, `MFA_CONFIGURATION_TOKEN`, `authenticated`, cold-start `/oauth2/callback`, and `SessionMode.demo`)

---

## Wave 3 — Feature Screens (3 Parallel Feature Workers) + Single Post-Wave Route Wiring

> **Prerequisite:** Wave 2 gate passes (`flutter analyze`, `flutter test`).
> **Parallel Workers (`3A`, `3B`, `3C`):** Strictly disjoint module folders. None of `3A`–`3C` touch `router.dart`, `wave3_placeholders.dart`, or `home_placeholder_page.dart`.

### Worker 3A (`home-dashboards`): Home & Dashboards
- **Owned Files:**
  - `lib/modules/home/home_page.dart`
  - `lib/modules/dashboard/dashboards_page.dart` (adaptive 2-pane on `>=840dp`)
  - `lib/modules/dashboard/dashboard_details_page.dart` (live WS telemetry + `SparklineChart` + `useStrictDataTypes=true` + fullscreen + open-in-browser option)
  - `test/modules/home/home_page_test.dart`, `test/modules/dashboard/dashboards_page_test.dart`, `test/modules/dashboard/dashboard_details_page_test.dart`

### Worker 3B (`alarms-devices`): Alarms & Devices
- **Owned Files:**
  - `lib/modules/alarm/alarms_page.dart`, `lib/modules/alarm/alarm_details_page.dart`, `lib/modules/alarm/widgets/user_info_avatar_widget.dart` (adaptive 2-pane on `>=840dp`, dynamic assignee sheet, unassign clearing, optimistic comments)
  - `lib/modules/device/devices_main_page.dart`, `lib/modules/device/devices_list_page.dart`, `lib/modules/device/device_details_page.dart` (5 segments: `Telemetry`, `Attributes`, `RPC`, `Alarms`, `Info` + Relations; adaptive 2-pane on `>=840dp`)
  - `test/modules/alarm/alarms_page_test.dart`, `test/modules/alarm/alarm_details_page_test.dart`
  - `test/modules/device/devices_main_page_test.dart`, `test/modules/device/devices_list_page_test.dart`, `test/modules/device/device_details_page_test.dart`

### Worker 3C (`more-entities`): More Hub, Customers (+ Details), Assets (+ Details), Audit Logs, Notifications, Profile & Settings
- **Owned Files:**
  - `lib/modules/more/more_page.dart`
  - `lib/modules/customer/customers_page.dart`, `lib/modules/customer/customer_details_page.dart` (adaptive 2-pane on `>=840dp`)
  - `lib/modules/asset/assets_page.dart`, `lib/modules/asset/asset_details_page.dart` (adaptive 2-pane on `>=840dp`)
  - `lib/modules/audit_log/audit_logs_page.dart`
  - `lib/modules/notification/notifications_page.dart`
  - `lib/modules/profile/profile_settings_page.dart`
  - `test/modules/more/more_page_test.dart`, `test/modules/customer/customers_page_test.dart`, `test/modules/customer/customer_details_page_test.dart`, `test/modules/asset/assets_page_test.dart`, `test/modules/asset/asset_details_page_test.dart`, `test/modules/audit_log/audit_logs_page_test.dart`, `test/modules/notification/notifications_page_test.dart`, `test/modules/profile/profile_settings_page_test.dart`

### Step 3.4 — Single Post-Wave Route Integration Owner (`router-integrator`)
> Runs immediately after `3A`, `3B`, `3C` finish. Only ONE agent edits these files:
- **Owned Files:**
  - `lib/config/routes/router.dart` (replace `wave3_placeholders.dart` imports with all real Wave 3 screens)
  - Delete `lib/config/routes/wave3_placeholders.dart` and `lib/modules/home/home_placeholder_page.dart`
  - Update `test/config/router_guard_test.dart` & `test/widget_test.dart` to verify full route graph against real pages.

---

## Wave 4 — Cleanup, Static/UI Audit, APK Build, Live Emulator & Codex Review

> **Prerequisite:** Wave 3 + Step 3.4 gate passes. Single dedicated QA/Integration owner executes Wave 4 cleanly (zero overlapping edits).

1. **Final Cleanup:** Remove deprecated `DesignTokens.paddigZero` and `TbValicationMessages` aliases if unused; clean up any stale legacy mock providers in `lib/core/mock/mock_data.dart`.
2. **Static & Formatting Gates:**
   - `dart format --output=none --set-exit-if-changed .`
   - `flutter analyze` (`No issues found!`)
   - `python .agents/skills/flutter-ui/scripts/flutter_ui_audit.py .` -> **0 `RED` findings; review every `YELLOW` finding and fix or explicitly document justification.**
3. **Full Test Suite:**
   - `flutter test` -> 100% pass across all unit, repository, WS, router, widget, accessibility (`>=48dp`, `Semantics`, `2.0x` text scale), Light/Dark M3, and `disableAnimations` tests.
4. **Android Debug APK Build & Separate Device/Emulator Verification:**
   - `flutter build apk --debug` (then `cd android && .\gradlew --stop`).
   - Boot AVD (`tb_pixel_api35`), `adb install -r build/app/outputs/flutter-apk/app-debug.apk`.
   - **Verify deep-link & permissions on device:** test `adb shell am start -a android.intent.action.VIEW -d "org.thingsboard.pe.app.auth://callback?accessToken=test&refreshToken=test"` and confirm app handles callback without crash.
   - **Live `thingsboard.democloud.xyz` Smoke Test:** launch app on emulator, verify Login screen fetches OAuth2/password policy from `https://thingsboard.democloud.xyz/` without crash on `404` startup endpoints.
   - **Demo Mode End-to-End Visual Walkthrough + Screenshots:** tap `"Try Demo Mode"`, capture Light & Dark mode screenshots across Home, Dashboards + Details, Alarms + Details, Devices + Details (Telemetry/Attributes/RPC), More -> Customers (+ Details), Assets (+ Details), Audit Logs, Notifications, Profile & Settings.
5. **Final Codex Code Review:** Run `codex review` against the full branch diff and resolve any findings before final report.
