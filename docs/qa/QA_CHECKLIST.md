# QA/QC Checklist — ThingsBoard PE Mobile App

Dùng cho mỗi release candidate. Tự động hóa (CI) chặn lỗi code; checklist này bắt phần máy không bắt được:
cảm nhận giao diện, thiết bị thật, dữ liệu thật. Mỗi mục: đánh dấu, ghi thiết bị/phiên bản, đính kèm ảnh khi lỗi.

## 0. Cổng tự động (phải xanh trước khi test tay)
- [ ] CI workflow `CI` xanh: format, analyze (`--fatal-infos`), test + coverage floor, build APK debug
- [ ] Workflow `API contract drift` xanh (hoặc sai khác đã được duyệt trong `tools/api_contract/known_deviations.json`)
- [ ] Cục bộ: `powershell -ExecutionPolicy Bypass -File tools/qa/run_checks.ps1` → mọi cổng `PASS`

## 1. Ma trận thiết bị
Chạy các mục 3–7 trên **tối thiểu** các cỡ sau (thiết bị thật hoặc emulator):

| Nhóm | Cỡ (dp) | Ghi chú |
|---|---|---|
| Màn gập (ngoài) | 280×653 | Nhãn nav bị lược, vẫn đủ vùng chạm 48dp |
| Điện thoại nhỏ | 320×568 / 360×640 | Lề nav 8dp, không cắt chữ |
| Điện thoại chuẩn | 375×667, 390×844, 412×915 | Kịch bản chính |
| Điện thoại lớn | 430×932, 599×900 | Nav tối đa 480dp, căn giữa |
| Ngang (điện thoại) | 667×375, 844×390, 568×320 | Rail gọn, cuộn được, không tràn |
| Tablet | 768×1024, 1024×768 | Rail; mở rộng khi đủ rộng và cao |

Mỗi cỡ: Android (API 24+) và iOS (nếu build được).

## 2. Chế độ hiển thị (lặp lại cho mỗi cỡ chính)
- [ ] Sáng và Tối: chữ/icon đọc rõ, badge và trạng thái không chỉ dựa vào màu
- [ ] Cỡ chữ hệ thống 1.0x, 1.3x và 2.0x: không tràn, không che nút
- [ ] "Giảm chuyển động" bật: chuyển tab tức thì, không animation thừa
- [ ] "Độ tương phản cao" bật: thanh nav đặc, không mờ
- [ ] TalkBack/VoiceOver: mỗi nút icon có tên; tab đang chọn được đọc là "selected"; badge đọc kèm số ("Alarms, 3 active")

## 3. Điều hướng (thanh nav nổi)
- [ ] Pill bo tròn hoàn toàn hai đầu, kính mờ vẫn đọc rõ trên nội dung cuộn bên dưới
- [ ] Chạm icon: viên indicator trượt, nhãn trượt hiện **bên phải icon**, mượt, không giật
- [ ] Nhảy xa (Home → More): không có nhãn tab trung gian lóe lên
- [ ] Chạm liên tiếp nhanh: không nhảy vị trí, không treo animation
- [ ] Chạm lại tab đang chọn: về gốc của tab đó
- [ ] Nút Back hệ thống ở tab khác Home: về Home, rồi mới thoát app
- [ ] Hàng cuối của danh sách không bị nav che (cuộn hết cỡ)
- [ ] Bottom sheet (sửa hồ sơ, gán alarm, sửa thuộc tính, inspector) và hộp thoại phủ **lên trên** nav; nút ở đáy sheet bấm được
- [ ] Badge: Alarms = số alarm đang active; More = thông báo chưa đọc; số lớn hiển thị `99+`

## 4. Xác thực
- [ ] Đăng nhập đúng/sai (thông báo ngắn, giữ lại email đã nhập)
- [ ] 2FA: gửi mã, mã sai/hết hạn, gửi lại, quay về login
- [ ] Thiết lập MFA bắt buộc (`MFA_CONFIGURATION_TOKEN`)
- [ ] OAuth2 (Google…) và quay lại app qua deep link
- [ ] Quét QR đăng nhập; quét QR claim thiết bị
- [ ] Quên mật khẩu
- [ ] Token hết hạn khi đang dùng: tự làm mới 1 lần, không văng ra login oan
- [ ] Đăng xuất: xóa phiên, về login, không còn dữ liệu cũ khi đăng nhập tài khoản khác

## 5. Từng màn hình (dữ liệu thật hoặc Demo)
Với mỗi màn: **loading → dữ liệu → rỗng → lỗi (Retry) → 403**; kéo để làm mới; tải thêm khi cuộn; tìm kiếm.

| Màn | Kiểm riêng |
|---|---|
| Home | Dashboard sao/gần đây, thẻ Alarms/Devices, pill số liệu không giật khi cập nhật |
| Alarms | Lọc trạng thái/mức độ, ack/clear/assign, bình luận, biểu tượng mức độ nhận ra được cả khi đơn sắc |
| Devices | Lọc theo profile/active, chi tiết: telemetry live, biểu đồ lịch sử (đổi khoảng/aggregation), thuộc tính, RPC, claim |
| Dashboards | Mở, sao/bỏ sao, toàn màn hình |
| Assets / Customers | Danh sách, chi tiết, quan hệ |
| Audit logs | Lọc thời gian/hành động; JSON dài không tràn |
| Notifications | Đánh dấu đã đọc (một/tất cả), xóa |
| Profile & Settings | Sửa hồ sơ, đổi mật khẩu (chính sách mật khẩu), đổi theme, đổi server |
- [ ] Dữ liệu thiếu trường (không tên, không loại, ngày trống) hiển thị gọn, không đỏ màn hình
- [ ] Tên rất dài / Unicode (tiếng Việt, emoji): cắt `…`, không tràn
- [ ] Tên thiết bị có ký tự `/ ? # %` và khoảng trắng: claim vẫn gọi đúng thiết bị

## 6. Mạng và phiên
- [ ] Tắt mạng giữa chừng: thông báo ngắn, bật lại thì Retry thành công
- [ ] Server trả 5xx / chậm (>15s): không treo spinner vô hạn
- [ ] Đổi server/host giữa phiên: dữ liệu host cũ không lọt sang host mới
- [ ] Demo mode ↔ Live: chuyển qua lại, mọi thao tác Demo (ack, đọc thông báo, sửa hồ sơ) cập nhật tức thì và có nhãn `DEMO`
- [ ] WebSocket: dữ liệu live cập nhật; thoát màn hình thì ngừng đăng ký; app quay lại từ nền thì nối lại

## 7. Hiệu năng và ổn định (thiết bị tầm trung)
- [ ] Cuộn danh sách dài 60fps, không khựng khi nav mờ (blur) nằm trên nội dung
- [ ] Khởi động nguội < 3s; không crash khi xoay màn hình nhiều lần
- [ ] Bộ nhớ ổn định sau 10 phút dùng (không tăng liên tục)
- [ ] Không log token/mật khẩu (kiểm `adb logcat` bản debug)

## 8. Bảo mật nhanh
- [ ] Token chỉ trong secure storage; không có trong log, ảnh chụp lỗi, hay URL
- [ ] Header là `X-Authorization: Bearer …` (không dùng `Authorization`)
- [ ] 403 hiển thị trạng thái "không đủ quyền", không bị che bằng endpoint khác

## 9. Báo lỗi
Ghi: bước tái hiện, kỳ vọng/thực tế, thiết bị + hệ điều hành + cỡ chữ + theme, server (live/demo), ảnh/video. Lỗi API đính thêm request/response (đã che token) từ Network Inspector.
