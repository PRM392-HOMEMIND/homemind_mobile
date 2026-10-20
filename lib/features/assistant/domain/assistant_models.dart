enum AssistantTurnKind {
  readResult('read_result'),
  writeDraft('write_draft'),
  writeCommitted('write_committed'),
  clarify('clarify'),
  unknown('unknown'),
  cancelled('cancelled');

  const AssistantTurnKind(this.wireValue);
  final String wireValue;

  static AssistantTurnKind parse(Object? value) {
    for (final kind in values) {
      if (kind.wireValue == value) return kind;
    }
    throw FormatException('kind không hợp lệ: $value');
  }
}

class ToolCall {
  const ToolCall({required this.toolId, required this.arguments});

  final String toolId;
  final Map<String, Object?> arguments;

  factory ToolCall.fromJson(Map<String, Object?> json) => ToolCall(
    toolId: (json['toolId'] as String?) ?? '',
    arguments: _asMap(json['arguments']),
  );
}

class InventoryItem {
  const InventoryItem({
    required this.productId,
    required this.name,
    required this.category,
    required this.quantity,
    required this.unit,
    required this.expiryDate,
    required this.expiryLevel,
    required this.status,
    this.lotId,
    this.storageLocation,
    this.createdBy,
    this.canEdit = true,
  });

  final String productId;
  final String? lotId;

  /// Nơi cất (tùy chọn) của lô dùng trước.
  final String? storageLocation;
  final String? createdBy;
  final bool canEdit;
  final String name;
  final String? category;
  final double? quantity;
  final String? unit;
  final String? expiryDate;
  final String expiryLevel;
  final String status;

  factory InventoryItem.fromJson(Map<String, Object?> json) => InventoryItem(
    productId: (json['productId'] as String?) ?? '',
    lotId: json['lotId'] as String?,
    name: (json['name'] as String?) ?? '',
    category: json['category'] as String?,
    quantity: (json['quantity'] as num?)?.toDouble(),
    unit: json['unit'] as String?,
    expiryDate: json['expiryDate'] as String?,
    expiryLevel: (json['expiryLevel'] as String?) ?? 'ok',
    status: (json['status'] as String?) ?? 'in_stock',
    storageLocation: json['storageLocation'] as String?,
    createdBy: json['createdBy'] as String?,
    canEdit: json['canEdit'] == true,
  );

  InventoryItem copyWith({
    double? quantity,
    String? unit,
    String? expiryDate,
    String? expiryLevel,
    String? status,
    String? storageLocation,
  }) => InventoryItem(
    productId: productId,
    lotId: lotId,
    storageLocation: storageLocation ?? this.storageLocation,
    name: name,
    category: category,
    quantity: quantity ?? this.quantity,
    unit: unit ?? this.unit,
    expiryDate: expiryDate ?? this.expiryDate,
    expiryLevel: expiryLevel ?? this.expiryLevel,
    status: status ?? this.status,
    createdBy: createdBy,
    canEdit: canEdit,
  );
}

class ShoppingItem {
  const ShoppingItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.status,
    required this.source,
    this.createdBy,
    this.canEdit = true,
  });

  final String id;
  final String name;
  final double? quantity;
  final String? unit;
  final String status;
  final String source;
  final String? createdBy;
  final bool canEdit;

  factory ShoppingItem.fromJson(Map<String, Object?> json) => ShoppingItem(
    id: (json['id'] as String?) ?? '',
    name: (json['name'] as String?) ?? '',
    quantity: (json['quantity'] as num?)?.toDouble(),
    unit: json['unit'] as String?,
    status: (json['status'] as String?) ?? 'needed',
    source: (json['source'] as String?) ?? 'manual',
    createdBy: json['createdBy'] as String?,
    canEdit: json['canEdit'] == true,
  );

  ShoppingItem copyWith({String? status}) => ShoppingItem(
    id: id,
    name: name,
    quantity: quantity,
    unit: unit,
    status: status ?? this.status,
    source: source,
    createdBy: createdBy,
    canEdit: canEdit,
  );
}

class HomeAlert {
  const HomeAlert({
    required this.type,
    required this.severity,
    required this.productId,
    required this.title,
    required this.subtitle,
    required this.cta,
    this.expiryDate,
  });

  final String type;
  final String severity;
  final String productId;
  final String title;
  final String subtitle;
  final String cta;
  final String? expiryDate;

