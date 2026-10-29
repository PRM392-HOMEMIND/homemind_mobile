import 'package:flutter/material.dart';

import '../../../core/config/plan_billing_visibility.dart';

import '../../../app/homemind_theme.dart';
import '../../../core/config/env_config.dart';
import '../../../core/l10n/app_text.dart';
import '../../assistant/domain/assistant_models.dart';
import '../../assistant/domain/assistant_service.dart';
import 'paywall_sheet.dart';
import 'plan_catalog.dart';

const Color _amberText = Color(0xFF92400E);

/// Thẻ gói dịch vụ cuối trang chủ: nhắc nâng cấp khi gói miễn phí sắp đầy,
/// yên lặng khi đã dùng gói trả phí. Không giả lập thanh toán.
class PlanCard extends StatelessWidget {
  const PlanCard({
    required this.home,
    required this.service,
    required this.isMerchant,
    super.key,
  });

  final HomeSummary home;
  final AssistantService service;
  final bool isMerchant;

  void _openPaywall(BuildContext context) =>
      PaywallSheet.show(context, service: service, source: 'home_card');

  @override
  Widget build(BuildContext context) {
    if (!PlanBillingVisibility.of(context)) return const SizedBox.shrink();
    return Container(
      key: const Key('plan_card'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
        border: Border.all(color: HomeMindTheme.border),
        boxShadow: HomeMindTheme.softShadow,
      ),
      child: home.plan == 'free' ? _free(context) : _paid(context),
    );
  }

