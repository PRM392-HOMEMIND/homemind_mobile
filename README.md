# 📱 HomeMind Mobile Application

> **Ứng dụng di động quản lý tồn kho và trợ lý gia đình thông minh (Smart Home Inventory).**  
> Xây dựng bằng **Flutter (Dart)** với kiến trúc phân tầng **Feature-First / Clean Architecture**.

---

## 🌟 Tính năng chính
- 🎤 **Trợ lý AI Giọng nói tiếng Việt:** Nhập liệu bằng giọng nói, tự động phân tích đồ dùng, số lượng, hạn sử dụng chỉ trong <5 giây.
- 📦 **Quản lý Tủ đồ & Hạn sử dụng:** Theo dõi danh sách đồ dùng trong nhà, cảnh báo trước khi đồ hết hạn (cận date 7 ngày, 30 ngày).
- 🛒 **Danh sách Mua sắm (Shopping List):** Đồ dùng hết hàng sẽ tự động gợi ý thêm vào danh sách đi chợ.
- 💰 **Quản lý Chi tiêu (Spending Tracker):** Thống kê chi phí mua sắm theo tháng và danh mục.
- 👨‍👩‍👧‍👦 **Không gian Gia đình (Family Workspace):** Chia sẻ tủ đồ chung giữa các thành viên, phân quyền chủ hộ.
- 💳 **Nâng cấp Gói dịch vụ:** Tích hợp thanh toán PayOS hiển thị mã VietQR trực tiếp.

---

## 📂 Cấu trúc mã nguồn

`	ext
homemind_frontend/
├── lib/
│   ├── main.dart             # Điểm khởi chạy ứng dụng (App Entrypoint)
│   ├── app/                  # Theme giao diện & Khung điều hướng (AppShell)
│   ├── core/                 # Cấu hình môi trường, đa ngôn ngữ, định dạng tiền tệ, đơn vị
│   └── features/             # Các phân hệ nghiệp vụ độc lập (Feature-First)
│       ├── auth/             # Màn hình & Logic Đăng nhập / Đăng ký / Onboarding
│       ├── home/             # Trang chủ, tổng hợp nhanh tình trạng tủ đồ
│       ├── inventory/        # Quản lý kho đồ dùng, hạn sử dụng, thêm/sửa/xóa
│       ├── shopping/         # Danh sách đi chợ & mua sắm
│       ├── spending/         # Theo dõi chi tiêu gia đình
│       ├── voice/            # Thu âm microphone & Speech-to-Text
│       ├── assistant/        # Chatbot trợ lý AI thông minh
│       ├── billing/          # Nâng cấp gói cước & hiển thị VietQR PayOS
│       └── family/           # Không gian làm việc gia đình & lời mời thành viên
├── assets/                   # Icons, logos, fonts
├── test/                     # Unit test & Widget test
└── pubspec.yaml              # Khai báo packages & dependencies
`

---

## 🛠️ Hướng dẫn khởi chạy ứng dụng

### 1. Yêu cầu môi trường
- **Flutter SDK:** >= 3.24.x (kênh stable)
- **Dart SDK:** >= 3.5.x
- **Android Studio / Xcode:** Kèm Android Emulator hoặc thiết bị thật

### 2. Cài đặt Dependencies
`ash
flutter pub get
`

### 3. Kết nối với Backend
Ứng dụng sử dụng cờ --dart-define để nạp địa chỉ URL của backend server:

`ash
# Chạy trên Android Emulator kết nối với Backend Localhost (10.0.2.2 là localhost trên máy host):
flutter run --dart-define=BACKEND_BASE_URL=http://10.0.2.2:3000

# Chạy trên thiết bị Android thật (kết nối qua IP mạng LAN của máy chạy backend):
flutter run --dart-define=BACKEND_BASE_URL=http://<IP_LAN_CUA_MAY_TINH>:3000

# Chạy kết nối với Backend Production / VPS:
flutter run --dart-define=BACKEND_BASE_URL=https://<domain_cua_ban>
`

---

## 🧪 Chạy Kiểm thử (Testing)
`ash
flutter test
`

---

## 📜 Giấy phép
Dự án được phát triển trong khuôn khổ môn học PRM393 - Đại học FPT.
