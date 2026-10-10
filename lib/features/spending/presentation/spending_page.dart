import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/widgets/page_skeleton.dart';
import '../../assistant/data/workspace_pages.dart';
import '../../assistant/data/backend_assistant_service.dart'
    show HomeMindApiException;

import '../../../app/homemind_theme.dart';
import '../../../core/l10n/app_text.dart';
import '../../../core/money.dart';
import '../../assistant/data/cached_assistant_service.dart' show syncValue;
import '../../assistant/domain/assistant_models.dart';
import '../../assistant/domain/assistant_service.dart';
import 'price_entry_sheet.dart';

/// Tháng hiện tại theo giờ Việt Nam, dạng `YYYY-MM` (khớp cách server chia tháng).
String currentSpendingMonth([DateTime? now]) {
  final vn = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 7));
  return '${vn.year.toString().padLeft(4, '0')}-${vn.month.toString().padLeft(2, '0')}';
}

String _shiftMonth(String month, int delta) {
  final y = int.parse(month.substring(0, 4)), m = int.parse(month.substring(5));
  final index = y * 12 + (m - 1) + delta;
  return '${(index ~/ 12).toString().padLeft(4, '0')}-${(index % 12 + 1).toString().padLeft(2, '0')}';
}

String spendingMonthLabel(String month) =>
    tr('Tháng {0}/{1}', [int.parse(month.substring(5)), month.substring(0, 4)]);

/// Dòng so với tháng trước; null khi chưa có gì để so sánh.
({String text, bool up})? spendingDelta(SpendingSummary s) {
  if (s.previousTotalVnd <= 0 || s.totalVnd <= 0) return null;
  final pct = ((s.totalVnd - s.previousTotalVnd) * 100 / s.previousTotalVnd)
      .round();
  if (pct == 0) {
    return (text: tr('Gần như không đổi so với tháng trước'), up: false);
  }
  return pct > 0
      ? (text: tr('Tăng {0}% so với tháng trước', [pct]), up: true)
      : (text: tr('Giảm {0}% so với tháng trước', [-pct]), up: false);
}

/// Chi tiêu theo tháng. Giá là tùy chọn nên màn hình luôn nói rõ tổng này chỉ
/// gồm các lần mua đã có giá và cho nhập giá còn thiếu ngay tại đây.
class SpendingPage extends StatefulWidget {
  const SpendingPage({
    required this.service,
    required this.source,
    required this.merchant,
    super.key,
  });

  final AssistantService service;
  final SpendingSource source;
  final bool merchant;

  @override
  State<SpendingPage> createState() => _SpendingPageState();
}

class _SpendingPageState extends State<SpendingPage> {
  late final String _now = currentSpendingMonth();
  late String _month = _now;
  String _scope = 'workspace';
  WorkspacePages? get _pages => widget.service is WorkspacePagesSource
      ? (widget.service as WorkspacePagesSource).workspacePages
      : null;
  // Install an error listener immediately; FutureBuilder attaches on the next
  // frame. Errors remain on the original future and are rendered by the builder.
  Future<SpendingSummary> _observe(Future<SpendingSummary> future) {
    unawaited(
      future.then<void>((_) {}, onError: (Object error, StackTrace stack) {}),
    );
    return future;
  }

  Future<SpendingSummary> _fetch({String? cursor}) => _observe(
    _pages?.spending(month: _month, scope: _scope, cursor: cursor) ??
        widget.source.getSpending(month: _month),
  );
  late Future<SpendingSummary> _future = _fetch();
  // Bản đang hiển thị: được sửa tại chỗ khi nhập giá để số liệu đổi ngay.
  SpendingSummary? _shown;
  final Set<String> _saving = {};
  @override
  void didUpdateWidget(SpendingPage old) {
    super.didUpdateWidget(old);
    if (old.service != widget.service || old.source != widget.source) {
      _shown = null;
      _saving.clear();
      _scope = 'workspace';
      _future = _fetch();
    }
  }

