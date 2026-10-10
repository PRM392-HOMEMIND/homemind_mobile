import 'package:flutter/material.dart';

import '../../../app/homemind_theme.dart';
import '../../../core/l10n/app_text.dart';
import '../../../core/money.dart';
import '../../assistant/data/cached_assistant_service.dart' show syncValue;
import '../../assistant/domain/assistant_models.dart';
import '../../assistant/domain/assistant_service.dart';
import 'spending_page.dart';

/// Thẻ "Chi tiêu tháng này" ở trang chủ. Chỉ hiện khi dịch vụ hỗ trợ và tháng
/// này đã có ít nhất một lần mua; lỗi mạng thì ẩn lặng lẽ (thẻ phụ, không chặn trang).
class SpendingCard extends StatefulWidget {
  const SpendingCard({
    required this.service,
    required this.merchant,
    super.key,
  });

  final AssistantService service;
  final bool merchant;

  /// Dịch vụ có hỗ trợ chi tiêu không (bản giả lập trong test thì không).
  static bool supported(AssistantService service) =>
      service is SpendingSource &&
      (service as SpendingSource).spendingAvailable;

  @override
  State<SpendingCard> createState() => _SpendingCardState();
}

class _SpendingCardState extends State<SpendingCard> {
  late Future<SpendingSummary> _future;

  SpendingSource get _source => widget.service as SpendingSource;

  @override
  void initState() {
    super.initState();
    _future = _source.getSpending();
    widget.service.dataChanges.addListener(_onDataChanged);
  }

  @override
  void didUpdateWidget(SpendingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service)) {
      oldWidget.service.dataChanges.removeListener(_onDataChanged);
      widget.service.dataChanges.addListener(_onDataChanged);
      _future = _source.getSpending();
    }
  }

  @override
  void dispose() {
    widget.service.dataChanges.removeListener(_onDataChanged);
    super.dispose();
  }

  // Có dữ liệu mới: đọc lại. Đệm ở service nên không tốn mạng nếu chưa có ghi.
  void _onDataChanged() {
    if (!mounted) return;
    setState(() {
      _future = _source.getSpending();
    });
  }

  Future<void> _open() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SpendingPage(
          service: widget.service,
          source: _source,
          merchant: widget.merchant,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _future = _source.getSpending();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SpendingSummary>(
      future: _future,
      initialData: syncValue(_future),
      builder: (context, snapshot) {
        final summary = snapshot.data;
        if (summary == null) {
          // Giữ chỗ khi đang tải lần đầu để trang không bị nhảy; lỗi thì ẩn.
          return snapshot.hasError
              ? const SizedBox.shrink()
              : const SizedBox(height: 88);
        }
        if (summary.isEmpty) return const SizedBox.shrink();
        return _Body(summary: summary, merchant: widget.merchant, onTap: _open);
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.summary,
    required this.merchant,
    required this.onTap,
  });

  final SpendingSummary summary;
  final bool merchant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final delta = spendingDelta(summary);
    final month = int.tryParse(summary.month.substring(5)) ?? 0;
    final title = merchant
        ? tr('Nhập hàng tháng {0}', [month])
        : tr('Chi tiêu tháng {0}', [month]);
    final amount = summary.pricedCount == 0 ? '—' : formatVnd(summary.totalVnd);
    final missing = summary.unpricedCount;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Semantics(
        button: true,
        label:
            '$title: $amount${missing > 0 ? ', ${tr('{0} lần mua chưa có giá', [missing])}' : ''}',
        excludeSemantics: true,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(HomeMindTheme.radiusLg),
          child: InkWell(
            key: const Key('spending_card'),
            borderRadius: BorderRadius.circular(HomeMindTheme.radiusLg),
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(HomeMindTheme.radiusLg),
                border: Border.all(color: HomeMindTheme.border),
                boxShadow: HomeMindTheme.softShadow,
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: HomeMindTheme.primaryLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: const Text('💰', style: TextStyle(fontSize: 22)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 13,
                                color: HomeMindTheme.textSub,
                              ),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                amount,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: HomeMindTheme.textMain,
                                ),
                              ),
                            ),
                            if (delta != null)
                              Text(
                                delta.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: delta.up
                                      ? const Color(0xFF92400E)
                                      : HomeMindTheme.primaryStrong,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: HomeMindTheme.textMuted,
                      ),
                    ],
                  ),
                  if (missing > 0) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: HomeMindTheme.soonBg,
                        borderRadius: BorderRadius.circular(
                          HomeMindTheme.radiusMd,
                        ),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: Color(0xFF92400E),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              tr(
                                '{0} lần mua chưa có giá, tổng thực tế có thể cao hơn',
                                [missing],
                              ),
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.3,
                                color: Color(0xFF78350F),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            tr('Nhập giá'),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: HomeMindTheme.primaryStrong,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
