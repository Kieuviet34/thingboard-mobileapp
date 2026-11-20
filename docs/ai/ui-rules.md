# UI/UX Rules — Material Design 3, Minimal-Text IoT, Custom Icons & Motion

> Grounded in `.agents/skills/material-design-3-ui/SKILL.md`, `.agents/skills/flutter-ui/SKILL.md`, and `lib/config/themes/`.
> All UI edits in `lib/` MUST follow these rules.

---

## 1. Material Design 3 & Semantic Tokens
- **Enable M3 everywhere:** `ThemeData(useMaterial3: true, ...)` in `lib/config/themes/tb_theme.dart`. Remove Material 2 fallbacks (`Typography.material2018()`).
- **Light & Dark Themes:** `MaterialApp.router` in `lib/main.dart` MUST provide distinct `theme` (`Brightness.light`) and `darkTheme` (`Brightness.dark`) and respect user/system `ThemeMode` (do not hardcode `ThemeMode.light` or pass light theme to `darkTheme`).
- **Semantic ColorScheme Roles:** Generate base schemes via `ColorScheme.fromSeed(...)` with ThingsBoard brand overrides, and use `Theme.of(context).colorScheme` exclusively in widgets:
  - Screen base: `surface`, containers: `surfaceContainerLowest` -> `surfaceContainerHighest`, borders: `outlineVariant` / `outline`.
  - Primary CTA: `primary` + `onPrimary`; softer emphasis: `primaryContainer` + `onPrimaryContainer` (`FilledButton.tonal`).
  - Destructive/error: `error` + `onError` / `errorContainer` + `onErrorContainer`.
- **IoT Status `ThemeExtension`:** Define a `TbStatusColors` `ThemeExtension<TbStatusColors>` for semantic IoT/Alarm states (`critical`, `major`, `minor`, `warning`, `indeterminate`, `cleared`, `online`, `offline`, `demo`) with paired `on*` / container roles for both light and dark themes.
- **No Raw Styling in Widgets:** NEVER hardcode `Color(0xFF...)`, arbitrary `fontSize`, or magic spacing inside `lib/modules/` or `lib/widgets/`. Always read `Theme.of(context).colorScheme`, `Theme.of(context).textTheme`, `TbStatusColors`, and `DesignTokens` (`lib/config/themes/design_tokens.dart`).

---

## 2. Minimal-Text, Scannable IoT UI ("gọn gàng ít chữ nhất")
IoT operators scan telemetry and alarms at a glance. Every screen must maximize signal-to-prose ratio:
- **Ban verbose prose:** No multi-line explanatory paragraphs inside list cards, empty states, or dashboard tiles. Empty/error states use **1 short title (2–4 words) + 1 concise action button**.
- **Metric Pills:** Display live telemetry as compact pills: `[Custom Icon] 24.6 °C` using `fontFeatures: [FontFeature.tabularFigures()]` so updating numbers never jitter horizontally.
- **Status Badges:** Use compact 1-word status chips (`ACTIVE`, `ACK`, `ONLINE`, `OFFLINE`, `CRITICAL`) pairing **icon glyph + semantic color + short label** (never color alone, never full sentences).
- **Icon + Value Pairs:** Device/asset/customer rows show at most **3 scannable lines**:
  1. Primary name + status badge
  2. Type/profile icon + label (`Sensor · Floor 2`)
  3. Compact metric strip (2–3 key pills or relative timestamp like `2m ago`)
- **Progressive Disclosure:** Keep summary rows clean; move secondary attributes, JSON payloads, relations, and audit history into detail tabs, expandable sections, or `ModalBottomSheet`.
- **Restrained Containment:** Do NOT wrap every section or list row in nested elevated cards. Use M3 `ListTile` / flat tonal `surfaceContainerLow` groups separated by `DesignTokens.spacing8` or `outlineVariant` dividers; reserve `Card` for genuinely distinct interactive units.

---

## 3. Custom Icon Identity ("bộ nhận diện icon riêng")
Move away from generic stock `Icons.*` across the app. Build and maintain a cohesive ThingsBoard IoT icon kit (`TbIcons` in `lib/widgets/icons/`):
- **Brand Assets Foundation:** Leverage existing `assets/images/` (`thingsboard.svg`, `thingsboard_outer.svg`, `thingsboard_center.svg`, `device-placeholder.svg`, `device-profile-placeholder.svg`, `dashboard-placeholder.svg`, `scaner.svg`, etc.) and add custom crisp vector/SVG or `CustomPainter` icons where stock icons feel generic.
- **Required Custom Icon Categories:**
  1. **Bottom Navigation / Shell:** Custom active (filled/duotone) vs inactive (outlined) icons for `Home/Dashboards`, `Alarms`, `Devices`, `More`.
  2. **IoT Entity & Device Types:** Sensor node, gateway/router, smart meter, actuator/switch, asset/building, customer/organization.
  3. **Telemetry & Control:** Temperature, humidity, power/energy, signal/RSSI, battery, RPC command pulse.
  4. **Alarm Severities & Status:** Distinct geometric glyphs for `CRITICAL` (octagon/alert), `MAJOR` (triangle), `MINOR` (diamond), `WARNING` (circle-bang), `INDETERMINATE` (question/dashed), `CLEARED` (check-shield) so severity is recognizable even in monochrome.
