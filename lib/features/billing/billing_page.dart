import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/config/plan_billing_visibility.dart';

import '../../core/widgets/page_skeleton.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../app/homemind_theme.dart';
import '../../core/config/env_config.dart';
import '../../core/l10n/app_text.dart';
import 'billing_service.dart';
import '../home/presentation/profile_page.dart';
import 'billing_widgets.dart';
import 'billing_distribution.dart';

String _planName(Object? value) => switch (value) {
  'free' => tr('Miễn phí'),
  'personal' => AppText.isEnglish ? tr('Gói Cá nhân') : tr('Cá nhân'),
  'family' => tr('Gia đình'),
  'micro_pos' => 'Micro-POS',
  _ => tr('Đang tải'),
};
String _date(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return '—';
  String pad(int v) => v.toString().padLeft(2, '0');
  return '${pad(date.day)}/${pad(date.month)}/${date.year} ${pad(date.hour)}:${pad(date.minute)}:${pad(date.second)}';
}

class BillingPage extends StatefulWidget {
  const BillingPage({
    required this.gateway,
    required this.refreshEntitlements,
    this.launchCheckout,
    this.voiceUsage,
    this.initialPayment,
    this.checkoutStopwatchFactory = Stopwatch.new,
    super.key,
  });
  final BillingGateway gateway;
  final Future<void> Function() refreshEntitlements;
  final Future<bool> Function(Uri)? launchCheckout;
  final Widget? voiceUsage;
  final Future<Map<String, Object?>> Function()? initialPayment;
  final Stopwatch Function() checkoutStopwatchFactory;
  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage> with WidgetsBindingObserver {
  Map<String, Object?>? _catalog, _overview, _payment;
  String? _error;
  bool _busy = false;
  int _generation = 0;
  bool _activated = false;
  CheckoutClock? _checkoutClock;

  void _receivePayment(Map<String, Object?>? payment) {
    if (payment != null) payment = billingPaymentForDistribution(payment);
    // Anchor when the response is received, before a lazy card can mount.
    // Preserve elapsed time across rebuilds and scrolling off-screen.
    if (payment == null || _checkoutClock?.matches(payment) != true) {
      _checkoutClock?.stop();
      _checkoutClock = payment == null
          ? null
          : CheckoutClock.fromPayment(
              payment,
              stopwatchFactory: widget.checkoutStopwatchFactory,
            );
    }
    _payment = payment;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  bool _started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && PlanBillingVisibility.of(context)) {
      _started = true;
      _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    _checkoutClock?.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Payment verification is deliberately manual. Returning from a browser
    // or backgrounding the app never creates or reconciles an order.
  }

  bool _current(int generation) => mounted && generation == _generation;
  @override
  void didUpdateWidget(covariant BillingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.gateway, widget.gateway)) {
      ++_generation;
      _catalog = _overview = _payment = null;
      _checkoutClock?.stop();
      _checkoutClock = null;
      _busy = false;
      _activated = false;
      if (PlanBillingVisibility.of(context)) _load();
    }
  }

  Future<void> _load() => _run((generation) async {
    final catalog = await widget.gateway.plans(),
        overview = await widget.gateway.overview(),
        pending = widget.initialPayment != null
            ? await widget.initialPayment!()
            : await widget.gateway.pending();
    if (!_current(generation)) return;
    setState(() {
      _catalog = catalog;
      _overview = billingOverviewForDistribution(overview);
      _receivePayment(pending);
      _error = null;
    });
    await _accept(pending, generation);
  });

  Future<void> _accept(Map<String, Object?>? payment, int generation) async {
    if (!_current(generation)) return;
    if (payment == null) return;
    if (payment['financialState'] == 'PAID' &&
        payment['fulfillment'] == 'GRANTED') {
      await widget.gateway.clearPending();
      if (!_current(generation)) return;
      await widget.refreshEntitlements();
      if (!_current(generation)) return;
      final overview = await widget.gateway.overview();
      if (_current(generation)) {
        setState(() {
          _overview = billingOverviewForDistribution(overview);
          _activated = true;
        });
      }
    } else if (['CANCELLED', 'EXPIRED'].contains(payment['status'])) {
      await widget.gateway.clearPending();
    }
  }

  bool get _pending =>
      _payment != null &&
      !['PAID', 'CANCELLED', 'EXPIRED', 'REVIEW'].contains(_payment!['status']);
  Future<void> _check() async {
    if (!EnvConfig.externalBillingAllowed) return;
    if (_busy || _payment?['id'] is! String) return;
    final id = _payment!['id'] as String;
    await _run((generation) async {
      final result = await widget.gateway.reconcile(id);
      if (!_current(generation) || _payment?['id'] != id) return;
      setState(() => _receivePayment(result));
      await _accept(result, generation);
      if (!_current(generation)) return;
      final overview = await widget.gateway.overview();
      if (_current(generation)) {
        setState(() => _overview = billingOverviewForDistribution(overview));
      }
    });
  }

  Future<void> _run(Future<void> Function(int generation) action) async {
    if (_busy) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(generation).timeout(const Duration(seconds: 25));
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = 'Chưa hoàn tất yêu cầu. Kiểm tra trạng thái trước khi tạo đơn khác.',
        );
      }
    } finally {
      if (_current(generation)) {
        setState(() => _busy = false);
        ++_generation; // invalidate late completions after a timeout
      }
    }
  }

  Future<void> _buy(Map plan) async {
    if (!EnvConfig.externalBillingAllowed) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Xác nhận gói')),
        content: Text(
          tr(
            '{0}: {1} VND / 30 ngày. Nâng gói thu đủ giá, áp dụng ngay sau xác minh thanh toán và bắt đầu kỳ mới với lượt dùng bằng 0. Không cộng thời gian hoặc lượt cũ. Không tự động gia hạn.',
            [_planName(plan['plan']), plan['amount']],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Quay lại')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Tạo đơn thanh toán')),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    await _run((generation) async {
      final payment = await widget.gateway.create(plan['id'] as String);
      if (!_current(generation)) return;
      setState(() {
        _receivePayment(payment);
        _activated = false;
      });
      await _accept(payment, generation);
      if (!_current(generation)) return;
      if (payment['checkoutUrl'] is String &&
          payment['financialState'] != 'PAID') {
        await _open(payment['checkoutUrl'] as String);
      }
    });
  }

  Future<void> _open(String value) async {
    if (!EnvConfig.externalBillingAllowed) {
      throw StateError(
        tr('Không mở thanh toán ngoài trong bản phân phối này.'),
      );
    }
    final uri = billingCheckoutUri(value);
    final success =
        await (widget.launchCheckout?.call(uri) ??
            launchUrl(uri, mode: LaunchMode.externalApplication));
    if (!success) throw StateError(tr('Chưa mở được trình duyệt.'));
  }

  String _state(Map payment) => switch ((
    payment['financialState'],
    payment['fulfillment'],
    payment['status'],
  )) {
    ('PAID', 'GRANTED', _) => tr('Đã xác minh thanh toán và cấp gói'),
    ('PAID', 'REVIEW', _) => tr(
      'Đã ghi nhận tiền — chờ kiểm tra trước khi cấp gói',
    ),
    (_, _, 'UNDERPAID') => tr('Chưa đủ tiền — chưa cấp gói'),
    (_, _, 'CANCELLED') => tr('Đã hủy đơn chưa thanh toán'),
    (_, _, 'EXPIRED') => tr('Đơn đã hết hạn'),
    (_, _, 'REVIEW') => tr('Đơn cần được kiểm tra — chưa cấp gói'),
    _ => tr('Đang chờ xác minh — chưa cấp gói'),
  };
  @override
  Widget build(BuildContext context) {
    if (!PlanBillingVisibility.of(context)) {
      return PlanBillingVisibility.fallback(
        context,
        (_) => const ProfilePage(),
      );
    }
    final entitlement = _overview?['entitlement'] as Map?;
    final subscription = _overview?['subscription'] as Map?;
    final manual = entitlement?['source'] == 'legacy_manual';
    final enabled =
        EnvConfig.externalBillingAllowed &&
        _catalog?['checkoutEnabled'] == true &&
        !manual;
    final history = (_overview?['payments'] as List?) ?? [];
    final eligibility = _overview?['eligibility'] as Map?;
    final workspaceType = _overview?['workspaceType'];
    return Scaffold(
      appBar: AppBar(title: Text(tr('Gói & thanh toán'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_catalog == null && _error == null)
            const PageSkeleton(SkeletonPage.billing, sectionOnly: true),
          if (_overview != null)
            BillingCurrentPlanCard(
              plan: entitlement?['plan'],
              subscription: subscription,
              productLimit: (entitlement?['productLimit'] as num?)?.toInt(),
            ),
          if (widget.voiceUsage != null) widget.voiceUsage!,
          for (final scheduled in (_overview?['scheduled'] as List?) ?? [])
            BillingNotice(
              tr('Đã mua, chờ áp dụng: {0} từ {1} đến {2}', [
                _planName((scheduled as Map)['plan']),
                _date(scheduled['startsAt']),
                _date(scheduled['expiresAt']),
              ]),
            ),
          if (manual)
            BillingNotice(
              tr(
                'Gói được cấp thủ công vẫn được giữ nguyên. Cần liên hệ chủ sản phẩm để xét chuyển đổi.',
              ),
            ),
          if (!EnvConfig.externalBillingAllowed)
            BillingNotice(
              tr(
                'Thanh toán gói hiện chưa được hỗ trợ trong phiên bản này. Bạn vẫn có thể xem gói hiện tại và lịch sử thanh toán.',
              ),
              key: const Key('billing_payment_disabled'),
            ),
          if (EnvConfig.externalBillingAllowed &&
              _catalog?['checkoutEnabled'] == false)
            BillingNotice(tr('Thanh toán chưa được cấu hình trên máy chủ.')),
          if (_activated)
            BillingNotice(
              tr(
                'Thanh toán đã được máy chủ xác minh. Gói và thời gian áp dụng hiển thị bên trên.',
              ),
              key: const Key('billing_verified'),
            ),
          if (_error != null) ...[
            BillingNotice(
              tr(_error!),
              error: true,
              key: const Key('billing_error'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(tr('Tải lại')),
            ),
          ],
          if (EnvConfig.externalBillingAllowed)
            BillingSectionTitle(tr('Chọn gói phù hợp')),
          for (final raw
              in EnvConfig.externalBillingAllowed
                  ? (_catalog?['plans'] as List?) ?? []
                  : [])
            Builder(
              builder: (context) {
                final plan = raw as Map;
                final segments = plan['workspaceTypes'];
                if (workspaceType == null ||
                    segments is! List ||
                    !segments.contains(workspaceType)) {
                  return const SizedBox.shrink();
                }
                final reason = eligibility?[plan['plan']];
                final same = plan['plan'] == entitlement?['plan'];
                final canPurchase =
                    enabled &&
                    !(_busy ||
                        _pending ||
                        reason != null ||
                        same ||
                        eligibility == null ||
                        !eligibility.containsKey(plan['plan']));
                return BillingPlanCard(
                  plan: plan,
                  current: same,
                  canPurchase: canPurchase,
                  onPurchase: canPurchase ? () => _buy(plan) : null,
                );
              },
            ),
          BillingSectionTitle(tr('HomeMind đang hoàn thiện')),
          ComingSoonCard(
            key: const Key('billing_annual_soon'),
            title: tr('Gói năm'),
            description: tr('Hiện tại bạn có thể sử dụng gói 30 ngày.'),
            icon: Icons.event_note_rounded,
            soon: true,
          ),
          ComingSoonCard(
            key: const Key('billing_renewal_soon'),
            title: tr('Gia hạn tự động'),
            description: tr('HomeMind đang hoàn thiện tính năng này'),
            icon: Icons.update_rounded,
          ),
          if (EnvConfig.externalBillingAllowed &&
              _payment?['unresolvedIntent'] == true) ...[
            BillingNotice(
              tr(
                'Đơn trước chưa rõ kết quả. Bấm khôi phục để kiểm tra cùng yêu cầu; không tạo đơn mới.',
              ),
            ),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run((generation) async {
                      final result = await widget.gateway.create(
                        _payment!['priceId'] as String,
                      );
                      if (!_current(generation)) return;
                      setState(() => _receivePayment(result));
                      await _accept(result, generation);
                    }),
              icon: const Icon(Icons.restore_rounded),
              label: Text(tr('Khôi phục đơn đang chờ')),
            ),
          ] else if (_payment != null && _payment!['id'] != null) ...[
            BillingSectionTitle(tr('Thanh toán của bạn')),
            BillingPaymentCard(
              payment: _payment!,
              clock: _checkoutClock,
              stateText: _state(_payment!),
              pending: _pending,
              checkoutEnabled: enabled,
              busy: _busy,
              onCheck: _check,
              onOpen: () =>
                  _run((_) => _open(_payment!['checkoutUrl'] as String)),
              onCancel: () => _run((generation) async {
                final p = await widget.gateway.cancel(
                  _payment!['id'] as String,
                );
                if (!_current(generation)) return;
                setState(() => _receivePayment(p));
                await _accept(p, generation);
                if (!_current(generation)) return;
                final overview = await widget.gateway.overview();
                if (_current(generation)) {
                  setState(
                    () => _overview = billingOverviewForDistribution(overview),
                  );
                }
              }),
            ),
          ],
          BillingSectionTitle(tr('Lịch sử thanh toán')),
          if (history.isEmpty) const BillingEmptyHistory(),
          for (final raw in history)
            BillingHistoryCard(
              payment: billingPaymentForDistribution(
                Map<String, Object?>.from(raw as Map),
              ),
              stateText: _state(raw),
            ),
          if (_overview?['nextOffset'] is int)
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run((generation) async {
                      final next = await widget.gateway.overview(
                        offset: _overview!['nextOffset'] as int,
                      );
                      if (_current(generation)) {
                        setState(
                          () => _overview = billingOverviewForDistribution({
                            ...next,
                            'payments': [
                              ...history,
                              ...next['payments'] as List,
                            ],
                          }),
                        );
                      }
                    }),
              child: Text(tr('Xem thêm')),
            ),
          const SizedBox(height: 16),
          ComingSoonCard(
            key: const Key('billing_refund_soon'),
            title: tr('Yêu cầu hoàn tiền'),
            description: tr(
              'Tính năng gửi yêu cầu hoàn tiền đang được HomeMind hoàn thiện.',
            ),
            icon: Icons.handyman_outlined,
          ),
          const BillingSupportCard(),
          OutlinedButton.icon(
            key: const Key('billing_reload'),
            style: OutlinedButton.styleFrom(
              foregroundColor: HomeMindTheme.primaryStrong,
              side: const BorderSide(color: HomeMindTheme.sectionBorder),
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onPressed: _busy ? null : _load,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(tr('Tải lại dữ liệu thanh toán')),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
