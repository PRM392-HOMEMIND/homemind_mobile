import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/core/config/plan_billing_visibility.dart';

/// Existing billing business/presentation contracts run in the explicitly
/// restored client UI. This does not enable checkout or override entitlements.
/// Default-hidden navigation is covered separately without this fixture.
extension RestoredPlanBillingUi on WidgetTester {
  Future<void> pumpRestoredPlanBillingWidget(Widget child) =>
      pumpWidget(PlanBillingVisibility(visible: true, child: child));
}
