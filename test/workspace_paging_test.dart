import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';
import 'package:homemind_mobile/core/l10n/app_text.dart';
import 'package:homemind_mobile/core/quantity.dart';
import 'package:homemind_mobile/core/widgets/page_skeleton.dart';
import 'package:homemind_mobile/features/assistant/data/workspace_pages.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_service.dart';
import 'package:homemind_mobile/features/family/family_page.dart';
import 'package:homemind_mobile/features/family/family_gateway.dart';
import 'package:homemind_mobile/features/home/domain/home_hub_gateway.dart';
import 'package:homemind_mobile/features/home/presentation/durable_notifications_surface.dart';
import 'package:homemind_mobile/features/spending/presentation/spending_page.dart';

import 'support/fake_assistant_service.dart';

import 'package:homemind_mobile/features/assistant/data/backend_assistant_service.dart';

class PagesService extends FakeAssistantService
    implements WorkspacePagesSource, SpendingSource {
  PagesService(this.workspacePages) : super(delay: Duration.zero);
  @override
  final WorkspacePages workspacePages;
  @override
  bool get spendingAvailable => true;
  @override
  Future<SpendingSummary> getSpending({String? month}) =>
      throw StateError('Must use scoped paging');
  @override
  Future<void> updateLot({
    required String lotId,
    int? priceVnd,
    String? storageLocation,
  }) async {}
}

Widget app(Widget child) =>
    MaterialApp(theme: HomeMindTheme.themeData, home: child);
Map<String, Object?> spending(
  Uri uri, {
  bool more = false,
  String label = 'Món',
}) => {
  'month': uri.queryParameters['month'],
  'scope': uri.queryParameters['scope'],
  'totalVnd': 0,
  'previousTotalVnd': 0,
  'pricedCount': 0,
  'unpricedCount': 2,
  'unpricedLotCount': 2,
  'byCategory': [],
  'unpriced': [
    {
      'lotId': more ? 'second' : 'first',
      'purchaseId': more ? 'p2' : 'p1',
      'productId': 'p',
      'name': '$label ${more ? 2 : 1}',
      'purchasedAt': '2026-10-01T00:00:00Z',
      'canEdit': false,
    },
  ],
  'hasMore': !more,
  'nextCursor': more ? null : 'cursor-next',
};

