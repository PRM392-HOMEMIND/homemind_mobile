import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/config/env_config.dart';
import '../../core/config/plan_billing_visibility.dart';
import 'billing_distribution.dart';

import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/homemind_theme.dart';
import '../../core/l10n/app_text.dart';

String billingMoney(Object? value) {
  if (value is! num) return '—';
  final digits = value.toInt().toString();
  final grouped = digits.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]}${AppText.isEnglish ? ',' : '.'}',
  );
  return AppText.isEnglish ? '$grouped VND' : '$grouped\u0111';
}

String billingPlanName(Object? value) => switch (value) {
  'free' => tr('Miễn phí'),
  'personal' => tr('Cá nhân'),
  'family' => tr('Gia đình'),
  'micro_pos' => 'Micro-POS',
  _ => tr('Đang tải'),
};

/// Decorative plan identity only; purchase rules remain with BillingPage.
class PlanVisualIdentity extends StatelessWidget {
  const PlanVisualIdentity({required this.plan, this.muted = false, super.key});

  final Object? plan;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final (icon, surface) = switch (plan) {
      'free' => (Icons.home_rounded, const Color(0xFFE5F0EA)),
      'personal' => (Icons.person_rounded, HomeMindTheme.primaryLight),
      'family' => (Icons.family_restroom_rounded, const Color(0xFFD9EFE5)),
      'micro_pos' => (Icons.storefront_rounded, HomeMindTheme.soonBg),
      _ => (Icons.home_rounded, HomeMindTheme.background),
    };
    return ExcludeSemantics(
      child: Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: muted ? HomeMindTheme.border : surface,
          borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
        ),
        child: Icon(
          icon,
          size: 26,
          color: muted ? HomeMindTheme.textSub : HomeMindTheme.primaryStrong,
        ),
      ),
    );
  }
}

String billingDate(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return '—';
  String pad(int v) => v.toString().padLeft(2, '0');
  return '${pad(date.day)}/${pad(date.month)}/${date.year} ${pad(date.hour)}:${pad(date.minute)}:${pad(date.second)}';
}

ButtonStyle get billingPrimaryButton => FilledButton.styleFrom(
  backgroundColor: HomeMindTheme.primaryStrong,
  foregroundColor: Colors.white,
  minimumSize: const Size.fromHeight(48),
  padding: const EdgeInsets.all(16),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
);

class BillingSurface extends StatelessWidget {
  const BillingSurface({
    required this.child,
    this.mint = false,
    this.muted = false,
    this.padding = 20,
    super.key,
  });
  final Widget child;
  final bool mint;
  final bool muted;
  final double padding;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: EdgeInsets.all(padding),
    decoration: BoxDecoration(
      color: mint
          ? HomeMindTheme.primaryTint
          : muted
          ? HomeMindTheme.background
          : Colors.white,
      borderRadius: BorderRadius.circular(HomeMindTheme.radiusLg),
      border: Border.all(
        color: mint
            ? HomeMindTheme.primary.withValues(alpha: .3)
            : HomeMindTheme.border,
      ),
      boxShadow: HomeMindTheme.softShadow,
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class BillingSectionTitle extends StatelessWidget {
  const BillingSectionTitle(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 12),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: HomeMindTheme.textMain,
      ),
    ),
  );
}

class BillingBadge extends StatelessWidget {
  const BillingBadge(
    this.text, {
    this.icon,
    this.warning = false,
    this.muted = false,
    this.color,
    super.key,
  });
  final String text;
  final IconData? icon;
  final bool warning;
  final bool muted;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color:
          color?.withValues(alpha: .09) ??
          (muted
              ? HomeMindTheme.border
              : warning
              ? HomeMindTheme.soonBg
              : HomeMindTheme.primaryLight),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: color ?? HomeMindTheme.textMain),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color ?? HomeMindTheme.textMain,
            ),
          ),
        ),
      ],
    ),
  );
}

