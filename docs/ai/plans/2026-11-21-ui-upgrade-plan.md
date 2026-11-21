# Plan: Nâng cấp UI toàn app theo `docs/ai/ui-rules.md`

Ngày: 2026-11-21 · Nhánh: `dmhoang`

## Vấn đề cốt lõi
Đưa các màn hình hiện có trong `lib/modules/`, `lib/widgets/` và `lib/core/auth/` về đúng rule M3 + "ít chữ" + icon kit `TbIcons` + a11y, mà không đổi hành vi nghiệp vụ hay luồng điều hướng.

## Hiện trạng đo được (trước khi sửa)
- Theme M3 (`tb_theme.dart`, `tb_status_colors.dart`, `design_tokens.dart`) đã có: không cần đụng.
- Có sẵn widget dùng chung: `tb_metric_pill`, `tb_status_badge`, `tb_empty_state`, `tb_shimmer`, `tb_motion`, `tb_app_bar`, `tb_app_search_bar`.
- Vi phạm rule: 27 file còn dùng `Icons.*` stock; 26 chỗ `Card(`; 1 `fontSize` cứng; `TbIcons` mới có severity + device type + telemetry.
- 0 `Color(0x…)` cứng trong `modules/`, `widgets/`, `core/auth/`.

## Giả định
- "Nâng cấp UI all" = áp rule `ui-rules.md` cho mọi màn hình, không đổi luồng/API/model.
- Icon chức năng (search, filter, refresh, settings…) giữ Material Icons; chỉ thay bằng `TbIcons` ở nơi đã có kind tương ứng (nav, severity, device, telemetry). Vẽ thêm painter mới là follow-up.
- Không chạy Gradle/APK trong đợt này (theo quy tắc JVM của dự án); kiểm bằng `flutter analyze`, `flutter test`, `dart format`.

## Đợt 1 — Shell & widget dùng chung
1. Shell điều hướng (`navigation_page.dart`, `tb_navigation_bar_widget.dart`, `bottom_navbar_items.dart`): nav dùng `TbIcon` active/inactive khi có kind; tooltip/Semantics cho nút icon-only.
2. `tb_empty_state.dart`, `tb_status_badge.dart`, `tb_app_bar.dart`, `tb_app_search_bar.dart`: tiêu đề ≤4 từ + 1 hành động; hit target ≥48dp; không màu-đơn-độc.

## Đợt 2 — Màn hình chính (list/summary)
Home, Dashboards, Alarms, Devices (list + main): bỏ `Card` lồng trong list → `ListTile` / nhóm `surfaceContainerLow`; metric pill với tabular figures; thay icon stock bằng `TbIcons` khi có kind; `Hero` tag theo id ở list→detail nếu chưa có.

## Đợt 3 — Màn hình phụ & chi tiết
More, Customers (+details), Assets (+details), Audit logs, Notifications, Profile & Settings, Device/Alarm/Dashboard details: giảm chữ, progressive disclosure, thay `fontSize` cứng bằng `textTheme`.

## Đợt 4 — Auth
Login widgets, MFA, 2FA, reset password, OAuth callback: chỉ sửa icon/tokens/a11y; không đổi flow đăng nhập.

## Kiểm chứng
- `flutter analyze` sạch (không tăng warning so với baseline).
- `flutter test` pass.
- `dart format` trên file đã sửa.
- Ghi rõ những gì chưa làm trong báo cáo cuối (follow-up).

## Kết quả thực tế (đã làm)
Kiểm kê cho thấy phần lớn rule trong `ui-rules.md` đã được áp dụng từ các đợt trước: shell nav có `TbIcon` active/inactive + tooltip + badge; mọi `IconButton` đã có `tooltip`; shimmer đã thay spinner ở lần tải đầu; Hero tag có ở 7 chỗ; `TbMetricPill` dùng tabular figures; `TbMotion` có reduced-motion. Đợt này chỉ sửa phần còn lệch:
- `DesignTokens`: thêm `navBarHeight`, `radiusFloatingBar`, `bottomNavClearance`, `emptyStateBadgeSize`, `emptyStateMaxWidth`.
- `navigation_page.dart`: thay số ma padding/radius/height của thanh nav nổi.
- `tb_empty_state.dart`: thay số ma kích thước badge và độ rộng tối đa.
- `home_page.dart`, `more_page.dart`: khoảng đệm dưới nav → `bottomNavClearance`.
- `alarms_page.dart`: `size: 24` → `iconMedium`.

Kiểm chứng: `dart format` (0 file đổi), `flutter analyze` (No issues found), `flutter test` (194 test pass). Chưa build APK (quy tắc JVM của dự án; chưa chạy qua `jvm-ondemand.ps1`).

Giữ nguyên có chủ đích: spinner trong nút submit và spinner "tải thêm" cuối list phân trang; icon chức năng (back/search/check/chevron/refresh) dùng Material Icons vì kit `TbIcons` chưa có kind cho chúng.

## Đợt bổ sung — Nav nổi bo tròn hoàn toàn, responsive
> Đã được thay thế bởi `TbFloatingNavBar` (kính mờ + nhãn trượt sang phải) — xem [2026-11-21-nav-api-qa-ci-plan.md](2026-11-21-nav-api-qa-ci-plan.md). Ghi chú dưới đây là bước trung gian.
- Nguyên nhân lỗi cũ: bóng đổ nằm trong `ClipRRect` nên bị cắt; viền 1px làm thanh cao 66 với bán kính 32 (đầu không tròn hẳn); nền `alpha 0.82` + blur làm lộ nội dung bên dưới.
- Bước trung gian: `Material` + `StadiumBorder` (tròn hoàn toàn mọi chiều cao), nền đặc, viền `outlineVariant`, bỏ bóng đổ (bóng `elevation` vẽ thành viền đen cứng trong render). Sau đó người dùng yêu cầu kính mờ trong suốt nên bản cuối dùng blur + alpha 0.85, tự đặc khi bật độ tương phản cao.
- Responsive: lề 8dp khi `< 360dp`, tối đa `480dp` căn giữa trên điện thoại lớn/gập; rail không `extended` khi màn ngang thấp (`height < 480`), rail cuộn được thay vì overflow; `bottomNavClearance` = chiều cao nav + khoảng hở + đệm.
- Ý đồ hiển thị dữ liệu giám sát: nav yên tĩnh (chỉ hiện nhãn tab đang chọn, badge đỏ chỉ cho alarm/thông báo chưa đọc) để số liệu/biểu đồ là trọng tâm.
- Test: `navigation_page_test.dart` thêm ma trận 13 cỡ máy × 2 mức chữ (1.0x, 2.0x): không overflow, pill tròn + đặc + trong biên màn hình.

## Ngoài phạm vi (follow-up)
- Vẽ painter `TbIcons` cho mọi icon chức năng còn lại.
- Shimmer/Hero/stagger cho toàn bộ màn hình (chỉ làm chỗ đã có widget sẵn).
- Test widget mới cho từng màn hình đã đổi (ghi nhận gap).
- Build APK/iOS và kiểm thử trên thiết bị.
