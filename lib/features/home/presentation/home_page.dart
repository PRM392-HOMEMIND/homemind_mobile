import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/config/plan_billing_visibility.dart';

import '../../../core/widgets/page_skeleton.dart';
import '../../assistant/data/backend_assistant_service.dart'
    show HomeMindApiException;
import '../../family/family_gateway.dart';
import '../../family/family_page.dart';

import '../../../core/l10n/app_text.dart';

import '../../../app/homemind_theme.dart';
import '../../../core/date_format.dart';
import '../../../core/product_groups.dart';
import '../../assistant/data/cached_assistant_service.dart';
import '../../assistant/domain/assistant_models.dart';
import '../../assistant/domain/assistant_service.dart';
import 'notifications_sheet.dart';
import '../domain/home_hub_gateway.dart';
import 'home_header.dart';
import 'home_section.dart';
import 'home_surface.dart';
import 'global_search_surface.dart';
import 'durable_notifications_surface.dart';
import 'hub_entity_page.dart';
import 'paywall_sheet.dart';
import 'plan_card.dart';
import '../../spending/presentation/spending_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    required this.service,
    required this.onOpenAssistant,
    required this.onOpenShopping,
    this.onOpenInventory,
    this.onOpenVoice,
    this.onRoleChanged,
    this.onOpenProfile,
    this.onOpenSecurity,
    super.key,
  });

  final AssistantService service;
  final VoidCallback onOpenAssistant;
  final VoidCallback onOpenShopping;
  final VoidCallback? onOpenInventory;
  final VoidCallback? onOpenVoice;
  final ValueChanged<AccountRole>? onRoleChanged;
  final VoidCallback? onOpenProfile, onOpenSecurity;

  @override
  State<HomePage> createState() => _HomePageState();
}

