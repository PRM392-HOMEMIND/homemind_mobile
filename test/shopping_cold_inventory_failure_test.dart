import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';
import 'package:homemind_mobile/features/assistant/data/workspace_pages.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/shopping/presentation/shopping_page.dart';

import 'support/recording_plan_service.dart';

class _ColdInventory extends RecordingPlanService
    implements WorkspacePagesSource {
  _ColdInventory()
    : super(
        initialRole: AccountRole.consumer,
        email: 'fixture@example.invalid',
      );
  final inventory = Completer<List<InventoryItem>>();
  @override
  Future<List<InventoryItem>> getInventory() => inventory.future;
  @override
  late final WorkspacePages workspacePages = WorkspacePages(
    workspaceId: 'owned-fixture',
    request: (method, path) async =>
        throw StateError('owned paging request failed'),
  );
}

void main() {
  testWidgets(
    'paging errors before a cold inventory completes are handled by retry UI',
    (tester) async {
      final service = _ColdInventory();
      await tester.pumpWidget(
        MaterialApp(
          theme: HomeMindTheme.themeData,
          home: Scaffold(body: ShoppingPage(service: service)),
        ),
      );
      await tester.pump();
      service.inventory.complete(<InventoryItem>[]);
      await tester.pumpAndSettle();
      expect(find.text('Thử lại'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