class BillingCurrentPlanCard extends StatelessWidget {
  const BillingCurrentPlanCard({
    required this.plan,
    this.subscription,
    this.productLimit,
    super.key,
  });
  final Object? plan;
  final Map? subscription;

  /// Hạn mức sản phẩm của gói đang dùng (null = không giới hạn / chưa rõ).
  final int? productLimit;
  @override
  Widget build(BuildContext context) => BillingSurface(
    mint: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PlanVisualIdentity(plan: plan),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('GÓI HIỆN TẠI'),
                    style: const TextStyle(
                      fontSize: 12,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w800,
                      color: HomeMindTheme.primaryStrong,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    billingPlanName(plan),
                    key: const Key('billing_current'),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: HomeMindTheme.textMain,
                    ),
                  ),
                  const SizedBox(height: 8),
                  BillingBadge(
                    tr('Đang sử dụng'),
                    icon: Icons.check_circle_outline_rounded,
                  ),
                  if (plan == 'free') ...[
                    const SizedBox(height: 6),
                    BillingBadge(
                      tr('Vĩnh viễn'),
                      icon: Icons.all_inclusive_rounded,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (plan == 'free' && productLimit != null) ...[
          const SizedBox(height: 12),
          Text(
            tr('Tối đa {0} sản phẩm', [productLimit]),
            key: const Key('billing_free_product_limit'),
            style: const TextStyle(fontSize: 13, color: HomeMindTheme.textSub),
          ),
        ],
        if (plan != 'free' && subscription != null) ...[
          const SizedBox(height: 12),
          Text(
            tr('Hiệu lực: {0} → {1}', [
              billingDate(subscription!['startsAt']),
              billingDate(subscription!['expiresAt']),
            ]),
            style: const TextStyle(fontSize: 13, color: HomeMindTheme.textSub),
          ),
        ],
      ],
    ),
  );
}