  void _go(String month) {
    setState(() {
      _month = month;
      _shown = null;
      _future = _fetch();
    });
  }

  void _reload() {
    setState(() {
      _future = _fetch();
    });
  }

  Future<void> _enterPrice(UnpricedPurchase purchase) async {
    if (!purchase.canEdit || _saving.contains(purchase.lotId)) return;
    final source = widget.source, month = _month, scope = _scope;
    final result = await PriceEntrySheet.show(
      context,
      purchase: purchase,
      merchant: widget.merchant,
    );
    final price = result?.priceVnd;
    if (result == null ||
        price == null ||
        !mounted ||
        source != widget.source ||
        month != _month ||
        scope != _scope) {
      return;
    }
    setState(() {
      _saving.add(purchase.lotId);
    });
    try {
      await source.updateLot(
        lotId: purchase.lotId,
        priceVnd: price,
        storageLocation: result.storageLocation,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('Chưa lưu được giá. Bạn thử lại nhé.')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      _saving.remove(purchase.lotId);
      if (mounted &&
          source == widget.source &&
          month == _month &&
          scope == _scope) {
        _reload();
      }
    }
  }

  void _more() {
    final previous = _shown;
    if (previous?.nextCursor == null) return;
    setState(() {
      _future = _observe(
        _fetch(cursor: previous!.nextCursor).then(
          (next) => SpendingSummary(
            month: next.month,
            totalVnd: next.totalVnd,
            pricedCount: next.pricedCount,
            unpricedCount: next.unpricedCount,
            previousTotalVnd: next.previousTotalVnd,
            byCategory: next.byCategory,
            scope: next.scope,
            nextCursor: next.nextCursor,
            byMember: next.byMember,
            unpricedLotCount: next.unpricedLotCount,
            unpriced: {
              for (final row in [...previous.unpriced, ...next.unpriced])
                row.lotId: row,
            }.values.toList(),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeMindTheme.background,
      appBar: AppBar(
        backgroundColor: HomeMindTheme.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.merchant ? tr('Chi phí nhập hàng') : tr('Chi tiêu'),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: HomeMindTheme.textMain,
          ),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<SpendingSummary>(
          key: ValueKey('${identityHashCode(widget.source)}:$_month:$_scope'),
          future: _future,
          initialData: syncValue(_future),
          builder: (context, snapshot) {
            final data = snapshot.data;
            final error = snapshot.error;
            final denied =
                error is HomeMindApiException &&
                (error.statusCode == 401 || error.statusCode == 403);
            if (denied) {
              _shown = null;
            } else if (data != null) {
              _shown = data;
            }
            final summary = _shown;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: [
                if (_pages != null)
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final scope in ['personal', 'workspace'])
                        ChoiceChip(
                          label: Text(
                            tr(
                              scope == 'personal'
                                  ? 'Chi tiêu cá nhân'
                                  : 'Chi tiêu workspace',
                            ),
                          ),
                          selected: _scope == scope,
                          onSelected: (_) {
                            if (_scope != scope) {
                              setState(() {
                                _scope = scope;
                                _shown = null;
                                _future = _fetch();
                              });
                            }
                          },
                        ),
                    ],
                  ),
                if (_pages != null)
                  Text(
                    tr(
                      'Cá nhân chỉ gồm lần mua của bạn trong workspace đang chọn.',
                    ),
                  ),
                _MonthSwitcher(
                  month: _month,
                  canGoNext: _month != _now,
                  onPrevious: () => _go(_shiftMonth(_month, -1)),
                  onNext: () => _go(_shiftMonth(_month, 1)),
                ),
                const SizedBox(height: 12),
                if (summary == null && snapshot.hasError)
                  _Notice(
                    icon: Icons.cloud_off_outlined,
                    text: tr('Chưa tải được chi tiêu. Bạn thử lại nhé.'),
                    action: tr('Tải lại'),
                    onAction: _reload,
                  )
                else if (summary == null)
                  const PageSkeleton(SkeletonPage.spending, sectionOnly: true)
                else ...[
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const LinearProgressIndicator(),
                  if (snapshot.hasError)
                    _Notice(
                      icon: Icons.cloud_off_outlined,
                      text: tr('Chưa tải được chi tiêu. Bạn thử lại nhé.'),
                      action: tr('Tải lại'),
                      onAction: _reload,
                    ),
                  _Hero(summary: summary, merchant: widget.merchant),
                  if (summary.unpricedCount > 0) ...[
                    const SizedBox(height: 12),
                    _Notice(
                      icon: Icons.info_outline_rounded,
                      warning: true,
                      text: tr(
                        '{0} lần mua chưa có giá nên chưa được cộng vào tổng. Nhập giá để số liệu chính xác hơn.',
                        [summary.unpricedCount],
                      ),
                    ),
                  ],
                  if (summary.isEmpty) ...[
                    const SizedBox(height: 28),
                    _EmptyState(
                      text: tr(
                        'Chưa có lần mua nào trong tháng này. Khi bạn lưu đồ vào kho, hãy nhập giá để theo dõi chi tiêu.',
                      ),
                    ),
                  ],
                  if (summary.byCategory.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _SectionTitle(tr('Theo nhóm')),
                    const SizedBox(height: 8),
                    _CategoryBars(rows: summary.byCategory),
                  ],
                  if (_scope == 'workspace' && summary.byMember.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _SectionTitle(tr('Theo người ghi')),
                    for (final row in summary.byMember)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          row['displayName'] as String? ??
                              tr('Chưa rõ người ghi'),
                        ),
                        subtitle: Text(
                          '${row['purchaseCount']} ${tr('lần mua')}',
                        ),
                        trailing: Text(
                          formatVnd((row['knownTotalVnd'] as num).toInt()),
                        ),
                      ),
                  ],
                  if (summary.unpriced.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _SectionTitle(
                      tr('Chưa có giá ({0})', [summary.unpricedCount]),
                    ),
                    const SizedBox(height: 8),
                    for (final purchase in summary.unpriced)
                      _UnpricedRow(
                        purchase: purchase,
                        busy:
                            _saving.contains(purchase.lotId) ||
                            !purchase.canEdit,
                        onEnter: () => _enterPrice(purchase),
                      ),
                    if (summary.nextCursor != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: TextButton(
                          key: const Key('spending_more'),
                          onPressed:
                              snapshot.connectionState ==
                                  ConnectionState.waiting
                              ? null
                              : _more,
                          child: Text(tr('Xem thêm')),
                        ),
                      ),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const Text('🧾', style: TextStyle(fontSize: 40)),
      const SizedBox(height: 8),
      Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13,
          height: 1.4,
          color: HomeMindTheme.textSub,
        ),
      ),
    ],
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: HomeMindTheme.textMain,
      ),
    ),
  );
}

class _MonthSwitcher extends StatelessWidget {
  const _MonthSwitcher({
    required this.month,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
  });

