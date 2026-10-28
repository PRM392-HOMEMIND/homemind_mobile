import 'package:flutter/foundation.dart';

import 'dart:convert';

import 'dart:io';

import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_service.dart';

/// Test double; production luôn khởi tạo `BackendAssistantService`.
class FakeAssistantService implements AssistantService {
  final Duration delay;

  /// Optional synchronous reader for tests driven entirely by the fake clock.
  final String Function(String path)? fixtureReader;
  AccountRole _currentRole = AccountRole.consumer;
  final Set<String> _readNotificationIds = {};

  FakeAssistantService({
    this.delay = const Duration(milliseconds: 450),
    this.fixtureReader,
    AccountRole initialRole = AccountRole.consumer,
  }) : _currentRole = initialRole;

  @override
  AccountRole get currentRole => _currentRole;

  @override
  Listenable get dataChanges => _dataChanges;
  final _dataChanges = ChangeNotifier();

  @override
  Stream<String> get backgroundErrors => const Stream<String>.empty();

  /// Ghi lại các yêu cầu nâng cấp (plan, source) để test kiểm tra.
  final List<({String plan, String source})> upgradeRequests = [];

  /// Đặt khác null để mô phỏng lỗi khi gửi yêu cầu nâng cấp.
  Object? upgradeError;

  @override
  Future<void> requestUpgrade({
    required String plan,
    required String source,
  }) async {
    if (upgradeError != null) throw upgradeError!;
    upgradeRequests.add((plan: plan, source: source));
  }

  @override
  void switchRole(AccountRole role) {
    _currentRole = role;
  }