  factory HomeAlert.fromJson(Map<String, Object?> json) => HomeAlert(
    type: (json['type'] as String?) ?? 'expiry',
    severity: (json['severity'] as String?) ?? 'soon',
    productId: (json['productId'] as String?) ?? '',
    title: (json['title'] as String?) ?? '',
    subtitle: (json['subtitle'] as String?) ?? '',
    cta: (json['cta'] as String?) ?? 'buy',
    expiryDate: json['expiryDate'] as String?,
  );
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.context,
    required this.type,
    required this.read,
  });

  final String id;
  final String title;
  final String body;
  final String context;
  final String type;
  final bool read;

  factory AppNotification.fromJson(Map<String, Object?> json) =>
      AppNotification(
        id: (json['id'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        body: (json['body'] as String?) ?? '',
        context: (json['context'] as String?) ?? '',
        type: (json['type'] as String?) ?? 'system',
        read: json['read'] == true,
      );

  AppNotification copyWith({bool? read}) => AppNotification(
    id: id,
    title: title,
    body: body,
    context: context,
    type: type,
    read: read ?? this.read,
  );
}

class HomeSummary {
  const HomeSummary({
    required this.totalProducts,
    required this.inStockCount,
    required this.outCount,
    required this.expiredCount,
    required this.expiringSoonCount,
    required this.shoppingNeededCount,
    required this.freePlanLimit,
    required this.productCountTowardLimit,
    required this.expiringSoon,
    required this.expired,
    required this.alerts,
    this.plan = 'free',
    this.requestedPlans = const [],
  });

  final int totalProducts;
  final int inStockCount;
  final int outCount;
  final int expiredCount;
  final int expiringSoonCount;
  final int shoppingNeededCount;
  final int freePlanLimit;
  final int productCountTowardLimit;
  final List<InventoryItem> expiringSoon;
  final List<InventoryItem> expired;
  final List<HomeAlert> alerts;
  final String plan;

  /// Các gói workspace này đã yêu cầu nâng cấp (server ghi nhận).
  final List<String> requestedPlans;

  factory HomeSummary.fromJson(Map<String, Object?> json) => HomeSummary(
    totalProducts: (json['totalProducts'] as num?)?.toInt() ?? 0,
    inStockCount: (json['inStockCount'] as num?)?.toInt() ?? 0,
    outCount: (json['outCount'] as num?)?.toInt() ?? 0,
    expiredCount: (json['expiredCount'] as num?)?.toInt() ?? 0,
    expiringSoonCount: (json['expiringSoonCount'] as num?)?.toInt() ?? 0,
    shoppingNeededCount: (json['shoppingNeededCount'] as num?)?.toInt() ?? 0,
    freePlanLimit: (json['freePlanLimit'] as num?)?.toInt() ?? 30,
    productCountTowardLimit:
        (json['productCountTowardLimit'] as num?)?.toInt() ?? 0,
    expiringSoon: _items(json['expiringSoon']),
    expired: _items(json['expired']),
    alerts: _list(json['alerts'])
        .whereType<Map>()
        .map((e) => HomeAlert.fromJson(_asMap(e)))
        .toList(growable: false),
    plan: (json['plan'] as String?) ?? 'free',
    requestedPlans: _list(json['requestedPlans'])
        .whereType<String>()
        .toList(growable: false),
  );

  HomeSummary copyWith({
    int? totalProducts,
    int? inStockCount,
    int? outCount,
    int? expiredCount,
    int? expiringSoonCount,
    int? shoppingNeededCount,
    int? productCountTowardLimit,
    List<InventoryItem>? expiringSoon,
    List<InventoryItem>? expired,
    List<HomeAlert>? alerts,
    List<String>? requestedPlans,
  }) => HomeSummary(
    totalProducts: totalProducts ?? this.totalProducts,
    inStockCount: inStockCount ?? this.inStockCount,
    outCount: outCount ?? this.outCount,
    expiredCount: expiredCount ?? this.expiredCount,
    expiringSoonCount: expiringSoonCount ?? this.expiringSoonCount,
    shoppingNeededCount: shoppingNeededCount ?? this.shoppingNeededCount,
    freePlanLimit: freePlanLimit,
    productCountTowardLimit:
        productCountTowardLimit ?? this.productCountTowardLimit,
    expiringSoon: expiringSoon ?? this.expiringSoon,
    expired: expired ?? this.expired,
    alerts: alerts ?? this.alerts,
    plan: plan,
    requestedPlans: requestedPlans ?? this.requestedPlans,
  );
}

/// Toàn bộ dữ liệu màn hình trong MỘT lần gọi
/// (`GET /workspaces/{id}/bootstrap`).
class Bootstrap {
  const Bootstrap({
    required this.home,
    required this.inventory,
    required this.inventoryTotal,
    required this.shoppingItems,
    required this.suggestions,
    required this.notifications,
    required this.unreadCount,
    this.serverTime,
  });

  final HomeSummary home;
  final List<InventoryItem> inventory;
  final int inventoryTotal;
  final List<ShoppingItem> shoppingItems;
  final List<Map<String, Object?>> suggestions;
  final List<AppNotification> notifications;
  final int unreadCount;
  final String? serverTime;

  factory Bootstrap.fromJson(Map<String, Object?> json) {
    final inventory = _asMap(json['inventory']);
    final shopping = _asMap(json['shopping']);
    final notifications = _asMap(json['notifications']);
    final inventoryItems = _list(inventory['items'])
        .whereType<Map>()
        .map((e) => InventoryItem.fromJson(_asMap(e)))
        .toList(growable: false);
    final notificationItems = _list(notifications['items'])
        .whereType<Map>()
        .map((e) => AppNotification.fromJson(_asMap(e)))
        .toList(growable: false);
    return Bootstrap(
      home: HomeSummary.fromJson(_asMap(json['home'])),
      inventory: inventoryItems,
      inventoryTotal:
          (inventory['total'] as num?)?.toInt() ?? inventoryItems.length,
      shoppingItems: _list(shopping['items'])
          .whereType<Map>()
          .map((e) => ShoppingItem.fromJson(_asMap(e)))
          .toList(growable: false),
      suggestions: _list(shopping['suggestions'])
          .whereType<Map>()
          .map(_asMap)
          .toList(growable: false),
      notifications: notificationItems,
      unreadCount:
          (notifications['unreadCount'] as num?)?.toInt() ??
          notificationItems.where((n) => !n.read).length,
      serverTime: json['serverTime'] as String?,
    );
  }
}

enum AccountRole {
  consumer,
  merchant;

  String get label => switch (this) {
    AccountRole.consumer => 'Người dùng gia đình',
    AccountRole.merchant => 'Người bán tạp hóa',
  };

  String get shortTitle => switch (this) {
    AccountRole.consumer => 'Gia đình',
    AccountRole.merchant => 'Tạp hóa',
  };

  String get iconEmoji => switch (this) {
    AccountRole.consumer => '👤',
    AccountRole.merchant => '🏪',
  };
}

class UserProfile {
  const UserProfile({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.workspaceId,
    required this.workspaceName,
    required this.workspaceType,
    required this.role,
    this.phone,
    this.loginPhone,
    this.address,
    this.language = 'vi',
    this.voiceQuota,
  });

  final String userId;
  final String email;
  final String displayName;
  final String workspaceId;
  final String workspaceName;
  final String workspaceType;
  final String role;
  final String? phone;

  /// Canonical login identifier; the profile contact field may be edited separately.
  final String? loginPhone;
  final String? address;

  /// Ngôn ngữ giao diện đã chọn: 'vi' hoặc 'en'.
  final String language;
  final VoiceQuota? voiceQuota;

  UserProfile copyWith({
    String? displayName,
    String? phone,
    String? address,
    String? language,
    VoiceQuota? voiceQuota,
  }) => UserProfile(
    userId: userId,
    email: email,
    displayName: displayName ?? this.displayName,
    workspaceId: workspaceId,
    workspaceName: workspaceName,
    workspaceType: workspaceType,
    role: role,
    phone: phone ?? this.phone,
    loginPhone: loginPhone,
    address: address ?? this.address,
    language: language ?? this.language,
    voiceQuota: voiceQuota ?? this.voiceQuota,
  );

  AccountRole get accountRole =>
      workspaceType == 'store' || workspaceType == 'grocery_store'
      ? AccountRole.merchant
      : AccountRole.consumer;

  factory UserProfile.fromJson(Map<String, Object?> json) => UserProfile(
    userId: (json['userId'] as String?) ?? '',
    email: (json['email'] as String?) ?? '',
    displayName: (json['displayName'] as String?) ?? '',
    workspaceId: (json['workspaceId'] as String?) ?? '',
    workspaceName: (json['workspaceName'] as String?) ?? '',
    workspaceType: (json['workspaceType'] as String?) ?? 'household',
    role: (json['role'] as String?) ?? 'owner',
    phone: json['phone'] as String?,
    loginPhone: json['loginPhone'] as String?,
    address: json['address'] as String?,
    language: (json['language'] as String?) == 'en' ? 'en' : 'vi',
    voiceQuota: json['voiceQuota'] is Map
        ? VoiceQuota.fromJson(_asMap(json['voiceQuota']))
        : null,
  );
}

class VoiceQuota {
  const VoiceQuota({
    required this.periodId,
    required this.plan,
    required this.used,
    required this.total,
    required this.remaining,
    required this.startsAt,
    required this.expiresAt,
    required this.serverNow,
  });
  final String periodId, plan;
  final int used, total, remaining;
  final DateTime startsAt, expiresAt, serverNow;
  factory VoiceQuota.fromJson(Map<String, Object?> json) {
    final used = json['used'],
        total = json['total'],
        remaining = json['remaining'];
    if (used is! int ||
        total is! int ||
        remaining is! int ||
        used < 0 ||
        total <= 0 ||
        used > total ||
        remaining < 0 ||
        remaining > total - used ||
        json['periodId'] is! String) {
      throw const FormatException('Invalid authoritative voice quota');
    }
    return VoiceQuota(
      periodId: json['periodId'] as String,
      plan: json['plan'] as String,
      used: used,
      total: total,
      remaining: remaining,
      startsAt: DateTime.parse(json['startsAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      serverNow: DateTime.parse(json['serverNow'] as String),
    );
  }
}

abstract interface class VoiceQuotaSource {
  Future<VoiceQuota?> getVoiceQuota();
}

class AssistantTurn {
  const AssistantTurn({
    required this.schemaVersion,
    required this.turnId,
    required this.kind,
    required this.dictionaryVersion,
    required this.correctedInput,
    required this.processingTimeMs,
    required this.message,
    required this.warnings,
    required this.requiresConfirmation,
    required this.toolsUsed,
    required this.toolsProposed,
    required this.data,
    required this.ok,
    required this.created,
    this.voiceQuota,
    this.followUps = const [],
  });

  /// Các bản nháp còn lại của CÙNG một câu nói (nhiều việc ghi); duyệt lần lượt sau bản đầu.
  final List<AssistantTurn> followUps;

  final String schemaVersion;
  final String turnId;
  final AssistantTurnKind kind;
  final String dictionaryVersion;
  final String? correctedInput;
  final int processingTimeMs;
  final String message;
  final List<String> warnings;
  final bool requiresConfirmation;
  final List<ToolCall> toolsUsed;
  final List<ToolCall> toolsProposed;
  final Map<String, Object?>? data;
  final bool? ok;
  final Map<String, Object?>? created;
  final VoiceQuota? voiceQuota;

  bool get isWriteDraft => kind == AssistantTurnKind.writeDraft;
  bool get isRead => kind == AssistantTurnKind.readResult;

  factory AssistantTurn.fromJson(Map<String, Object?> json) {
    final kind = AssistantTurnKind.parse(json['kind']);
    return AssistantTurn(
      schemaVersion: (json['schemaVersion'] as String?) ?? '1.0',
      turnId: (json['turnId'] as String?) ?? '',
      kind: kind,
      dictionaryVersion: (json['dictionaryVersion'] as String?) ?? '1.1.0',
      correctedInput: json['correctedInput'] as String?,
      processingTimeMs: (json['processingTimeMs'] as num?)?.toInt() ?? 0,
      message: (json['message'] as String?) ?? '',
      warnings: _strings(json['warnings']),
      requiresConfirmation: json['requiresConfirmation'] == true,
      toolsUsed: _tools(json['toolsUsed']),
      toolsProposed: _tools(json['toolsProposed']),
      data: json['data'] is Map ? _asMap(json['data'] as Map) : null,
      ok: json['ok'] as bool?,
      created: json['created'] is Map ? _asMap(json['created'] as Map) : null,
      voiceQuota: json['voiceQuota'] is Map
          ? VoiceQuota.fromJson(_asMap(json['voiceQuota']))
          : null,
      followUps: [
        for (final f in (json['followUps'] as List? ?? const []))
          if (f is Map) AssistantTurn.fromJson(_asMap(f)),
      ],
    );
  }
}

List<Object?> _list(Object? value) => value is List ? value : const [];

List<String> _strings(Object? value) =>
    _list(value)
        .whereType<String>()
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

Map<String, Object?> _asMap(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, v) => MapEntry(key.toString(), v));
}

List<ToolCall> _tools(Object? value) =>
    _list(value)
        .whereType<Map>()
        .map((e) => ToolCall.fromJson(_asMap(e)))
        .toList(growable: false);

List<InventoryItem> _items(Object? value) =>
    _list(value)
        .whereType<Map>()
        .map((e) => InventoryItem.fromJson(_asMap(e)))
        .toList(growable: false);

/// Một lần mua (lô nhập kho) chưa có giá trong tháng.
class UnpricedPurchase {
  const UnpricedPurchase({
    required this.lotId,
    required this.productId,
    required this.name,
    required this.purchasedAt,
    this.storageLocation,
    this.createdBy,
    this.canEdit = true,
    this.purchaseId,
  });

  final String lotId;
  final String productId;
  final String name;
  final DateTime purchasedAt;
  final String? storageLocation;
  final String? createdBy, purchaseId;
  final bool canEdit;

  factory UnpricedPurchase.fromJson(Map<String, Object?> json) =>
      UnpricedPurchase(
        lotId: (json['lotId'] as String?) ?? '',
        productId: (json['productId'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        purchasedAt:
            DateTime.tryParse((json['purchasedAt'] as String?) ?? '')
                ?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0),
        storageLocation: json['storageLocation'] as String?,
        createdBy: json['createdBy'] as String?,
        purchaseId: json['purchaseId'] as String?,
        canEdit: json['canEdit'] == true,
      );
}

/// Chi tiêu một tháng. Giá là tùy chọn nên [totalVnd] chỉ cộng các lần mua
/// đã có giá; [unpricedCount] cho biết phần còn thiếu để người dùng tự đánh giá.
class SpendingSummary {
  const SpendingSummary({
    required this.month,
    required this.totalVnd,
    required this.pricedCount,
    required this.unpricedCount,
    required this.previousTotalVnd,
    required this.byCategory,
    required this.unpriced,
    this.scope = 'workspace',
    this.nextCursor,
    this.byMember = const [],
    this.unpricedLotCount = 0,
  });

  /// `YYYY-MM`.
  final String month;
  final int totalVnd;
  final int pricedCount;
  final int unpricedCount;
  final int previousTotalVnd;
  final String scope;
  final String? nextCursor;
  final List<Map<String, Object?>> byMember;
  final int unpricedLotCount;

  /// Danh mục (null = chưa phân loại) kèm số tiền, giảm dần, tối đa 5.
  final List<({String? category, int totalVnd})> byCategory;

  /// Tối đa 30 lần mua gần nhất chưa có giá (có thể ít hơn [unpricedCount]).
  final List<UnpricedPurchase> unpriced;

  bool get isEmpty => pricedCount == 0 && unpricedCount == 0;

  factory SpendingSummary.fromJson(Map<String, Object?> json) {
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    return SpendingSummary(
      month: (json['month'] as String?) ?? '',
      totalVnd: n(json['totalVnd']),
      pricedCount: n(json['pricedCount']),
      unpricedCount: n(json['unpricedCount']),
      previousTotalVnd: n(json['previousTotalVnd']),
      scope: json['scope'] as String? ?? 'workspace',
      nextCursor: json['hasMore'] == true
          ? json['nextCursor'] as String?
          : null,
      unpricedLotCount: n(json['unpricedLotCount']),
      byMember: [
        for (final row in (json['byMember'] as List? ?? []))
          Map<String, Object?>.from(row as Map),
      ],
      byCategory: [
        for (final c in (json['byCategory'] as List? ?? const []))
          if (c is Map)
            (category: c['category'] as String?, totalVnd: n(c['totalVnd'])),
      ],
      unpriced: [
        for (final u in (json['unpriced'] as List? ?? const []))
          if (u is Map) UnpricedPurchase.fromJson(Map<String, Object?>.from(u)),
      ],
    );
  }
}