  final String month;
  final bool canGoNext;
  final VoidCallback onPrevious, onNext;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      IconButton(
        key: const Key('spending_prev_month'),
        tooltip: tr('Tháng trước'),
        onPressed: onPrevious,
        icon: const Icon(Icons.chevron_left_rounded),
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      ),
      Semantics(
        liveRegion: true,
        child: Text(
          spendingMonthLabel(month),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: HomeMindTheme.textMain,
          ),
        ),
      ),
      IconButton(
        key: const Key('spending_next_month'),
        tooltip: tr('Tháng sau'),
        onPressed: canGoNext ? onNext : null,
        icon: const Icon(Icons.chevron_right_rounded),
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      ),
    ],
  );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.summary, required this.merchant});
  final SpendingSummary summary;
  final bool merchant;

  @override
  Widget build(BuildContext context) {
    final delta = spendingDelta(summary);
    final counted = summary.pricedCount + summary.unpricedCount;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(HomeMindTheme.radiusLg),
        border: Border.all(color: HomeMindTheme.border),
        boxShadow: HomeMindTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            merchant
                ? tr('Đã nhập hàng trong tháng')
                : tr('Đã chi trong tháng'),
            style: const TextStyle(fontSize: 13, color: HomeMindTheme.textSub),
          ),
          const SizedBox(height: 4),
          Semantics(
            label: tr('Tổng chi {0}', [formatVnd(summary.totalVnd)]),
            excludeSemantics: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                summary.pricedCount == 0 ? '—' : formatVnd(summary.totalVnd),
                key: const Key('spending_total'),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: HomeMindTheme.textMain,
                ),
              ),
            ),
          ),
          if (delta != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  delta.up
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  size: 18,
                  color: delta.up
                      ? HomeMindTheme.warning
                      : HomeMindTheme.primaryStrong,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    delta.text,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: delta.up
                          ? const Color(0xFF92400E)
                          : HomeMindTheme.primaryStrong,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (counted > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: summary.pricedCount / counted,
                minHeight: 6,
                backgroundColor: HomeMindTheme.border,
                color: HomeMindTheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tr('Đã có giá: {0}/{1} lần mua', [summary.pricedCount, counted]),
              style: const TextStyle(
                fontSize: 12,
                color: HomeMindTheme.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.text,
    this.warning = false,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final bool warning;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: warning ? HomeMindTheme.soonBg : Colors.white,
      borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
      border: Border.all(
        color: warning ? const Color(0xFFFDE68A) : HomeMindTheme.border,
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: warning ? const Color(0xFF92400E) : HomeMindTheme.textMuted,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: warning ? const Color(0xFF78350F) : HomeMindTheme.textSub,
            ),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: Text(action!),
          ),
      ],
    ),
  );
}

