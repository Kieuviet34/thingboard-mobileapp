# AGENTS.md

## Project
ThingsBoard PE / DemoCloud Flutter mobile app (`thingsboard_democloud_app`, Dart ^3.7.0, `hooks_riverpod`, `go_router`, `dio`).
Supports Android & iOS with Material Design 3 UI/UX and ThingsBoard PE 4.4.x REST/WebSocket + Demo/Offline mode.

## Commands
- Analyze: `flutter analyze`
- Test: `flutter test`
- Format: `dart format .`
- Build Android debug APK: `flutter build apk --debug`

## Map & Docs
- `lib/config/` — M3 themes, `DesignTokens`, `go_router` routes + auth guard
- `lib/core/` — auth, `api/` controllers/repositories, WebSocket service, `mock/` demo data
- `lib/modules/` — feature screens and navigation shell
- `lib/widgets/` — shared M3 components and `TbIcons` custom icon kit
- `docs/ai/ARCHITECTURE.md` — stack, module boundaries, external services, known pitfalls
- `docs/ai/ui-rules.md` — M3 tokens, minimal-text IoT UI, custom icons, GPU motion, accessibility
- `docs/ai/api-rules.md` — REST/WS rules, `X-Authorization` refresh, Demo mode, error mapping, TDD/QA

## Core Project Standards (Summary — full rules in `docs/ai/`)
- **Material Design 3 & Accessibility:** `useMaterial3: true`, semantic `ColorScheme` + status `ThemeExtension`, light & dark themes, adaptive breakpoints (`NavigationBar` -> `NavigationRail`/2-pane), `>= 48dp` touch targets, `Semantics`, never color-only status.
- **Minimal-Text IoT UI ("gọn gàng ít chữ nhất"):** Metric pills (`tabularFigures`), 1-word status badges, icon+value pairs, progressive disclosure; ban prose paragraphs and nested card-per-row clutter.
- **Custom Icon Identity ("bộ nhận diện icon riêng"):** Use `TbIcons` custom SVG/`CustomPainter` IoT kit (nav, device types, telemetry, alarm severity glyphs, assets) themed via `ColorScheme`; `RepaintBoundary` on painters.
- **GPU-Safe Motion:** Animate only `Transform`/`Opacity`/`Hero`/stagger/shimmer; dispose all `AnimationController`s; honor `MediaQuery.disableAnimationsOf(context)`.
- **API, Auth & QA:** Single `hooks_riverpod` + `dio` + shared `wss://<host>/api/ws` service; `X-Authorization: Bearer` with single-flight `/api/auth/token` refresh; graceful `404` startup fallbacks; seamless `SessionMode.demo` fallback; TDD unit + widget tests required.

## Additional Project Skills (non-SkillForge)
- `material-design-3-ui` -> `.agents/skills/material-design-3-ui/SKILL.md` (also `.claude/skills/material-design-3-ui/SKILL.md`; source: `skydashnet/material-design-3-ui-skill` v1.1.1; triggers: material-design-3-ui, material 3, m3, material you, design tokens, accessibility, adaptive layout)

<!-- skillforge:begin (auto-generated, edit outside this block) -->
## Prime directive — bám cốt lõi, đừng lan man
- Xác định ĐÚNG MỘT vấn đề cốt lõi của yêu cầu và nhắc lại nó bằng 1 câu trước khi làm. Mọi thay đổi phải phục vụ câu đó; việc ngoài phạm vi thì ghi ra "follow-up", không tự làm.
- Đọc vừa đủ: chỉ mở file/đoạn liên quan trực tiếp (dùng search theo symbol, không đọc cả cây thư mục, không dán file lớn vào ngữ cảnh). Đủ thông tin để hành động thì hành động, đừng khảo sát tràn lan.
- Đổi ít nhất có thể: diff nhỏ, đúng chỗ; không refactor/đổi tên/đổi style ngoài yêu cầu; không xoá code/test chưa hiểu rõ.
- Không bịa: không chắc về API/hành vi thì kiểm chứng bằng code/tài liệu (hoặc skill tra cứu), không đoán. Nêu rõ chỗ chưa chắc.
- Không trôi phạm vi: sau 2 lần sửa không xong hoặc thấy mình đang mở rộng ra ngoài cốt lõi thì DỪNG, tóm tắt, và xác nhận hướng lại.
- Chỉ nạp skill khớp task; bỏ qua skill không liên quan để khỏi loãng ngữ cảnh và sai trọng tâm.

## Working rules (all agents)
- Before coding: restate the goal, list assumptions, ask only when a wrong guess is costly. For >1 file or unclear scope, write a short plan first (`docs/ai/plans/`).
- Simplest thing that works. No speculative abstractions, no unrequested features, no drive-by refactors. Match surrounding code style.
- Surgical diffs: touch only what the task needs; never reformat unrelated code; never delete code/tests you don't understand.
- Read before write: search for existing helpers/patterns before adding new ones. Prefer editing over creating files.
- Verify, don't assume: run the build/tests/lint in **Commands** after changes and report real output. Done = verification passes, or the gap is stated.
- Bugs: reproduce -> root cause -> failing test -> fix -> confirm. No guess-and-patch loops; after 2 failed attempts stop and re-analyze.
- Tests for logic you add/change (behaviour, not implementation). Never weaken or skip a test to make it pass.
- Security: never hardcode/log secrets, tokens or PII; validate external input; least privilege; parameterized queries.
- Dependencies: justify each new one; prefer platform/std lib; pin versions.
- Git: small logical commits, imperative messages; never force-push, rewrite history or commit secrets without explicit approval.
- Context economy: open files on demand, not whole trees; keep durable knowledge in `docs/ai/` (ARCHITECTURE.md, decisions/) instead of this file.
- Skills: when a task matches an installed skill, follow it instead of improvising; ignore skills unrelated to the task.
- Report: concise — what changed, why, how it was verified, risks/follow-ups.