/// Displays authoritative counters. It never reserves, renews or grants quota.
class BillingUsageCard extends StatelessWidget {
  const BillingUsageCard({
    required this.used,
    required this.total,
    required this.remaining,
    required this.expiresAt,
    this.plan,
    super.key,
  });
  final int used, total, remaining;
  final DateTime expiresAt;
  final String? plan;
  @override
  Widget build(BuildContext context) => BillingSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (PlanBillingVisibility.of(context))
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PlanVisualIdentity(plan: plan),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      billingPlanName(plan),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (plan == 'free')
                      BillingBadge(
                        tr('Vĩnh viễn'),
                        icon: Icons.all_inclusive_rounded,
                      ),
                  ],
                ),
              ),
            ],
          ),
        const SizedBox(height: 8),
        Text(
          tr(
            PlanBillingVisibility.of(context)
                ? 'Lượt trợ lý của gói đang dùng'
                : 'Lượt trợ lý trong kỳ',
          ),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text(
          '$used/$total',
          key: const Key('voice_quota_used_total'),
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: tr('Đã dùng {0} trên {1} lượt', [used, total]),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: used / total,
              minHeight: 10,
              color: remaining == 0
                  ? HomeMindTheme.warning
                  : HomeMindTheme.primaryStrong,
              backgroundColor: HomeMindTheme.primaryLight,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          tr('Còn {0} lượt trong kỳ', [remaining]),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: HomeMindTheme.primaryStrong,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          tr('Lượt dùng làm mới lúc: {0}', [
            billingDate(expiresAt.toIso8601String()),
          ]),
          style: const TextStyle(fontSize: 12, color: HomeMindTheme.textSub),
        ),
        if (remaining == 0) ...[
          const SizedBox(height: 12),
          BillingBadge(
            tr(
              PlanBillingVisibility.of(context)
                  ? 'Gói đang dùng đã hết lượt trợ lý trong kỳ này.'
                  : 'Đã hết lượt trợ lý trong kỳ này.',
            ),
            icon: Icons.hourglass_bottom_rounded,
            warning: true,
          ),
        ],
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(
            tr('Cách tính lượt'),
            style: const TextStyle(fontSize: 12),
          ),
          children: [
            Text(
              tr(
                'Lượt dùng chung trong không gian. Kết quả trợ lý hợp lệ, kể cả câu gõ, tính một lượt. Xác nhận không tính thêm; hủy không hoàn lượt đã dùng.',
              ),
              style: const TextStyle(
                fontSize: 12,
                color: HomeMindTheme.textSub,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class BillingPlanCard extends StatefulWidget {
  const BillingPlanCard({
    required this.plan,
    required this.current,
    required this.canPurchase,
    required this.onPurchase,
    super.key,
  });
  final Map plan;
  final bool current, canPurchase;
  final VoidCallback? onPurchase;
  @override
  State<BillingPlanCard> createState() => _BillingPlanCardState();
}

class _BillingPlanCardState extends State<BillingPlanCard> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final p = widget.plan;
    final locked = !widget.current && !widget.canPurchase;
    return BillingSurface(
      mint: widget.current,
      muted: locked,
      padding: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            label: tr('Chi tiết gói {0}', [billingPlanName(p['plan'])]),
            child: InkWell(
              key: Key('billing_plan_${p['plan']}'),
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PlanVisualIdentity(plan: p['plan'], muted: locked),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            billingPlanName(p['plan']),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${billingMoney(p['amount'])} · ${tr('30 ngày')}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: HomeMindTheme.textSub,
                            ),
                          ),
                          if (p['voiceLimit'] != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              tr('{0} lượt AI Voice', [p['voiceLimit']]),
                              style: const TextStyle(
                                fontSize: 13,
                                color: HomeMindTheme.textSub,
                              ),
                            ),
                          ],
                          if (widget.current || locked) ...[
                            const SizedBox(height: 8),
                            BillingBadge(
                              widget.current
                                  ? tr('Đang sử dụng')
                                  : tr('Chưa khả dụng'),
                              muted: locked,
                              icon: widget.current
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.lock_outline_rounded,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: HomeMindTheme.textSub,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  for (final feature in [
                    if (p['voiceLimit'] != null)
                      tr('{0} lượt AI Voice', [p['voiceLimit']]),
                    p['productLimit'] == null
                        ? tr(
                            'Không giới hạn số sản phẩm; các chức năng hiện có.',
                          )
                        : tr('Tối đa {0} sản phẩm; các chức năng hiện có.', [
                            p['productLimit'],
                          ]),
                    tr('Thời hạn 30 ngày. Không tự động gia hạn.'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.check_rounded,
                            size: 20,
                            color: HomeMindTheme.primaryStrong,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              feature,
                              style: const TextStyle(
                                fontSize: 13,
                                color: HomeMindTheme.textSub,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (!widget.current && EnvConfig.externalBillingAllowed)
                    FilledButton(
                      key: Key('billing_buy_${p['plan']}'),
                      style: billingPrimaryButton,
                      onPressed: widget.canPurchase ? widget.onPurchase : null,
                      child: Text(
                        widget.canPurchase
                            ? tr('Chọn gói {0}', [billingPlanName(p['plan'])])
                            : tr('Chưa khả dụng'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class ComingSoonCard extends StatelessWidget {
  const ComingSoonCard({
    required this.title,
    required this.description,
    required this.icon,
    this.soon = false,
    super.key,
  });
  final String title, description;
  final IconData icon;
  final bool soon;
  @override
  Widget build(BuildContext context) => Semantics(
    enabled: false,
    label: '$title. ${tr('Chưa thể sử dụng')}',
    child: Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: HomeMindTheme.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: HomeMindTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 22, color: HomeMindTheme.textSub),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: HomeMindTheme.textSub,
                      ),
                    ),
                    const SizedBox(height: 8),
                    BillingBadge(
                      soon ? tr('Sắp ra mắt') : tr('Đang phát triển'),
                      icon: Icons.construction_rounded,
                      warning: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(fontSize: 13, color: HomeMindTheme.textSub),
          ),
        ],
      ),
    ),
  );
}

class BillingNotice extends StatelessWidget {
  const BillingNotice(this.text, {this.error = false, super.key});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) => BillingSurface(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          error ? Icons.wifi_off_rounded : Icons.info_outline_rounded,
          color: error ? HomeMindTheme.danger : HomeMindTheme.primaryStrong,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: HomeMindTheme.textSub),
          ),
        ),
      ],
    ),
  );
}

