import 'package:flutter/material.dart';

import '../../../core/l10n/app_text.dart';
import '../../assistant/data/cached_assistant_service.dart';
import '../../assistant/domain/assistant_models.dart';
import '../../assistant/domain/assistant_service.dart';

/// Thông tin các gói (chỉ dùng số liệu chính thức của chủ sản phẩm).
class PlanInfo {
  const PlanInfo(this.key, this.name, this.price);

  final String key; // free | personal | family | micro_pos
  final String name; // đã dịch
  final String price; // đã dịch

  static PlanInfo of(String key) => switch (key) {
    'personal' => PlanInfo(key, tr('Cá nhân'), tr('29.000đ / 30 ngày')),
    'family' => PlanInfo(key, tr('Gia đình'), tr('59.000đ / 30 ngày')),
    'micro_pos' => PlanInfo(key, 'Micro-POS', tr('149.000đ / 30 ngày')),
    _ => PlanInfo('free', tr('Miễn phí'), tr('0đ')),
  };

  /// Paid plans follow the authenticated workspace segment.
  static List<String> upgradeableFor(bool merchant) =>
      merchant ? const ['micro_pos'] : const ['personal', 'family'];

  static String recommendedFor(bool merchant) =>
      merchant ? 'micro_pos' : 'personal';

  /// Lượt trợ lý AI của gói Miễn phí mỗi kỳ 30 ngày (khớp backend
  /// assistant_quota: gói free = 15 lượt).
  static const int freeAssistantQuota = 15;
}

/// Mức sử dụng gói miễn phí so với giới hạn.
enum PlanLevel { ok, nearFull, full }

class PlanUsage {
  const PlanUsage(this.used, this.limit);

  factory PlanUsage.of(HomeSummary home) =>
      PlanUsage(home.productCountTowardLimit, home.freePlanLimit);

  final int used;
  final int limit;

  double get ratio => limit <= 0 ? 0 : used / limit;
  int get remaining => (limit - used).clamp(0, 1 << 30);

  /// <70% xanh, 70–99% hổ phách, >=100% đỏ.
  PlanLevel get level => ratio >= 1
      ? PlanLevel.full
      : ratio >= 0.7
      ? PlanLevel.nearFull
      : PlanLevel.ok;
}

/// Kết quả kiểm tra thêm sản phẩm mới theo gói.
enum PlanGateResult { allowed, blockedFree, blockedPaidLimit }

/// Kiểm tra phía client (trùng quy tắc backend) trước khi gửi yêu cầu thêm
/// SẢN PHẨM MỚI. Chỉ gói free/micro_pos có hạn mức số; personal/family không
/// bao giờ bị chặn. Thêm lô cho sản phẩm đã có (trùng tên) luôn được phép.
class PlanGate {
  const PlanGate._();

  static String normalize(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  static PlanGateResult checkAddProduct({
    required HomeSummary home,
    required Iterable<InventoryItem> inventory,
    required String productName,
  }) {
    if (home.plan != 'free' && home.plan != 'micro_pos') {
      return PlanGateResult.allowed;
    }
    if (home.freePlanLimit <= 0 ||
        home.productCountTowardLimit < home.freePlanLimit) {
      return PlanGateResult.allowed;
    }
    final key = normalize(productName);
    if (key.isNotEmpty && inventory.any((i) => normalize(i.name) == key)) {
      return PlanGateResult.allowed;
    }
    return home.plan == 'free'
        ? PlanGateResult.blockedFree
        : PlanGateResult.blockedPaidLimit;
  }

  /// Câu thông báo khi bị chặn (null nếu được phép).
  static String? message(PlanGateResult result, String plan, int limit) =>
      switch (result) {
        PlanGateResult.allowed => null,
        PlanGateResult.blockedFree => tr(
          'Gói Miễn phí đã đủ {0} sản phẩm. Nâng cấp để thêm sản phẩm mới.',
          [limit],
        ),
        PlanGateResult.blockedPaidLimit => tr(
          'Gói {0} đã đủ {1} mặt hàng. Hãy liên hệ để nâng hạn mức.',
          [PlanInfo.of(plan).name, limit],
        ),
      };
}

/// Đọc HomeSummary từ bộ nhớ đệm (đồng bộ khi có) và dựng lại khi dữ liệu đổi.
/// Lỗi hoặc chưa có dữ liệu: [builder] nhận null (chỉ việc không hiện gì).
class HomeSummaryGate extends StatefulWidget {
  const HomeSummaryGate({
    required this.service,
    required this.builder,
    super.key,
  });

  final AssistantService service;
  final Widget Function(BuildContext context, HomeSummary? home) builder;

  @override
  State<HomeSummaryGate> createState() => _HomeSummaryGateState();
}

class _HomeSummaryGateState extends State<HomeSummaryGate> {
  HomeSummary? _home;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    widget.service.dataChanges.addListener(_onChanged);
    _load(notify: false);
  }

  @override
  void didUpdateWidget(covariant HomeSummaryGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service)) {
      oldWidget.service.dataChanges.removeListener(_onChanged);
      widget.service.dataChanges.addListener(_onChanged);
      _load(notify: false);
    }
  }

  @override
  void dispose() {
    widget.service.dataChanges.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => _load(notify: true);

  void _load({required bool notify}) {
    final token = ++_token;
    final Future<HomeSummary> future;
    try {
      future = widget.service.getHomeSummary();
    } catch (_) {
      return;
    }
    final now = syncValue(future);
    if (now != null) {
      _home = now;
      if (notify && mounted) setState(() {});
      return;
    }
    future.then((value) {
      if (!mounted || token != _token) return;
      setState(() => _home = value);
    }, onError: (Object _) {});
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _home);
}