## Flutter / cross-platform rules
- Dart null-safety; `flutter analyze` clean; immutable models; feature-first folders.
- Keep the state-management lib already used (Riverpod/Bloc/…); never introduce a second one.
- Small `const` widgets; no business logic in widgets; platform channels behind interfaces.
- Commands: `flutter analyze`, `flutter test`, `dart format .`, `flutter build apk` / `flutter build ios`.
- Respect Material/Cupertino conventions and accessibility (Semantics); verify on Android and iOS.

## Công cụ dịch ngược đã cài trên máy này
- Danh sách công cụ, phiên bản, cách gọi nhanh, MCP đang bật/tắt: `.skillforge/TOOLS.md` (tự sinh; đọc khi cần, không nạp mặc định).
- MCP mặc định TẮT để tiết kiệm token. Bật khi cần: `python -m skillforge mcp on <tên>`; xong thì `mcp off <tên>`.

<!-- SKILLS_INDEX_START -->
## Chỉ mục Định tuyến Skills & MCP (Tiết kiệm Token)
- **Nguyên tắc:** Chỉ nạp `SKILL.md` khớp đúng tác vụ đang làm (không đọc tràn lan toàn bộ thư mục skill). Khi cần bật MCP đang tắt hoặc gọi CLI tool, đọc `.skillforge/TOOLS.md`.
- **Skills đã cài trong repo:**
  - `api-designer` -> `.agents/skills/api-designer/SKILL.md` (triggers: api-designer, api-designer-rest, backend, api, api-design)
  - `code-review` -> `.agents/skills/code-review/SKILL.md` (triggers: code-review, mattpocock-core, all, workflow)
  - `diagnosing-bugs` -> `.agents/skills/diagnosing-bugs/SKILL.md` (triggers: diagnosing-bugs, mattpocock-core, all, workflow)
  - `domain-modeling` -> `.agents/skills/domain-modeling/SKILL.md` (triggers: domain-modeling, mattpocock-core, all, workflow)
  - `find-bugs` -> `.agents/skills/find-bugs/SKILL.md` (triggers: find-bugs, sentry-security-review, backend, web, security, backend-security)
  - `find-docs` -> `.agents/skills/find-docs/SKILL.md` (triggers: find-docs, context7-skill, all, docs)
  - `flutter-ui` -> `.agents/skills/flutter-ui/SKILL.md` (triggers: flutter-ui, flutter-ui-naime, mobile, flutter, mobile-cross)
  - `grill-me` -> `.agents/skills/grill-me/SKILL.md` (triggers: grill-me, mattpocock-core, all, workflow)
  - `handoff` -> `.agents/skills/handoff/SKILL.md` (triggers: handoff, mattpocock-core, all, workflow)
  - `impeccable` -> `.agents/skills/impeccable/SKILL.md` (triggers: impeccable, web, ui, web-ui)
  - `implement` -> `.agents/skills/implement/SKILL.md` (triggers: implement, mattpocock-core, all, workflow)
  - `improve-codebase-architecture` -> `.agents/skills/improve-codebase-architecture/SKILL.md` (triggers: improve-codebase-architecture, mattpocock-core, all, workflow)
  - `research` -> `.agents/skills/research/SKILL.md` (triggers: research, mattpocock-core, all, workflow)
  - `security-review` -> `.agents/skills/security-review/SKILL.md` (triggers: security-review, sentry-security-review, backend, web, security, backend-security)
  - `setup-matt-pocock-skills` -> `.agents/skills/setup-matt-pocock-skills/SKILL.md` (triggers: setup-matt-pocock-skills, mattpocock-core, all, workflow)
  - `tdd` -> `.agents/skills/tdd/SKILL.md` (triggers: tdd, mattpocock-core, all, workflow)
  - `to-spec` -> `.agents/skills/to-spec/SKILL.md` (triggers: to-spec, mattpocock-core, all, workflow)
  - `to-tickets` -> `.agents/skills/to-tickets/SKILL.md` (triggers: to-tickets, mattpocock-core, all, workflow)
- **MCP đang bật (repo):** `codegraph` · **MCP Global:** `codegraph`
- **MCP khả dụng theo nhu cầu** (`python -m skillforge mcp on <tên>` hoặc `--global`): `chrome-devtools`, `codebase-memory`, `codegraph`, `context7`, `ghidra`, `github`, `hermes`, `ida-pro`, `jadx`, `markitdown`, `playwright`, `rea`
<!-- SKILLS_INDEX_END -->
<!-- skillforge:end -->
