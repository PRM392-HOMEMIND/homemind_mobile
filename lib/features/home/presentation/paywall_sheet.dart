import 'package:flutter/material.dart';

import '../../../core/config/plan_billing_visibility.dart';

import '../../../core/config/env_config.dart';

import '../../../app/homemind_theme.dart';
import '../../../core/l10n/app_text.dart';
import '../../assistant/data/cached_assistant_service.dart';
import '../../assistant/domain/assistant_models.dart';
import '../../assistant/domain/assistant_service.dart';
import 'plan_catalog.dart';
import 'profile_page.dart';
import '../../billing/billing_page.dart';
import '../../billing/billing_service.dart';
import '../../voice/presentation/voice_quota_panel.dart';

/// Bảng chọn gói. Chưa có cổng thanh toán: nút chỉ ghi nhận yêu cầu nâng cấp
/// lên server và nói thật là đội ngũ sẽ liên hệ.
class PaywallSheet extends StatefulWidget {
  const PaywallSheet({
    required this.service,
    required this.source,
    this.controller,
    super.key,
  });

  final AssistantService service;

  /// home_card | limit_reached | inventory_banner | paywall
  final String source;

  static Future<void> show(
    BuildContext context, {
    required AssistantService service,
    required String source,
    Future<Map<String, Object?>> Function()? initialPayment,
  }) {
    if (!PlanBillingVisibility.of(context)) return Future<void>.value();
    final sourceService = service;
    final billingSource = sourceService is BillingSource
        ? sourceService as BillingSource
        : null;
    if (billingSource?.billing != null) {
      return Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => BillingPage(
            gateway: billingSource!.billing!,
            initialPayment: initialPayment,
            refreshEntitlements: billingSource.refreshBillingEntitlements,
            voiceUsage: VoiceQuotaPanel(
              service: service,
              billingPresentation: true,
            ),
          ),
        ),
      );
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.86,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, controller) => PaywallSheet(
          service: service,
          source: source,
          controller: controller,
        ),
      ),
    );
  }

  final ScrollController? controller;

  @override
  State<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<PaywallSheet> {
  HomeSummary? _home;
  String? _email;
  String _selected = 'personal';
  bool _busy = false;
  bool _done = false;
  String? _error;

  bool get _merchant => widget.service.currentRole == AccountRole.merchant;
  String get _currentPlan => _home?.plan ?? 'free';

  @override
  void initState() {
    super.initState();
    _selected = _initialSelection(null);
  }

  bool _started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && PlanBillingVisibility.of(context)) {
      _started = true;
      _readHome();
      _readEmail();
    }
  }

  void _readHome() {
    try {
      final future = widget.service.getHomeSummary();
      final now = syncValue(future);
      if (now != null) {
        _home = now;
        _selected = _initialSelection(now);
        return;
      }
      future.then((value) {
        if (!mounted) return;
        setState(() {
          _home = value;
          _selected = _initialSelection(value);
        });
      }, onError: (Object _) {});
    } catch (_) {}
  }

  void _readEmail() {
    try {
      final future = widget.service.getMe();
      final now = syncValue(future);
      if (now != null) {
        _email = now.email;
        return;
      }
      future.then((me) {
        if (mounted) setState(() => _email = me.email);
      }, onError: (Object _) {});
    } catch (_) {}
  }

  /// Gói gợi ý được chọn sẵn; nếu đang dùng gói đó thì chọn gói kế tiếp.
  String _initialSelection(HomeSummary? home) {
    final current = home?.plan ?? 'free';
    final options = PlanInfo.upgradeableFor(_merchant);
    final recommended = PlanInfo.recommendedFor(_merchant);
    if (recommended != current) return recommended;
    return options.firstWhere((p) => p != current, orElse: () => recommended);
  }

  bool _selectable(String key) => key != 'free' && key != _currentPlan;

  Future<void> _submit() async {
    if (!EnvConfig.externalBillingAllowed) return;
    if (_busy || !_selectable(_selected)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.requestUpgrade(
        plan: _selected,
        source: widget.source,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _done = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = tr(
          'Chưa gửi được yêu cầu. Bạn kiểm tra mạng rồi thử lại nhé.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PlanBillingVisibility.of(context)) {
      return PlanBillingVisibility.fallback(
        context,
        (_) => ProfilePage(service: widget.service),
      );
    }
    if (!EnvConfig.externalBillingAllowed) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            tr(
              'Thanh toán gói hiện chưa được hỗ trợ trong phiên bản này. Bạn vẫn có thể xem gói hiện tại và lịch sử thanh toán.',
            ),
          ),
        ),
      );
    }
    return Container(
      key: const Key('paywall_sheet'),
      decoration: const BoxDecoration(
        color: HomeMindTheme.background,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(HomeMindTheme.radiusXl),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: HomeMindTheme.border,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Expanded(child: _done ? _success(context) : _chooser(context)),
        ],
      ),
    );
  }

  // ── Trạng thái thành công (thật thà: chưa thanh toán) ───────────────────
  Widget _success(BuildContext context) {
    final email = (_email == null || _email!.isEmpty)
        ? tr('tài khoản của bạn')
        : _email!;
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 28),
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: HomeMindTheme.primaryLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.mark_email_read_rounded,
              size: 30,
              color: HomeMindTheme.primaryDark,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          tr('Đã ghi nhận! Chúng tôi sẽ liên hệ bạn qua {0} để hoàn tất.', [
            email,
          ]),
          key: const Key('paywall_success'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            height: 1.4,
            fontWeight: FontWeight.w700,
            color: HomeMindTheme.textMain,
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          key: const Key('paywall_close'),
          onPressed: () => Navigator.of(context).maybePop(),
          style: _primaryStyle(),
          child: Text(tr('Đóng')),
        ),
      ],
    );
  }

  ScrollController? get _scroll => widget.controller;

  ButtonStyle _primaryStyle() => ElevatedButton.styleFrom(
    backgroundColor: HomeMindTheme.primary,
    foregroundColor: Colors.white,
    elevation: 0,
    shape: const StadiumBorder(),
    minimumSize: const Size.fromHeight(46),
    textStyle: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w800,
      fontFamily: HomeMindTheme.fontFamily,
    ),
  );

  Widget _chooser(BuildContext context) {
    final keys = ['free', ...PlanInfo.upgradeableFor(_merchant)];
    final limit = _home?.freePlanLimit ?? 30;
    final canSubmit = _selectable(_selected);
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: HomeMindTheme.premium.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(
                        HomeMindTheme.radiusMd,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Text('👑', style: TextStyle(fontSize: 22)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('Chọn gói phù hợp với bạn'),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: HomeMindTheme.textMain,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tr(
                            'Trung bình mỗi hộ gia đình lãng phí khoảng 123.000đ/tháng vì đồ hết hạn',
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: HomeMindTheme.textSub,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (final key in keys) ...[
                _planTile(key, limit),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null)
                Container(
                  key: const Key('paywall_error'),
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: HomeMindTheme.urgentBg,
                    borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
                    border: Border.all(color: HomeMindTheme.urgentBorder),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: HomeMindTheme.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (canSubmit)
                ElevatedButton(
                  key: const Key('paywall_submit'),
                  onPressed: _busy ? null : _submit,
                  style: _primaryStyle(),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          tr('Đăng ký gói {0}', [PlanInfo.of(_selected).name]),
                        ),
                ),
              const SizedBox(height: 8),
              Text(
                tr(
                  'Thanh toán sắp ra mắt — hiện chúng tôi hỗ trợ đăng ký trực tiếp.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: HomeMindTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<String> _benefits(String key, int limit) => switch (key) {
    'personal' => [tr('Không giới hạn sản phẩm')],
    'family' => [tr('Không giới hạn sản phẩm')],
    'micro_pos' => [tr('Tối đa 500 sản phẩm'), tr('Quản lý kho')],
    _ => [
      _merchant ? tr('{0} mặt hàng', [limit]) : tr('{0} sản phẩm', [limit]),
      tr('{0} lượt trợ lý AI / 30 ngày', [PlanInfo.freeAssistantQuota]),
    ],
  };

  Widget _planTile(String key, int limit) {
    final info = PlanInfo.of(key);
    final isCurrent = key == _currentPlan;
    final selectable = _selectable(key);
    final selected = selectable && _selected == key;
    final recommended = key == PlanInfo.recommendedFor(_merchant);
    return InkWell(
      key: Key('paywall_plan_$key'),
      borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
      onTap: selectable && !_busy
          ? () => setState(() {
              _selected = key;
              _error = null;
            })
          : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? HomeMindTheme.primaryTint : Colors.white,
          borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
          border: Border.all(
            color: selected ? HomeMindTheme.primary : HomeMindTheme.border,
            width: selected ? 1.6 : 1,
          ),
          boxShadow: HomeMindTheme.softShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                key: Key(
                  selected ? 'paywall_radio_on_$key' : 'paywall_radio_off_$key',
                ),
                size: 22,
                color: selected
                    ? HomeMindTheme.primary
                    : (selectable
                          ? HomeMindTheme.textMuted
                          : HomeMindTheme.border),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        info.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: HomeMindTheme.textMain,
                        ),
                      ),
                      if (isCurrent)
                        _badge(
                          tr('Gói hiện tại'),
                          HomeMindTheme.primaryLight,
                          HomeMindTheme.primaryDark,
                        )
                      else if (recommended && selectable)
                        _badge(
                          tr('Phổ biến'),
                          HomeMindTheme.premium,
                          HomeMindTheme.textMain,
                        )
                      else if (key == 'micro_pos' && !_merchant)
                        _badge(
                          tr('Cho tiệm tạp hóa'),
                          const Color(0xFFE0F2FE),
                          const Color(0xFF075985),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    info.price,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: key == 'free'
                          ? HomeMindTheme.textSub
                          : HomeMindTheme.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final b in _benefits(key, limit))
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.check_rounded,
                              size: 14,
                              color: HomeMindTheme.primary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              b,
                              style: const TextStyle(
                                fontSize: 12,
                                color: HomeMindTheme.textSub,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg),
    ),
  );
}