class BillingPaymentCard extends StatelessWidget {
  const BillingPaymentCard({
    required this.payment,
    required this.stateText,
    required this.pending,
    required this.checkoutEnabled,
    required this.busy,
    required this.onCheck,
    required this.onOpen,
    required this.onCancel,
    this.clock,
    super.key,
  });
  final Map payment;
  final String stateText;
  final bool pending, checkoutEnabled, busy;
  final VoidCallback onCheck, onOpen, onCancel;
  final CheckoutClock? clock;
  @override
  Widget build(BuildContext context) {
    if (!EnvConfig.externalBillingAllowed) {
      return BillingHistoryCard(
        payment: consumptionPayment(payment),
        stateText: stateText,
      );
    }
    return CheckoutWindow(
      payment: payment,
      clock: clock,
      builder: (context, expired, countdown) {
        final pending = this.pending && !expired;
        final qr = payment['qr'] as Map?;
        final price = payment['price'] as Map?;
        return BillingSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: BillingStatusBadge(payment: payment),
              ),
              const SizedBox(height: 12),
              Text(
                billingPlanName(price?['plan']),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                billingMoney(price?['amount'] ?? qr?['amount']),
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                stateText,
                key: const Key('billing_payment_state'),
                style: const TextStyle(
                  fontSize: 13,
                  color: HomeMindTheme.textSub,
                ),
              ),
              if (payment['origin'] == 'SIMULATED_TEST')
                const Text(
                  'SIMULATED_TEST',
                  key: Key('billing_simulated_test'),
                ),
              if (this.pending && countdown != null) ...[
                const SizedBox(height: 12),
                Text(
                  expired
                      ? tr(
                          'Thời gian thanh toán đã kết thúc. Bấm kiểm tra trạng thái.',
                        )
                      : tr('Còn {0} để thanh toán', [countdown]),
                  key: const Key('billing_countdown'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
              if (pending && checkoutEnabled && qr != null) ...[
                const SizedBox(height: 20),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 256),
                    child: LayoutBuilder(
                      builder: (context, constraints) => Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: HomeMindTheme.border),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: QrImageView(
                          data: qr['payload'] as String,
                          size: constraints.maxWidth - 24,
                          padding: const EdgeInsets.all(12),
                          backgroundColor: Colors.white,
                          key: const Key('billing_official_qr'),
                          semanticsLabel: tr('Mã QR thanh toán'),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  tr('Quét bằng ứng dụng ngân hàng'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  tr('Chuyển đúng số tiền và nội dung hiển thị bên dưới.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: HomeMindTheme.textSub,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                key: const Key('billing_transfer_details'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  tr('Thông tin chuyển khoản'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                children: [
                  if (qr != null) ...[
                    _detail(tr('Ngân hàng (BIN): {0}', [qr['bin']])),
                    _detail(
                      tr('Chủ tài khoản: {0}', [qr['accountName'] ?? '—']),
                    ),
                    _detail(
                      tr('Số tài khoản: {0}', [qr['accountNumber'] ?? '—']),
                    ),
                    _detail(
                      tr('Nội dung chuyển khoản: {0}', [
                        qr['description'] ?? '—',
                      ]),
                    ),
                    _detail(
                      tr('Số tiền: {0}', [
                        billingMoney(qr['amount'] ?? price?['amount']),
                      ]),
                    ),
                    if (pending && checkoutEnabled && !busy) ...[
                      _copy(
                        context,
                        tr('Sao chép số tài khoản'),
                        qr['accountNumber'] as String,
                        tr('Đã sao chép số tài khoản'),
                      ),
                      _copy(
                        context,
                        tr('Sao chép nội dung chuyển khoản'),
                        qr['description'] as String,
                        tr('Đã sao chép nội dung chuyển khoản'),
                      ),
                    ],
                  ],
                  _detail(
                    tr('Mã đơn: {0} · Đã nhận: {1} VND', [
                      payment['orderCode'],
                      payment['amountPaid'],
                    ]),
                  ),
                  if (price?['amount'] is num)
                    _detail(tr('Số tiền đơn: {0} VND', [price!['amount']])),
                  if (payment['createdAt'] is String)
                    Container(
                      key: const Key('billing_created_at'),
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: HomeMindTheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        tr('Tạo lúc: {0}', [billingDate(payment['createdAt'])]),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: HomeMindTheme.textMain,
                        ),
                      ),
                    ),
                  if (payment['paidAt'] is String)
                    _detail(
                      tr('Đã thanh toán lúc: {0}', [
                        billingDate(payment['paidAt']),
                      ]),
                    ),
                  if (payment['expiresAt'] is String)
                    _detail(
                      tr('Đơn chưa thanh toán hết hạn: {0}', [
                        billingDate(payment['expiresAt']),
                      ]),
                    ),
                  ...billingGrantDetails(payment),
                  ...billingCancellationDetails(payment),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  padding: const EdgeInsets.all(16),
                ),
                onPressed: busy ? null : onCheck,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Text(
                  tr(busy ? 'Đang kiểm tra...' : 'Kiểm tra trạng thái'),
                  textAlign: TextAlign.center,
                ),
              ),
              if (pending &&
                  payment['checkoutUrl'] is String &&
                  checkoutEnabled) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: busy ? null : onOpen,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text(
                    tr('Mở lại trang thanh toán'),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              if (pending) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: HomeMindTheme.danger,
                  ),
                  onPressed: busy ? null : onCancel,
                  icon: const Icon(Icons.close_rounded),
                  label: Text(
                    tr('Hủy đơn chưa thanh toán'),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

Widget _detail(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: Align(
    alignment: Alignment.centerLeft,
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, color: HomeMindTheme.textSub),
    ),
  ),
);

Widget _copy(
  BuildContext context,
  String label,
  String value,
  String feedback, {
  ButtonStyle? style,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: OutlinedButton.icon(
    style: style,
    onPressed: () async {
      try {
        await Clipboard.setData(ClipboardData(text: value));
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(feedback)));
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('Chưa sao chép được. Hãy thử lại.'))),
          );
        }
      }
    },
    icon: const Icon(Icons.copy_rounded, size: 18),
    label: Text(label, textAlign: TextAlign.center),
  ),
);