  Future<Map<String, Object?>> _load(String name) async {
    final path = 'test/support/mocks/$name';
    final raw = fixtureReader?.call(path) ?? await File(path).readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw StateError('Mock $name không phải JSON object.');
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<void> _delayWait([Duration? custom]) async {
    final d = custom ?? delay;
    if (d > Duration.zero) {
      await Future<void>.delayed(d);
    }
  }

  UserProfile? _patched;

  @override
  Future<UserProfile> updateProfile({
    String? displayName,
    String? phone,
    String? address,
    String? language,
  }) async {
    _patched = null;
    final base = await getMe();
    _patched = base.copyWith(
      displayName: displayName,
      phone: phone,
      address: address,
      language: language,
    );
    return _patched!;
  }

  @override
  Future<UserProfile> getMe() async {
    final patched = _patched;
    if (patched != null) return patched;
    await _delayWait();
    if (_currentRole == AccountRole.merchant) {
      return const UserProfile(
        userId: 'user-merchant-02',
        email: 'store@homemind.vn',
        displayName: 'Cô Lan',
        workspaceId: 'ws-store-02',
        workspaceName: 'Tiệm Tạp Hóa Lan Anh',
        workspaceType: 'grocery_store',
        role: 'merchant',
        phone: '0988 765 432',
        address: '142 Nguyễn Thị Thập, Tân Quy, Q.7, TP.HCM',
      );
    }
    final raw = await _load('me.json');
    return UserProfile(
      userId: (raw['userId'] as String?) ?? 'user-consumer-01',
      email: (raw['email'] as String?) ?? 'person@homemind.vn',
      displayName: (raw['displayName'] as String?) ?? 'Minh Anh',
      workspaceId: (raw['workspaceId'] as String?) ?? 'ws-home-01',
      workspaceName: (raw['workspaceName'] as String?) ?? 'Tủ đồ Gia đình',
      workspaceType: 'household',
      role: 'consumer',
      phone: '0912 345 678',
      address: 'Căn hộ 802, Sunrise City, Q.7, TP.HCM',
    );
  }

  @override
  Future<HomeSummary> getHomeSummary() async {
    await _delayWait();
    if (_currentRole == AccountRole.merchant) {
      return const HomeSummary(
        totalProducts: 128,
        inStockCount: 116,
        outCount: 12,
        expiredCount: 2,
        expiringSoonCount: 6,
        shoppingNeededCount: 5,
        freePlanLimit: 500,
        productCountTowardLimit: 128,
        expiringSoon: [
          InventoryItem(
            productId: 'm-4',
            name: 'Sữa chua Cô Gái Hà Lan 100g',
            category: 'Sữa & Bơ',
            quantity: 24,
            unit: 'hộp',
            expiryDate: '2026-09-24',
            expiryLevel: 'urgent',
            status: 'in_stock',
          ),
          InventoryItem(
            productId: 'm-8',
            name: 'Bánh Chocopie Orion 12 cái',
            category: 'Bánh kẹo',
            quantity: 10,
            unit: 'hộp',
            expiryDate: '2026-10-02',
            expiryLevel: 'soon',
            status: 'in_stock',
          ),
          InventoryItem(
            productId: 'm-exp-1',
            name: 'Bánh mì sandwich bơ sữa',
            category: 'Bánh kẹo',
            quantity: 4,
            unit: 'gói',
            expiryDate: '2026-09-22',
            expiryLevel: 'urgent',
            status: 'in_stock',
          ),
        ],
        expired: [
          InventoryItem(
            productId: 'm-exp-0',
            name: 'Sữa tươi thanh trùng 450ml',
            category: 'Sữa & Bơ',
            quantity: 2,
            unit: 'chai',
            expiryDate: '2026-09-18',
            expiryLevel: 'expired',
            status: 'in_stock',
          ),
        ],
        alerts: [
          HomeAlert(
            type: 'expiry',
            severity: 'urgent',
            productId: 'm-4',
            title: 'Hàng cận date cần xả gấp ⚠️',
            subtitle:
                'Sữa chua Cô Gái Hà Lan còn 3 ngày — khuyến nghị giảm giá 30%.',
            cta: 'discount',
          ),
          HomeAlert(
            type: 'stock',
            severity: 'soon',
            productId: 'm-2',
            title: 'Bia Tiger sắp hết tồn kho',
            subtitle: 'Chỉ còn 5 thùng — cần đặt đại lý thêm 10 thùng.',
            cta: 'order_supplier',
          ),
        ],
      );
    }
    return HomeSummary.fromJson(await _load('home_summary.json'));
  }

  @override
  Future<({List<AppNotification> items, int unreadCount})>
  getNotifications() async {
    final summary = await getHomeSummary();
    final items = summary.alerts
        .map(
          (alert) => AppNotification(
            id: 'expiry.${alert.productId}.${alert.expiryDate ?? 'unknown'}',
            title: alert.title,
            body: alert.subtitle,
            context: 'Dữ liệu test',
            type: alert.type,
            read: _readNotificationIds.contains(
              'expiry.${alert.productId}.${alert.expiryDate ?? 'unknown'}',
            ),
          ),
        )
        .toList(growable: false);
    return (
      items: items,
      unreadCount: items.where((item) => !item.read).length,
    );
  }

  @override
  Future<void> markNotificationRead(String notificationId) async {
    _readNotificationIds.add(notificationId);
  }

  @override
  Future<void> markAllNotificationsRead() async {
    final notifications = await getNotifications();
    _readNotificationIds.addAll(notifications.items.map((item) => item.id));
  }

  @override
  Future<List<InventoryItem>> getInventory() async {
    await _delayWait();
    if (_currentRole == AccountRole.merchant) {
      return const [
        InventoryItem(
          productId: 'm-1',
          name: 'Mì Hảo Hảo Tôm Chua Cay',
          category: 'Thực phẩm',
          quantity: 48,
          unit: 'gói',
          expiryDate: '2027-03-15',
          expiryLevel: 'ok',
          status: 'in_stock',
        ),
        InventoryItem(
          productId: 'm-2',
          name: 'Bia Tiger Crystal 330ml',
          category: 'Đồ tươi',
          quantity: 5,
          unit: 'thùng',
          expiryDate: '2027-05-20',
          expiryLevel: 'ok',
          status: 'in_stock',
        ),
        InventoryItem(
          productId: 'm-3',
          name: 'Nước ngọt Coca-Cola 330ml',
          category: 'Đồ tươi',
          quantity: 18,
          unit: 'lon',
          expiryDate: '2027-04-10',
          expiryLevel: 'ok',
          status: 'in_stock',
        ),
        InventoryItem(
          productId: 'm-4',
          name: 'Sữa chua Cô Gái Hà Lan 100g',
          category: 'Thực phẩm',
          quantity: 24,
          unit: 'hộp',
          expiryDate: '2026-09-24',
          expiryLevel: 'urgent',
          status: 'in_stock',
        ),
        InventoryItem(
          productId: 'm-5',
          name: 'Dầu ăn Tường An Cooking Oil 5L',
          category: 'Gia vị',
          quantity: 6,
          unit: 'can',
          expiryDate: '2027-08-01',
          expiryLevel: 'ok',
          status: 'in_stock',
        ),
        InventoryItem(
          productId: 'm-6',
          name: 'Nước mắm Chinsu Cá Hồi 500ml',
          category: 'Gia vị',
          quantity: 15,
          unit: 'chai',
          expiryDate: '2028-01-10',
          expiryLevel: 'ok',
          status: 'in_stock',
        ),
        InventoryItem(
          productId: 'm-7',
          name: 'Bột giặt OMO Comfort 3kg',
          category: 'Đồ gia dụng',
          quantity: 8,
          unit: 'túi',
          expiryDate: '2028-06-15',
          expiryLevel: 'ok',
          status: 'in_stock',
        ),
        InventoryItem(
          productId: 'm-8',
          name: 'Bánh Chocopie Orion 12 cái',
          category: 'Thực phẩm',
          quantity: 10,
          unit: 'hộp',
          expiryDate: '2026-10-02',
          expiryLevel: 'soon',
          status: 'in_stock',
        ),
        InventoryItem(
          productId: 'm-9',
          name: 'Nước tăng lực Sting dâu 330ml',
          category: 'Đồ tươi',
          quantity: 48,
          unit: 'chai',
          expiryDate: '2027-02-28',
          expiryLevel: 'ok',
          status: 'in_stock',
        ),
        InventoryItem(
          productId: 'm-10',
          name: 'Muối tinh sấy Visalco 1kg',
          category: 'Gia vị',
          quantity: 30,
          unit: 'gói',
          expiryDate: '2028-12-31',
          expiryLevel: 'ok',
          status: 'in_stock',
        ),
        InventoryItem(
          productId: 'm-11',
          name: 'Bột ngọt Ajinomoto 454g',
          category: 'Gia vị',
          quantity: 12,
          unit: 'gói',
          expiryDate: '2028-09-01',
          expiryLevel: 'ok',
          status: 'in_stock',
        ),
        InventoryItem(
          productId: 'm-12',
          name: 'Nước rửa chén Sunlight Chanh 750ml',
          category: 'Đồ gia dụng',
          quantity: 10,
          unit: 'chai',
          expiryDate: '2028-03-20',
          expiryLevel: 'ok',
          status: 'in_stock',
        ),
      ];
    }
    final json = await _load('inventory_list.json');
    final items = json['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map(
          (e) => InventoryItem.fromJson(
            e.map((k, v) => MapEntry(k.toString(), v)),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<({List<ShoppingItem> items, List<Map<String, Object?>> suggestions})>
  getShoppingList() async {
    await _delayWait();
    if (_currentRole == AccountRole.merchant) {
      const merchantItems = [
        ShoppingItem(
          id: 'shop-m-1',
          name: 'Bia Heineken Silver 330ml (Đại lý Tân Phát)',
          quantity: 10,
          unit: 'thùng',
          status: 'needed',
          source: 'supplier',
        ),
        ShoppingItem(
          id: 'shop-m-2',
          name: 'Nước tăng lực Sting dâu chai 330ml',
          quantity: 5,
          unit: 'két',
          status: 'needed',
          source: 'supplier',
        ),
        ShoppingItem(
          id: 'shop-m-3',
          name: 'Giấy vệ sinh Pulppy 10 cuộn',
          quantity: 12,
          unit: 'lốc',
          status: 'needed',
          source: 'supplier',
        ),
        ShoppingItem(
          id: 'shop-m-4',
          name: 'Bột ngọt Ajinomoto 454g (thùng 20)',
          quantity: 2,
          unit: 'thùng',
          status: 'needed',
          source: 'supplier',
        ),
        ShoppingItem(
          id: 'shop-m-5',
          name: 'Thuốc lá Craven A (Cây 10 gói)',
          quantity: 2,
          unit: 'cây',
          status: 'out',
          source: 'supplier',
        ),
        ShoppingItem(
          id: 'shop-m-6',
          name: 'Khăn ướt Baby Care 80 tờ',
          quantity: 10,
          unit: 'gói',
          status: 'out',
          source: 'supplier',
        ),
        ShoppingItem(
          id: 'shop-m-7',
          name: 'Nước tương Tam Thái Tử Nhất Ca 500ml',
          quantity: 1,
          unit: 'thùng',
          status: 'bought',
          source: 'supplier',
        ),
      ];

      final merchantSuggestions = [
        {
          'title': 'Đại lý Tân Phát giảm 5% cho đơn bia > 20 thùng',
          'supplier': 'Đại lý Bia & Nước ngọt Tân Phát',
          'phone': '0903 111 222',
        },
        {
          'title':
              'NPP Tạp hoá Sài Gòn có chương trình tích điểm gia vị Chinsu',
          'supplier': 'NPP Tạp hoá Sài Gòn',
          'phone': '0908 333 444',
        },
      ];

      return (items: merchantItems, suggestions: merchantSuggestions);
    }
    final json = await _load('shopping_list.json');
    final items = (json['items'] is List ? json['items'] as List : const [])
        .whereType<Map>()
        .map(
          (e) =>
              ShoppingItem.fromJson(e.map((k, v) => MapEntry(k.toString(), v))),
        )
        .toList(growable: false);
    final suggestions =
        (json['suggestions'] is List ? json['suggestions'] as List : const [])
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v as Object?)))
            .toList(growable: false);
    return (items: items, suggestions: suggestions);
  }

  @override
  Future<void> markInventoryOut({
    required String productId,
    double? quantity,
    required bool addToShoppingList,
  }) async {
    await _delayWait();
  }

  @override
  Future<void> addShoppingItem({
    required String name,
    double? quantity,
    String? unit,
  }) async {
    await _delayWait();
  }

  @override
  Future<void> receiveShoppingItem({
    required String itemId,
    double? quantity,
    String? unit,
    String? expiryDate,
    int? priceVnd,
    String? storageLocation,
  }) async {
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> updateShoppingItem({
    required String itemId,
    required String status,
  }) async {
    await _delayWait();
  }

  @override
  Future<AssistantTurn> turn({
    required String text,
    String inputType = 'voice_transcript',
  }) async {
    await _delayWait(const Duration(milliseconds: 700));
    final file = _routeMockFile(text);
    final json = await _load(file);
    final userSpokenText = text.trim();

    // Nếu là thao tác thêm hàng vào kho, bóc tách thông minh theo câu nói thực tế
    if (file == 'assistant_turn_write_add.json' && userSpokenText.isNotEmpty) {
      final t = userSpokenText.toLowerCase();
      String productName = 'Đường';
      int quantity = 1;
      String unit = 'kg';
      String category = 'Gia vị';

      if (t.contains('sữa')) {
        productName = 'Sữa tươi';
        category = 'Sữa & Bơ';
        unit = 'hộp';
        if (t.contains('lốc')) {
          productName = 'Lốc sữa';
          unit = 'lốc';
        } else if (t.contains('thùng')) {
          productName = 'Thùng sữa';
          unit = 'thùng';
        } else if (t.contains('chai')) {
          unit = 'chai';
        }
      } else if (t.contains('trứng')) {
        productName = 'Trứng gà';
        category = 'Thực phẩm';
        unit = 'quả';
      } else if (t.contains('bánh')) {
        productName = 'Bánh mì';
        category = 'Bánh kẹo';
        unit = 'ổ';
      } else if (t.contains('bia')) {
        productName = 'Bia Tiger';
        category = 'Đồ uống';
        unit = 'thùng';
      }

      if (t.contains('1 ') ||
          t.contains('một ') ||
          t.contains('1lốc') ||
          t.contains('1hộp')) {
        quantity = 1;
      }
      if (t.contains('2 ') || t.contains('hai ')) {
        quantity = 2;
      }
      if (t.contains('3 ') || t.contains('ba ')) {
        quantity = 3;
      }
      if (t.contains('4 ') || t.contains('bốn ')) {
        quantity = 4;
      }
      if (t.contains('5 ') || t.contains('năm ')) {
        quantity = 5;
      }

      final now = DateTime.now();
      String expiryDate =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-28';
      if (t.contains('cuối tháng này') || t.contains('tháng này')) {
        final lastDay = DateTime(now.year, now.month + 1, 0);
        expiryDate =
            '${lastDay.year}-${lastDay.month.toString().padLeft(2, '0')}-${lastDay.day.toString().padLeft(2, '0')}';
      } else if (t.contains('tuần sau') || t.contains('7 ngày')) {
        final nextWeek = now.add(const Duration(days: 7));
        expiryDate =
            '${nextWeek.year}-${nextWeek.month.toString().padLeft(2, '0')}-${nextWeek.day.toString().padLeft(2, '0')}';
      } else if (t.contains('ngày mai')) {
        final tomorrow = now.add(const Duration(days: 1));
        expiryDate =
            '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
      }

      return AssistantTurn.fromJson({
        'schemaVersion': '1.0',
        'turnId': 'write-${DateTime.now().millisecondsSinceEpoch}',
        'kind': 'write_draft',
        'dictionaryVersion': '1.1.0',
        'correctedInput': userSpokenText,
        'requiresConfirmation': true,
        'toolsProposed': [
          {
            'toolId': 'inventory.add',
            'arguments': {
              'productName': productName,
              'quantity': quantity,
              'unit': unit,
              'category': category,
              'expiryDate': expiryDate,
              'items': [
                {
                  'name': productName,
                  'quantity': quantity,
                  'unit': unit,
                  'category': category,
                  'expiryDate': expiryDate,
                },
              ],
              'confidence': {
                'productName': 0.98,
                'quantity': 0.95,
                'unit': 0.92,
                'expiryDate': 0.95,
                'category': 0.90,
              },
            },
          },
        ],
        'message':
            'Tôi hiểu bạn muốn thêm $quantity $unit $productName vào kho với hạn dùng $expiryDate. Hãy kiểm tra trước khi lưu.',
      });
    }

    return AssistantTurn.fromJson({
      ...json,
      if (userSpokenText.isNotEmpty) 'correctedInput': userSpokenText,
    });
  }

  @override
  Future<AssistantTurn> confirm({
    required String turnId,
    required List<ToolCall> tools,
  }) async {
    await _delayWait();
    final json = await _load('assistant_confirm_ok.json');
    return AssistantTurn.fromJson({
      ...json,
      'turnId': turnId,
      'message': tools.isEmpty
          ? json['message']
          : 'Đã xác nhận ${tools.first.toolId} (mock).',
    });
  }

  @override
  Future<AssistantTurn> cancel({required String turnId}) async {
    await _delayWait();
    final json = await _load('assistant_cancel_ok.json');
    return AssistantTurn.fromJson({...json, 'turnId': turnId});
  }

  /// Keyword router — chỉ dùng cho mock; production do AI Dictionary.
  String _routeMockFile(String text) {
    final t = text.toLowerCase();
    if (t.contains('đèn') || t.contains('thời tiết') || t.contains('bật')) {
      return 'assistant_turn_unknown.json';
    }

    // 1. Nhập hàng / thêm đồ vào tủ / vừa mua / mới mua (Ghi dữ liệu kho)
    // Ưu tiên kiểm tra trước các câu lệnh thêm đồ có kèm hạn sử dụng
    if (t.contains('vừa mua') ||
        t.contains('mới mua') ||
        t.contains('vừa mới') ||
        t.contains('mua về') ||
        t.contains('thêm vào tủ') ||
        t.contains('thêm vào kho') ||
        t.contains('cho vào kho') ||
        t.contains('cho vào tủ') ||
        t.contains('nhập hàng') ||
        t.contains('thêm hàng') ||
        t.contains('đường')) {
      return 'assistant_turn_write_add.json';
    }

    // 2. Truy vấn giỏ hàng / danh sách cần mua / đi chợ
    if (t.contains('giỏ hàng') ||
        t.contains('mua đồ') ||
        t.contains('muốn mua') ||
        t.contains('đi chợ') ||
        t.contains('cần mua') ||
        t.contains('danh sách mua') ||
        t.contains('hôm nay mua') ||
        (t.contains('mua gì') && !t.contains('nhớ mua'))) {
      return 'assistant_turn_read_shopping.json';
    }

    // 3. Thêm mặt hàng vào danh sách cần mua
    if (t.contains('nhớ mua') ||
        t.contains('thêm vào giỏ') ||
        t.contains('thêm vào cần mua') ||
        t.contains('thêm vào danh sách') ||
        (t.contains('mua') && t.contains('trứng')) ||
        t.contains('nước mắm với')) {
      return 'assistant_turn_write_shopping_add.json';
    }

    // 4. Kiểm tra hạn sử dụng / cận date / sắp hết hạn
    if (t.contains('hết hạn') ||
        t.contains('sắp hết') ||
        t.contains('cận date') ||
        t.contains('quá hạn') ||
        t.contains('hết date') ||
        t.contains('sản phẩm hết')) {
      return 'assistant_turn_read_expiring.json';
    }

    // 5. Tóm tắt tổng quan
    if (t.contains('tóm tắt') || t.contains('tổng quan')) {
      return 'assistant_turn_read_home.json';
    }

    // 6. Kiểm tra đồ trong nhà / tủ lạnh / kho
    if (t.contains('còn gì') ||
        t.contains('trong nhà') ||
        t.contains('tồn kho') ||
        t.contains('trong tủ') ||
        t.contains('trong kho') ||
        t.contains('kiểm tra tủ') ||
        t.contains('kiểm tra kho')) {
      return 'assistant_turn_read_list.json';
    }

    // 7. Đánh dấu hết hàng
    if (t.contains('hết sữa') || t.contains('hết hàng') || t.contains('hết ')) {
      return 'assistant_turn_write_mark_out.json';
    }

    return 'assistant_turn_clarify.json';
  }
}
