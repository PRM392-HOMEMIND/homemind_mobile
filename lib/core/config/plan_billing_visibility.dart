import 'package:flutter/widgets.dart';

import '../l10n/app_text.dart';

/// Client navigation/display policy only. Never changes server entitlements,
/// quota or purchase availability. A rebuild is required to restore the UI.
class PlanBillingVisibility extends InheritedWidget {
  const PlanBillingVisibility({
    this.visible = defaultVisible,
    this.fallbackBuilder,
    required super.child,
    super.key,
  });

  // Shared by every flavor/platform. No URL, environment default or remote
  // response can enable it. Restore here and rebuild the Flutter app.
  static const defaultVisible = false;
  final bool visible;
  final WidgetBuilder? fallbackBuilder;

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<PlanBillingVisibility>()
          ?.visible ??
      defaultVisible;

  static Widget fallback(BuildContext context, WidgetBuilder orElse) =>
      (context
          .dependOnInheritedWidgetOfExactType<PlanBillingVisibility>()
          ?.fallbackBuilder ??
      orElse)(context);

  /// Actual hub destinations, not backend permissions.
  static bool isPlanTarget(String type, String id) =>
      type == 'plan' ||
      type == 'billing' ||
      (type == 'feature' && {'billing', 'history', 'help'}.contains(id));

  // System presentation only. Never match the word "gói" alone: it is also a
  // quantity/unit in inventory and shopping. User-owned entity rows are retained.
  static final _billingText = RegExp(
    r'\b(?:BILLING|PAYMENT|SUBSCRIPTION|PAYOS|PLAN)_[A-Z0-9_]+\b|'
    r'\b(billing|subscription|payment|invoice|checkout|paywall|premium|upgrade|lifetime)\b|'
    r'thanh toán|nâng cấp|mua gói|đổi gói|gia hạn|vĩnh viễn|'
    r'gói (miễn phí|cá nhân|gia đình|free|hiện tại|đang dùng|dịch vụ)|'
    r'(current|free|paid) plan|purchase history|restore purchases|\bforever\b|unlimited duration|không thời hạn',
    caseSensitive: false,
    unicode: true,
  );

  static bool isBillingText(
    String text, {
    Iterable<String> preservedValues = const [],
  }) {
    // Classify system copy without treating explicit user entity labels as
    // billing. Return/render the original value; never rewrite cached data.
    var systemCopy = text;
    final labels =
        preservedValues
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    for (final value in labels) {
      final label = RegExp(
        '(^|[^\\p{L}\\p{N}_])${RegExp.escape(value)}(?=\$|[^\\p{L}\\p{N}_])',
        unicode: true,
      );
      systemCopy = systemCopy.replaceAllMapped(label, (match) => match[1]!);
    }
    return _billingText.hasMatch(systemCopy);
  }

  static Iterable<String> entityLabels(Object? value) sync* {
    if (value is Map) {
      for (final entry in value.entries) {
        if ({
              'name',
              'productName',
              'category',
              'storageLocation',
              'workspaceName',
            }.contains(entry.key) &&
            entry.value is String) {
          yield entry.value as String;
        } else if (entry.value is Map || entry.value is Iterable) {
          yield* entityLabels(entry.value);
        }
      }
    } else if (value is Iterable) {
      for (final item in value) {
        yield* entityLabels(item);
      }
    }
  }

  static bool isBillingRecord(Map row) {
    final type = row['type']?.toString() ?? '';
    // Search uses `notification` as the route type; its notification kind is
    // obtained separately from the existing authorized detail endpoint.
    final kind = type == 'notification'
        ? row['notificationType']?.toString() ?? ''
        : type;
    if (isPlanTarget(type, row['id']?.toString() ?? '') ||
        type.startsWith('billing.') ||
        isPlanTarget(kind, row['id']?.toString() ?? '') ||
        kind.startsWith('billing.') ||
        isPlanTarget(
          row['targetType']?.toString() ?? '',
          row['targetId']?.toString() ?? '',
        )) {
      return true;
    }
    if ({
          'inventory',
          'shopping',
          'profile',
          'family',
          'family_invitation',
        }.contains(kind) ||
        kind.startsWith('inventory.') ||
        kind.startsWith('shopping.') ||
        kind == 'expiry') {
      return false;
    }
    return [
      'title',
      'body',
      'detail',
      'summary',
    ].any((key) => isBillingText(row[key]?.toString() ?? ''));
  }

  static bool showsRecord(BuildContext context, Map row) =>
      of(context) || !isBillingRecord(row);

  /// Map server/system copy at its render boundary; do not mutate cached data,
  /// exceptions, quota, API results or user-entered item names.
  static String message(
    BuildContext context,
    String text, {
    String? fallback,
    Iterable<String> preservedValues = const [],
  }) => !of(context) && isBillingText(text, preservedValues: preservedValues)
      ? fallback ?? tr('Đã đạt hạn mức sử dụng hiện tại.')
      : text;

  @override
  bool updateShouldNotify(PlanBillingVisibility oldWidget) =>
      visible != oldWidget.visible ||
      fallbackBuilder != oldWidget.fallbackBuilder;
}
