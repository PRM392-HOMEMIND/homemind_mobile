import 'support/load_app_fonts.dart';

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';
import 'package:homemind_mobile/core/l10n/app_text.dart';
import 'package:homemind_mobile/core/widgets/page_skeleton.dart';
import 'package:homemind_mobile/features/family/family_gateway.dart';
import 'package:homemind_mobile/features/family/family_page.dart';

const member = {
  'userId': 'relative',
  'displayName': 'Người thân có tên rất dài để kiểm tra bố cục',
  'role': 'member',
  'joinedAt': '2026-10-13T01:00:00Z',
  'usage': 25,
  'recordedPurchases': 2,
};
Map<String, Object?> overview({String role = 'owner'}) => {
  'workspaceId': 'family',
  'name': 'Gia đình thử nghiệm',
  'eligible': true,
  'sharingEnabled': true,
  'role': role,
  'ownerId': 'owner',
  'relativeCount': 1,
  'pendingCount': 2,
  'availableSeats': 2,
  'members': [
    {
      'userId': 'owner',
      'displayName': 'Chủ nhóm',
      'role': 'owner',
      'joinedAt': '2026-10-12T00:00:00Z',
      'usage': 30,
      'recordedPurchases': 1,
    },
    member,
  ],
  'quota': {
    'periodId': 'quota',
    'plan': 'family',
    'used': 55,
    'total': 100,
    'remaining': 45,
    'startsAt': '2026-10-01T00:00:00Z',
    'expiresAt': '2026-10-31T00:00:00Z',
    'serverNow': '2026-10-13T00:00:00Z',
  },
};
FamilyGateway gateway(
  FamilyRequest request, {
  Future<void> Function()? refresh,
}) => FamilyGateway(
  workspaceId: 'family',
  userId: 'owner',
  request: request,
  newKey: () => 'test-idempotency-key',
  refreshContext: refresh ?? () async {},
);
Widget app(Widget page, {double scale = 1}) => MaterialApp(
  theme: HomeMindTheme.themeData,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: page,
);

