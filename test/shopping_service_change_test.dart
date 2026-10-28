import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/shopping/presentation/shopping_page.dart';

import 'support/recording_plan_service.dart';

class _Service extends RecordingPlanService {
  _Service() : super(initialRole: AccountRole.merchant);
  final profiles = <Completer<UserProfile>>[];
  @override
  Future<UserProfile> getMe() {
    final request = Completer<UserProfile>();
    profiles.add(request);
    return request.future;
  }

  @override
  Future<List<InventoryItem>> getInventory() async => [];
  @override
  Future<({List<ShoppingItem> items, List<Map<String, Object?>> suggestions})>
  getShoppingList() async =>
      (items: <ShoppingItem>[], suggestions: <Map<String, Object?>>[]);
}

UserProfile _profile(String name) => UserProfile(
  userId: name,
  email: 'fixture@example.invalid',
  displayName: name,
  workspaceId: name,
  workspaceName: name,
  workspaceType: 'store',
  role: 'merchant',
);

void main() {
  testWidgets(
    'stale profile cannot cross service replacement, including A B A',
    (tester) async {
      final a = _Service(), b = _Service();
      Future<void> show(_Service service) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: HomeMindTheme.themeData,
          home: Scaffold(body: ShoppingPage(service: service)),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(a);
      await show(b);
      b.profiles.last.complete(_profile('Current B'));
      await tester.pumpAndSettle();
      expect(find.text('Current B'), findsOneWidget);
      await show(a);
      a.profiles.last.complete(_profile('Current A'));
      await tester.pumpAndSettle();
      a.profiles.first.complete(_profile('Stale A'));
      await tester.pumpAndSettle();
      expect(find.text('Current A'), findsOneWidget);
      expect(find.text('Stale A'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
