import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/widgets/page_skeleton.dart';
import '../../assistant/data/workspace_pages.dart';

import 'package:flutter/material.dart';

import '../../../core/config/plan_billing_visibility.dart';

import '../../../core/l10n/app_text.dart';

import '../../../app/homemind_theme.dart';
import '../../../core/product_groups.dart';
import 'receive_sheet.dart';
import '../../assistant/data/backend_assistant_service.dart'
    show HomeMindApiException;
import '../../home/presentation/paywall_sheet.dart';
import '../../home/presentation/plan_catalog.dart';
import '../../assistant/data/cached_assistant_service.dart';
import '../../assistant/domain/assistant_models.dart';
import '../../assistant/domain/assistant_service.dart';

class ShoppingPage extends StatefulWidget {
  const ShoppingPage({required this.service, this.onBack, super.key});

  final AssistantService service;
  final VoidCallback? onBack;

  @override
  State<ShoppingPage> createState() => _ShoppingPageState();
}

class _ShoppingPageState extends State<ShoppingPage> {
  late Future<
    ({
      List<ShoppingItem> items,
      List<Map<String, Object?>> suggestions,
      List<InventoryItem> inventory,
    })
  >
  _future;

  String _filter = 'need'; // 'need', 'out', 'skipped'
  bool _busy = false;
  bool _searchVisible = false;
  String _query = '';
  WorkspacePages? get _pages => widget.service is WorkspacePagesSource
      ? (widget.service as WorkspacePagesSource).workspacePages
      : null;
  final Map<String, String?> _cursors = {};
  final Map<String, int> _totals = {};
  List<ShoppingItem>? _pageRows;
  int _pageGeneration = 0;
  bool _paging = false;
  Object? _pageError;
  Timer? _searchTimer;
  String? _workspaceName;
  int _profileRequest = 0;
  final _addController = TextEditingController();

  bool _matches(String name) =>
      name.toLowerCase().contains(_query.trim().toLowerCase());

  void _loadWorkspaceName() {
    final service = widget.service;
    final request = ++_profileRequest;
    service
        .getMe()
        .then((profile) {
          if (mounted &&
              identical(service, widget.service) &&
              request == _profileRequest &&
              _workspaceName != profile.workspaceName) {
            setState(() => _workspaceName = profile.workspaceName);
          }
        })
        .catchError((Object _) {});
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
    _loadWorkspaceName();
    widget.service.dataChanges.addListener(_onDataChanged);
  }

  /// Bộ nhớ đệm đổi (ghi lạc quan / làm mới nền): đọc lại, trả về tức thì.
  void _onDataChanged() {
    if (mounted) {
      _reload();
      _loadWorkspaceName();
    }
  }

