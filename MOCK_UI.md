> Historical design/reference — trước migration ngày 02/10/2026. Các đoạn Supabase mô tả kiến trúc cũ, không phải cấu hình hay lệnh chạy hiện tại. Runtime hiện dùng Nest custom auth + PostgreSQL native; xem [hướng dẫn backend](../homemind_backend/README.md).

# Mock UI — test fixture, không dùng trong production

Production dùng `RemoteAuthService` và `BackendAssistantService`. `FakeAssistantService` chỉ được test inject để chạy widget test bằng `assets/mocks/*.json` đúng shape `docs/API_CONTRACTS.md`.

## Chạy

```powershell
cd D:\MONHOCKI7\EXE\HomeMind\apps\homemind_mobile
flutter pub get
flutter run
```

## Màn hình

| Tab | Nguồn mock |
|---|---|
| Home | `me.json` + `home_summary.json` |
| Kho | `inventory_list.json` |
| Mua sắm | `shopping_list.json` |
| AI | `assistant_turn_*.json` theo keyword |

Chip mẫu trên tab AI map sẵn các câu demo. Write draft → màn **Xác nhận** → `assistant_confirm_ok.json`.

## Gắn BE sau này

1. Implement `AssistantService` thật (Supabase).
2. Chỉ inject fake service từ test; không đổi wiring mặc định trong `main.dart`.
3. **Không** đổi model/`fromJson` nếu contract giữ nguyên.