String _shortStatus(Map p) =>
    switch ((p['financialState'], p['fulfillment'], p['status'])) {
      ('PAID', 'REVIEW', _) || (_, _, 'REVIEW') => tr('Đang xác minh'),
      ('PAID', 'GRANTED', _) => tr('Đã thanh toán'),
      (_, _, 'CANCELLED') => tr('Đã hủy'),
      (_, _, 'EXPIRED') => tr('Hết hạn'),
      _ => tr('Chờ thanh toán'),
    };

List<Widget> billingGrantDetails(Map p) {
  final g = p['grant'];
  if (g is! Map || g.isEmpty) return [];
  return [
    _detail(
      tr('Hiệu lực: {0} → {1}', [
        billingDate(g['startsAt']),
        billingDate(g['expiresAt']),
      ]),
    ),
    if (g['supersededAt'] != null)
      _detail(
        tr('Đã thay bằng gói mới. Hạn ban đầu: {0}', [
          billingDate(g['originalExpiresAt']),
        ]),
      ),
  ];
}

class BillingHistoryCard extends StatelessWidget {
  const BillingHistoryCard({
    required this.payment,
    required this.stateText,
    super.key,
  });
  final Map payment;
  final String stateText;
  @override
  Widget build(BuildContext context) {
    final payment = EnvConfig.externalBillingAllowed
        ? this.payment
        : consumptionPayment(this.payment);
    final price = payment['price'] as Map?;
    return BillingSurface(
      padding: 0,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        key: Key('billing_history_${payment['id']}'),
        tilePadding: const EdgeInsets.all(16),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              billingPlanName(price?['plan']),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            if (price?['amount'] != null)
              Text(
                billingMoney(price?['amount']),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                billingDate(payment['createdAt']),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              BillingStatusBadge(payment: payment),
            ],
          ),
        ),
        children: [
          _detail(stateText),
          if (payment['origin'] == 'SIMULATED_TEST') _detail('SIMULATED_TEST'),
          if (payment['orderCode'] != null)
            _detail(tr('Mã đơn: {0}', [payment['orderCode']])),
          if (price?['amount'] is num)
            _detail(tr('Số tiền đơn: {0} VND', [price!['amount']])),
          _detail(tr('Tạo lúc: {0}', [billingDate(payment['createdAt'])])),
          if (payment['paidAt'] is String)
            _detail(
              tr('Đã thanh toán lúc: {0}', [billingDate(payment['paidAt'])]),
            ),
          ...billingGrantDetails(payment),
          ...billingCancellationDetails(payment),
        ],
      ),
    );
  }
}