void main() {
  setUpAll(loadAppFonts);
  setUp(() => AppText.setLanguage('vi', persist: false));
  testWidgets(
    'bulk preview reports each email; invalid rows cannot create any invitation',
    (tester) async {
      final calls = <String>[];
      final api = gateway((method, path, {body, idempotencyKey}) async {
        calls.add(path);
        expect(body?['emails'], 'valid@example.test, missing@example.test');
        return {
          'canSubmit': false,
          'validationToken': null,
          'results': [
            {
              'email': 'valid@example.test',
              'code': 'READY',
              'message': 'Có thể mời.',
            },
            {
              'email': 'missing@example.test',
              'code': 'EMAIL_NOT_REGISTERED',
              'message': 'Email missing@example.test chưa được đăng ký tài khoản HomeMind.',
            },
          ],
        };
      });
      await tester.pumpWidget(app(FamilyInvitePage(gateway: api)));
      await tester.enterText(
        find.byKey(const Key('family_emails')),
        'valid@example.test, missing@example.test',
      );
      await tester.tap(find.byKey(const Key('family_validate')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Email missing@example.test chưa được đăng ký tài khoản HomeMind.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('family_send_batch')))
            .onPressed,
        isNull,
      );
      expect(calls, ['/workspaces/family/invitations/validate']);
      expect(
        find.text(
          'Nhập một hoặc nhiều email, mỗi email cách nhau bằng dấu phẩy (,). Tối đa 5 người thân trong Workspace.',
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'changing validated input invalidates token; double submit creates one batch',
    (tester) async {
      final response = Completer<Map<String, Object?>>();
      var creates = 0;
      final api = gateway((method, path, {body, idempotencyKey}) async {
        if (path.endsWith('/validate')) {
          return {
            'canSubmit': true,
            'validationToken': 'signed-preview',
            'results': [
              {'email': 'one@example.test', 'message': 'Có thể mời.'},
            ],
          };
        }
        expect(path, endsWith('/batch'));
        expect(idempotencyKey, 'test-idempotency-key');
        expect(body?['validationToken'], 'signed-preview');
        creates++;
        return response.future;
      });
      await tester.pumpWidget(app(FamilyInvitePage(gateway: api)));
      await tester.enterText(
        find.byKey(const Key('family_emails')),
        'one@example.test',
      );
      await tester.tap(find.byKey(const Key('family_validate')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('family_send_batch')))
            .onPressed,
        isNotNull,
      );
      await tester.enterText(
        find.byKey(const Key('family_emails')),
        'two@example.test',
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('family_send_batch')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('family_validate')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('family_send_batch')));
      await tester.tap(find.byKey(const Key('family_send_batch')));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('family_send_batch')))
            .onPressed,
        isNull,
      );
      expect(creates, 1);
      response.complete({'items': []});
      await tester.pumpAndSettle();
    },
  );
  for (final role in ['owner', 'member']) {
    testWidgets('$role sees shared quota; only owner sees management', (
      tester,
    ) async {
      final api = gateway(
        (method, path, {body, idempotencyKey}) async =>
            path.endsWith('/family') ? overview(role: role) : {'items': []},
      );
      await tester.pumpWidget(app(FamilyPage(gateway: api)));
      await tester.pumpAndSettle();
      expect(find.textContaining('55/100'), findsOneWidget);
      expect(find.textContaining('45'), findsWidgets);
      await tester.scrollUntilVisible(find.text('Thành viên và sử dụng'), 250);
      await tester.pumpAndSettle();
      if (role == 'owner') {
        expect(find.byKey(const Key('family_invite')), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('family_remove_relative')),
          250,
        );
        expect(
          find.byKey(const ValueKey('family_remove_relative')),
          findsOneWidget,
        );
      } else {
        expect(find.byKey(const Key('family_invite')), findsNothing);
        expect(
          find.byKey(const ValueKey('family_remove_relative')),
          findsNothing,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'inbox pagination and declined confirmation do not switch workspace',
    (tester) async {
      var refreshed = 0;
      final calls = <String>[];
      final api = gateway(
        (method, path, {body, idempotencyKey}) async {
          calls.add(path);
          if (method == 'POST') return {'state': 'DECLINED'};
          final next = path.contains('cursor=next');
          return {
            'items': [
              {
                'id': next ? 'second' : 'first',
                'workspaceName': next ? 'Gia đình hai' : 'Gia đình một',
                'inviterName': 'Chủ nhóm',
                'state': 'PENDING',
                'expiresAt': '2026-10-20T00:00:00Z',
              },
            ],
            'hasMore': !next,
            'nextCursor': next ? null : 'next',
          };
        },
        refresh: () async {
          refreshed++;
        },
      );
      await tester.pumpWidget(app(FamilyInvitationsPage(gateway: api)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xem thêm'));
      await tester.pumpAndSettle();
      expect(find.text('Gia đình một'), findsOneWidget);
      expect(find.text('Gia đình hai'), findsOneWidget);
      await tester.tap(find.text('Từ chối').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('24 giờ'), findsOneWidget);
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(calls.where((path) => path.endsWith('/decline')), hasLength(1));
      expect(refreshed, 0);
    },
  );
  testWidgets(
    'initial skeleton becomes error then retries without fake members',
    (tester) async {
      final load = Completer<Map<String, Object?>>();
      var retry = false;
      final api = gateway(
        (method, path, {body, idempotencyKey}) => path.endsWith('/family')
            ? (retry ? Future.value(overview()) : load.future)
            : Future.value({'items': []}),
      );
      await tester.pumpWidget(app(FamilyPage(gateway: api)));
      await tester.pump();
      expect(find.byType(PageSkeleton), findsOneWidget);
      expect(find.text('Chủ nhóm'), findsNothing);
      load.completeError(StateError('Offline'));
      await tester.pumpAndSettle();
      expect(find.byType(PageSkeleton), findsNothing);
      expect(find.byKey(const Key('family_error')), findsOneWidget);
      retry = true;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(find.textContaining('55/100'), findsOneWidget);
    },
  );
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'Family pages fit 320px and text scale $scale; rendered frames',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = gateway(
          (method, path, {body, idempotencyKey}) async =>
              path.endsWith('/family') ? overview() : {'items': []},
        );
        final pages = <String, Widget>{
          'overview': FamilyPage(gateway: api),
          'invite': FamilyInvitePage(gateway: api),
          'member': const FamilyMemberPage(member: member),
          'inbox': FamilyInvitationsPage(gateway: api),
        };
        for (final entry in pages.entries) {
          final key = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: key,
              child: app(entry.value, scale: scale),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: entry.key);
          final output = Platform.environment['HOMEMIND_LOCAL_FRAME_DIR'];
          if (output != null) {
            await tester.runAsync(() async {
              final image =
                  await (key.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 2);
              try {
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await Directory(output).create(recursive: true);
                await File('$output/family_${entry.key}_${scale.toInt()}.png')
                    .writeAsBytes(bytes!.buffer.asUint8List());
              } finally {
                image.dispose();
              }
            });
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
    );
  }
}