  // ── Gói trả phí: thẻ yên lặng, không bán thêm ──────────────────────────
  Widget _paid(BuildContext context) {
    final info = PlanInfo.of(home.plan);
    final unit = isMerchant ? tr('mặt hàng') : tr('sản phẩm');
    final title = home.plan == 'micro_pos'
        ? tr('Gói {0} · {1}/{2} mặt hàng', [
            info.name,
            home.productCountTowardLimit,
            home.freePlanLimit,
          ])
        : tr('Gói {0} · {1} {2} — không giới hạn', [
            info.name,
            home.productCountTowardLimit,
            unit,
          ]);
    final canUpgradeFamily =
        PlanBillingVisibility.of(context) &&
        EnvConfig.externalBillingAllowed &&
        home.plan == 'personal' &&
        !home.requestedPlans.contains('family');
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: const BoxDecoration(
            color: HomeMindTheme.primaryLight,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.verified_rounded,
            size: 18,
            color: HomeMindTheme.primaryDark,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            key: const Key('plan_card_title'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: HomeMindTheme.textMain,
            ),
          ),
        ),
        if (canUpgradeFamily)
          TextButton(
            key: const Key('plan_card_family'),
            onPressed: () => _openPaywall(context),
            style: TextButton.styleFrom(
              foregroundColor: HomeMindTheme.primaryDark,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFamily: HomeMindTheme.fontFamily,
              ),
            ),
            child: Text(tr('Nâng lên Gia đình')),
          ),
      ],
    );
  }

  // ── Gói miễn phí: phễu chuyển đổi ──────────────────────────────────────
  Widget _free(BuildContext context) {
    final usage = PlanUsage.of(home);
    final level = usage.level;
    final (Color accent, Color textColor) = switch (level) {
      PlanLevel.ok => (HomeMindTheme.primary, HomeMindTheme.textMain),
      PlanLevel.nearFull => (HomeMindTheme.warning, _amberText),
      PlanLevel.full => (HomeMindTheme.danger, HomeMindTheme.danger),
    };
    final unit = isMerchant ? tr('mặt hàng') : tr('sản phẩm');
    final requested = home.requestedPlans;
    final usageLine = tr('Gói Miễn phí · {0}/{1} {2}', [
      usage.used,
      usage.limit,
      unit,
    ]);

    final String title;
    final String line;
    switch (level) {
      case PlanLevel.ok:
        title = usageLine;
        line = !EnvConfig.externalBillingAllowed
            ? tr('Còn {0} chỗ trống trong gói hiện tại.', [usage.remaining])
            : isMerchant
            ? tr(
                'Còn {0} chỗ trống. Nâng cấp Micro-POS (149.000đ / 30 ngày) để quản lý kho và được nhắc nhập hàng.',
                [usage.remaining],
              )
            : tr(
                'Còn {0} chỗ trống. Nâng cấp gói Cá nhân hoặc Gia đình để lưu không giới hạn sản phẩm.',
                [usage.remaining],
              );
      case PlanLevel.nearFull:
        title = tr('Sắp đầy! Chỉ còn {0} chỗ trống', [usage.remaining]);
        line = usageLine;
      case PlanLevel.full:
        title = isMerchant
            ? tr('Đã đầy {0}/{0} mặt hàng — không thể thêm mặt hàng mới', [
                usage.limit,
              ])
            : tr('Đã đầy {0}/{0} sản phẩm — không thể thêm sản phẩm mới', [
                usage.limit,
              ]);
        line = usageLine;
    }

    final ctaLabel = !EnvConfig.externalBillingAllowed
        ? tr('Xem gói hiện tại')
        : isMerchant
        ? tr('Nâng cấp từ 149.000đ / 30 ngày')
        : tr('Nâng cấp từ 29.000đ / 30 ngày');
    const ctaText = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w800,
      fontFamily: HomeMindTheme.fontFamily,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          key: const Key('plan_card_title'),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            key: const Key('plan_card_progress'),
            value: usage.ratio.clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor: accent.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(accent),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          line,
          style: const TextStyle(
            fontSize: 12,
            height: 1.35,
            color: HomeMindTheme.textSub,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          tr(
            'Trung bình mỗi hộ gia đình lãng phí khoảng 123.000đ/tháng vì đồ hết hạn',
          ),
          style: const TextStyle(fontSize: 11, color: HomeMindTheme.textMuted),
        ),
        if (PlanBillingVisibility.of(context)) ...[
          const SizedBox(height: 10),
          if (requested.isNotEmpty && EnvConfig.externalBillingAllowed)
            _requested(context, requested.last)
          else if (level == PlanLevel.ok)
            OutlinedButton(
              key: const Key('plan_card_cta'),
              onPressed: () => _openPaywall(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: HomeMindTheme.primaryDark,
                side: const BorderSide(color: HomeMindTheme.primary),
                shape: const StadiumBorder(),
                minimumSize: const Size(0, 38),
                textStyle: ctaText,
              ),
              child: Text(ctaLabel),
            )
          else
            ElevatedButton(
              key: const Key('plan_card_cta'),
              onPressed: () => _openPaywall(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: level == PlanLevel.full
                    ? HomeMindTheme.danger
                    : HomeMindTheme.premium,
                foregroundColor: level == PlanLevel.full
                    ? Colors.white
                    : HomeMindTheme.textMain,
                elevation: 0,
                shape: const StadiumBorder(),
                minimumSize: const Size(0, 38),
                textStyle: ctaText,
              ),
              child: Text(ctaLabel),
            ),
        ],
      ],
    );
  }

  Widget _requested(BuildContext context, String planKey) {
    final name = PlanInfo.of(planKey).name;
    return Container(
      key: const Key('plan_card_requested'),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: HomeMindTheme.primaryTint,
        borderRadius: BorderRadius.circular(HomeMindTheme.radiusSm + 2),
        border: Border.all(color: HomeMindTheme.normalBorder),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: HomeMindTheme.primaryDark,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr(
                'Đã ghi nhận yêu cầu nâng cấp gói {0}. Chúng tôi sẽ liên hệ bạn sớm.',
                [name],
              ),
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: HomeMindTheme.textMain,
              ),
            ),
          ),
          TextButton(
            key: const Key('plan_card_change'),
            onPressed: () => _openPaywall(context),
            style: TextButton.styleFrom(
              foregroundColor: HomeMindTheme.primaryDark,
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFamily: HomeMindTheme.fontFamily,
              ),
            ),
            child: Text(tr('Đổi gói')),
          ),
        ],
      ),
    );
  }
}

/// Dải nhắc gọn (hổ phách) dùng ở Kho đồ và màn xác nhận.
class PlanNudgeBanner extends StatelessWidget {
  const PlanNudgeBanner({
    required this.text,
    required this.action,
    required this.onTap,
    super.key,
  });

  final String text;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: HomeMindTheme.soonBg,
        borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
        border: Border.all(
          color: HomeMindTheme.warning.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: _amberText,
              ),
            ),
          ),
          if (PlanBillingVisibility.of(context))
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                foregroundColor: _amberText,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  fontFamily: HomeMindTheme.fontFamily,
                ),
              ),
              child: Text(action),
            ),
        ],
      ),
    );
  }
}