class BillingStatusBadge extends StatelessWidget {
  const BillingStatusBadge({required this.payment, super.key});
  final Map payment;
  static ({Color color, IconData icon}) visual(Map p) =>
      switch ((p['financialState'], p['fulfillment'], p['status'])) {
        ('PAID', 'GRANTED', _) => (
          color: HomeMindTheme.primaryStrong,
          icon: Icons.check_circle_outline_rounded,
        ),
        (_, _, 'CANCELLED') => (
          color: HomeMindTheme.danger,
          icon: Icons.cancel_outlined,
        ),
        (_, _, 'EXPIRED') => (
          color: HomeMindTheme.textSub,
          icon: Icons.timer_off_outlined,
        ),
        _ => (color: HomeMindTheme.warning, icon: Icons.schedule_rounded),
      };
  @override
  Widget build(BuildContext context) {
    final identity = visual(payment);
    return BillingBadge(
      _shortStatus(payment),
      icon: identity.icon,
      color: identity.color,
    );
  }
}

List<Widget> billingCancellationDetails(Map p) => [
  if (p['cancelledAt'] != null)
    _detail(tr('Đã hủy lúc: {0}', [billingDate(p['cancelledAt'])])),
  if (p['status'] == 'CANCELLED' && p['cancelledAt'] == null)
    _detail(tr('Thời điểm hủy chưa có dữ liệu')),
  if (p['cancellationTimeSource'] == 'SERVER_CONFIRMED')
    _detail(tr('Thời điểm máy chủ xác nhận hủy')),
];

