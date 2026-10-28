import 'package:flutter/foundation.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';

import 'fake_assistant_service.dart';

/// Test double cho luồng gói dịch vụ: trả HomeSummary/hồ sơ do test đặt (đồng
/// bộ như bộ nhớ đệm) và ghi lại các lần gọi [requestUpgrade].
class RecordingPlanService extends FakeAssistantService {
  RecordingPlanService({
    this.plan = 'free',
    this.used = 10,
    this.limit = 30,
    this.requested = const [],
    super.initialRole,
    this.email = 'tuan@homemind.vn',
  }) : super(delay: Duration.zero);

  String plan;
  int used;
  int limit;
  List<String> requested;
  String email;

  /// Mỗi lần gọi requestUpgrade: (plan, source).
  final List<({String plan, String source})> calls = [];

  /// Nếu khác null, requestUpgrade ném lỗi này.
  Object? failWith;

  @override
  Future<HomeSummary> getHomeSummary() => SynchronousFuture(
    HomeSummary(
      totalProducts: used,
      inStockCount: used,
      outCount: 0,
      expiredCount: 0,
      expiringSoonCount: 0,
      shoppingNeededCount: 0,
      freePlanLimit: limit,
      productCountTowardLimit: used,
      expiringSoon: const [],
      expired: const [],
      alerts: const [],
      plan: plan,
      requestedPlans: requested,
    ),
  );

  @override
  Future<UserProfile> getMe() => SynchronousFuture(
    UserProfile(
      userId: 'u1',
      email: email,
      displayName: 'Anh Tuấn',
      workspaceId: 'ws-1',
      workspaceName: 'Nhà riêng',
      workspaceType: currentRole == AccountRole.merchant
          ? 'grocery_store'
          : 'household',
      role: currentRole == AccountRole.merchant ? 'merchant' : 'consumer',
    ),
  );

  @override
  Future<void> requestUpgrade({
    required String plan,
    required String source,
  }) async {
    if (failWith != null) throw failWith!;
    calls.add((plan: plan, source: source));
  }
}