  @override
  void didUpdateWidget(covariant ShoppingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service)) {
      oldWidget.service.dataChanges.removeListener(_onDataChanged);
      widget.service.dataChanges.addListener(_onDataChanged);
      _workspaceName = null;
      _pageRows = null;
      _cursors.clear();
      _totals.clear();
      _query = '';
      ++_pageGeneration;
      _future = _load();
      _loadWorkspaceName();
    }
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    ++_pageGeneration;
    widget.service.dataChanges.removeListener(_onDataChanged);
    _addController.dispose();
    super.dispose();
  }

  Future<
    ({
      List<ShoppingItem> items,
      List<Map<String, Object?>> suggestions,
      List<InventoryItem> inventory,
    })
  >
  _load() {
    if (_pages != null) {
      final future = _loadPaged();
      // A newer cache notification can replace this future before a frame
      // attaches FutureBuilder. Observe it while preserving its UI error.
      future.ignore();
      return future;
    }
    final shopFuture = widget.service.getShoppingList();
    final invFuture = widget.service.getInventory();
    // Có bộ nhớ đệm: dựng ngay trong cùng khung hình, không chờ gì cả.
    final shopNow = syncValue(shopFuture);
    final invNow = syncValue(invFuture);
    if (shopNow != null && invNow != null) {
      return SynchronousFuture((
        items: shopNow.items,
        suggestions: shopNow.suggestions,
        inventory: invNow,
      ));
    }
    return _loadAsync(shopFuture, invFuture);
  }

  Future<
    ({
      List<ShoppingItem> items,
      List<Map<String, Object?>> suggestions,
      List<InventoryItem> inventory,
    })
  >
  _loadPaged() async {
    final generation = ++_pageGeneration;
    final pages = _pages!, q = _query.trim();
    final needed = pages.shopping(status: 'needed', q: q);
    final skipped = pages.shopping(status: 'skipped', q: q);
    final inventory = Future<List<InventoryItem>>.value(
      widget.service.getInventory(),
    );
    final results = await Future.wait<Object>([needed, skipped, inventory]);
    if (generation != _pageGeneration) {
      // A search, service replacement or disposal cancels this result. It is
      // not a network failure, even if FutureBuilder still observes the old
      // future during search debounce. Never publish rows from the old scope.
      return (
        items: <ShoppingItem>[],
        suggestions: <Map<String, Object?>>[],
        inventory: <InventoryItem>[],
      );
    }
    final a =
        results[0]
            as ({
              List<ShoppingItem> items,
              List<Map<String, Object?>> suggestions,
              int total,
              String? nextCursor,
            });
    final b =
        results[1]
            as ({
              List<ShoppingItem> items,
              List<Map<String, Object?>> suggestions,
              int total,
              String? nextCursor,
            });
    _pageRows = [...a.items, ...b.items];
    _cursors.addAll({'needed': a.nextCursor, 'skipped': b.nextCursor});
    _totals.addAll({'needed': a.total, 'skipped': b.total});
    _pageError = null;
    return (
      items: _pageRows!,
      suggestions: a.suggestions,
      inventory: results[2] as List<InventoryItem>,
    );
  }

  Future<void> _more() async {
    final status = _filter == 'need' ? 'needed' : 'skipped',
        cursor = _cursors[_filter == 'need' ? 'needed' : 'skipped'];
    if (_paging || cursor == null || _pages == null) return;
    final generation = _pageGeneration;
    setState(() {
      _paging = true;
      _pageError = null;
    });
    try {
      final page = await _pages!.shopping(
        status: status,
        q: _query.trim(),
        cursor: cursor,
      );
      if (!mounted || generation != _pageGeneration) return;
      setState(() {
        _pageRows = {
          for (final row in [...?_pageRows, ...page.items]) row.id: row,
        }.values.toList();
        _cursors[status] = page.nextCursor;
        _totals[status] = page.total;
      });
    } catch (error) {
      if (mounted && generation == _pageGeneration) {
        setState(() => _pageError = error);
      }
    } finally {
      if (mounted) setState(() => _paging = false);
    }
  }

  void _search(String value) {
    _searchTimer?.cancel();
    setState(() {
      _query = value;
      ++_pageGeneration;
      _paging = false;
      _cursors.clear();
    });
    if (_pages != null) {
      _searchTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _pageRows = null;
            _cursors.clear();
            _totals.clear();
            _future = _load();
          });
        }
      });
    }
  }

  Future<
    ({
      List<ShoppingItem> items,
      List<Map<String, Object?>> suggestions,
      List<InventoryItem> inventory,
    })
  >
  _loadAsync(
    Future<({List<ShoppingItem> items, List<Map<String, Object?>> suggestions})>
    shopFuture,
    Future<List<InventoryItem>> invFuture,
  ) async {
    final results = await Future.wait<Object?>([shopFuture, invFuture]);
    final shopData =
        results[0]
            as ({
              List<ShoppingItem> items,
              List<Map<String, Object?>> suggestions,
            });
    return (
      items: shopData.items,
      suggestions: shopData.suggestions,
      inventory: results[1] as List<InventoryItem>,
    );
  }

  void _reload() => setState(() {
    _future = _load();
  });

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          // Callers supply local templates, including verbatim product names.
          // Plan-specific copy is gated at the explicit PLAN_LIMIT branch.
          content: Text(message),
          backgroundColor: error ? HomeMindTheme.danger : HomeMindTheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  /// Chạy một thao tác ghi lên server, rồi tải lại dữ liệu thật.
  Future<void> _run(
    Future<void> Function() action, {
    required String success,
    required String failure,
    Future<void> Function(HomeMindApiException error)? onPlanLimit,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      _toast(success);
    } catch (error) {
      if (onPlanLimit != null &&
          error is HomeMindApiException &&
          error.isPlanLimit) {
        await onPlanLimit(error);
      } else {
        _toast(failure, error: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _future = _load();
        });
      }
    }
  }

  bool get _isMerchant => widget.service.currentRole == AccountRole.merchant;

  void _setStatus(ShoppingItem item, String status) {
    if (!item.canEdit || _busy) return;
    final label = switch (status) {
      'skipped' => tr('Đã bỏ qua "{0}".', [item.name]),
      _ =>
        _isMerchant
            ? tr('Đã đưa "{0}" về danh sách cần nhập.', [item.name])
            : tr('Đã đưa "{0}" về danh sách cần mua.', [item.name]),
    };
    _run(
      () => widget.service.updateShoppingItem(itemId: item.id, status: status),
      success: label,
      failure: tr('Chưa cập nhật được "{0}". Bạn thử lại nhé.', [item.name]),
    );
  }

  /// Nơi cất đã dùng cho món cùng tên trong kho (đọc từ bộ nhớ, không gọi mạng).
  String? _knownLocation(String name) {
    final inventory = syncValue(widget.service.getInventory());
    if (inventory == null) return null;
    final lower = name.trim().toLowerCase();
    for (final item in inventory) {
      if (item.name.trim().toLowerCase() == lower) return item.storageLocation;
    }
    return null;
  }

  /// Hàng đã về: hỏi số lượng thực nhận rồi cất vào kho/tủ đồ (một thao tác
  /// ở server: cộng tồn kho và đóng món trong danh sách).
  Future<void> _receive(ShoppingItem item) async {
    if (_busy || !item.canEdit) return;
    // Kiểm tra hạn mức trước: món mới mà gói đã đủ thì không mở form nhận hàng.
    final gate = await _gateFor(item.name);
    if (gate != PlanGateResult.allowed) {
      await _handleBlocked(gate);
      return;
    }
    if (!mounted) return;
    final result = await ReceiveSheet.show(
      context,
      item: item,
      merchant: _isMerchant,
      initialLocation: _knownLocation(item.name),
    );
    if (result == null || !mounted) return;
    final q = result.quantity;
    final qty = q == null
        ? ''
        : (q == q.roundToDouble() ? q.toInt().toString() : q.toString());
    // Chỉ nêu những gì người dùng đã nhập; không bịa số lượng hay đơn vị.
    final what = [
      if (qty.isNotEmpty) qty,
      if (result.unit != null) result.unit!,
    ].join(' ');
    await _run(
      () => widget.service.receiveShoppingItem(
        itemId: item.id,
        quantity: result.quantity,
        unit: result.unit,
        expiryDate: result.expiryDate,
        priceVnd: result.priceVnd,
        storageLocation: result.storageLocation,
      ),
      success: _isMerchant
          ? (what.isEmpty
                ? tr('Đã nhập hàng "{0}".', [item.name])
                : tr('Đã nhập hàng {0} "{1}".', [what, item.name]))
          : (what.isEmpty
                ? tr('Đã mua "{0}".', [item.name])
                : tr('Đã mua {0} "{1}".', [what, item.name])),
      failure: tr('Chưa ghi được "{0}". Bạn thử lại nhé.', [item.name]),
      onPlanLimit: (error) {
        if (!mounted) return Future.value();
        if (!PlanBillingVisibility.of(context)) {
          _toast(
            tr('Không thể thêm sản phẩm mới vì đã đạt giới hạn lưu trữ.'),
            error: true,
          );
          return Future.value();
        }
        final plan = error.details?['plan'];
        final limit = error.details?['limit'];
        if (plan is String && plan != 'free') {
          _toast(
            PlanGate.message(
              PlanGateResult.blockedPaidLimit,
              plan,
              limit is num ? limit.toInt() : 500,
            )!,
            error: true,
          );
          return Future.value();
        }
        return _handleBlocked(PlanGateResult.blockedFree);
      },
    );
  }

  HomeSummary? _lastHome;

  Future<PlanGateResult> _gateFor(String name) async {
    try {
      final home = await widget.service.getHomeSummary();
      final inventory = await widget.service.getInventory();
      _lastHome = home;
      return PlanGate.checkAddProduct(
        home: home,
        inventory: inventory,
        productName: name,
      );
    } catch (_) {
      return PlanGateResult.allowed; // không tra được thì để server quyết định
    }
  }

  Future<void> _handleBlocked(PlanGateResult gate) async {
    if (!mounted) return;
    if (!PlanBillingVisibility.of(context)) {
      _toast(
        tr('Không thể thêm sản phẩm mới vì đã đạt giới hạn lưu trữ.'),
        error: true,
      );
      return;
    }
    if (gate == PlanGateResult.blockedPaidLimit) {
      final home = _lastHome;
      _toast(
        PlanGate.message(
          gate,
          home?.plan ?? 'micro_pos',
          home?.freePlanLimit ?? 500,
        )!,
        error: true,
      );
      return;
    }
    await PaywallSheet.show(
      context,
      service: widget.service,
      source: 'limit_reached',
    );
  }

  void _addByName(String name, {String? unit}) {
    _run(
      () => widget.service.addShoppingItem(name: name, unit: unit),
      success: _isMerchant
          ? tr('Đã thêm "{0}" vào danh sách cần nhập.', [name])
          : tr('Đã thêm "{0}" vào danh sách cần mua.', [name]),
      failure: tr('Chưa thêm được "{0}". Bạn thử lại nhé.', [name]),
    );
  }

  void _submitQuickAdd() {
    final name = _addController.text.trim();
    if (name.isEmpty || _busy) return;
    _addController.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    _addByName(name);
  }

  /// Ô nhập nhanh: gõ tên món rồi bấm + (hoặc Enter) là thêm vào danh sách.
  Widget _quickAddBar(bool isMerchant) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: HomeMindTheme.border),
        boxShadow: HomeMindTheme.softShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('shopping_quick_add'),
              controller: _addController,
              enabled: !_busy,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _submitQuickAdd(),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: HomeMindTheme.textMain,
              ),
              decoration: InputDecoration(
                hintText: isMerchant
                    ? tr('Thêm món cần nhập…')
                    : tr('Thêm món cần mua…'),
                hintStyle: const TextStyle(
                  fontSize: 15,
                  color: HomeMindTheme.textMuted,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          IconButton.filled(
            key: const Key('shopping_quick_add_button'),
            tooltip: tr('Thêm'),
            onPressed: _busy ? null : _submitQuickAdd,
            style: IconButton.styleFrom(
              backgroundColor: HomeMindTheme.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(44, 44),
            ),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMerchant = widget.service.currentRole == AccountRole.merchant;

    return FutureBuilder(
      key: ValueKey(widget.service),
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
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
                      'Chưa tải được danh sách.\nBạn kiểm tra mạng rồi thử lại nhé.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _reload,
                    child: Text(tr('Thử lại')),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const SingleChildScrollView(
            child: PageSkeleton(SkeletonPage.shopping),
          );
        }
        final data = snapshot.data!;
        final rawItems = _pages != null
            ? (_pageRows ?? data.items)
            : data.items;
        final inventory = data.inventory;
        final suggestions = data.suggestions
            .where((s) => _matches(s['name'] as String? ?? ''))
            .toList();

        // Collect out of stock items from inventory
        final outOfStockItems = inventory
            .where((x) => x.status == 'out' && _matches(x.name))
            .toList();

        // Categorize items
        final needList = rawItems
            .where((x) => x.status == 'needed' && _matches(x.name))
            .toList();
        final skippedList = rawItems
            .where((x) => x.status == 'skipped' && _matches(x.name))
            .toList();
        final neededNames = rawItems
            .where((x) => x.status == 'needed')
            .map((x) => x.name.toLowerCase())
            .toSet();

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            if (snapshot.connectionState == ConnectionState.waiting)
              const LinearProgressIndicator(),
            // Tiêu đề + tìm kiếm (giống các tab khác, không có hàng logo thừa)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.onBack != null || Navigator.canPop(context))
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 2),
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: HomeMindTheme.textMain,
                      ),
                      onPressed:
                          widget.onBack ?? () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isMerchant && (_workspaceName ?? '').isNotEmpty) ...[
                        Text(
                          _workspaceName!,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: HomeMindTheme.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              isMerchant
                                  ? tr('Hàng cần nhập thêm ')
                                  : tr('Danh sách cần mua '),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: HomeMindTheme.textMain,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          Text(
                            isMerchant ? '🚚' : '🛒',
                            style: const TextStyle(fontSize: 22),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isMerchant
                            ? tr('Những món tiệm cần nhập thêm')
                            : tr(
                                'Những món bạn cần mua lại hoặc bổ sung cho gia đình',
                              ),
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          color: HomeMindTheme.textSub,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: tr('Tìm kiếm'),
                  icon: Icon(
                    _searchVisible ? Icons.close_rounded : Icons.search_rounded,
                    color: HomeMindTheme.textSub,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  onPressed: () => setState(() {
                    _searchVisible = !_searchVisible;
                    if (!_searchVisible) _search('');
                  }),
                ),
              ],
            ),
            if (_searchVisible) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('shopping_search'),
                autofocus: true,
                onChanged: _search,
                decoration: InputDecoration(
                  hintText: isMerchant
                      ? tr('Tìm món cần nhập...')
                      : tr('Tìm kiếm sản phẩm cần mua...'),
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (_filter == 'need') _quickAddBar(isMerchant),

            // Filter chips
            SizedBox(
              height: 44,
              child: ShaderMask(
                // Mờ dần mép phải: chip bị cắt là dấu hiệu "còn cuộn được".
                shaderCallback: (rect) => const LinearGradient(
                  colors: [Colors.white, Colors.white, Colors.transparent],
                  stops: [0, 0.92, 1],
                ).createShader(rect),
                blendMode: BlendMode.dstIn,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _FilterTab(
                      label: isMerchant
                          ? tr('Cần nhập ({0})', [
                              _totals['needed'] ?? needList.length,
                            ])
                          : tr('Cần mua ({0})', [
                              _totals['needed'] ?? needList.length,
                            ]),
                      selected: _filter == 'need',
                      onTap: () => setState(() => _filter = 'need'),
                    ),
                    const SizedBox(width: 8),
                    _FilterTab(
                      label: isMerchant
                          ? tr('Hết hàng ({0})', [outOfStockItems.length])
                          : tr('Đã hết ({0})', [outOfStockItems.length]),
                      selected: _filter == 'out',
                      hasAlert: outOfStockItems.isNotEmpty,
                      onTap: () => setState(() => _filter = 'out'),
                    ),
                    const SizedBox(width: 8),
                    _FilterTab(
                      label: tr('Đã bỏ qua ({0})', [
                        _totals['skipped'] ?? skippedList.length,
                      ]),
                      selected: _filter == 'skipped',
                      onTap: () => setState(() => _filter = 'skipped'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Content based on selected filter
            if (_filter == 'need') ...[
              if (needList.isEmpty)
                _emptyPlaceholder(
                  isMerchant
                      ? tr('Không có mặt hàng nào cần nhập.')
                      : tr('Không có món nào cần mua.'),
                  hint: tr(
                    'Gõ tên món vào ô phía trên, hoặc bấm nút Nói rồi đọc "nhớ mua sả".',
                  ),
                )
              else
                ...needList.map((item) {
                  return _ShoppingCard(
                    key: ValueKey('shopping_item_${item.id}'),
                    name: item.name,
                    reason: item.source == 'auto_out_of_stock'
                        ? tr('Tự thêm vì đã hết')
                        : null,
                    details: [
                      if (item.quantity != null) _fmtQty(item.quantity!),
                      if (item.unit != null) item.unit,
                    ].whereType<String>().join(' '),
                    buyLabel: isMerchant ? tr('Đã nhập hàng') : tr('Đã mua'),
                    buyEnabled: item.canEdit && !_busy,
                    onBuy: () => _receive(item),
                    markBoughtLabel: tr('Bỏ qua'),
                    onMarkBought: item.canEdit && !_busy
                        ? () => _setStatus(item, 'skipped')
                        : null,
                  );
                }),
            ] else if (_filter == 'out') ...[
              if (outOfStockItems.isEmpty)
                _emptyPlaceholder(
                  isMerchant
                      ? tr('Không có mặt hàng nào hết trên quầy kệ.')
                      : tr('Không có món nào đã hết.'),
                )
              else
                ...outOfStockItems.map((item) {
                  return _ShoppingCard(
                    key: ValueKey('shopping_out_${item.productId}'),
                    name: item.name,
                    details: groupOf(
                      category: item.category,
                      name: item.name,
                    ).label,
                    buyEnabled: !neededNames.contains(item.name.toLowerCase()),
                    onBuy: () => _addByName(item.name, unit: item.unit),
                    buyLabel: neededNames.contains(item.name.toLowerCase())
                        ? tr('Đã trong danh sách')
                        : (isMerchant ? tr('Cần nhập lại') : tr('Cần mua lại')),
                  );
                }),
            ] else if (_filter == 'skipped') ...[
              if (skippedList.isEmpty)
                _emptyPlaceholder(tr('Chưa có món nào bị bỏ qua.'))
              else
                ...skippedList.map((item) {
                  return _ShoppingCard(
                    key: ValueKey('shopping_item_${item.id}'),
                    name: item.name,
                    details: '',
                    onBuy: () => _setStatus(item, 'needed'),
                    buyEnabled: item.canEdit && !_busy,
                    buyLabel: tr('Khôi phục'),
                  );
                }),
            ],

            if (_pageError != null)
              Text(tr('Chưa tải được trang tiếp theo. Hãy thử lại.')),
            if (_filter != 'out' &&
                _cursors[_filter == 'need' ? 'needed' : 'skipped'] != null)
              TextButton(
                key: const Key('shopping_more'),
                onPressed: _paging ? null : _more,
                child: Text(tr(_paging ? 'Đang tải dữ liệu' : 'Xem thêm')),
              ),
            if (_filter == 'need' && needList.isNotEmpty && needList.length < 4)
              _voiceTip(isMerchant),

            // AI Suggestions section
            if (suggestions.isNotEmpty && _filter == 'need') ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  const Text('💡', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text(
                    isMerchant
                        ? tr('Gợi ý: hàng đã hết trên kệ')
                        : tr('Gợi ý mua sắm thông minh'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: HomeMindTheme.textMain,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...suggestions.map(
                (s) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
                    border: Border.all(color: HomeMindTheme.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: HomeMindTheme.primaryLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            HomeMindTheme.getCategoryEmoji('${s['name']}'),
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${s['name']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () => _addByName('${s['name']}'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: HomeMindTheme.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          minimumSize: const Size(0, 44),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          tr('Thêm'),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// Gợi ý ngắn khi danh sách còn ít món: nói cũng thêm được, không cần gõ.
  Widget _voiceTip(bool isMerchant) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HomeMindTheme.primaryTint,
        borderRadius: BorderRadius.circular(HomeMindTheme.radiusLg),
        border: Border.all(
          color: HomeMindTheme.mintBorder.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.mic_rounded,
            color: HomeMindTheme.primaryDark,
            size: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isMerchant
                  ? tr(
                      'Bấm nút Nói rồi đọc "cần nhập 5 thùng bia" để thêm nhanh.',
                    )
                  : tr(
                      'Bấm nút Nói rồi đọc "nhớ mua nửa ký sả" để thêm nhanh.',
                    ),
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: HomeMindTheme.textSub,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyPlaceholder(String message, {String? hint}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(HomeMindTheme.radiusLg),
        border: Border.all(color: HomeMindTheme.border),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: HomeMindTheme.primaryLight,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Text('🛒', style: TextStyle(fontSize: 34)),
          ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: HomeMindTheme.textMain,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: HomeMindTheme.textSub,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterTab extends StatelessWidget {
  const _FilterTab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.hasAlert = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool hasAlert;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: HomeMindTheme.primary,
      labelStyle: TextStyle(
        color: selected ? Colors.white : HomeMindTheme.textSub,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        fontSize: 13,
      ),
      shape: const StadiumBorder(),
      side: BorderSide(
        color: selected
            ? HomeMindTheme.primary
            : hasAlert
            ? HomeMindTheme.warning.withValues(alpha: 0.5)
            : HomeMindTheme.border,
      ),
    );
  }
}

class _ShoppingCard extends StatelessWidget {
  const _ShoppingCard({
    required this.name,
    required this.details,
    required this.onBuy,
    this.onMarkBought,
    this.reason,
    this.buyLabel,
    this.markBoughtLabel,
    this.buyEnabled = true,
    super.key,
  });

  final String name;
  final String? reason;
  final String details;
  final VoidCallback onBuy;
  final VoidCallback? onMarkBought;
  final String? buyLabel;
  final String? markBoughtLabel;
  final bool buyEnabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(HomeMindTheme.radiusLg),
        border: Border.all(color: HomeMindTheme.border),
        boxShadow: HomeMindTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: HomeMindTheme.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    HomeMindTheme.getCategoryEmoji(name),
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        height: 1.25,
                        color: HomeMindTheme.textMain,
                      ),
                    ),
                    if (reason != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        reason!,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: HomeMindTheme.textSub,
                        ),
                      ),
                    ],
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        details,
                        style: const TextStyle(
                          fontSize: 13,
                          color: HomeMindTheme.primaryDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: ElevatedButton(
                  onPressed: buyEnabled ? onBuy : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HomeMindTheme.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE5E7EB),
                    disabledForegroundColor: HomeMindTheme.textMuted,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    minimumSize: const Size(0, 44),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    buyLabel ?? tr('Đã mua'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (onMarkBought != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  // "Bỏ qua" nhẹ hơn "Đã mua": hành động phụ, không tranh sự chú ý.
                  child: TextButton(
                    onPressed: onMarkBought,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      minimumSize: const Size(0, 44),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      markBoughtLabel ?? tr('Đã mua'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: HomeMindTheme.textSub,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

String _fmtQty(num value) =>
    value == value.roundToDouble() ? value.toInt().toString() : '$value';

// Handled by Tran Gia Phu
