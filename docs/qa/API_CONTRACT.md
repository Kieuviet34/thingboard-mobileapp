# API Contract — kiểm chứng app với ThingsBoard gốc

Mục tiêu: dữ liệu app **gửi lên** và **đọc về** luôn khớp ThingsBoard REST API **4.4.1PAAS**
(OpenAPI công khai `https://demo.thingsboard.io/v3/api-docs`). Sai khác bị CI chặn, không để người dùng phát hiện.

## Ba lớp bảo vệ

| Lớp | Chạy ở đâu | Bắt được gì | Cần mạng |
|---|---|---|---|
| **Hợp đồng runtime** `test/core/api/repositories/contract/*` | `flutter test` (mỗi PR) | Request thật mà repository gửi (path, method, tham số query bắt buộc/lạ/enum, enum của path-param, header bắt buộc, body lồng nhau: kiểu/enum/trường lạ/trường bắt buộc) **và** response mà fixture trả về (cùng các kiểm tra trên), nên fixture phải giống payload thật của ThingsBoard | Không (dùng snapshot) |
| **Audit endpoint** `tools/api_contract/audit_endpoints.py` | Workflow `API contract drift` | Mọi chuỗi `/api/...` trong `lib/core` tồn tại trong spec với đúng method | Có (tải spec) |
| **Audit model** `tools/api_contract/audit_models.py` | Workflow `API contract drift` | Khóa JSON mà `fromJson`/`toJson` đọc/ghi có trong schema; trường bắt buộc bị bỏ qua | Có |

Snapshot rút gọn (chỉ endpoint app dùng, kèm đồ thị schema tới 4 bước tham chiếu) nằm ở `test/fixtures/contract/tb_pe_4_4_1_subset.json` (~90 KB), nên PR không cần tải spec 1.8 MB.

Cách dùng trong test: `contract.expectAllConform(adapter)` kiểm mọi request và response mà `MockDioAdapter` đã ghi lại. `MockDioAdapter` cũng tôn trọng `CancelToken` giống adapter thật (request bị hủy báo `DioExceptionType.cancel`, không trả phản hồi muộn).

## Chạy cục bộ

```powershell
# 1) Tải spec (dữ liệu công khai) vào thư mục tạm NGOÀI repo
Invoke-WebRequest https://demo.thingsboard.io/v3/api-docs -OutFile $env:TEMP\tb-openapi.json

# 2) Audit + kiểm snapshot còn mới
python -I tools/api_contract/audit_endpoints.py --spec $env:TEMP\tb-openapi.json --allow tools/api_contract/known_deviations.json
python -I tools/api_contract/audit_models.py    --spec $env:TEMP\tb-openapi.json --allow tools/api_contract/known_deviations.json
python -I tools/api_contract/build_subset.py    --spec $env:TEMP\tb-openapi.json

# 3) Hợp đồng runtime (offline)
flutter test test/core/api test/helpers
```
Hoặc gom tất cả: `tools/qa/run_checks.ps1 -Spec $env:TEMP\tb-openapi.json`.

Tra nhanh spec khi viết fixture (đừng đoán tên trường):
```powershell
python -I tools/api_contract/show_schema.py --spec $env:TEMP\tb-openapi.json schema AlarmInfo
python -I tools/api_contract/show_schema.py --spec $env:TEMP\tb-openapi.json op GET /api/v2/alarms
```
(Trong Git Bash đặt `MSYS_NO_PATHCONV=1` để đường dẫn `/api/...` không bị đổi.)

## Khi thêm hoặc đổi endpoint
1. Viết/ sửa **test hợp đồng** trước (mẫu: `alarm_repository_contract_test.dart`): gọi repository với payload đúng schema, `contract.expectConforms(adapter.capturedRequests)`, khẳng định giá trị đã parse và body bằng literal.
2. Sửa code đến khi xanh.
3. Chạy lại `build_subset.py`, commit snapshot.
4. Nếu path được **ghép lúc chạy** (không phải literal `/api/...`), thêm vào `tools/api_contract/extra_operations.json` (nếu không, công cụ không thấy nó).
5. Nếu cố ý lệch spec (dự phòng cho bản cũ/CE), thêm vào `known_deviations.json` **kèm lý do**; mọi thứ không có trong file này đều làm CI đỏ.

## Khi ThingsBoard đổi API
Workflow `API contract drift` chạy hằng tuần (thứ Hai). Nếu đỏ: đọc diff snapshot (`test/fixtures/contract`), quyết định chỉnh app hay ghi nhận sai khác, rồi cập nhật snapshot trong cùng PR.

## Giới hạn đã biết (đừng tin quá mức)
- Response chỉ được kiểm trên **fixture của test** (không phải server thật): nó chứng minh fixture đúng hình dạng và app đọc được hình dạng đó, không chứng minh server luôn gửi đúng spec. Với server thật, bảo vệ là workflow `API contract drift` và QA thủ công.
- Schema đa hình (`oneOf`/`anyOf`) và tham chiếu sâu hơn 4 bước được coi là tự do (không kiểm). Giá trị `null` được chấp nhận ở mọi trường.
- Spec do springdoc sinh có chỗ sai/thiếu; các trường hợp đã biết nằm trong `known_deviations.json`: `GET .../values/timeseries` chỉ mô tả "latest" (`query_params`), `POST /api/rpc/twoway` ghi response là `string` trong khi thực tế là JSON của thiết bị (`responses`), các id `AuditLogId`/`AlarmCommentId`/`DeviceCredentialsId` chỉ có `id` (không có `entityType`).
- `entityFilter` của `POST /api/entitiesQuery/count` là đa hình trong spec nên không kiểm được; test khẳng định body bằng literal.
- `MockDioAdapter` trả 404 cho route chưa đăng ký; với repository có dự phòng 404, hãy khẳng định `capturedRequests` để không pass vì lý do sai.

## Sai khác đã duyệt (tóm tắt — nguồn: `known_deviations.json`)
- `GET /api/tenant/assetInfos`, `/api/tenant/deviceInfos`: dự phòng CE chỉ khi `/all` trả 404.
- `GET .../values/timeseries?startTs…`: dự phòng cho server < 4.4 chỉ khi `.../history` trả 404.
- `TbNotification.read`: cờ cũ/Demo; hợp đồng 4.4.1 là `status` (`SENT|READ`).

Báo cáo kiểm toán chi tiết: [audit-2026-11-21-api.md](audit-2026-11-21-api.md).
