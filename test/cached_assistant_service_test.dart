import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/features/assistant/data/backend_assistant_service.dart'
    show HomeMindApiException;
import 'package:homemind_mobile/features/assistant/data/cached_assistant_service.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_service.dart';

const _latency = Duration(milliseconds: 120);

const _milk = InventoryItem(
  productId: 'p-milk',
  name: 'Sữa tươi',
  category: 'Sữa',
  quantity: 2,
  unit: 'hộp',
  expiryDate: '2026-10-03',
  expiryLevel: 'urgent',
  status: 'in_stock',
);
const _rice = InventoryItem(
  productId: 'p-rice',
  name: 'Gạo',
  category: 'Gia vị',
  quantity: 5,
  unit: 'kg',
  expiryDate: null,
  expiryLevel: 'ok',
  status: 'in_stock',
);

Bootstrap _serverData() => Bootstrap(
  home: const HomeSummary(
    totalProducts: 2,
    inStockCount: 2,
    outCount: 0,
    expiredCount: 0,
    expiringSoonCount: 1,
    shoppingNeededCount: 1,
    freePlanLimit: 30,
    productCountTowardLimit: 2,
    expiringSoon: [_milk],
    expired: [],
    alerts: [
      HomeAlert(
        type: 'expiry',
        severity: 'urgent',
        productId: 'p-milk',
        title: 'Sữa tươi sắp hết hạn',
        subtitle: 'Còn 1 ngày',
        cta: 'buy',
      ),
    ],
  ),
  inventory: const [_milk, _rice],
  inventoryTotal: 2,
  shoppingItems: const [
    ShoppingItem(
      id: 's-eggs',
      name: 'Trứng',
      quantity: 10,
      unit: 'quả',
      status: 'needed',
      source: 'manual',
    ),
  ],
  suggestions: const [
    {'name': 'Dầu ăn', 'reason': 'out', 'productId': 'p-oil'},
  ],
  notifications: const [
    AppNotification(
      id: 'n1',
      title: 'A',
      body: 'a',
      context: '',
      type: 'expiry',
      read: false,
    ),
    AppNotification(
      id: 'n2',
      title: 'B',
      body: 'b',
      context: '',
      type: 'expiry',
      read: false,
    ),
  ],
  unreadCount: 2,
);

/// Service giả có độ trễ thật như mạng đến Tokyo. Đếm số lần gọi.
class _Base implements AssistantService {
  int bootstraps = 0;
  final writes = <String>[];
  Object? writeError;
  Duration bootstrapDelay = _latency;
  Completer<void>? writeGate;
  Bootstrap server = _serverData();

  Future<void> _write(String label) async {
    writes.add('start:$label');
    await (writeGate?.future ?? Future<void>.delayed(_latency));
    final error = writeError;
    if (error != null) throw error;
    writes.add('done:$label');
  }

  @override
  Future<void> markNotificationRead(String id) => _write('read:$id');

  @override
  Future<void> markAllNotificationsRead() => _write('readAll');

  @override
  Future<void> markInventoryOut({
    required String productId,
    double? quantity,
    required bool addToShoppingList,
  }) => _write('out:$productId:$quantity:$addToShoppingList');

  @override
  Future<void> addShoppingItem({
    required String name,
    double? quantity,
    String? unit,
  }) => _write('add:$name');

  @override
  Future<void> receiveShoppingItem({
    required String itemId,
    double? quantity,
    String? unit,
    String? expiryDate,
    int? priceVnd,
    String? storageLocation,
  }) => _write('receive:$itemId:$quantity');

  @override
  Future<void> updateShoppingItem({
    required String itemId,
    required String status,
  }) => _write('status:$itemId:$status');

  @override
  Listenable get dataChanges => ChangeNotifier();

  @override
  Stream<String> get backgroundErrors => const Stream<String>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SlowInner extends _Base implements BootstrapSource {
  @override
  Future<Bootstrap> getBootstrap() async {
    bootstraps++;
    final snapshot = server; // dữ liệu tại thời điểm gửi request
    await Future<void>.delayed(bootstrapDelay);
    return snapshot;
  }
}

/// Inner không có bootstrap: cache phải rơi về 4 lần gọi song song.
class _NoBootstrapInner extends _Base {
  int home = 0, inv = 0, shop = 0, notif = 0;

