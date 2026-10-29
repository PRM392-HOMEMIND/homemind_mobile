import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/l10n/app_text.dart';
import '../domain/assistant_models.dart';
import '../domain/assistant_service.dart';
import 'backend_assistant_service.dart' show HomeMindApiException;
import '../../billing/billing_service.dart';
import '../../home/domain/home_hub_gateway.dart';
import '../../family/family_gateway.dart';
import 'workspace_pages.dart';

/// Đọc giá trị của một Future đã hoàn thành đồng bộ (SynchronousFuture của bộ
/// nhớ đệm). Trả về null nếu Future còn đang chạy thật.
T? syncValue<T>(Future<T> future) {
  if (future is! SynchronousFuture<T>) return null;
  T? value;
  future.then((v) => value = v);
  return value;
}

class _Changes extends ChangeNotifier {
  void fire() => notifyListeners();
}

class ProfileSaveUncertain implements Exception {
  const ProfileSaveUncertain({required this.reconciled});
  final bool reconciled;
}

/// Bộ nhớ đệm + ghi lạc quan bọc quanh một [AssistantService] thật.
///
/// * Đọc: trả về ngay từ ảnh chụp (snapshot) trong bộ nhớ; lần đầu chỉ gọi
///   MỘT request (bootstrap). Ảnh cũ hơn [staleAfter] được làm mới ngầm.
/// * Ghi: sửa snapshot và báo `dataChanges` ĐỒNG BỘ, trả về Future đã xong,
///   rồi gửi request thật ở nền theo hàng đợi tuần tự (giữ thứ tự). Thành
///   công thì lên lịch một lần làm mới (debounce) để khớp dữ liệu server; thất
///   bại thì làm mới để khôi phục và phát lỗi qua [backgroundErrors].
class CachedAssistantService
    implements
        AssistantService,
        BillingSource,
        SpendingSource,
        VoiceQuotaSource,
        FamilySource,
        WorkspacePagesSource,
        HomeHubSource {
  CachedAssistantService(
    this._inner, {
    UserProfile? initialProfile,
    this.staleAfter = const Duration(seconds: 20),
    this.reconcileDelay = const Duration(milliseconds: 400),
    DateTime Function()? clock,
  }) : _me = initialProfile,
       _clock = clock ?? DateTime.now;

  final AssistantService _inner;
  @override
  FamilyGateway? get family =>
      _inner is FamilySource ? (_inner as FamilySource).family : null;
  @override
  WorkspacePages? get workspacePages => _inner is WorkspacePagesSource
      ? (_inner as WorkspacePagesSource).workspacePages
      : null;
  @override
  HomeHubGateway? get homeHub =>
      _inner is HomeHubSource ? (_inner as HomeHubSource).homeHub : null;
  @override
  BillingGateway? get billing =>
      _inner is BillingSource ? (_inner as BillingSource).billing : null;
  @override
  Future<void> refreshBillingEntitlements() async {
    _me = await _inner.getMe();
    if (_disposed) return;
    _notify();
    await refresh(force: true);
  }

  @override
  Future<VoiceQuota?> getVoiceQuota() {
    final pending = _quotaInFlight;
    if (pending != null) return pending;
    final future = _fetchVoiceQuota();
    _quotaInFlight = future;
    return future.whenComplete(() => _quotaInFlight = null);
  }

  Future<VoiceQuota?>? _quotaInFlight;
  Future<VoiceQuota?> _fetchVoiceQuota() async {
    if (_inner is! VoiceQuotaSource) {
      return null; // Existing isolated test doubles.
    }
    final actual = await _inner.getMe();
    if (_disposed) throw StateError('Profile service disposed');
    if (actual.voiceQuota == null) {
      throw const FormatException('Missing authoritative voice quota');
    }
    _me = actual;
    _notify();
    return actual.voiceQuota;
  }

  final Duration staleAfter;
  final Duration reconcileDelay;
  final DateTime Function() _clock;

  final _Changes _changes = _Changes();
  final StreamController<String> _errors = StreamController.broadcast();

  // ── Snapshot ───────────────────────────────────────────────────────────
  bool _hasData = false;
  DateTime? _loadedAt;
  late HomeSummary _home;
  List<InventoryItem> _inventory = const [];
  List<ShoppingItem> _shopping = const [];
  List<Map<String, Object?>> _suggestions = const [];
  List<AppNotification> _notifications = const [];
  int _unread = 0;
  UserProfile? _me;

  // ── Đồng bộ ────────────────────────────────────────────────────────────
  Future<void>? _inflight;
  int _inflightStartMutation = 0;
  int _mutations = 0; // tăng mỗi khi sửa snapshot theo kiểu lạc quan
  int _pendingWrites = 0;
  bool _needsReconcile = false;
  Future<void> _writeTail = Future<void>.value();
  Future<void> _profileTail = Future<void>.value();
  bool _profileOutcomeUnknown = false;
  Timer? _reconcileTimer;
  int _tempCounter = 0;
  bool _disposed = false;

  @override
  Listenable get dataChanges => _changes;

  @override
  Stream<String> get backgroundErrors => _errors.stream;

  /// Đã có dữ liệu trong bộ nhớ chưa.
  bool get hasData => _hasData;

  void dispose() {
    _disposed = true;
    _reconcileTimer?.cancel();
    _errors.close();
    _changes.dispose();
  }

  // ── Vai trò / hồ sơ ────────────────────────────────────────────────────

  @override
  AccountRole get currentRole => _inner.currentRole;

  @override
  void switchRole(AccountRole role) => _inner.switchRole(role);

  @override
  Future<UserProfile> getMe() {
    final me = _me;
    if (me != null) return SynchronousFuture<UserProfile>(me);
    return _inner.getMe().then((value) => _me = value);
  }

  @override
  Future<UserProfile> updateProfile({
    String? displayName,
    String? phone,
    String? address,
    String? language,
  }) {
    final result = _profileTail.then((_) async {
      if (_disposed) throw StateError('Profile service disposed');
      if (_profileOutcomeUnknown) {
        try {
          final actual = await _inner.getMe();
          if (_disposed) throw StateError('Profile service disposed');
          _me = actual;
          _profileOutcomeUnknown = false;
          _notify();
        } catch (_) {
          throw const ProfileSaveUncertain(reconciled: false);
        }
      }
      late UserProfile saved;
      try {
        saved = await _inner.updateProfile(
          displayName: displayName,
          phone: phone,
          address: address,
          language: language,
        );
      } catch (error) {
        // A validation/auth rejection is definitive. Keep the committed cache
        // and let the caller keep the form open, without a background toast.
        if (error is HomeMindApiException &&
            error.statusCode != null &&
            error.statusCode! >= 400 &&
            error.statusCode! < 500) {
          rethrow;
        }
        // PATCH is never replayed blindly after a lost response. Read the
        // authoritative state, then distinguish confirmed save from uncertainty.
        UserProfile? actual;
        try {
          actual = await _inner.getMe();
        } catch (_) {}
        if (_disposed) throw StateError('Profile service disposed');
        if (actual != null) {
          _me = actual;
          _notify();
          final matches =
              (displayName == null ||
                  actual.displayName == displayName.trim()) &&
              (phone == null || (actual.phone ?? '') == phone.trim()) &&
              (address == null || (actual.address ?? '') == address.trim()) &&
              (language == null || actual.language == language);
          if (matches) return actual;
        }
        _profileOutcomeUnknown = actual == null;
        throw ProfileSaveUncertain(reconciled: actual != null);
      }
      if (_disposed) throw StateError('Profile service disposed');
      _me = saved;
      _mutations++;
      _notify();
      return saved;
    });
    _profileTail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  // ── Đọc ────────────────────────────────────────────────────────────────

  Future<T> _read<T>(T Function() pick) {
    if (_hasData) {
      _revalidateIfStale();
      return SynchronousFuture<T>(pick());
    }
    return refresh().then((_) => pick());
  }

  @override
  Future<HomeSummary> getHomeSummary() => _read(() => _home);

  @override
  Future<({List<AppNotification> items, int unreadCount})> getNotifications() =>
      _read(() => (items: _notifications, unreadCount: _unread));

  @override
  Future<List<InventoryItem>> getInventory() => _read(() => _inventory);

  @override
  Future<({List<ShoppingItem> items, List<Map<String, Object?>> suggestions})>
  getShoppingList() =>
      _read(() => (items: _shopping, suggestions: _suggestions));

  void _revalidateIfStale() {
    final at = _loadedAt;
    if (at == null || _inflight != null) return;
    if (_clock().difference(at) > staleAfter) _backgroundRefresh();
  }

  void _backgroundRefresh({bool force = false}) {
    if (_disposed) return;
    refresh(force: force).catchError((Object _) {});
  }

  /// Làm mới từ server (dùng cho kéo-để-làm-mới với `force: true`). Nhiều
  /// người gọi cùng lúc dùng chung một Future. Lỗi được ném lại cho người gọi.
  Future<void> refresh({bool force = false}) {
    if (!force && _hasData) {
      final at = _loadedAt;
      if (at != null && _clock().difference(at) <= staleAfter) {
        return SynchronousFuture<void>(null);
      }
    }
    final current = _inflight;
    if (current != null) {
      // Lần đang chạy bắt đầu trước một thay đổi lạc quan thì kết quả của nó
      // sẽ bị bỏ qua; chờ nó xong rồi chạy lại để khôi phục đúng.
      if (force && _inflightStartMutation != _mutations) {
        return current.then(
          (_) => refresh(force: true),
          onError: (_) => refresh(force: true),
        );
      }
      return current;
    }
    _inflightStartMutation = _mutations;
    final future = _refreshNow().whenComplete(() => _inflight = null);
    _inflight = future;
    return future;
  }

  Future<void> _refreshNow() async {
    final startMutations = _mutations;
    final data = await _fetch();
    if (_disposed) return;
    final canApply =
        !_hasData || (_pendingWrites == 0 && startMutations == _mutations);
    if (!canApply) return; // dữ liệu cũ hơn thay đổi lạc quan: bỏ qua
    _home = data.home;
    _inventory = data.inventory;
    _shopping = data.shoppingItems;
    _suggestions = data.suggestions;
    _notifications = data.notifications;
    _unread = data.unreadCount;
    _hasData = true;
    _loadedAt = _clock();
    _notify();
  }

  Future<Bootstrap> _fetch() async {
    final inner = _inner;
    if (inner is BootstrapSource) {
      return (inner as BootstrapSource).getBootstrap();
    }
    final results = await Future.wait<Object?>([
      inner.getHomeSummary(),
      inner.getInventory(),
      inner.getShoppingList(),
      inner.getNotifications(),
    ]);
    final shopping =
        results[2]
            as ({
              List<ShoppingItem> items,
              List<Map<String, Object?>> suggestions,
            });
    final notifications =
        results[3] as ({List<AppNotification> items, int unreadCount});
    final inventory = results[1] as List<InventoryItem>;
    return Bootstrap(
      home: results[0] as HomeSummary,
      inventory: inventory,
      inventoryTotal: inventory.length,
      shoppingItems: shopping.items,
      suggestions: shopping.suggestions,
      notifications: notifications.items,
      unreadCount: notifications.unreadCount,
    );
  }

  void _notify() {
    if (!_disposed) _changes.fire();
  }

  // ── Hàng đợi ghi tuần tự ──────────────────────────────────────────────

  void _enqueue(Future<void> Function() send, {bool affectsData = true}) {
    if (affectsData) _spendingStale();
    _pendingWrites++;
    _writeTail = _writeTail.then((_) async {
      var failed = false;
      try {
        await send();
      } catch (error) {
        failed = true;
        _needsReconcile = true;
        if (!_disposed) _errors.add(_friendlyMessage(error));
      } finally {
        _pendingWrites--;
        if (_pendingWrites == 0) _onQueueDrained(failed);
      }
    });
  }

  void _onQueueDrained(bool lastFailed) {
    if (_disposed) return;
    _reconcileTimer?.cancel();
    if (_needsReconcile) {
      // Có lần ghi thất bại: khôi phục NGAY bằng dữ liệu server.
      _needsReconcile = false;
      _backgroundRefresh(force: true);
      return;
    }
    _reconcileTimer = Timer(reconcileDelay, () {
      _backgroundRefresh(force: true);
    });
  }

  String _friendlyMessage(Object error) {
    if (error is HomeMindApiException && error.isPlanLimit) {
      return tr(
        'Gói của bạn đã đủ số lượng sản phẩm. Hãy nâng cấp để thêm sản phẩm mới.',
      );
    }
    final text = error.toString();
    if (error is SocketException ||
        error is TimeoutException ||
        text.contains('Không thể kết nối') ||
        text.contains('SocketException') ||
        text.contains('ClientException')) {
      return tr('Không kết nối được mạng. Bạn kiểm tra Wi-Fi rồi thử lại nhé.');
    }
    return tr(
      'Chưa lưu được thay đổi. Mình đã khôi phục lại, bạn thử lại nhé.',
    );
  }

  bool _isTemp(String id) => id.startsWith('tmp-');

  String _temp(String kind) => 'tmp-$kind-${++_tempCounter}';

  /// Mã tạm (tạo lúc ghi lạc quan) chưa được server cấp mã thật: tra lại theo
  /// tên ngay trước khi gửi.
  Future<String> _realShoppingId(String id, String name) async {
    if (!_isTemp(id)) return id;
    final list = await _inner.getShoppingList();
    for (final item in list.items) {
      if (!_isTemp(item.id) &&
          item.status == 'needed' &&
          item.name.toLowerCase() == name.toLowerCase()) {
        return item.id;
      }
    }
    throw StateError('Không tìm thấy món vừa thêm.');
  }

  Future<String> _realProductId(String id, String name) async {
    if (!_isTemp(id)) return id;
    final list = await _inner.getInventory();
    for (final item in list) {
      if (!_isTemp(item.productId) &&
          item.name.toLowerCase() == name.toLowerCase()) {
        return item.productId;
      }
    }
    throw StateError('Không tìm thấy sản phẩm vừa thêm.');
  }

  // ── Ghi lạc quan ──────────────────────────────────────────────────────

  void _commit() {
    _mutations++;
    _notify();
  }

  @override
  Future<void> markNotificationRead(String notificationId) {
    if (_hasData) {
      final index = _notifications.indexWhere((n) => n.id == notificationId);
      if (index != -1 && !_notifications[index].read) {
        _notifications = List.of(_notifications)
          ..[index] = _notifications[index].copyWith(read: true);
        _unread = (_unread - 1).clamp(0, 1 << 30);
      }
      _commit();
    }
    _enqueue(
      () => _inner.markNotificationRead(notificationId),
      affectsData: false,
    );
    return SynchronousFuture<void>(null);
  }

  @override
  Future<void> markAllNotificationsRead() {
    // Preserve ordered legacy mutations; reconciliation supplies the real remaining count.
    // Never optimistically claim an arbitrary bounded batch cleared every notification.
    _enqueue(() => _inner.markAllNotificationsRead(), affectsData: false);
    return SynchronousFuture<void>(null);
  }

  @override
  Future<void> markInventoryOut({
    required String productId,
    double? quantity,
    required bool addToShoppingList,
  }) {
    String? name;
    if (_hasData) {
      final index = _inventory.indexWhere((i) => i.productId == productId);
      if (index != -1) {
        final item = _inventory[index];
        name = item.name;
        final wasIn = item.status != 'out';
        final remaining = quantity == null || item.quantity == null
            ? 0.0
            : (item.quantity! - quantity).clamp(0.0, double.infinity);
        final goesOut = remaining <= 0;
        _inventory = List.of(_inventory)
          ..[index] = goesOut
              ? item.copyWith(quantity: 0, status: 'out')
              : item.copyWith(quantity: remaining);
        var home = _home;
        if (wasIn && goesOut) {
          final inSoon = home.expiringSoon.any((i) => i.productId == productId);
          final inExpired = home.expired.any((i) => i.productId == productId);
          home = home.copyWith(
            inStockCount: (home.inStockCount - 1).clamp(0, 1 << 30),
            outCount: home.outCount + 1,
            expiringSoon: [
              for (final i in home.expiringSoon)
                if (i.productId != productId) i,
            ],
            expired: [
              for (final i in home.expired)
                if (i.productId != productId) i,
            ],
            expiringSoonCount: inSoon
                ? (home.expiringSoonCount - 1).clamp(0, 1 << 30)
                : null,
            expiredCount: inExpired
                ? (home.expiredCount - 1).clamp(0, 1 << 30)
                : null,
            alerts: [
              for (final a in home.alerts)
                if (a.productId != productId) a,
            ],
          );
        }
        if (addToShoppingList &&
            !_shopping.any(
              (s) =>
                  s.status == 'needed' &&
                  s.name.toLowerCase() == item.name.toLowerCase(),
            )) {
          _shopping = [
            ..._shopping,
            ShoppingItem(
              id: _temp('shop'),
              name: item.name,
              quantity: null,
              unit: item.unit,
              status: 'needed',
              source: 'auto_out_of_stock',
            ),
          ];
          home = home.copyWith(
            shoppingNeededCount: home.shoppingNeededCount + 1,
          );
        }
        _home = home;
        _commit();
      }
    }
    final fallbackName = name;
    _enqueue(() async {
      final id = fallbackName == null
          ? productId
          : await _realProductId(productId, fallbackName);
      await _inner.markInventoryOut(
        productId: id,
        quantity: quantity,
        addToShoppingList: addToShoppingList,
      );
    });
    return SynchronousFuture<void>(null);
  }

  @override
  Future<void> updateShoppingItem({
    required String itemId,
    required String status,
  }) {
    String? name;
    if (_hasData) {
      final index = _shopping.indexWhere((s) => s.id == itemId);
      if (index != -1) {
        final item = _shopping[index];
        name = item.name;
        if (item.status != status) {
          _shopping = List.of(_shopping)
            ..[index] = item.copyWith(status: status);
          var delta = 0;
          if (item.status == 'needed') delta--;
          if (status == 'needed') delta++;
          _home = _home.copyWith(
            shoppingNeededCount: (_home.shoppingNeededCount + delta).clamp(
              0,
              1 << 30,
            ),
          );
          if (status == 'needed') _dropSuggestion(item.name);
          _commit();
        }
      }
    }
    final fallbackName = name;
    _enqueue(() async {
      final id = fallbackName == null
          ? itemId
          : await _realShoppingId(itemId, fallbackName);
      await _inner.updateShoppingItem(itemId: id, status: status);
    });
    return SynchronousFuture<void>(null);
  }

  @override
  Future<void> addShoppingItem({
    required String name,
    double? quantity,
    String? unit,
  }) {
    if (_hasData) {
      final exists = _shopping.any(
        (s) =>
            s.status == 'needed' && s.name.toLowerCase() == name.toLowerCase(),
      );
      if (!exists) {
        _shopping = [
          ..._shopping,
          ShoppingItem(
            id: _temp('shop'),
            name: name,
            quantity: quantity,
            unit: unit,
            status: 'needed',
            source: 'manual',
          ),
        ];
        _home = _home.copyWith(
          shoppingNeededCount: _home.shoppingNeededCount + 1,
        );
      }
      _dropSuggestion(name);
      _commit();
    }
    _enqueue(
      () => _inner.addShoppingItem(name: name, quantity: quantity, unit: unit),
    );
    return SynchronousFuture<void>(null);
  }

  @override
  Future<void> receiveShoppingItem({
    required String itemId,
    double? quantity,
    String? unit,
    String? expiryDate,
    int? priceVnd,
    String? storageLocation,
  }) {
    String? name;
    if (_hasData) {
      final index = _shopping.indexWhere((s) => s.id == itemId);
      if (index != -1) {
        final item = _shopping[index];
        name = item.name;
        var home = _home;
        if (item.status != 'bought') {
          _shopping = List.of(_shopping)
            ..[index] = item.copyWith(status: 'bought');
          if (item.status == 'needed') {
            home = home.copyWith(
              shoppingNeededCount: (home.shoppingNeededCount - 1).clamp(
                0,
                1 << 30,
              ),
            );
          }
        }
        final invIndex = _inventory.indexWhere(
          (i) => i.name.toLowerCase() == item.name.toLowerCase(),
        );
        if (invIndex != -1) {
          final existing = _inventory[invIndex];
          final wasOut = existing.status == 'out';
          _inventory = List.of(_inventory)
            ..[invIndex] = existing.copyWith(
              // Không nói số lượng thì giữ nguyên số đang có (chỉ là "có hàng").
              quantity: quantity == null
                  ? (wasOut ? null : existing.quantity)
                  : (wasOut ? 0 : (existing.quantity ?? 0)) + quantity,
              unit: existing.unit ?? unit,
              status: 'in_stock',
              storageLocation: storageLocation,
              expiryDate: wasOut ? expiryDate : null,
              expiryLevel: wasOut && expiryDate != null
                  ? _levelFor(expiryDate)
                  : (wasOut ? 'ok' : null),
            );
          if (wasOut) {
            home = home.copyWith(
              inStockCount: home.inStockCount + 1,
              outCount: (home.outCount - 1).clamp(0, 1 << 30),
            );
          }
        } else {
          _inventory = [
            ..._inventory,
            InventoryItem(
              productId: _temp('inv'),
              name: item.name,
              category: null,
              quantity: quantity,
              unit: unit,
              expiryDate: expiryDate,
              expiryLevel: expiryDate == null ? 'ok' : _levelFor(expiryDate),
              status: 'in_stock',
              storageLocation: storageLocation,
            ),
          ];
          home = home.copyWith(
            totalProducts: home.totalProducts + 1,
            inStockCount: home.inStockCount + 1,
            productCountTowardLimit: home.productCountTowardLimit + 1,
          );
        }
        _home = home;
        _commit();
      }
    }
    final fallbackName = name;
    _enqueue(() async {
      final id = fallbackName == null
          ? itemId
          : await _realShoppingId(itemId, fallbackName);
      await _inner.receiveShoppingItem(
        itemId: id,
        quantity: quantity,
        unit: unit,
        expiryDate: expiryDate,
        priceVnd: priceVnd,
        storageLocation: storageLocation,
      );
    });
    return SynchronousFuture<void>(null);
  }

  // ── Chi tiêu: đọc/ghi qua server, có đệm ngắn ─────────────────────────

  static const _spendingTtl = Duration(seconds: 30);
  final Map<String, ({DateTime at, SpendingSummary value})> _spending = {};
  final Map<String, Future<SpendingSummary>> _spendingInflight = {};
  int _spendingGeneration = 0;

  void _spendingStale() {
    _spendingGeneration++;
    _spending.clear();
    _spendingInflight.clear();
  }

  @override
  bool get spendingAvailable {
    final inner = _inner;
    return inner is SpendingSource &&
        (inner as SpendingSource).spendingAvailable;
  }

  @override
  Future<SpendingSummary> getSpending({String? month}) {
    final inner = _inner;
    if (inner is! SpendingSource) {
      return Future.error(UnsupportedError('Chưa hỗ trợ chi tiêu.'));
    }
    final key = month ?? '';
    final hit = _spending[key];
    if (hit != null && _clock().difference(hit.at) < _spendingTtl) {
      return SynchronousFuture<SpendingSummary>(hit.value);
    }
    return _spendingInflight[key] ??= () async {
      final generation = _spendingGeneration;
      // Các ghi đang chờ phải xong trước để tổng khớp với thứ người dùng vừa nhập.
      await _writeTail;
      try {
        final value = await (inner as SpendingSource).getSpending(month: month);
        if (generation == _spendingGeneration) {
          _spending[key] = (at: _clock(), value: value);
        }
        return value;
      } finally {
        if (generation == _spendingGeneration) _spendingInflight.remove(key);
      }
    }();
  }

  @override
  Future<void> updateLot({
    required String lotId,
    int? priceVnd,
    String? storageLocation,
  }) async {
    final inner = _inner;
    if (inner is! SpendingSource) {
      throw UnsupportedError('Chưa hỗ trợ chi tiêu.');
    }
    _spendingStale();
    await _writeTail;
    try {
      await (inner as SpendingSource).updateLot(
        lotId: lotId,
        priceVnd: priceVnd,
        storageLocation: storageLocation,
      );
    } finally {
      _spendingStale();
    }
    _backgroundRefresh(force: true);
    _notify();
  }

  void _dropSuggestion(String name) {
    final lower = name.toLowerCase();
    _suggestions = [
      for (final s in _suggestions)
        if (((s['name'] as String?) ?? '').toLowerCase() != lower) s,
    ];
  }

  String _levelFor(String isoDate) {
    final date = DateTime.tryParse(isoDate);
    if (date == null) return 'ok';
    final now = _clock();
    final days = DateTime(
      date.year,
      date.month,
      date.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days < 0) return 'expired';
    if (days <= 2) return 'urgent';
    if (days <= 7) return 'soon';
    return 'ok';
  }

  @override
  Future<void> requestUpgrade({required String plan, required String source}) {
    if (_hasData && !_home.requestedPlans.contains(plan)) {
      final previous = _home.requestedPlans;
      _home = _home.copyWith(requestedPlans: [...previous, plan]);
      _commit();
      _enqueue(() async {
        try {
          await _inner.requestUpgrade(plan: plan, source: source);
        } catch (_) {
          // Hoàn tác: bỏ gói vừa thêm lạc quan rồi để hàng đợi báo lỗi.
          _home = _home.copyWith(
            requestedPlans: [
              for (final p in _home.requestedPlans)
                if (p != plan || previous.contains(plan)) p,
            ],
          );
          _commit();
          rethrow;
        }
      });
    } else {
      _enqueue(() => _inner.requestUpgrade(plan: plan, source: source));
    }
    return SynchronousFuture<void>(null);
  }

  // ── Không lạc quan: chuyển thẳng cho service thật ─────────────────────

  @override
  Future<AssistantTurn> turn({
    required String text,
    String inputType = 'voice_transcript',
  }) async {
    late AssistantTurn turn;
    try {
      turn = await _inner.turn(text: text, inputType: inputType);
    } on HomeMindApiException catch (error) {
      final quota = error.voiceQuota;
      if (!_disposed &&
          quota != null &&
          _me != null &&
          (_me!.voiceQuota == null ||
              !quota.serverNow.isBefore(_me!.voiceQuota!.serverNow))) {
        _me = _me!.copyWith(voiceQuota: quota);
        _notify();
      }
      rethrow;
    }
    if (!_disposed &&
        turn.voiceQuota != null &&
        _me != null &&
        (_me!.voiceQuota == null ||
            !turn.voiceQuota!.serverNow.isBefore(_me!.voiceQuota!.serverNow))) {
      _me = _me!.copyWith(voiceQuota: turn.voiceQuota);
      _notify();
    }
    return turn;
  }

  @override
  Future<AssistantTurn> confirm({
    required String turnId,
    required List<ToolCall> tools,
  }) async {
    final turn = await _writeTail.then(
      (_) => _inner.confirm(turnId: turnId, tools: tools),
    );
    // Dữ liệu đã đổi trên server: làm mới ngầm, màn hình tự cập nhật khi xong.
    _spendingStale();
    _backgroundRefresh(force: true);
    return turn;
  }

  @override
  Future<AssistantTurn> cancel({required String turnId}) =>
      _inner.cancel(turnId: turnId);
}
