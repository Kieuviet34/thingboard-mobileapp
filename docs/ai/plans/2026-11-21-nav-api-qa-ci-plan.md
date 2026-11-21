# Plan: Nav chuyển động mới · Kiểm toán API gốc · CI & QA/QC · Dọn codebase

Ngày: 2026-11-21 · Nhánh: `dmhoang` · Tiếp nối [2026-11-21-ui-upgrade-plan.md](2026-11-21-ui-upgrade-plan.md)

## Mục tiêu (mỗi mảng một vấn đề cốt lõi)
1. **Nav:** pill bo tròn hoàn toàn, kính mờ (translucent) vẫn đọc rõ; chạm icon → nhãn trượt hiện **bên phải icon** (không còn nhãn dưới), mượt, GPU-safe, tôn trọng reduced-motion.
2. **API:** mọi request app gửi và mọi trường app đọc khớp **ThingsBoard REST API 4.4.1PAAS** (OpenAPI công khai), có test chứng minh.
3. **CI & QA/QC:** pipeline tự động chặn lỗi (format, analyze, test, contract, build) + checklist QA thủ công.
4. **Codebase sạch:** không code chết, không file tạm, `analyze` 0 issue, format sạch.

## Phân vai model (tiết kiệm token)
| Việc | Model |
|---|---|
| Lập plan, thiết kế nav, thiết kế công cụ contract, review diff, quyết định sửa API | Sonnet 5.5 (phiên chính) |
| Việc lặp/cơ học: viết test hợp đồng theo mẫu, đối chiếu từng repository, dọn code chết | Haiku 5.5 (subagent, đọc-ghi theo công thức có sẵn) |
| Review cuối độc lập (nếu cần) | Opus 5.5 |
Quy tắc: subagent không chạy Gradle; chỉ phiên chính chạy `flutter build`. Agent chỉ format file của mình, không `dart format .` toàn repo.

## Nguồn chuẩn (API gốc)
- OpenAPI công khai `https://demo.thingsboard.io/v3/api-docs` → **version 4.4.1PAAS** (745 path, 1082 schema), tải vào thư mục tạm (không commit bản gốc 1.8MB).
- Snapshot rút gọn (chỉ endpoint/schema app dùng) commit tại `test/fixtures/contract/` để CI chạy offline, tái sinh được bằng `tools/api_contract/`.
- Nội bộ: `docs/research/api-controller-matrix.md`, `docs/research/thingsboard-pe-api.md`.

## Checklist

### A. Nav (WP-A)
- [x] A1 Chốt thiết kế: kính mờ (`surface` alpha + blur), viền `outlineVariant`, indicator `primaryContainer`, chữ `onPrimaryContainer` (tương phản ≥ 4.5:1 cả sáng/tối)
- [x] A2 `TbFloatingNavBar` tự dựng (nhãn bên phải icon); layout tính bằng hàm thuần để test được
- [x] A3 Chuyển động chỉ dùng paint/transform (Opacity/translate/RRect repaint), không animate width/padding; tắt khi `disableAnimations`
- [x] A4 a11y: `Semantics(button, selected)`, tooltip, vùng chạm ≥ 48dp, badge đọc được
- [x] A5 Test: unit layout math; widget test 13 cỡ máy × 2 cỡ chữ; tap chuyển tab; reduced-motion
- [x] A6 Ảnh chụp kiểm tra sáng/tối/ngang/tablet, đọc lại từng ảnh
- [x] A7 Xóa `TbNavigationBarWidget`/`BottomNavbarItems` nếu không còn dùng

### B. API audit (WP-B/C)
- [x] B1 Công cụ tĩnh `tools/api_contract/`: trích endpoint từ repositories, đối chiếu spec (path, method)
- [x] B2 Công cụ khóa model: so khóa `json['x']` của model với schema (thiếu/thừa/sai chính tả)
- [x] B3 Báo cáo sai khác → `docs/api/audit-2026-11-21.md`
- [x] B4 Helper test `test/helpers/openapi_contract.dart`: xác thực request thực tế (method, path, tham số bắt buộc, enum, body)
- [x] B5 Test hợp đồng cho từng repository (alarm, device, asset, customer, dashboard, notification, audit, telemetry, rpc, auth, user profile, server config)
- [x] B6 Sửa từng sai khác đã xác nhận theo TDD (test đỏ → sửa → xanh), mỗi sửa có bằng chứng spec
- [x] B7 Controller: kiểm đầu vào/đầu ra, lỗi `TbFailure`, hủy request, race; bổ sung test thiếu
- [x] B8 UI hiển thị dữ liệu: loading/empty/error/retry không crash với payload thiếu trường

### C. CI & QA/QC (WP-D)
- [x] C1 `.github/workflows/ci.yml`: format check → analyze → test + coverage → contract → build apk debug
- [x] C2 Cache pub/gradle, pin phiên bản Flutter, hủy run cũ (concurrency)
- [x] C3 `docs/qa/QA_CHECKLIST.md`: checklist thủ công theo màn hình/cỡ máy/dark/chữ lớn/offline/demo
- [x] C4 `docs/qa/API_CONTRACT.md`: cách chạy/tái sinh contract, quy trình khi ThingsBoard đổi API
- [x] C5 PR template + ngưỡng coverage
- [x] C6 Cập nhật `AGENTS.md`/`api-rules.md` lệnh kiểm chứng cho khớp CI

### D. Codebase sạch (WP-E)
- [x] D1 Xóa file tạm (`test/screenshots/`), code chết, import thừa, token không dùng
- [x] D2 `dart format --set-exit-if-changed .` sạch
- [x] D3 `flutter analyze` 0 issue
- [x] D4 `flutter test` toàn bộ xanh (ghi số test)
- [x] D5 `flutter build apk --debug` (JDK 17 qua `JAVA_HOME`, xong `jvm-ondemand.ps1 stop`): build OK 178s

## Cổng nghiệm thu
Chỉ đánh dấu xong khi có output thật của lệnh tương ứng. Hạng mục không kiểm chứng được ghi rõ trong báo cáo cuối.
