# Plan: password dialog, device info, dashboards, unified section style (2026-11-26)

Status: EXECUTED under the user's autonomous /loop instruction. Codex plan review: FAIL, fixed. Diff review: R1 FAIL, R2 FAIL, R3 PASS (fixes applied). Final: flutter test 259/259, analyze clean, dart format clean. Deviations: dashboard "target name" row removed (resolver does not load names without extra API calls); live API verification blocked (401). Owner: lead. Baseline: `flutter test` 209/209 green.

## 1. Requirements (restated) and interpretation
- **R1 Password.** On a phone, the floating `NavigationBar` (`navigation_page.dart`, `extendBody: true`) and the keyboard cover the "Update Password" button. Fix: open `_ChangePasswordSheet` with `showDialog(useRootNavigator: true)` as a centered, scrollable `Dialog` (`SingleChildScrollView` + `viewInsets` padding), with a Cancel action. Flow and API checked by tests. Why: a root dialog is above the shell, so nothing can cover it, and the keyboard only scrolls it.
- **R1 API (verified by reading the code).** `POST /api/auth/changePassword {currentPassword,newPassword}` -> `LoginResponse`. The controller writes the new token and refreshToken to secure storage (live mode). `TbAuthInterceptor` reads the token from storage on every request, so REST uses the new token right away. A controller test already covers this (`entities_telemetry_notifications_controller_test.dart:153`). The live check is blocked (401 on the test account).
- **R2 Dashboards, "shows info best".** List: one compact row or tile per dashboard (title, 1-line meta such as `Assigned · 3 customers` or relative time, star/visit action). No prose. Detail: a **summary header** (target entity name + ONLINE/OFFLINE/DEMO badge + metric count + last-update time) above the existing metric grid (value pill + sparkline). Why: an operator should see status first and trends second, and that matches the 3-line rule in ui-rules section 2.
- **R3 Device info.** In `_DeviceInfoSection`, one header row (name, status badge, profile icon), then grouped key-value sections: **Overview** (Profile=`deviceProfileName`, Label, Owner, Created, Active, Gateway if `additionalInfo.gateway`), **Credentials** (show/hide/copy, unchanged), **Relations**. Fix the bug where 'Profile' shows `device.type`. Why: it fixes the wrong data and puts the most-checked fields first.
- **R4 Consistent theme, concretely:** every detail and settings section uses ONE primitive `TbSectionCard` (`surfaceContainerLow`, `borderRadiusLarge`, `outlineVariant` 1px, `cardPadding`, `titleSmall w600` title, optional trailing action) and ONE `TbKvRow` (label `bodySmall onSurfaceVariant`, value `bodyMedium` with tabular figures, ellipsis). Sections are spaced `spacing12`, status always uses `TbStatusBadge`, and no ad-hoc `Container`/`Material` cards. Why: "the same on every page" can only be enforced through one shared widget. Scope: device info, dashboards, profile/settings. Other pages are a follow-up.

## 2. Tasks and file ownership (no file shared between A, B, C)
| Task | Owns (only these files) | Model |
|---|---|---|
| **S (lead, first)** | NEW `lib/widgets/tb_section_card.dart` (`TbSectionCard` + `TbKvRow`), NEW `test/widgets/tb_section_card_test.dart` | haiku max |
| **A Password** | `lib/modules/profile/profile_settings_page.dart`, `test/modules/profile/profile_settings_page_test.dart` | sonnet high |
| **B Device info** | `lib/modules/device/device_details_page.dart` (`_DeviceInfoSection`, `_InfoKvRow` only), `lib/core/api/repositories/device_repository.dart`, `lib/core/models/device_models.dart`, `test/modules/device/device_details_page_test.dart`, `test/core/api/models_parsing_test.dart` | sonnet high |
| **C Dashboards** | `lib/modules/dashboard/dashboards_page.dart`, `lib/modules/dashboard/dashboard_details_page.dart`, `test/modules/dashboard/*_test.dart` | sonnet high |

Shared-file edits: **only Task S** (a new widget file). A, B and C import it and do not edit it. If they need an API change, they tell the lead. Run order: S -> (A, B, C in parallel) -> lead runs the full suite.
B touches `models_parsing_test.dart`. It is only B's because nobody else touches it. `repositories_fallback_test.dart` is B's too if B needs it.

## 3. Tests first (red before green), acceptance and verification
### Task S
- `TbSectionCard renders title, child and trailing action`. `TbKvRow shows label/value, ellipsizes long value, '—' for empty`. `TbSectionCard uses surfaceContainerLow + outlineVariant in light and dark`.
- Accept: no raw colors or sizes; widget is const-constructible.