void main() {
  setUp(() => AppText.setLanguage('vi', persist: false));
  test('quantity rejects precision overflow, infinities and signs while preserving valid decimal boundaries', () {
    for (final text in [
      '0',
      '-1',
      'NaN',
      'Infinity',
      '1e2',
      '0.0001',
      '1.2345',
      '1000000000',
      '',
      '1,2,3',
    ]) {
      expect(parseQuantity(text), isNull, reason: text);
    }
    expect(parseQuantity('0,001'), .001);
    expect(parseQuantity('999999999.999'), 999999999.999);
    expect(parseQuantity(' 0.3 '), .3);
  });
  testWidgets(
    'spending appends next cursor once and clears rows when switching scope',
    (tester) async {
      tester.view.physicalSize = const Size(500, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final calls = <Uri>[];
      final service = PagesService(
        WorkspacePages(
          workspaceId: 'ws',
          request: (method, path) async {
            final uri = Uri.parse(path);
            calls.add(uri);
            return spending(
              uri,
              more: uri.queryParameters.containsKey('cursor'),
              label: uri.queryParameters['scope'] == 'personal'
                  ? 'Cá nhân'
                  : 'Nhóm',
            );
          },
        ),
      );
      await tester.pumpWidget(
        app(SpendingPage(service: service, source: service, merchant: false)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nhóm 1'), findsOneWidget);
      expect(find.text('Nhóm 2'), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('spending_more')));
      await tester.tap(find.byKey(const Key('spending_more')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Nhóm 1'), findsOneWidget);
      expect(find.text('Nhóm 2'), findsOneWidget);
      expect(calls.map((c) => c.queryParameters['cursor']).toList(), [
        null,
        'cursor-next',
      ]);
      expect(find.byKey(const Key('spending_more')), findsNothing);
      await tester.ensureVisible(find.text('Chi tiêu cá nhân'));
      await tester.tap(find.text('Chi tiêu cá nhân'));
      await tester.pumpAndSettle();
      expect(find.text('Nhóm 1'), findsNothing);
      expect(find.text('Nhóm 2'), findsNothing);
      expect(find.text('Cá nhân 1'), findsOneWidget);
      expect(calls.last.queryParameters['cursor'], isNull);
      expect(calls.last.queryParameters['scope'], 'personal');
    },
  );
  testWidgets(
    'spending immediately removes old rows when the next page loses authorization',
    (tester) async {
      tester.view.physicalSize = const Size(500, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = PagesService(
        WorkspacePages(
          workspaceId: 'ws',
          request: (m, p) async {
            final uri = Uri.parse(p);
            if (uri.queryParameters.containsKey('cursor')) {
              throw const HomeMindApiException(
                'Lost Family access',
                statusCode: 403,
                code: 'FORBIDDEN',
              );
            }
            return spending(uri, label: 'Protected');
          },
        ),
      );
      await tester.pumpWidget(
        app(SpendingPage(service: service, source: service, merchant: false)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Protected 1'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('spending_more')));
      await tester.tap(find.byKey(const Key('spending_more')));
      await tester.pumpAndSettle();
      expect(find.text('Protected 1'), findsNothing);
      expect(
        find.text('Chưa tải được chi tiêu. Bạn thử lại nhé.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('spending ignores a response from a previous workspace', (
    tester,
  ) async {
    final old = Completer<Map<String, Object?>>();
    final before = PagesService(
      WorkspacePages(workspaceId: 'old', request: (m, p) => old.future),
    );
    final after = PagesService(
      WorkspacePages(
        workspaceId: 'new',
        request: (m, p) async => spending(Uri.parse(p), label: 'Mới'),
      ),
    );
    await tester.pumpWidget(
      app(SpendingPage(service: before, source: before, merchant: false)),
    );
    await tester.pump();
    expect(find.byType(PageSkeleton), findsOneWidget);
    await tester.pumpWidget(
      app(SpendingPage(service: after, source: after, merchant: false)),
    );
    await tester.pumpAndSettle();
    old.complete(
      spending(Uri.parse('/?month=2026-10&scope=workspace'), label: 'Cũ'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cũ 1'), findsNothing);
    expect(find.text('Mới 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'notification batches require another click and preserve cutoff; do not claim all unread is zero',
    (tester) async {
      final sent = <Map<String, Object?>>[];
      final counts = <int>[];
      final hub = HomeHubGateway(
        scope: 'user:ws',
        workspaceId: 'ws',
        request: (m, p) async => {
          'items': [],
          'hasMore': false,
          'nextCursor': null,
          'unreadCount': sent.isEmpty
              ? 100
              : sent.length == 1
              ? 75
              : 25,
        },
        write: (p, body) async {
          sent.add(body);
          return {
            'readCount': 50,
            'remainingCount': sent.length == 1 ? 50 : 0,
            'hasMore': sent.length == 1,
            'cutoff': '2026-10-13T00:00:00Z',
          };
        },
      );
      await tester.pumpWidget(
        app(
          Scaffold(
            body: DurableNotificationsSurface(
              gateway: hub,
              onUnread: counts.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notifications_read_batch')));
      await tester.pumpAndSettle();
      expect(sent, hasLength(1));
      expect(sent.first, {});
      expect(counts.last, 75);
      expect(find.textContaining('Còn 50 thông báo'), findsOneWidget);
      await tester.tap(find.byKey(const Key('notifications_read_batch')));
      await tester.pumpAndSettle();
      expect(sent, hasLength(2));
      expect(sent.last['cutoff'], '2026-10-13T00:00:00Z');
      expect(counts.last, 25);
    },
  );
  testWidgets(
    'old invitation preview cannot enable submit after a workspace switch',
    (tester) async {
      final old = Completer<Map<String, Object?>>();
      FamilyGateway gateway(String ws) => FamilyGateway(
        userId: 'owner',
        workspaceId: ws,
        newKey: () => 'key',
        refreshContext: () async {},
        request: (m, p, {body, idempotencyKey}) => ws == 'old'
            ? old.future
            : Future.value({'canSubmit': false, 'results': []}),
      );
      await tester.pumpWidget(app(FamilyInvitePage(gateway: gateway('old'))));
      await tester.enterText(
        find.byKey(const Key('family_emails')),
        'person@example.invalid',
      );
      await tester.tap(find.byKey(const Key('family_validate')));
      await tester.pump();
      await tester.pumpWidget(app(FamilyInvitePage(gateway: gateway('new'))));
      old.complete({
        'canSubmit': true,
        'validationToken': 'old-token',
        'results': [],
      });
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('family_send_batch')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('family_emails')))
            .controller!
            .text,
        isEmpty,
      );
    },
  );
  testWidgets(
    'all page skeletons have one loading announcement, no gestures and fit320px at2x text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      try {
        for (final page in SkeletonPage.values) {
          await tester.pumpWidget(
            app(
              Scaffold(
                body: MediaQuery(
                  data: const MediaQueryData(
                    textScaler: TextScaler.linear(2),
                    disableAnimations: true,
                  ),
                  child: SingleChildScrollView(child: PageSkeleton(page)),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(find.bySemanticsLabel('Đang tải dữ liệu'), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(PageSkeleton),
              matching: find.byType(ButtonStyleButton),
            ),
            findsNothing,
          );
          expect(tester.takeException(), isNull, reason: page.name);
        }
      } finally {
        semantics.dispose();
      }
    },
  );
}