class BillingSupportCard extends StatelessWidget {
  const BillingSupportCard({super.key});
  static const email = 'homemind.support@gmail.com';
  @override
  Widget build(BuildContext context) => Container(
    key: const Key('billing_support_surface'),
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: HomeMindTheme.mintSurface,
      border: Border.all(color: HomeMindTheme.mintBorder),
      borderRadius: BorderRadius.circular(HomeMindTheme.radiusLg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: HomeMindTheme.card,
                borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
              ),
              child: const ExcludeSemantics(
                child: Icon(
                  Icons.support_agent_rounded,
                  color: HomeMindTheme.primaryStrong,
                  size: 26,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tr('Hỗ trợ HomeMind'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: HomeMindTheme.primaryStrong,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          tr('Cần hỗ trợ về tài khoản hoặc thanh toán?'),
          style: const TextStyle(
            fontSize: 14,
            height: 1.4,
            color: HomeMindTheme.textSub,
          ),
        ),
        const SizedBox(height: 8),
        const SelectableText(
          email,
          style: TextStyle(fontSize: 14, color: HomeMindTheme.textMain),
        ),
        const SizedBox(height: 14),
        _copy(
          context,
          tr('Sao chép email hỗ trợ'),
          email,
          tr('Đã sao chép email hỗ trợ'),
          style: OutlinedButton.styleFrom(
            foregroundColor: HomeMindTheme.primaryStrong,
            backgroundColor: HomeMindTheme.card,
            minimumSize: const Size(48, 48),
            side: const BorderSide(color: HomeMindTheme.mintBorder),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    ),
  );
}

/// Receipt-time anchor shared by the page and its lazily mounted payment card.
/// Uses only the server interval and monotonic elapsed time, never wall time.
class CheckoutClock {
  CheckoutClock.fromPayment(
    Map payment, {
    Stopwatch Function() stopwatchFactory = Stopwatch.new,
  }) : _id = payment['id'],
       _deadline = payment['expiresAt'],
       _server = payment['serverNow'],
       _elapsed = stopwatchFactory() {
    final deadline = DateTime.tryParse(_deadline?.toString() ?? '');
    final server = DateTime.tryParse(_server?.toString() ?? '');
    _initial = deadline != null && server != null
        ? deadline.difference(server)
        : null;
    _elapsed.start();
  }
  final Object? _id, _deadline, _server;
  final Stopwatch _elapsed;
  Duration? _initial;
  bool matches(Map payment) =>
      _id == payment['id'] &&
      _deadline == payment['expiresAt'] &&
      _server == payment['serverNow'];
  int? get remainingSeconds => _initial == null
      ? null
      : ((_initial!.inMilliseconds - _elapsed.elapsedMilliseconds + 999) ~/
                1000)
            .clamp(0, 86400);
  void stop() => _elapsed.stop();
}

/// A local monotonic countdown only. This widget makes ZERO network requests.
class CheckoutWindow extends StatefulWidget {
  const CheckoutWindow({
    required this.payment,
    required this.builder,
    this.stopwatchFactory = Stopwatch.new,
    this.clock,
    super.key,
  });
  final Map payment;
  final Widget Function(BuildContext, bool, String?) builder;
  final Stopwatch Function() stopwatchFactory;
  final CheckoutClock? clock;
  @override
  State<CheckoutWindow> createState() => _CheckoutWindowState();
}

class _CheckoutWindowState extends State<CheckoutWindow> {
  late CheckoutClock _clock;
  bool _ownsClock = false;
  Timer? _tick;
  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    _tick?.cancel();
    _ownsClock = widget.clock == null;
    _clock =
        widget.clock ??
        CheckoutClock.fromPayment(
          widget.payment,
          stopwatchFactory: widget.stopwatchFactory,
        );
    if ((_clock.remainingSeconds ?? 0) > 0) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        if ((_clock.remainingSeconds ?? 0) <= 0) _tick?.cancel();
      });
    }
  }

  @override
  void didUpdateWidget(covariant CheckoutWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.clock, widget.clock) ||
        !_clock.matches(widget.payment)) {
      if (_ownsClock) _clock.stop();
      _bind();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    if (_ownsClock) _clock.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _clock.remainingSeconds;
    final n = remaining ?? 0;
    final text = remaining == null
        ? null
        : '${(n ~/ 60).toString().padLeft(2, '0')}:${(n % 60).toString().padLeft(2, '0')}';
    return widget.builder(context, remaining == null || remaining <= 0, text);
  }
}

class BillingEmptyHistory extends StatelessWidget {
  const BillingEmptyHistory({super.key});
  @override
  Widget build(BuildContext context) => BillingSurface(
    child: Column(
      children: [
        const Icon(
          Icons.receipt_long_outlined,
          size: 40,
          color: HomeMindTheme.textSub,
        ),
        const SizedBox(height: 12),
        Text(
          tr('Chưa có giao dịch'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          tr('Các giao dịch mua gói của bạn sẽ xuất hiện tại đây.'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: HomeMindTheme.textSub),
        ),
      ],
    ),
  );
}
