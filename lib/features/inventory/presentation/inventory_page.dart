import 'package:flutter/material.dart';

import '../../../core/widgets/page_skeleton.dart';

import '../../../core/l10n/app_text.dart';

import '../../../app/homemind_theme.dart';
import '../../assistant/domain/assistant_models.dart';
import '../../assistant/domain/assistant_service.dart';
import '../../../core/date_format.dart';
import '../../../core/product_groups.dart';
import '../../home/presentation/paywall_sheet.dart';
import '../../home/presentation/plan_card.dart';
import '../../../core/config/plan_billing_visibility.dart';
import '../../home/presentation/plan_catalog.dart';
import 'repurchase_dialog.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({
    required this.service,
    this.initialFilterExpiring = false,
    this.onBack,
    super.key,
  });

  final AssistantService service;
  final bool initialFilterExpiring;
  final VoidCallback? onBack;

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _searchController = TextEditingController();
  late Future<List<InventoryItem>> _future;
  bool _busy = false;

  late bool _filterExpiring;
  ProductGroup? _selectedGroup; // null = tất cả

  @override
  void initState() {
    super.initState();
    _filterExpiring = widget.initialFilterExpiring;
    _future = widget.service.getInventory();
    widget.service.dataChanges.addListener(_onDataChanged);
  }

  /// Bộ nhớ đệm đổi (ghi lạc quan / làm mới nền): đọc lại, trả về tức thì.
  void _onDataChanged() {
    if (mounted) _reload();
  }

  void _reload() => setState(() {
    _future = widget.service.getInventory();
  });

  @override
  void didUpdateWidget(covariant InventoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service)) {
      oldWidget.service.dataChanges.removeListener(_onDataChanged);
      widget.service.dataChanges.addListener(_onDataChanged);
    }
  }

  @override
  void dispose() {
    widget.service.dataChanges.removeListener(_onDataChanged);
    _searchController.dispose();
    super.dispose();
  }

  Color _levelColor(String level) => switch (level) {
    'expired' || 'urgent' => HomeMindTheme.danger,
    'soon' || 'attention' => HomeMindTheme.warning,
    _ => HomeMindTheme.primaryDark,
  };

  String _levelLabel(String level) => switch (level) {
    'expired' => tr('Đã hết hạn'),
    'urgent' => tr('Rất gấp'),
    'soon' || 'attention' => tr('Sắp hết hạn'),
    _ => tr('An toàn'),
  };

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? HomeMindTheme.danger : HomeMindTheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _handleMarkOut(InventoryItem item) async {
    if (_busy || !item.canEdit) return;
    final wantsRebuy = await RepurchaseDialog.show(
      context,
      item.name,
      merchant: widget.service.currentRole == AccountRole.merchant,
    );
    // Đóng hộp thoại mà không chọn gì = không làm gì cả.
    if (wantsRebuy == null || !mounted) return;

    final isMerchant = widget.service.currentRole == AccountRole.merchant;
    setState(() => _busy = true);
    try {
      await widget.service.markInventoryOut(
        productId: item.productId,
        quantity: null,
        addToShoppingList: wantsRebuy,
      );
      _toast(
        wantsRebuy
            ? (isMerchant
                  ? tr('Đã báo hết "{0}" và thêm vào danh sách cần nhập.', [
                      item.name,
                    ])
                  : tr('Đã báo hết "{0}" và thêm vào danh sách cần mua.', [
                      item.name,
                    ]))
            : tr('Đã báo hết "{0}".', [item.name]),
      );
    } catch (_) {
      _toast(
        tr('Chưa báo hết được "{0}". Bạn thử lại nhé.', [item.name]),
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reload();
      }
    }
  }

  Widget _groupChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
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
          color: selected ? HomeMindTheme.primary : HomeMindTheme.border,
        ),
      ),
    );
  }

  /// Nhắc nhẹ khi gói miễn phí sắp đầy (>= 80%); lỗi/không có dữ liệu thì ẩn.
  Widget _planBanner() {
    return HomeSummaryGate(
      service: widget.service,
      builder: (context, home) {
        if (home == null || home.plan != 'free') return const SizedBox.shrink();
        final usage = PlanUsage.of(home);
        if (usage.limit <= 0 || usage.ratio < 0.8) {
          return const SizedBox.shrink();
        }
        return PlanNudgeBanner(
          key: const Key('inventory_plan_banner'),
          text: tr(
            PlanBillingVisibility.of(context)
                ? '⚠️ Gói miễn phí sắp đầy ({0}/{1})'
                : '⚠️ Sắp đạt giới hạn lưu trữ ({0}/{1})',
            [usage.used, usage.limit],
          ),
          action: tr('Xem gói hiện tại'),
          onTap: () => PaywallSheet.show(
            context,
            service: widget.service,
            source: 'inventory_banner',
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMerchant = widget.service.currentRole == AccountRole.merchant;

    return FutureBuilder(
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
            child: PageSkeleton(SkeletonPage.inventory),
          );
        }

        final allItems = snapshot.data!;
        final inStockItems = allItems.where((x) => x.status != 'out').toList();

        final query = _searchController.text.trim().toLowerCase();
        final filtered = inStockItems.where((item) {
          final matchesSearch =
              query.isEmpty || item.name.toLowerCase().contains(query);
          final matchesCat =
              _selectedGroup == null ||
              groupOf(category: item.category, name: item.name) ==
                  _selectedGroup;

          final isExpiring =
              item.expiryLevel == 'urgent' ||
              item.expiryLevel == 'soon' ||
              item.expiryLevel == 'expired' ||
              item.expiryLevel == 'attention';
          final matchesExpiring = !_filterExpiring || isExpiring;

          return matchesSearch && matchesCat && matchesExpiring;
        }).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            // Sub-topbar
            Row(
              children: [
                if (widget.onBack != null || Navigator.canPop(context)) ...[
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed:
                        widget.onBack ?? () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    isMerchant ? tr('Kho hàng của tiệm') : tr('Tủ đồ của bạn'),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: HomeMindTheme.textMain,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              isMerchant
                  ? tr('Những món đang có trong tiệm.')
                  : tr('Những món đang có trong nhà.'),
              style: const TextStyle(
                fontSize: 13,
                color: HomeMindTheme.textSub,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isMerchant
                  ? tr('{0} món đang có · Món sắp hết hạn xếp trước', [
                      inStockItems.length,
                    ])
                  : tr('{0} món đang có · Món sắp hết hạn xếp trước', [
                      inStockItems.length,
                    ]),
              style: const TextStyle(
                fontSize: 13,
                color: HomeMindTheme.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _planBanner(),
            const SizedBox(height: 4),

            // Search bar
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
                border: Border.all(color: HomeMindTheme.border),
                boxShadow: HomeMindTheme.softShadow,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              child: Row(
                children: [
                  const Icon(
                    Icons.search_rounded,
                    color: HomeMindTheme.textMuted,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                        fontSize: 13,
                        color: HomeMindTheme.textMain,
                      ),
                      decoration: InputDecoration(
                        hintText: isMerchant
                            ? tr('Tìm mặt hàng trên quầy kệ tiệm...')
                            : tr('Tìm sản phẩm trong tủ nhà...'),
                        hintStyle: const TextStyle(
                          color: HomeMindTheme.textMuted,
                          fontSize: 13,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      child: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: HomeMindTheme.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Bật/tắt: chỉ hiện sản phẩm sắp quá hạn (chip, không dùng checkbox)
            Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                button: true,
                toggled: _filterExpiring,
                child: Material(
                  color: _filterExpiring ? HomeMindTheme.soonBg : Colors.white,
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: _filterExpiring
                          ? HomeMindTheme.warning
                          : HomeMindTheme.border,
                    ),
                  ),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () =>
                        setState(() => _filterExpiring = !_filterExpiring),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _filterExpiring
                                  ? Icons.check_rounded
                                  : Icons.schedule_rounded,
                              size: 18,
                              color: HomeMindTheme.warning,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                (isMerchant
                                        ? tr('⚠️ Chỉ hiện hàng sắp hết hạn')
                                        : tr(
                                            '⚠️ Chỉ hiện sản phẩm sắp quá hạn',
                                          ))
                                    .replaceFirst('⚠️ ', ''),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: HomeMindTheme.textMain,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            if (_filterExpiring) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      tr('Đang lọc các món sắp quá hạn'),
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFFB45309),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _filterExpiring = false),
                      child: Text(
                        tr('Hiện tất cả'),
                        style: TextStyle(
                          fontSize: 13,
                          color: HomeMindTheme.primaryDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),

            // Bộ lọc theo nhóm lớn (chỉ hiện nhóm đang có món)
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
                    _groupChip(
                      label: tr('Tất cả'),
                      selected: _selectedGroup == null,
                      onTap: () => setState(() => _selectedGroup = null),
                    ),
                    for (final group in ProductGroup.values)
                      if (inStockItems.any(
                        (i) =>
                            groupOf(category: i.category, name: i.name) ==
                            group,
                      ))
                        _groupChip(
                          label:
                              '${group.emoji} ${group.label} (${inStockItems.where((i) => groupOf(category: i.category, name: i.name) == group).length})',
                          selected: _selectedGroup == group,
                          onTap: () => setState(() => _selectedGroup = group),
                        ),
                  ],
                ),
              ),
            ),
            if (_selectedGroup != null) ...[
              const SizedBox(height: 8),
              Text(
                '${_selectedGroup!.label}: ${_selectedGroup!.hint}',
                style: const TextStyle(
                  fontSize: 13,
                  color: HomeMindTheme.textSub,
                  height: 1.3,
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Product cards list
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Column(
                    children: [
                      const Text('🔍', style: TextStyle(fontSize: 36)),
                      const SizedBox(height: 8),
                      Text(
                        tr('Không tìm thấy sản phẩm phù hợp.'),
                        style: TextStyle(
                          color: HomeMindTheme.textSub,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _filterExpiring = false;
                            _selectedGroup = null;
                          });
                        },
                        child: Text(tr('Đặt lại bộ lọc')),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...filtered.map((item) {
                final isUrgent =
                    item.expiryLevel == 'urgent' ||
                    item.expiryLevel == 'expired';
                final levelText = _levelLabel(item.expiryLevel);
                final levelColor = _levelColor(item.expiryLevel);

                return Container(
                  key: ValueKey('inventory_item_${item.productId}'),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Avatar
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: HomeMindTheme.primaryLight,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: HomeMindTheme.primary.withValues(
                                  alpha: 0.1,
                                ),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                groupOf(
                                  category: item.category,
                                  name: item.name,
                                ).emoji,
                                style: const TextStyle(fontSize: 20),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Name, Category, Expiry
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: HomeMindTheme.textMain,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF4F4F5),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          groupOf(
                                            category: item.category,
                                            name: item.name,
                                          ).label,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: HomeMindTheme.textSub,
                                          ),
                                        ),
                                      ),
                                    ],
                                    Text(
                                      item.quantity != null
                                          ? tr('Còn {0} {1}', [
                                              _fmtQty(item.quantity!),
                                              item.unit ?? '',
                                            ])
                                          : tr('Còn'),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: HomeMindTheme.primaryDark,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isUrgent
                                            ? HomeMindTheme.urgentBg
                                            : levelColor ==
                                                  HomeMindTheme.warning
                                            ? HomeMindTheme.soonBg
                                            : HomeMindTheme.primaryLight,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        levelText,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: levelColor,
                                        ),
                                      ),
                                    ),
                                    if (item.expiryDate != null) ...[
                                      Text(
                                        tr('HSD: {0}', [
                                          formatDay(item.expiryDate),
                                        ]),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: levelColor,
                                        ),
                                      ),
                                    ],
                                    if (item.storageLocation != null)
                                      Semantics(
                                        label: tr('Nơi cất: {0}', [
                                          item.storageLocation,
                                        ]),
                                        excludeSemantics: true,
                                        child: Text(
                                          '📍 ${item.storageLocation}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: HomeMindTheme.textSub,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: _busy || !item.canEdit
                              ? null
                              : () => _handleMarkOut(item),
                          icon: const Icon(
                            Icons.remove_shopping_cart_outlined,
                            size: 18,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: HomeMindTheme.textSub,
                            side: const BorderSide(color: HomeMindTheme.border),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            minimumSize: const Size(0, 44),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: const StadiumBorder(),
                          ),
                          label: Text(
                            isMerchant
                                ? tr('Báo hết hàng')
                                : tr('Đánh dấu Hết'),
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
              }),
          ],
        );
      },
    );
  }
}

String _fmtQty(num value) =>
    value == value.roundToDouble() ? value.toInt().toString() : '$value';

// Handled by Tran Gia Phu