- **Implementation Rules for Custom Icons:**
  - Consistent visual weight: `24dp` base grid, `1.75dp` stroke width, rounded stroke caps/joins.
  - Theme-aware coloring: SVGs MUST apply `ColorFilter.mode(color, BlendMode.srcIn)` (or `Theme.of(context).colorScheme` / `IconTheme.of(context).color`), never baked-in black/gray fills that break Dark Mode.
  - Wrap complex `CustomPaint` icons/illustrations in `RepaintBoundary`.
  - Every interactive icon-only control MUST provide `tooltip` or `Semantics(label: ..., button: true)`.

---

## 4. Smooth GPU-Accelerated Motion & Micro-interactions
Motion must clarify spatial hierarchy, live updates, and user feedback at 60/120fps:
- **GPU-Safe Properties Only:** Animate `Transform.translate`, `Transform.scale`, `Transform.rotate`, `Opacity`, `FadeTransition`, `ScaleTransition`, `SlideTransition`, or `AnimatedSwitcher`. NEVER animate `width`, `height`, `margin`, `padding`, or `Positioned` top/left inside animation loops.
- **Required Micro-interactions:**
  - **Page Transitions:** Use `GoRouter` `CustomTransitionPage` (M3 shared-axis / fade-through) instead of jarring default cuts.
  - **Shared Elements (`Hero`):** Unique data-driven `Hero` tags (`'device-${device.id}'`, `'alarm-${alarm.id}'`, `'dashboard-${dashboard.id}'`) from list cards into detail headers.
  - **Loading Skeletons:** Use smooth animated shimmer placeholders (`surfaceContainerLow` -> `surfaceContainerHigh` gradient) for initial list/card loads instead of bare centered spinners.
  - **Live Telemetry Feedback:** Subtle `AnimatedSwitcher` or pulse indicator when WebSocket telemetry/alarm updates arrive; tabular figures prevent layout shift.
  - **Staggered List Entry:** Optional short stagger (`<= 40ms` per visible item, capped total `<= 320ms`) on first load only — never replay on scroll or minor state updates.
  - **Tactile Press Feedback:** Subtle scale (`0.98`) + M3 ink ripple on primary interactive cards/pills.
- **Lifecycle & Disposal:** Every `AnimationController` MUST be disposed in `State.dispose()` (or managed via `useAnimationController` from `flutter_hooks`).
- **Reduced Motion:** Check `MediaQuery.disableAnimationsOf(context)`; when `true`, collapse transitions/staggers to instant or minimal opacity fades. Every state must remain 100% clear with animations disabled.

---

## 5. Adaptive Layout, Navigation & Accessibility (Release Gate)
- **Adaptive Breakpoints:**
  - Compact (`width < 600`): bottom `NavigationBar` (`NavigationPage`).
  - Medium (`600 <= width < 840`): `NavigationRail`.
  - Expanded (`width >= 840`): `NavigationRail` / persistent drawer + 2-pane master-detail for `Devices`, `Alarms`, `Dashboards`, `Assets`, and `Customers` (never stretch a single-column phone card across a tablet screen).
- **Navigation Integrity:** Use `GoRouter` (`context.go` / `context.push`), `StatefulShellRoute.indexedStack` (or equivalent shell) so tab scroll/filter state persists, and `PopScope` (never deprecated `WillPopScope`).
- **Accessibility Checklist:**
  - Minimum `48dp x 48dp` hit target on every tappable control (pad smaller `20dp`/`24dp` icons with `constraints: BoxConstraints(minWidth: 48, minHeight: 48)` or `MaterialTapTargetSize.padded`).
  - Text contrast `>= 4.5:1`; non-text icon/badge/chart graphics `>= 3:1` in both Light and Dark themes.
  - Support dynamic text scaling up to `2.0x` (`MediaQuery.textScaler`) — never put text inside fixed-height boxes that clip at `1.5x`–`2.0x` scale; use `Flexible`/`Expanded` and `maxLines` + `TextOverflow.ellipsis` thoughtfully.
  - Non-decorative images/icons have `Semantics`; decorative assets use `ExcludeSemantics`.
- **Widget Craft:** Small `const` widgets, `ListView.builder` / `SliverList` for collections, no business logic in `build()`, `ref.watch()` in `build()` and `ref.read()` only in callbacks.
