import 'package:flutter/foundation.dart';

import 'assistant_models.dart';

abstract interface class AssistantService {
  AccountRole get currentRole;

  /// Báo mỗi khi dữ liệu đã lưu đệm thay đổi (ghi lạc quan, làm mới nền...).
  /// Trang lắng nghe rồi đọc lại bằng các hàm get (đọc từ bộ nhớ, rất nhanh).
  Listenable get dataChanges;

  /// Thông báo lỗi tiếng Việt (thân thiện) của các lần ghi chạy ngầm thất bại.
  Stream<String> get backgroundErrors;

  void switchRole(AccountRole role);

  Future<UserProfile> getMe();

  /// Cập nhật hồ sơ của chính mình. Tham số nào để null thì giữ nguyên;
  /// truyền chuỗi rỗng ở [phone]/[address] để xóa.
  Future<UserProfile> updateProfile({
    String? displayName,
    String? phone,
    String? address,
    String? language,
  });

  Future<HomeSummary> getHomeSummary();

  Future<({List<AppNotification> items, int unreadCount})> getNotifications();

  Future<void> markNotificationRead(String notificationId);

  Future<void> markAllNotificationsRead();

  Future<List<InventoryItem>> getInventory();

  Future<({List<ShoppingItem> items, List<Map<String, Object?>> suggestions})>
  getShoppingList();

  Future<void> markInventoryOut({
    required String productId,
    double? quantity,
    required bool addToShoppingList,
  });

  Future<void> addShoppingItem({
    required String name,
    double? quantity,
    String? unit,
  });

  /// Hàng đã về: cất vào kho/tủ đồ và đóng món trong danh sách mua
  /// (một thao tác ở server, thử lại an toàn).
  Future<void> receiveShoppingItem({
    required String itemId,
    double? quantity,
    String? unit,
    String? expiryDate,
    int? priceVnd,
    String? storageLocation,
  });

  Future<void> updateShoppingItem({
    required String itemId,
    required String status,
  });

  /// Ghi nhận yêu cầu nâng cấp gói (chưa có cổng thanh toán; đội ngũ sẽ liên hệ).
  /// [plan]: personal | family | micro_pos. [source]: home_card |
  /// limit_reached | inventory_banner | paywall.
  Future<void> requestUpgrade({required String plan, required String source});

  Future<AssistantTurn> turn({
    required String text,
    String inputType = 'voice_transcript',
  });

  Future<AssistantTurn> confirm({
    required String turnId,
    required List<ToolCall> tools,
  });

  Future<AssistantTurn> cancel({required String turnId});
}

/// Dịch vụ lấy được toàn bộ dữ liệu màn hình bằng một lần gọi.
abstract interface class BootstrapSource {
  Future<Bootstrap> getBootstrap();
}

/// Chi tiêu theo tháng và giá/nơi cất của từng lô. Tách riêng để bản giả lập
/// không có tính năng này vẫn dùng được (màn hình tự ẩn khi không hỗ trợ).
abstract interface class SpendingSource {
  /// false khi dịch vụ phía sau không có chi tiêu (bản bọc đệm quanh bản giả lập).
  bool get spendingAvailable;

  /// [month] dạng `YYYY-MM`; mặc định tháng hiện tại (giờ Việt Nam).
  Future<SpendingSummary> getSpending({String? month});

  /// Nhập giá (tổng tiền, VND) và/hoặc nơi cất của một lô. Tham số null = giữ nguyên.
  Future<void> updateLot({
    required String lotId,
    int? priceVnd,
    String? storageLocation,
  });
}

// Handled by Tran Gia Phu