class _CategoryBars extends StatelessWidget {
  const _CategoryBars({required this.rows});
  final List<({String? category, int totalVnd})> rows;

  @override
  Widget build(BuildContext context) {
    final max = rows
        .map((r) => r.totalVnd)
        .fold<int>(1, (a, b) => b > a ? b : a);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(HomeMindTheme.radiusLg),
        border: Border.all(color: HomeMindTheme.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Semantics(
              label:
                  '${rows[i].category ?? tr('Chưa phân loại')}: ${formatVnd(rows[i].totalVnd)}',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          rows[i].category == null
                              ? tr('Chưa phân loại')
                              : '${HomeMindTheme.getCategoryEmoji(rows[i].category)} ${rows[i].category}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: HomeMindTheme.textMain,
                          ),
                        ),
                      ),
                      Text(
                        formatVnd(rows[i].totalVnd),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: HomeMindTheme.textMain,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: rows[i].totalVnd / max,
                      minHeight: 8,
                      backgroundColor: HomeMindTheme.primaryLight,
                      color: HomeMindTheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UnpricedRow extends StatelessWidget {
  const _UnpricedRow({
    required this.purchase,
    required this.busy,
    required this.onEnter,
  });

  final UnpricedPurchase purchase;
  final bool busy;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    final d = purchase.purchasedAt;
    final when =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    final detail = [
      tr('Mua ngày {0}', [when]),
      if (purchase.storageLocation != null) '📍 ${purchase.storageLocation}',
      if (!purchase.canEdit) tr('Chỉ xem'),
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
        border: Border.all(color: HomeMindTheme.border),
      ),
      child: Row(
        children: [
          Text(
            HomeMindTheme.getCategoryEmoji(purchase.name),
            style: const TextStyle(fontSize: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  purchase.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: HomeMindTheme.textMain,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: HomeMindTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: Key('enter_price_${purchase.lotId}'),
            onPressed: busy ? null : onEnter,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              foregroundColor: HomeMindTheme.primaryStrong,
              side: const BorderSide(color: HomeMindTheme.primary),
              shape: const StadiumBorder(),
            ),
            child: Text(
              tr('Nhập giá'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// Handled by Tran Gia Phu