  @override
  Future<HomeSummary> getHomeSummary() async {
    home++;
    return server.home;
  }

  @override
  Future<List<InventoryItem>> getInventory() async {
    inv++;
    return server.inventory;
  }

  @override
  Future<({List<ShoppingItem> items, List<Map<String, Object?>> suggestions})>
  getShoppingList() async {
    shop++;
    return (items: server.shoppingItems, suggestions: server.suggestions);
  }

  @override
  Future<({List<AppNotification> items, int unreadCount})>
  getNotifications() async {
    notif++;
    return (items: server.notifications, unreadCount: server.unreadCount);
  }
}

/// Đọc đồng bộ từ snapshot (chỉ hợp lệ khi đã có dữ liệu).
T _now<T>(Future<T> f) {
  final v = syncValue(f);
  if (v == null) fail('Đáng lẽ phải trả về đồng bộ từ bộ nhớ đệm.');
  return v;
}

void main() {
  late _Base inner;
  late CachedAssistantService cache;

  Future<CachedAssistantService> warm([_Base? custom]) async {
    inner = custom ?? _SlowInner();
    cache = CachedAssistantService(
      inner,
      reconcileDelay: const Duration(milliseconds: 20),
    );
    await cache.getHomeSummary();
    return cache;
  }

  tearDown(() => cache.dispose());

  test('lần đầu chỉ gọi đúng 1 bootstrap dù nhiều nơi cùng đọc', () async {
    inner = _SlowInner();
    cache = CachedAssistantService(inner);
    final results = await Future.wait<Object?>([
      cache.getHomeSummary(),
      cache.getInventory(),
      cache.getShoppingList(),
      cache.getNotifications(),
    ]);
    expect((inner as _SlowInner).bootstraps, 1);
    expect((results[1] as List<InventoryItem>).length, 2);
  });

  test('lần đọc thứ hai trả về tức thì, không gọi thêm', () async {
    await warm();
    final sw = Stopwatch()..start();
    final home = _now(cache.getHomeSummary());
    final inv = _now(cache.getInventory());
    _now(cache.getShoppingList());
    _now(cache.getNotifications());
    sw.stop();
    expect(home.inStockCount, 2);
    expect(inv.length, 2);
    expect(sw.elapsedMilliseconds, lessThan(20));
    expect((inner as _SlowInner).bootstraps, 1);
  });

  test('inner không có bootstrap: rơi về 4 getter song song', () async {
    final fallback = _NoBootstrapInner();
    await warm(fallback);
    expect(
      [fallback.home, fallback.inv, fallback.shop, fallback.notif],
      [1, 1, 1, 1],
    );
    expect(_now(cache.getNotifications()).unreadCount, 2);
  });

  test('ghi lạc quan thấy ngay (đồng bộ) trước khi request xong', () async {
    await warm();
    var notified = 0;
    cache.dataChanges.addListener(() => notified++);

    cache.markNotificationRead('n1');

    // Cùng một "tick": chưa có await nào.
    expect(notified, 1);
    final data = _now(cache.getNotifications());
    expect(data.unreadCount, 1);
    expect(data.items.firstWhere((n) => n.id == 'n1').read, isTrue);
    expect(inner.writes, isNot(contains('done:read:n1')));
    await Future<void>.delayed(_latency * 2);
    expect(inner.writes, contains('done:read:n1'));
  });

  test('các lần ghi được gửi tuần tự đúng thứ tự', () async {
    await warm();
    await cache.markNotificationRead('n1');
    await cache.markAllNotificationsRead();
    await cache.addShoppingItem(name: 'Muối');
    await Future<void>.delayed(_latency * 5);
    expect(inner.writes, [
      'start:read:n1',
      'done:read:n1',
      'start:readAll',
      'done:readAll',
      'start:add:Muối',
      'done:add:Muối',
    ]);
  });

  test('ghi thất bại: khôi phục từ server và phát lỗi tiếng Việt', () async {
    await warm();
    inner.writeError = const SocketException('boom');
    final errors = <String>[];
    cache.backgroundErrors.listen(errors.add);

    await cache.markNotificationRead('n1');
    expect(_now(cache.getNotifications()).unreadCount, 1); // lạc quan

    await Future<void>.delayed(_latency * 5);
    expect(errors, hasLength(1));
    expect(errors.single, startsWith('Không kết nối được mạng'));
    expect(errors.single, isNot(contains('SocketException')));
    // Server chưa đổi gì -> sau khi làm mới số chưa đọc quay lại 2.
    expect(_now(cache.getNotifications()).unreadCount, 2);
    expect((inner as _SlowInner).bootstraps, 2);
  });

  test(
    'lỗi không phải mạng: câu khôi phục chung, không lộ exception',
    () async {
      await warm();
      inner.writeError = StateError('500 internal');
      final errors = <String>[];
      cache.backgroundErrors.listen(errors.add);
      await cache.markAllNotificationsRead();
      await Future<void>.delayed(_latency * 5);
      expect(
        errors.single,
        'Chưa lưu được thay đổi. Mình đã khôi phục lại, bạn thử lại nhé.',
      );
    },
  );

  test('PLAN_LIMIT: phát câu nâng cấp thay vì câu khôi phục chung', () async {
    await warm();
    inner.writeError = const HomeMindApiException(
      'Plan limit',
      statusCode: 402,
      code: 'PLAN_LIMIT',
      details: {'plan': 'free', 'limit': 30, 'count': 30},
    );
    final errors = <String>[];
    cache.backgroundErrors.listen(errors.add);
    await cache.markAllNotificationsRead();
    await Future<void>.delayed(_latency * 5);
    expect(
      errors.single,
      'Gói của bạn đã đủ số lượng sản phẩm. Hãy nâng cấp để thêm sản phẩm mới.',
    );
  });

  test('làm mới cũ (bắt đầu trước khi ghi) không đè trạng thái lạc quan', () async {
    await warm();
    inner.writeGate = Completer<void>(); // giữ request ghi lại
    final refresh = cache.refresh(force: true); // chụp dữ liệu CŨ
    await Future<void>.delayed(const Duration(milliseconds: 10));

    await cache.markNotificationRead('n1'); // ghi lạc quan trong lúc chờ
    await refresh; // dữ liệu cũ về, phải bị bỏ qua
    expect(_now(cache.getNotifications()).unreadCount, 1);

    // Ghi xong -> làm mới đối soát lấy dữ liệu server (giả lập server đã đổi).
    inner.server = Bootstrap(
      home: inner.server.home,
      inventory: inner.server.inventory,
      inventoryTotal: 2,
      shoppingItems: inner.server.shoppingItems,
      suggestions: inner.server.suggestions,
      notifications: [
        inner.server.notifications.first.copyWith(read: true),
        inner.server.notifications.last,
      ],
      unreadCount: 1,
    );
    inner.writeGate!.complete();
    await Future<void>.delayed(_latency * 4);
    expect(_now(cache.getNotifications()).unreadCount, 1);
  });

  test('markInventoryOut cập nhật số liệu Trang chủ nhất quán', () async {
    await warm();
    await cache.markInventoryOut(productId: 'p-milk', addToShoppingList: true);
    final home = _now(cache.getHomeSummary());
    expect(home.inStockCount, 1);
    expect(home.outCount, 1);
    expect(home.expiringSoon, isEmpty);
    expect(home.expiringSoonCount, 0);
    expect(home.alerts, isEmpty);
    expect(home.shoppingNeededCount, 2);
    final inv = _now(cache.getInventory());
    expect(inv.firstWhere((i) => i.productId == 'p-milk').status, 'out');
    final shop = _now(cache.getShoppingList());
    expect(
      shop.items.where((s) => s.name == 'Sữa tươi' && s.status == 'needed'),
      hasLength(1),
    );
  });

  test('markInventoryOut một phần chỉ trừ số lượng', () async {
    await warm();
    await cache.markInventoryOut(
      productId: 'p-rice',
      quantity: 2,
      addToShoppingList: false,
    );
    final inv = _now(cache.getInventory());
    final rice = inv.firstWhere((i) => i.productId == 'p-rice');
    expect(rice.quantity, 3);
    expect(rice.status, 'in_stock');
    expect(_now(cache.getHomeSummary()).outCount, 0);
  });

  test('updateShoppingItem đổi trạng thái và số cần mua', () async {
    await warm();
    await cache.updateShoppingItem(itemId: 's-eggs', status: 'skipped');
    expect(_now(cache.getHomeSummary()).shoppingNeededCount, 0);
    expect(_now(cache.getShoppingList()).items.single.status, 'skipped');
    await cache.updateShoppingItem(itemId: 's-eggs', status: 'needed');
    expect(_now(cache.getHomeSummary()).shoppingNeededCount, 1);
  });

  test('addShoppingItem thêm món tạm và bớt gợi ý cùng tên', () async {
    await warm();
    await cache.addShoppingItem(name: 'dầu ăn', unit: 'chai');
    final shop = _now(cache.getShoppingList());
    expect(shop.items.last.id, startsWith('tmp-'));
    expect(shop.items.last.status, 'needed');
    expect(shop.suggestions, isEmpty);
    expect(_now(cache.getHomeSummary()).shoppingNeededCount, 2);
  });

  test(
    'receiveShoppingItem: món thành bought, cộng vào kho theo tên',
    () async {
      await warm();
      await cache.addShoppingItem(name: 'gạo');
      await cache.receiveShoppingItem(
        itemId: 's-eggs',
        quantity: 6,
        unit: 'quả',
      );
      var home = _now(cache.getHomeSummary());
      var inv = _now(cache.getInventory());
      // Trứng chưa có trong kho -> sản phẩm mới.
      expect(inv.last.name, 'Trứng');
      expect(inv.last.quantity, 6);
      expect(inv.last.status, 'in_stock');
      expect(home.totalProducts, 3);
      expect(home.inStockCount, 3);
      expect(
        _now(cache.getShoppingList()).items
            .firstWhere((s) => s.id == 's-eggs')
            .status,
        'bought',
      );
      expect(home.shoppingNeededCount, 1); // chỉ còn "gạo" vừa thêm

      // Gạo có sẵn trong kho (khác hoa thường) -> cộng dồn số lượng.
      final tempRice = _now(cache.getShoppingList()).items.last;
      await cache.receiveShoppingItem(
        itemId: tempRice.id,
        quantity: 3,
        unit: 'kg',
      );
      inv = _now(cache.getInventory());
      home = _now(cache.getHomeSummary());
      expect(inv.firstWhere((i) => i.productId == 'p-rice').quantity, 8);
      expect(home.totalProducts, 3);
      expect(home.shoppingNeededCount, 0);
    },
  );

  test('updateProfile chỉ công bố hồ sơ sau server acknowledgment', () async {
    const me = UserProfile(
      userId: 'u',
      email: 'a@b.c',
      displayName: 'Cũ',
      workspaceId: 'w',
      workspaceName: 'Nhà',
      workspaceType: 'household',
      role: 'owner',
    );
    final gate = Completer<UserProfile>();
    final profileInner = _ProfileInner(me)..saveGate = gate;
    cache = CachedAssistantService(profileInner, initialProfile: me);
    final pending = cache.updateProfile(displayName: 'Mới');
    expect(syncValue(pending), isNull);
    expect(_now(cache.getMe()).displayName, 'Cũ');
    gate.complete(me.copyWith(displayName: 'Mới'));
    expect((await pending).displayName, 'Mới');
    expect(_now(cache.getMe()).displayName, 'Mới');
  });
}

class _ProfileInner extends _Base {
  _ProfileInner(this.profile);
  UserProfile profile;
  Completer<UserProfile>? saveGate;
  @override
  Future<UserProfile> getMe() async => profile;
  @override
  Future<UserProfile> updateProfile({
    String? displayName,
    String? phone,
    String? address,
    String? language,
  }) async {
    profile =
        await (saveGate?.future ??
            Future.value(
              profile.copyWith(
                displayName: displayName,
                phone: phone,
                address: address,
                language: language,
              ),
            ));
    return profile;
  }
}
