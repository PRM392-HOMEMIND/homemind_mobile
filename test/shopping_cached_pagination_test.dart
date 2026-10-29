import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';
import 'package:homemind_mobile/features/assistant/data/workspace_pages.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/shopping/presentation/shopping_page.dart';

import 'support/recording_plan_service.dart';

class _CachedRows extends RecordingPlanService implements WorkspacePagesSource {
  _CachedRows()
    : super(
        initialRole: AccountRole.consumer,
        email: 'fixture@example.invalid',
      );
  @override
  Future<List<InventoryItem>> getInventory() =>
      SynchronousFuture(<InventoryItem>[]);
  @override
  late final WorkspacePages workspacePages = WorkspacePages(
    workspaceId: 'owned-fixture',
    request: (method, path) async {
      final skipped = Uri.parse(path).queryParameters['status'] == 'skipped';
      return {
        'items': skipped
            ? <Map<String, Object?>>[]
            : [
                for (final name in ['Gạo native E2E', 'Trứng native E2E'])
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
        'total': skipped ? 0 : 2,
        'hasMore': false,
        'nextCursor': null,
      };
    },
  );
}

void main() {
  testWidgets('paged shopping loads from a warm synchronous inventory cache', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: HomeMindTheme.themeData,
        home: Scaffold(body: ShoppingPage(service: _CachedRows())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Thử lại'), findsNothing);
    expect(
      find.byKey(const ValueKey('shopping_item_Gạo native E2E')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