enum _HomeFilter { all, expiring, shopping, inStock }

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late Future<
    ({
      UserProfile me,
      HomeSummary home,
      List<InventoryItem> inventory,
      List<ShoppingItem> shopping,
    })
  >
  _future;

  int? _unreadNotifs;
  TransitionRoute<HubTarget>? _surface;
  NavigatorState? _navigator;
  bool _opening = false;
  final _bellAnchor = GlobalKey();
  final _noticeChanges = ValueNotifier<int>(0);
  Timer? _noticeRefreshTimer;
  Future<void>? _noticeRefresh;
  DateTime? _lastNoticeFetch;
  int _scopeGeneration = 0;
  final List<AppNotification> _notifications = [];
  final _HomeFilter _activeFilter = _HomeFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = _load();
    widget.service.dataChanges.addListener(_onDataChanged);
  }

  /// Bộ nhớ đệm đổi (ghi lạc quan / làm mới nền): đọc lại, trả về tức thì,
  /// huy hiệu chuông và số liệu cập nhật ngay.
  void _onDataChanged() {
    if (!mounted) return;
    setState(() {
      _future = _load();
    });
    _noticeRefreshTimer?.cancel();
    _noticeRefreshTimer = Timer(
      const Duration(milliseconds: 1500),
      _refreshNoticeCount,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (_lastNoticeFetch == null ||
            DateTime.now().difference(_lastNoticeFetch!) >=
                const Duration(seconds: 30))) {
      _refreshNoticeCount();
    }
  }

  Future<void> _refreshNoticeCount() {
    if (_noticeRefresh != null) return _noticeRefresh!;
    final hub = _hub, generation = _scopeGeneration;
    if (hub == null) return Future.value();
    final work = () async {
      try {
        final data = await hub.notifications().timeout(
          const Duration(seconds: 15),
        );
        if (!mounted ||
            generation != _scopeGeneration ||
            _hub?.scope != hub.scope) {
          return;
        }
        final count = data['unreadCount'] as int;
        final changed = count != _unreadNotifs;
        setState(() => _unreadNotifs = count);
        _lastNoticeFetch = DateTime.now();
        if (changed) _noticeChanges.value++;
      } catch (_) {
        if (mounted && generation == _scopeGeneration) {
          setState(() => _unreadNotifs = null);
        }
      }
    }();
    _noticeRefresh = work;
    return work.whenComplete(() {
      if (identical(_noticeRefresh, work)) _noticeRefresh = null;
    });
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service)) {
      ++_scopeGeneration;
      _unreadNotifs = null;
      _lastNoticeFetch = null;
      oldWidget.service.dataChanges.removeListener(_onDataChanged);
      widget.service.dataChanges.addListener(_onDataChanged);
      _future = _load();
    }
  }

  void _applyNotifications(
    ({List<AppNotification> items, int unreadCount}) data,
  ) {
    _notifications
      ..clear()
      ..addAll(data.items);
    _unreadNotifs = data.unreadCount;
    _lastNoticeFetch = DateTime.now();
  }

  Future<
    ({
      UserProfile me,
      HomeSummary home,
      List<InventoryItem> inventory,
      List<ShoppingItem> shopping,
    })
  >
  _load() {
    final meF = widget.service.getMe();
    final homeF = widget.service.getHomeSummary();
    final invF = widget.service.getInventory();
    final shopF = widget.service.getShoppingList();
    final notifF = widget.service.getNotifications();
    // Có bộ nhớ đệm: dựng ngay trong cùng khung hình.
    final me = syncValue(meF);
    final home = syncValue(homeF);
    final inv = syncValue(invF);
    final shop = syncValue(shopF);
    final notif = syncValue(notifF);
    if (me != null &&
        home != null &&
        inv != null &&
        shop != null &&
        notif != null) {
      _applyNotifications(notif);
      return SynchronousFuture((
        me: me,
        home: home,
        inventory: inv,
        shopping: shop.items.where((i) => i.status == 'needed').toList(),
      ));
    }
    return _loadAsync(meF, homeF, invF, shopF, notifF);
  }

  Future<
    ({
      UserProfile me,
      HomeSummary home,
      List<InventoryItem> inventory,
      List<ShoppingItem> shopping,
    })
  >
  _loadAsync(
    Future<UserProfile> meF,
    Future<HomeSummary> homeF,
    Future<List<InventoryItem>> invF,
    Future<({List<ShoppingItem> items, List<Map<String, Object?>> suggestions})>
    shopF,
    Future<({List<AppNotification> items, int unreadCount})> notifF,
  ) async {
    final generation = _scopeGeneration, scope = _hub?.scope;
    // Cache can complete synchronously while the profile is still pending.
    // Normalize this mixed path before Future.wait attaches its callbacks.
    final results = await Future.wait<Object?>(
      <Future<Object?>>[
        meF,
        homeF,
        invF,
        shopF.then((d) => d.items.where((i) => i.status == 'needed').toList()),
        notifF.then<Object?>((d) => d, onError: (_) => null),
      ].map(Future<Object?>.value),
    );
    if (mounted && generation == _scopeGeneration && _hub?.scope == scope) {
      if (results[4] != null) {
        _applyNotifications(
          results[4] as ({List<AppNotification> items, int unreadCount}),
        );
      } else {
        _unreadNotifs = null;
      }
    }

    return (
      me: results[0] as UserProfile,
      home: results[1] as HomeSummary,
      inventory: results[2] as List<InventoryItem>,
      shopping: results[3] as List<ShoppingItem>,
    );
  }

  void _openNotifications() {
    if (_hub != null) {
      _openHub(notifications: true);
      return;
    }
    NotificationsSheet.show(
      context,
      notifications: _notifications,
      onMarkRead: _markNotificationRead,
      onMarkAllRead: _markAllNotificationsRead,
      onUnreadCountChanged: (count) {
        setState(() => _unreadNotifs = count);
      },
    );
  }

  HomeHubGateway? get _hub => widget.service is HomeHubSource
      ? (widget.service as HomeHubSource).homeHub
      : null;
  Future<void> _openHub({bool notifications = false, String? id}) async {
    if (_opening || _surface != null || _hub == null) return;
    _opening = true;
    final gateway = _hub!;
    final TransitionRoute<HubTarget> route = notifications
        ? homeNotificationsRoute(
            reducedMotion: MediaQuery.disableAnimationsOf(context),
            builder: (_) => DurableNotificationsSurface(
              gateway: gateway,
              initialId: id,
              changes: _noticeChanges,
              onUnread: (n) {
                if (mounted) setState(() => _unreadNotifs = n);
              },
            ),
          )
        : homeSearchRoute(
            reducedMotion: MediaQuery.disableAnimationsOf(context),
            builder: (_) => GlobalSearchSurface(gateway: gateway),
          );
    _surface = route;
    _navigator = Navigator.of(context);
    HubTarget? target;
    try {
      target = await _navigator!.push(route);
      await route.completed;
    } finally {
      if (_surface == route) _surface = null;
      _opening = false;
    }
    if (mounted && target != null) await _navigate(target);
  }

  Future<void> _navigate(HubTarget target) async {
    if (!mounted) return;
    if (!PlanBillingVisibility.of(context) &&
        PlanBillingVisibility.isPlanTarget(target.type, target.id)) {
      widget.onOpenProfile?.call();
      return;
    }
    if ({'family', 'family_invitation'}.contains(target.type)) {
      final source = widget.service;
      final gateway = source is FamilySource
          ? (source as FamilySource).family
          : null;
      if (gateway == null) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => target.type == 'family'
              ? FamilyPage(gateway: gateway)
              : FamilyInvitationsPage(
                  gateway: gateway,
                  invitationId: target.id,
                ),
        ),
      );
      return;
    }
    if (target.type == 'notification') {
      await _openHub(notifications: true, id: target.id);
      return;
    }
    if ({'inventory', 'shopping'}.contains(target.type)) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HubEntityPage(gateway: _hub!, target: target),
        ),
      );
      return;
    }
    if (target.type == 'billing') {
      await PaywallSheet.show(
        context,
        service: widget.service,
        source: 'home_card',
        initialPayment: () => _hub!.request(
          'GET',
          '/workspaces/${_hub!.workspaceId}/billing/payments/${Uri.encodeComponent(target.id)}',
        ),
      );
      return;
    }
    if (target.type == 'plan') {
      _openPlans();
      return;
    }
    if (target.type == 'profile') {
      widget.onOpenProfile?.call();
      return;
    }
    switch (target.id) {
      case 'inventory':
        widget.onOpenInventory?.call();
      case 'shopping':
        widget.onOpenShopping();
      case 'profile':
        widget.onOpenProfile?.call();
      case 'security':
        widget.onOpenSecurity?.call();
      case 'notifications':
        await _openHub(notifications: true);
      case 'billing' || 'history' || 'help':
        _openPlans();
      case 'home':
        break;
    }
  }

  void _openPlans() {
    if (!PlanBillingVisibility.of(context)) {
      widget.onOpenProfile?.call();
      return;
    }
    if (_opening) return;
    _opening = true;
    PaywallSheet.show(
      context,
      service: widget.service,
      source: 'home_card',
    ).whenComplete(() => _opening = false);
  }

  Future<void> _markNotificationRead(String notificationId) async {
    await widget.service.markNotificationRead(notificationId);
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index != -1) {
      _notifications[index] = _notifications[index].copyWith(read: true);
    }
  }

  Future<({List<AppNotification> items, int unreadCount})>
  _markAllNotificationsRead() async {
    await widget.service.markAllNotificationsRead();
    final result = await widget.service.getNotifications();
    if (mounted) {
      setState(() {
        _notifications
          ..clear()
          ..addAll(result.items);
        _unreadNotifs = result.unreadCount;
      });
    }
    return result;
  }

  @override
  void dispose() {
    ++_scopeGeneration;
    _noticeRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _noticeChanges.dispose();
    widget.service.dataChanges.removeListener(_onDataChanged);
    final route = _surface, navigator = _navigator;
    if (route != null && navigator != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) navigator.removeRoute(route);
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMerchant = widget.service.currentRole == AccountRole.merchant;

    return FutureBuilder(
      future: _future,
      builder: (context, snapshot) {
        final error = snapshot.error;
        final denied =
            error is HomeMindApiException &&
            (error.statusCode == 401 || error.statusCode == 403);
        if (snapshot.hasError && (!snapshot.hasData || denied)) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.wifi_off_rounded,
                    size: 56,
                    color: HomeMindTheme.textMuted,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr(
                      'Chưa tải được dữ liệu.\nBạn kiểm tra mạng rồi thử lại nhé.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() {
                      _future = _load();
                    }),
                    child: Text(tr('Thử lại')),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: HomeHeader(
                  searchHint: isMerchant
                      ? tr('Tìm hàng hoá, sản phẩm...')
                      : tr('Tìm đồ dùng, thực phẩm...'),
                  unread: null,
                  notificationAnchor: _bellAnchor,
                  onSearch: () => _openHub(),
                  onNotifications: _openNotifications,
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  children: [
                    _VoiceBannerCard(
                      onTap: widget.onOpenVoice ?? widget.onOpenAssistant,
                    ),
                    const SizedBox(height: 20),
                    const PageSkeleton(SkeletonPage.home, sectionOnly: true),
                  ],
                ),
              ),
            ],
          );
        }
        final data = snapshot.data!;
        final home = data.home;
        final inventory = data.inventory;
        final shopping = data.shopping;

        final inStockItems = inventory.where((x) => x.status != 'out').toList();
        // Cùng nguồn và cùng ngưỡng 30 ngày với tab Tủ đồ.
        final expiring = expiringItems(inventory);
        final expiringCount = expiring
            .where((i) => i.expiryLevel != 'expired')
            .length;

        return Column(
          children: [
            if (snapshot.connectionState == ConnectionState.waiting)
              const LinearProgressIndicator(),
            if (snapshot.hasError)
              Text(tr('Chưa tải được dữ liệu mới. Bạn thử lại nhé.')),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: HomeHeader(
                searchHint: isMerchant
                    ? tr('Tìm hàng hoá, sản phẩm...')
                    : tr('Tìm đồ dùng, thực phẩm...'),
                unread: _unreadNotifs,
                notificationAnchor: _bellAnchor,
                onSearch: () => _openHub(),
                onNotifications: _openNotifications,
              ),
            ),
            // ── Scrollable body ──
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  // AI Voice Assistant Quick Action Card
                  _VoiceBannerCard(
                    onTap: widget.onOpenVoice ?? widget.onOpenAssistant,
                  ),
                  const SizedBox(height: 20),

                  // Chi tiêu tháng này (chỉ khi đã có lần mua; ẩn nếu chưa hỗ trợ)
                  if (_activeFilter == _HomeFilter.all &&
                      SpendingCard.supported(widget.service))
                    SpendingCard(service: widget.service, merchant: isMerchant),

                  // Section: Sắp hết hạn / Hàng sắp hết hạn cần xả
                  if (_activeFilter == _HomeFilter.all ||
                      _activeFilter == _HomeFilter.expiring) ...[
                    HomeSection(
                      children: [
                        HomeSectionHeader(
                          title: isMerchant
                              ? tr('Hàng sắp hết hạn ⚠️')
                              : tr('Sắp hết hạn'),
                          subtitle: isMerchant
                              ? tr('Nên bán hoặc dùng trước những món này')
                              : tr('Ưu tiên dùng trước để tránh lãng phí'),
                          actionLabel: tr('Xem tất cả'),
                          onAction: () {
                            if (widget.onOpenInventory != null) {
                              widget.onOpenInventory!();
                            } else {
                              widget.onOpenShopping();
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        if (expiring.isEmpty)
                          HomeEmptyState(
                            icon: Icons.event_available_outlined,
                            message: tr('Không có món nào sắp hết hạn.'),
                          )
                        else
                          _HScroll(
                            count: expiring.length,
                            builder: (context, index) => _ExpiringCard(
                              item: expiring[index],
                              onTap:
                                  widget.onOpenInventory ??
                                  widget.onOpenShopping,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 28),
                  ],

                  // Section: Danh sách cần mua / Danh sách cần nhập
                  if (_activeFilter == _HomeFilter.all ||
                      _activeFilter == _HomeFilter.shopping) ...[
                    HomeSection(
                      children: [
                        HomeSectionHeader(
                          title: isMerchant
                              ? tr('Hàng cần nhập thêm')
                              : tr('Danh sách cần mua'),
                          subtitle: isMerchant
                              ? tr('Những món cần nhập thêm')
                              : tr('Các món đã hết hoặc được thêm để mua lại'),
                          actionLabel:
                              '${tr('Xem tất cả')} (${shopping.length})',
                          onAction: widget.onOpenShopping,
                        ),
                        const SizedBox(height: 12),
                        if (shopping.isEmpty)
                          HomeEmptyState(
                            icon: Icons.shopping_basket_outlined,
                            message: isMerchant
                                ? tr('Chưa có mặt hàng nào cần nhập.')
                                : tr('Chưa có món nào cần mua.'),
                          )
                        else
                          _HScroll(
                            count: shopping.length,
                            builder: (context, index) {
                              final item = shopping[index];
                              return Container(
                                width: 165,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFDF0),
                                  borderRadius: BorderRadius.circular(
                                    HomeMindTheme.radiusLg,
                                  ),
                                  border: Border.all(
                                    color: const Color(0xFFFDE68A),
                                  ),
                                  boxShadow: HomeMindTheme.softShadow,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          HomeMindTheme.getCategoryEmoji(
                                            item.name,
                                          ),
                                          style: const TextStyle(fontSize: 18),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            item.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                              color: HomeMindTheme.textMain,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.quantity != null
                                              ? '${_fmtQty(item.quantity!)} ${item.unit ?? ''}'
                                                    .trim()
                                              : tr('Trạng thái'),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: HomeMindTheme.textMuted,
                                          ),
                                        ),
                                        Text(
                                          item.source == 'auto_out_of_stock'
                                              ? (isMerchant
                                                    ? tr('Hết tồn kho')
                                                    : tr('Đã báo hết hàng'))
                                              : (isMerchant
                                                    ? tr('Cần nhập')
                                                    : tr('Cần mua')),
                                          style: const TextStyle(
                                            color: Color(0xFFD97706),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: widget.onOpenShopping,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          foregroundColor:
                                              HomeMindTheme.textMain,
                                          elevation: 0,
                                          minimumSize: const Size(0, 44),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          shape: const StadiumBorder(),
                                          side: const BorderSide(
                                            color: HomeMindTheme.border,
                                          ),
                                        ),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            tr('Xem danh sách'),
                                            maxLines: 1,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 28),
                  ],

                  // Section: Tủ đồ / Còn hàng
                  if (_activeFilter == _HomeFilter.all ||
                      _activeFilter == _HomeFilter.inStock) ...[
                    HomeSection(
                      children: [
                        HomeSectionHeader(
                          title: isMerchant
                              ? tr('Quầy kệ tiệm tạp hóa')
                              : tr('Tủ đồ của bạn'),
                          subtitle: isMerchant
                              ? tr('Hàng hóa đang bày bán tại quầy kệ tiệm')
                              : tr('Những món đang còn trong nhà'),
                          actionLabel:
                              '${tr('Xem tất cả')} (${inStockItems.length})',
                          onAction:
                              widget.onOpenInventory ?? widget.onOpenShopping,
                        ),
                        const SizedBox(height: 12),
                        if (inStockItems.isEmpty)
                          HomeEmptyState(
                            icon: Icons.kitchen_outlined,
                            message: isMerchant
                                ? tr('Chưa có mặt hàng trên quầy kệ.')
                                : tr('Chưa có món nào trong tủ.'),
                          )
                        else
                          _HScroll(
                            count: inStockItems.length,
                            builder: (context, index) {
                              final item = inStockItems[index];
                              final urgent =
                                  item.expiryLevel == 'urgent' ||
                                  item.expiryLevel == 'expired';
                              final isExpiring =
                                  urgent ||
                                  item.expiryLevel == 'soon' ||
                                  item.expiryLevel == 'attention';

                              return Container(
                                width: 165,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: urgent
                                      ? HomeMindTheme.urgentBg
                                      : isExpiring
                                      ? HomeMindTheme.soonBg
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(
                                    HomeMindTheme.radiusLg,
                                  ),
                                  border: Border.all(
                                    color: urgent
                                        ? HomeMindTheme.danger.withValues(
                                            alpha: 0.2,
                                          )
                                        : isExpiring
                                        ? HomeMindTheme.warning.withValues(
                                            alpha: 0.3,
                                          )
                                        : HomeMindTheme.border,
                                  ),
                                  boxShadow: HomeMindTheme.softShadow,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          groupOf(
                                            category: item.category,
                                            name: item.name,
                                          ).emoji,
                                          style: const TextStyle(fontSize: 20),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            item.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                              color: HomeMindTheme.textMain,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          groupOf(
                                            category: item.category,
                                            name: item.name,
                                          ).label,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: HomeMindTheme.textMuted,
                                          ),
                                        ),
                                        Text(
                                          '${tr('Còn')} ${item.quantity != null ? "· ${_fmtQty(item.quantity!)} ${item.unit ?? ''}" : ""}',
                                          style: TextStyle(
                                            color: urgent
                                                ? HomeMindTheme.danger
                                                : isExpiring
                                                ? const Color(0xFFB45309)
                                                : HomeMindTheme.primaryDark,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton(
                                        onPressed:
                                            widget.onOpenInventory ??
                                            widget.onOpenShopping,
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(
                                            color: HomeMindTheme.border,
                                          ),
                                          minimumSize: const Size(0, 44),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          shape: const StadiumBorder(),
                                        ),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            tr('Xem chi tiết'),
                                            maxLines: 1,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: HomeMindTheme.textSub,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 28),
                  ],

                  // Statistics row (chỉ hiện ở All)
                  if (_activeFilter == _HomeFilter.all) ...[
                    HomeSummaryGrid(
                      key: const Key('home_summary_grid'),
                      children: [
                        _StatChip(
                          label: isMerchant ? tr('Quầy kệ') : tr('Còn'),
                          value: '${home.inStockCount}',
                          color: HomeMindTheme.primaryDark,
                        ),
                        _StatChip(
                          label: tr('Sắp hết hạn'),
                          value: '$expiringCount',
                          color: HomeMindTheme.warning,
                        ),
                        _StatChip(
                          label: isMerchant ? tr('Quá hạn') : tr('Hết hạn'),
                          value: '${home.expiredCount}',
                          color: HomeMindTheme.danger,
                        ),
                        _StatChip(
                          label: isMerchant ? tr('Cần nhập') : tr('Cần mua'),
                          value: '${home.shoppingNeededCount}',
                          color: HomeMindTheme.textMain,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Thẻ gói: phễu chuyển đổi miễn phí -> trả phí
                  PlanCard(
                    home: home,
                    service: widget.service,
                    isMerchant: isMerchant,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Món còn hàng có hạn dùng trong 30 ngày tới hoặc đã quá hạn, gần hạn nhất trước.
/// Ngưỡng này trùng với bộ lọc "sắp quá hạn" ở tab Tủ đồ.
@visibleForTesting
List<InventoryItem> expiringItems(List<InventoryItem> inventory) {
  const levels = {'expired', 'urgent', 'soon', 'attention'};
  final items = inventory
      .where(
        (i) =>
            i.status != 'out' &&
            i.expiryDate != null &&
            levels.contains(i.expiryLevel),
      )
      .toList();
  items.sort((a, b) => a.expiryDate!.compareTo(b.expiryDate!));
  return items;
}

/// Số ngày từ hôm nay tới hạn dùng (âm = đã quá hạn), tính theo lịch địa phương.
int? _daysUntil(String? iso, DateTime now) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(iso ?? '');
  if (match == null) return null;
  final due = DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
  return due.difference(DateTime.utc(now.year, now.month, now.day)).inDays;
}

class _ExpiringCard extends StatelessWidget {
  const _ExpiringCard({required this.item, required this.onTap});

  final InventoryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final days = _daysUntil(item.expiryDate, DateTime.now());
    final expired = item.expiryLevel == 'expired';
    final urgent = expired || item.expiryLevel == 'urgent';
    final color = urgent ? HomeMindTheme.danger : HomeMindTheme.warning;
    final status = switch (days) {
      null => tr('Sắp tới hạn'),
      < 0 => tr('Quá hạn {0} ngày', [-days]),
      0 => tr('Hết hạn hôm nay'),
      1 => tr('Còn 1 ngày'),
      _ => tr('Còn {0} ngày', [days]),
    };
    return Container(
      width: 172,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: urgent ? HomeMindTheme.urgentBg : HomeMindTheme.soonBg,
        borderRadius: BorderRadius.circular(HomeMindTheme.radiusLg),
        border: Border.all(
          color: urgent ? const Color(0xFFFFD6D6) : const Color(0xFFFDE68A),
        ),
        boxShadow: HomeMindTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                groupOf(category: item.category, name: item.name).emoji,
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: HomeMindTheme.textMain,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            tr('HSD: {0}', [formatDay(item.expiryDate)]),
            style: const TextStyle(fontSize: 12, color: HomeMindTheme.textSub),
          ),
          const SizedBox(height: 2),
          Text(
            status,
            style: TextStyle(
              color: urgent ? HomeMindTheme.danger : const Color(0xFFB45309),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: HomeMindTheme.textMain,
                backgroundColor: Colors.white,
                side: BorderSide(color: color.withValues(alpha: 0.35)),
                minimumSize: const Size(0, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: const StadiumBorder(),
              ),
              child: Text(
                tr('Xem chi tiết'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceBannerCard extends StatelessWidget {
  const _VoiceBannerCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [HomeMindTheme.primaryLight, HomeMindTheme.primaryTint],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: HomeMindTheme.primary.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: EdgeInsets.all(18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Trợ lý giọng nói HomeMind'),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: HomeMindTheme.textMain,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  tr('Mọi lời yêu cầu của bạn, chúng tôi đều lắng nghe'),
                  style: TextStyle(
                    fontSize: 13,
                    color: HomeMindTheme.textSub,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [HomeMindTheme.primary, HomeMindTheme.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: HomeMindTheme.greenShadow,
              ),
              child: const Icon(
                Icons.mic_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    this.color = HomeMindTheme.textMain,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
        border: Border.all(color: HomeMindTheme.border),
        boxShadow: HomeMindTheme.softShadow,
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: HomeMindTheme.textSub,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtQty(num value) =>
    value == value.roundToDouble() ? value.toInt().toString() : '$value';

/// Hàng thẻ cuộn ngang có chiều cao đúng bằng thẻ cao nhất (không cố định,
/// tránh khoảng trống thừa trong thẻ).
class _HScroll extends StatelessWidget {
  const _HScroll({required this.count, required this.builder});

  final int count;
  final Widget Function(BuildContext context, int index) builder;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              builder(context, i),
            ],
          ],
        ),
      ),
    );
  }
}

// Handled by Tran Gia Phu