### Task A — password
1. **Regression (must fail before the fix):** `Update Password button is hit-testable above floating NavigationBar`. Pump `ProfileSettingsPage` inside `Scaffold(extendBody: true, bottomNavigationBar: NavigationBar(...))` on a nested `Navigator`, with surface 360x640 and `viewInsets.bottom = 300` (keyboard). Open Change Password, then `expect(find.widgetWithText(FilledButton,'Update Password').hitTestable(), findsOneWidget)`. Tap it and expect validation feedback.
2. `dialog is centered`: dialog rect center x equals screen center x (within 1px), and it is a `Dialog` on the root navigator.
3. `empty current password shows error, no API call` (`changePasswordCalls == 0`).
4. `policy: min length / uppercase / digit / special each block submit` (table-driven).
5. `mismatch confirm shows 'New passwords do not match'`.
6. `success: calls repo once with exact current/new values, closes dialog, shows 'Password changed successfully'`.
7. `TbFailure from repo (400 wrong current pwd) shows its message and keeps dialog open; button re-enabled`.
8. `double tap while saving submits once`.
9. `Cancel closes without API call`.
- Fix also: capture `ScaffoldMessenger`/`Navigator` before `await` (no context use after pop). Use the `TbSectionCard` style for profile sections if the diff stays small.
- Accept: 1-9 green, 2.0x text scale and dark theme tests still pass.

### Task B — device info
1. `TbDeviceInfo.fromJson`: profile name from `deviceProfileName` (not `type`); falls back to `type` when missing.
2. `active`: bool true, string "true", missing -> false.
3. `owner`: `ownerName` wins; falls back to `customerTitle`; nullUuid customerId -> null.
4. `createdTime`: num -> int; missing -> 0, and UI shows '—'.
5. `copyWith(active:)` keeps every other field (profile name, owner, created).
6. Widget: `Info tab shows Profile = deviceProfileName` (fixture with type != profile name, **fails now**), `shows Owner, Created (yyyy-MM-dd HH:mm), status badge ONLINE/OFFLINE`, `credentials Show/Hide/Copy still work`, `relations empty -> 'No linked entities'`, `relation tap navigates`, `sections use TbSectionCard (findsNWidgets(3))`.
7. Repository (mock dio): `getDeviceInfo uses /api/device/info/{id}; when 'active' missing, falls back to attribute`. Check this test exists and add it only if missing.
- Accept: Profile bug fixed, the nested `ListView(itemCount:3)` becomes a flat `ListView(children:[...])` of `TbSectionCard`s, and `_InfoKvRow` is removed (replaced by `TbKvRow`).

### Task C — dashboards
1. `detail shows summary header: entity name, status badge (DEMO in demo mode), metric count, last update`.
2. `metric cards use tabular figures and keep stable order on live update`.
3. `empty metrics -> 'Web dashboard' + Open in browser` (existing), `error -> Retry` (existing, keep).
4. `list row shows title + 1 meta line, max 3 lines, no overflow at 2.0x text scale`.
5. `list: search/filter/pagination still work` (existing tests stay green).
- Accept: no new providers. The summary is built from data already watched. Both pages use `TbSectionCard` or the M3 list style.

### Verification commands (lead, after each task and at the end)
```
FL=/c/src/flutter/bin/flutter.bat
$FL test test/modules/profile test/modules/device test/modules/dashboard test/core/api test/widgets
$FL test                       # full suite, expect >= 209 + new tests, 0 failures
$FL analyze --no-pub           # 0 issues in touched files
dart format --output=none --set-exit-if-changed lib/widgets/tb_section_card.dart <touched files>
```
Manual (optional, device-lab): demo mode, Profile -> Change Password with keyboard open, then tap Update.

## 4. Model choice
S: haiku max (mechanical widget). A, B, C: sonnet high (logic, layout and data parsing). If a task fails twice: opus advisor, then sonnet continues.

## 5. Quality rubric (100 points, pass >= 90)
| Area | Pts | Full marks when |
|---|---|---|
| Behavior fixed | 30 | Password button reachable with keyboard and nav bar (10). Password flow correct, errors shown (8). Device Profile, Owner, Created and Active correct (7). Dashboard summary header present (5). |
| Tests | 25 | Every listed test exists (15). The regression test fails on the old code (5). Full suite green (5). |
| UI consistency | 20 | All touched sections use TbSectionCard/TbKvRow (10). Tokens only, no raw colors or sizes (5). Dark mode and 2.0x text scale OK (5). |
| Code quality / minimal diff | 15 | Edits stay in the owned files and symbols (5). No new deps or providers (5). Analyze clean (5). |
| Verification evidence | 10 | Real command output pasted (test count and analyze result). |
Below 90: fix the lowest area first, at most 3 rounds, then stop and report.

## 6. Risks and open questions (for the user)
1. **Live password change is not verified.** The test account gets 401 on the server. Can you confirm the account works, or test it by hand once? Note that a successful change also changes the account's password.
2. **WebSocket after a password change:** ThingsBoard may revoke old sessions. REST refreshes the token from storage, but the auth state and the WS service may keep the old token until they reconnect. Fixing this means editing `auth_controller` and the WS service, which is outside these tasks. Follow-up?
3. `TbDeviceInfo ==` compares only id, name and active. A profile or owner change on the server may not rebuild `select()` watchers. Should it be widened (task B)?
4. `flutter analyze` needs Windows Developer Mode (symlinks). We use `--no-pub`. Turn on Developer Mode for a clean pub run?
5. Scope of R4: this plan unifies device info, dashboards and profile. Should alarms, assets, customers and audit pages follow in a second pass?
6. Dialog vs bottom sheet: the plan uses a centered dialog (the user said "or center it"). Prefer a full-height sheet?
