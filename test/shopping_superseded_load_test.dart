import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';
import 'package:homemind_mobile/features/assistant/data/workspace_pages.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/shopping/presentation/shopping_page.dart';

import 'support/recording_plan_service.dart';

class _Changes extends ChangeNotifier {
  void fire() => notifyListeners();
}

class _RacingRows extends RecordingPlanService implements WorkspacePagesSource {
  _RacingRows()
    : super(
        initialRole: AccountRole.consumer,
        email: 'fixture@example.invalid',
      );
  final changes = _Changes();
  final pending = <Completer<Map<String, Object?>>>[];
  @override
  Listenable get dataChanges => changes;
  @override
  Future<List<InventoryItem>> getInventory() =>
      SynchronousFuture(<InventoryItem>[]);
  @override
  late final WorkspacePages workspacePages = WorkspacePages(
    workspaceId: 'owned-fixture',
    request: (method, path) {
      final request = Completer<Map<String, Object?>>();
      pending.add(request);
      return request.future;
    },
  );
  void finish(int index, String name) {
    pending[index].complete({
      'items': [
        if (index.isEven)
          {
            'id': name,
            'name': name,
            'quantity': 1,
            'unit': 'hộp',
            'status': 'needed',
            'source': 'manual',
            'createdBy': 'owned',
            'canEdit': true,
          },
      ],
      'suggestions': <Map<String, Object?>>[],
      'total': index.isEven ? 1 : 0,
      'hasMore': false,
      'nextCursor': null,
    });
  }
}

Future<void> _show(WidgetTester tester, _RacingRows service) =>
    tester.pumpWidget(
      MaterialApp(
        theme: HomeMindTheme.themeData,
        home: Scaffold(body: ShoppingPage(service: service)),
      ),
    );

void main() {
  testWidgets(
    'an obsolete refresh cannot replace search with an error during debounce',
    (tester) async {
      final service = _RacingRows();
      await _show(tester, service);
      service.finish(0, 'Initial row');
      service.finish(1, 'Initial row');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Tìm kiếm'));
      await tester.pumpAndSettle();
      service.changes.fire();
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('shopping_search')),
        'Current',
      );
      service.finish(2, 'Obsolete row');
      service.finish(3, 'Obsolete row');
      await tester.pump();
      try {
        expect(find.text('Thử lại'), findsNothing);
        expect(find.byKey(const Key('shopping_search')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('shopping_item_Obsolete row')),
          findsNothing,
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(service.pending, hasLength(6));
        service.finish(4, 'Current row');
        service.finish(5, 'Current row');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('shopping_item_Current row')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'two cache notifications before a frame do not leak obsolete load errors',
    (tester) async {
      final service = _RacingRows();
      await _show(tester, service);
      service.finish(0, 'Initial row');
      service.finish(1, 'Initial row');
      await tester.pumpAndSettle();
      service.changes.fire();
      service.changes.fire();
      expect(service.pending, hasLength(6));
      service.finish(2, 'Obsolete row');
      service.finish(3, 'Obsolete row');
      service.finish(4, 'Current row');
      service.finish(5, 'Current row');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('shopping_item_Current row')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('shopping_item_Obsolete row')),
        findsNothing,
      );
      expect(find.text('Thử lại'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the current failed request still renders the retry state', (
    tester,
  ) async {
    final service = _RacingRows();
    await _show(tester, service);
    service.pending[0].completeError(StateError('owned request failed'));
    service.finish(1, 'Unused');
    await tester.pumpAndSettle();
    expect(find.text('Thử lại'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late paged rows cannot cross service replacement', (
    tester,
  ) async {
    final old = _RacingRows(), current = _RacingRows();
    await _show(tester, old);
    await _show(tester, current);
    current.finish(0, 'Current workspace');
    current.finish(1, 'Current workspace');
    await tester.pumpAndSettle();
    old.finish(0, 'Previous workspace');
    old.finish(1, 'Previous workspace');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('shopping_item_Current workspace')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('shopping_item_Previous workspace')),
      findsNothing,
    );
    expect(find.text('Thử lại'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing the page cancels a late load without an error', (
    tester,
  ) async {
    final service = _RacingRows();
    await _show(tester, service);
    final observed = tester
        .widget<FutureBuilder<dynamic>>(
          find.byWidgetPredicate((w) => w is FutureBuilder),
        )
        .future!;
    final outcome = observed.then<Object?>(
      (_) => null,
      onError: (Object error) => error,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    service.finish(0, 'Disposed workspace');
    service.finish(1, 'Disposed workspace');
    await tester.pumpAndSettle();
    expect(await outcome, isNull);
    expect(find.text('Disposed workspace'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
