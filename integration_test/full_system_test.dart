import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:homemind_mobile/main.dart' as app;
import 'package:homemind_mobile/core/config/env_config.dart';
import 'package:homemind_mobile/features/voice/presentation/voice_sheet.dart';
import 'package:homemind_mobile/features/shopping/presentation/receive_sheet.dart';
import 'package:homemind_mobile/features/shopping/presentation/shopping_page.dart';
import 'package:homemind_mobile/features/inventory/presentation/repurchase_dialog.dart';
import 'package:homemind_mobile/features/home/presentation/durable_notifications_surface.dart';
import 'package:homemind_mobile/features/home/presentation/hub_entity_page.dart';
import 'package:homemind_mobile/features/billing/billing_page.dart';
import 'package:homemind_mobile/features/home/presentation/profile_page.dart';

import 'native_ui_sync.dart' as native_ui;

// Uses the ordinary application entry point, real RemoteAuthService/HTTP/storage.
// All passwords are generated for disposable identities at runtime, never defines.
const base = String.fromEnvironment('BACKEND_BASE_URL');
const runId = String.fromEnvironment('E2E_RUN_ID');
const productionSafe = bool.fromEnvironment('E2E_PRODUCTION_SAFE');
const expectedRevision = String.fromEnvironment('E2E_EXPECTED_REVISION');
const controlUrl = String.fromEnvironment('E2E_CONTROL_URL');
final random = Random.secure();
String nonce() => List.generate(
  16,
  (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
final owned = <Map<String, dynamic>>[];
bool ai01Active = false;
void ai01Stage(String id) {
  if (ai01Active) debugPrint('E2E_AI01 $id');
}

Future<void> journalOwned() async {
  final context = await hostResult('owned-app-context');
  final nativeAppPackage = context['package'];
  final filesDirectory = context['filesDirectory'];
  if (nativeAppPackage is! String ||
      !RegExp(r'^[A-Za-z]\w*(?:\.[A-Za-z]\w*)+$').hasMatch(nativeAppPackage) ||
      !{
        '/data/user/0/$nativeAppPackage/files',
        '/data/data/$nativeAppPackage/files',
      }.contains(filesDirectory) ||
      !RegExp(r'^homemind-e2e-[a-f0-9]{12}$').hasMatch(runId)) {
    throw StateError('Verified Android identity and owned run required');
  }
  final file = File('$filesDirectory/$runId-owned.json');
  await file.parent.create(recursive: true);
  await file.writeAsString(
    jsonEncode(
      owned
          .map(
            (actor) => {
              for (final key in [
                'email',
                'password',
                'candidateEmail',
                'candidatePassword',
                'registered',
                'closed',
                'retained',
              ])
                if (actor.containsKey(key)) key: actor[key],
            },
          )
          .toList(),
    ),
    flush: true,
  );
  final permissions = await Process.run('/system/bin/chmod', [
    '600',
    file.path,
  ]);
  expect(permissions.exitCode, 0);
  await host('owned-identity-journal');
}

Future<void> host(String action) async {
  await hostResult(action);
}

Future<Map> hostResult(String action) async {
  final uri = Uri.parse(controlUrl);
  if (uri.scheme != 'http' ||
      uri.host != '127.0.0.1' ||
      uri.path != '/$runId') {
    throw StateError('Owned native host control is missing');
  }
  final response = await http
      .post(
        uri,
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'action': action}),
      )
      .timeout(const Duration(seconds: 40));
  final result = jsonDecode(response.body) as Map;
  native_ui.verifyHostResponse(response.statusCode, result['status']);
  return result;
}

Future<void> deliveredOtp(WidgetTester tester, {bool newEmail = false}) async {
  await waitFor(tester, find.byKey(const Key('otp_code')));
  late Map result;
  await native_ui.awaitWithFrames(tester, () async {
    result = await hostResult(newEmail ? 'email-code-new' : 'email-code');
  }());
  // Values remain private: verify the actual six-digit delivery and normal UI.
  expect(RegExp(r'^[0-9]{6}$').hasMatch(result['code'] as String), isTrue);
  await fill(tester, 'otp_code', result['code'] as String);
  await dismissKeyboard(tester);
  final deadline = DateTime.now().add(const Duration(seconds: 25));
  final button = find.byKey(const Key('otp_verify'));
  while (tester.widget<ElevatedButton>(button).onPressed == null &&
      DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);
  await tap(tester, button, deadline: deadline);
}

Future<void> loginNative(
  WidgetTester tester,
  String email,
  String password,
) async {
  await waitFor(tester, find.byKey(const Key('login_identifier')));
  await fill(tester, 'login_identifier', email);
  await fill(tester, 'login_password', password);
  await dismissKeyboard(tester);
  await tap(tester, find.byKey(const Key('login_submit')));
  await waitFor(tester, find.byKey(const Key('nav_home')));
}

Future<int> responseStatus(
  String path,
  String method,
  Map<String, dynamic>? body, [
  String? token,
]) async {
  final client = http.Client();
  try {
    final req = http.Request(method, Uri.parse('$base$path'));
    req.headers.addAll({
      'content-type': 'application/json',
      'x-homemind-distribution': EnvConfig.distribution,
      if (token != null) 'authorization': 'Bearer $token',
    });
    if (body != null) req.body = jsonEncode(body);
    final result = await client.send(req).timeout(const Duration(seconds: 20));
    await result.stream.drain<void>();
    return result.statusCode;
  } finally {
    client.close();
  }
}

Future<void> cleanupOwned() async {
  for (final actor in owned) {
    if (actor['retained'] == true) continue;
    if (actor['registered'] == false) {
      // Recover only this pre-journalled UI identity if its response was lost.
      try {
        final session = await request('/auth/login', 'POST', {
          'identifier': actor['email'],
          'password': actor['password'],
        });
        actor.addAll({...session, 'registered': true});
      } on StateError catch (error) {
        if (error.message == 'Fixture HTTP POST expected 2xx, got 401') {
          continue;
        }
        rethrow;
      }
    }
    if (actor['closed'] == true) {
      expect(
        await responseStatus('/auth/login', 'POST', {
          'identifier': actor['email'],
          'password': actor['password'],
        }),
        403,
      );
    } else {
      await request('/auth/account', 'DELETE', {
        'currentPassword': actor['password'],
      }, actor['accessToken'] as String);
      actor['closed'] = true;
    }
  }
  await journalOwned();
  await const FlutterSecureStorage().deleteAll();
}

Future<Map<String, dynamic>> request(
  String path,
  String method,
  Map<String, dynamic>? body, [
  String? token,
]) async {
  final uri = Uri.parse('$base$path');
  final headers = {
    'content-type': 'application/json',
    'x-homemind-distribution': EnvConfig.distribution,
    if (token != null) 'authorization': 'Bearer $token',
    'idempotency-key':
        '${nonce().substring(0, 8)}-0000-4000-8000-${nonce().substring(0, 12)}',
  };
  final client = http.Client();
  try {
    final req = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) req.body = jsonEncode(body);
    final response = await client
        .send(req)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw StateError(
        'Fixture HTTP $method expected 2xx, got ${response.statusCode}',
      );
    }
    return jsonDecode(await response.stream.bytesToString())
        as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  int seconds = 25,
  DateTime? deadline,
}) async {
  final until = deadline ?? DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(until)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  final shopping = find.byType(ShoppingPage);
  if (shopping.evaluate().isNotEmpty) {
    final scrolls = find.descendant(
      of: shopping,
      matching: find.byType(Scrollable),
    );
    debugPrint(
      'E2E_SHOPPING_READINESS ${jsonEncode({
        'firstOwnedRow': find.text('Gạo native E2E').evaluate().length,
        'secondOwnedRow': find.text('Trứng native E2E').evaluate().length,
        'retryVisible': find.text('Thử lại').evaluate().isNotEmpty,
        'emptyVisible': find.text('Không có món nào cần mua.').evaluate().isNotEmpty,
        'scrolls': [
          for (final element in scrolls.evaluate())
            if (tester.state<ScrollableState>(find.byWidget(element.widget)).position.hasContentDimensions) {'pixels': tester.state<ScrollableState>(find.byWidget(element.widget)).position.pixels, 'max': tester.state<ScrollableState>(find.byWidget(element.widget)).position.maxScrollExtent},
        ],
      })}',
    );
  }
  expect(
    finder,
    findsWidgets,
    reason: 'Native screen did not reach expected selector',
  );
}

Future<void> tap(
  WidgetTester tester,
  Finder finder, {
  DateTime? deadline,
}) async {
  deadline ??= DateTime.now().add(const Duration(seconds: 25));
  await waitFor(tester, finder, deadline: deadline);
  await tester.ensureVisible(finder.first);
  // Scrolling changes layout; flush that frame before computing the tap point.
  await tester.pump();
  final ready = finder.first.hitTestable();
  while (ready.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(
    ready,
    findsOneWidget,
    reason: 'Native target must receive pointer events before tapping',
  );
  await tester.tap(finder.first);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> waitForScrolled(
  WidgetTester tester,
  Finder finder,
  Finder page, {
  bool requirePointerTarget = true,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 25));
  final scrollable = find
      .descendant(of: page, matching: find.byType(Scrollable))
      .first;
  await waitFor(tester, scrollable, deadline: deadline);
  var forward = true;
  // The catalog can arrive while a lazy list is being scrolled. Keep observing
  // actual UI readiness within the existing selector deadline, even at an edge.
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder.first);
      await tester.pump();
      if (requirePointerTarget
          ? finder.first.hitTestable().evaluate().isNotEmpty
          : tester
                .getRect(scrollable)
                .contains(tester.getRect(finder.first).center)) {
        return;
      }
    }
    final position = tester.state<ScrollableState>(scrollable).position;
    if (position.hasContentDimensions) {
      if (position.pixels >= position.maxScrollExtent - 1) forward = false;
      if (position.pixels <= position.minScrollExtent + 1) forward = true;
    }
    // Async insertion may put a new card above the current viewport. Observe
    // both extents instead of searching only below an earlier loading layout.
    await tester.drag(scrollable, Offset(0, forward ? -250 : 250));
  }
  expect(
    finder.evaluate().length == 1 &&
        (requirePointerTarget
            ? finder.hitTestable().evaluate().length == 1
            : tester
                  .getRect(scrollable)
                  .contains(tester.getRect(finder.first).center)),
    isTrue,
    reason: 'Native lazy content must become ready and visible',
  );
}

Future<void> back(WidgetTester tester) async {
  await native_ui.backWhenReady(tester);
}

Future<void> fill(WidgetTester tester, String key, String value) async {
  final field = find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byType(EditableText),
  );
  await tester.ensureVisible(field);
  await tester.pump();
  await tester.tap(field);
  await tester.enterText(field, value);
  // Compare privately: a failed assertion must never print an entered password.
  expect(
    tester.widget<EditableText>(field).controller.text == value,
    isTrue,
    reason: 'Native controlled input did not match for $key',
  );
}

Future<void> dismissKeyboard(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  for (var i = 0; i < 30 && tester.view.viewInsets.bottom > 0; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    tester.view.viewInsets.bottom,
    0,
    reason: 'Native keyboard must close before form submit',
  );
}

Future<Map<String, dynamic>> persisted(
  WidgetTester tester,
  Map<String, dynamic> actor,
  String path,
  bool Function(Map<String, dynamic>) predicate,
) async {
  for (var i = 0; i < 25; i++) {
    final data = await request(
      path,
      'GET',
      null,
      actor['accessToken'] as String,
    );
    if (predicate(data)) return data;
    await tester.pump(const Duration(milliseconds: 250));
  }
  throw StateError('Owned native mutation was not persisted');
}

Future<void> say(WidgetTester tester, String text) async {
  await tap(tester, find.byKey(const Key('nav_voice')));
  final sheetDeadline = DateTime.now().add(const Duration(seconds: 25));
  await waitFor(tester, find.byType(VoiceSheet), deadline: sheetDeadline);
  final route = await native_ui.currentRouteWhenReady(
    tester,
    find.byType(VoiceSheet),
    timeout: sheetDeadline.difference(DateTime.now()),
  );
  // Typed input is available independently of the speech plugin status.
  // The host verifies the actual native deny action before widget interaction.
  ai01Stage('AI01-03');
  await native_ui.awaitWithFrames(tester, host('microphone-denied'));
  ai01Stage('AI01-08');
  final field = find.descendant(
    of: find.byType(VoiceSheet),
    matching: find.byType(TextField),
  );
  expect(field, findsOneWidget);
  ai01Stage('AI01-09');
  await tester.enterText(field, text);
  expect(tester.widget<TextField>(field).controller!.text, text);
  final submitDeadline = DateTime.now().add(const Duration(seconds: 25));
  await dismissKeyboard(tester);
  expect(
    tester.widget<TextField>(field).controller!.text == text,
    isTrue,
    reason: 'Native typed assistant input did not survive keyboard closure',
  );
  expect(route.isCurrent, isTrue);
  final removed = route.completed.then<void>((_) {});
  await tap(tester, find.text('Xong'), deadline: submitDeadline);
  ai01Stage('AI01-10');
  await native_ui.awaitWithFrames(
    tester,
    removed,
    timeout: submitDeadline.difference(DateTime.now()),
  );
  expect(find.byType(VoiceSheet), findsNothing);
}

void nativeTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    final semanticsBaseline = tester.binding.debugOutstandingSemanticsHandles;
    try {
      debugPrint('E2E_STAGE native_body');
      await body(tester);
    } finally {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 700));
      final before = tester.binding.debugOutstandingSemanticsHandles;
      final platformBefore = tester.binding.platformDispatcher.semanticsEnabled;
      try {
        await native_ui.waitForSemanticsBaseline(tester, semanticsBaseline);
      } finally {
        debugPrint(
          'E2E_SEMANTICS ${jsonEncode({'baseline': semanticsBaseline, 'before': before, 'after': tester.binding.debugOutstandingSemanticsHandles, 'platformBefore': platformBefore, 'platformAfter': tester.binding.platformDispatcher.semanticsEnabled})}',
        );
      }
    }
  });
}

Future<Map<String, dynamic>> start(
  WidgetTester tester, {
  String type = 'household',
}) async {
  if (!RegExp(r'^homemind-e2e-[a-f0-9]+$').hasMatch(runId) ||
      !(productionSafe
          ? base == 'https://api.homemind.vn/v1' &&
                RegExp(r'^[a-f0-9]{40}$').hasMatch(expectedRevision)
          : ['127.0.0.1', '10.0.2.2'].contains(Uri.parse(base).host))) {
    throw StateError(
      'Native destructive tests require an owned local Docker fixture',
    );
  }
  if (productionSafe) {
    final ready = await http
        .get(Uri.parse('$base/health/ready'))
        .timeout(const Duration(seconds: 15));
    expect(ready.statusCode, 200);
    expect(ready.headers['x-homemind-revision'], expectedRevision);
  }
  debugPrint('E2E_STAGE fixture_empty_frame');
  await tester.pumpWidget(const SizedBox.shrink());
  debugPrint('E2E_STAGE secure_storage_clear');
  await const FlutterSecureStorage().deleteAll();
  debugPrint('E2E_STAGE owned_registration');
  final email = '$runId+n-${nonce().substring(0, 20)}@example.com',
      password = nonce();
  final actor = <String, dynamic>{
    'email': email,
    'password': password,
    'registered': false,
  };
  owned.add(actor);
  await journalOwned();
  final challenge = await request('/auth/register', 'POST', {
    'acceptedTerms': true,
    'acceptedPrivacy': true,
    'displayName': 'E2E Native $type',
    'email': email,
    'password': password,
    'workspaceType': type,
  });
  expect(challenge['accessToken'], isNull);
  late Map delivered;
  await native_ui.awaitWithFrames(tester, () async {
    delivered = await hostResult('email-code');
  }());
  final session = await request('/auth/email/verify', 'POST', {
    'challengeId': challenge['challengeId'],
    'challengeToken': challenge['challengeToken'],
    'purpose': 'REGISTER',
    'code': delivered['code'],
  });
  actor.addAll({...session, 'registered': true});
  await journalOwned();
  final token = session['accessToken'] as String;
  final me = await request('/me', 'GET', null, token);
  actor['ws'] = me['workspaceId'];
  await request('/workspaces/${actor['ws']}/inventory/items', 'POST', {
    'productName': 'Sữa native E2E',
    'quantity': 2,
    'unit': 'hộp',
  }, token);
  for (final name in ['Trứng native E2E', 'Gạo native E2E']) {
    await request('/workspaces/${actor['ws']}/shopping-items', 'POST', {
      'name': name,
      'quantity': 1,
      'unit': 'hộp',
    }, token);
  }
  await app.main();
  await waitFor(tester, find.text('Bỏ qua'));
  await tap(tester, find.text('Bỏ qua'));
  await waitFor(tester, find.byKey(const Key('login_identifier')));
  await fill(tester, 'login_identifier', email);
  await fill(tester, 'login_password', password);
  await dismissKeyboard(tester);
  await tap(tester, find.byKey(const Key('login_submit')));
  await waitFor(tester, find.text('Cá nhân'));
  return actor;
}

Future<void> billingReadOnlyFlow(
  WidgetTester tester,
  Map<String, dynamic> actor,
) async {
  await tap(tester, find.byKey(const Key('nav_profile')));
  final row = find.byKey(const Key('profile_row_plan'));
  expect(row, findsNothing);
  expect(find.byKey(const Key('profile_upgrade')), findsNothing);
  expect(find.text('Xem gói hiện tại'), findsNothing);
  expect(find.byType(ProfilePage), findsOneWidget);
  expect(find.byType(BillingPage), findsNothing);
  await waitForScrolled(
    tester,
    find.byKey(const Key('voice_quota_used_total')),
    find.byType(ProfilePage),
  );
  expect(find.text('0/15'), findsOneWidget);
  expect(find.textContaining('Miễn phí'), findsNothing);
  expect(find.text('Vĩnh viễn'), findsNothing);
  expect(find.text('Lượt trợ lý trong kỳ'), findsOneWidget);
  for (final key in [
    'billing_buy_personal',
    'billing_buy_family',
    'billing_buy_micro_pos',
    'billing_official_qr',
    'billing_transfer_details',
    'billing_countdown',
  ]) {
    expect(find.byKey(Key(key)), findsNothing);
  }
  await host('background-resume');
  expect(find.byType(ProfilePage), findsOneWidget);
  expect(find.byType(BillingPage), findsNothing);
  final token = actor['accessToken'] as String, ws = actor['ws'];
  final catalog = await request('/billing/plans', 'GET', null);
  expect(catalog['checkoutEnabled'], false);
  final history = await request(
    '/workspaces/$ws/billing/payments',
    'GET',
    null,
    token,
  );
  expect(history['checkoutEnabled'], false);
  expect(history['payments'], isEmpty);
  expect((history['entitlement'] as Map)['plan'], 'free');
  final me = await request('/me', 'GET', null, token);
  expect(me['plan'], 'free');
  expect((me['voiceQuota'] as Map)['used'], 0);
  expect((me['voiceQuota'] as Map)['total'], 15);
  expect(find.byKey(const Key('billing_official_qr')), findsNothing);
  expect(find.byKey(const Key('billing_verified')), findsNothing);
}

Future<void> notificationFlow(
  WidgetTester tester,
  Map<String, dynamic> actor,
) async {
  final token = actor['accessToken'] as String, ws = actor['ws'];
  final baseline = await request(
    '/workspaces/$ws/notifications?limit=50',
    'GET',
    null,
    token,
  );
  expect(
    baseline['hasMore'],
    false,
  ); // Fresh owned fixture fits a bounded page.
  final previousProfileIds = (baseline['items'] as List)
      .where((dynamic n) => n['type'] == 'profile.updated')
      .map((dynamic n) => n['id'])
      .toSet();
  for (var i = 0; i < 8; i++) {
    await request('/me', 'PATCH', {
      'displayName': 'Native saved profile $i',
    }, token);
  }
  // Unrelated welcome/inventory/login events cannot prove the eight new
  // profile events have arrived. Keep the normal worker and the existing bound.
  await persisted(
    tester,
    actor,
    '/workspaces/$ws/notifications?limit=50',
    (d) =>
        (d['items'] as List)
            .where(
              (dynamic n) =>
                  n['type'] == 'profile.updated' &&
                  !previousProfileIds.contains(n['id']),
            )
            .length >=
        8,
  );
  final before = await persisted(
    tester,
    actor,
    '/workspaces/$ws/notifications?limit=5',
    (d) => d['hasMore'] == true && (d['unreadCount'] as int) >= 8,
  );
  expect((before['items'] as List).length, lessThanOrEqualTo(5));
  await tester.pumpWidget(const SizedBox.shrink());
  await app.main();
  await waitFor(tester, find.byKey(const Key('home_notifications')));
  await tap(tester, find.byKey(const Key('home_notifications')));
  await waitFor(tester, find.byType(DurableNotificationsSurface));
  final route = ModalRoute.of(
    tester.element(find.byType(DurableNotificationsSurface)),
  )!;
  final id = (before['items'] as List).firstWhere(
    (dynamic n) => n['read'] == false,
  )['id'];
  await tap(tester, find.byKey(Key('durable_notification_$id')));
  await waitFor(tester, find.byKey(const Key('notification_detail')));
  expect(
    ModalRoute.of(tester.element(find.byKey(const Key('notification_detail')))),
    same(route),
  );
  expect(find.byKey(Key('durable_notification_$id')), findsNothing);
  final read = await persisted(
    tester,
    actor,
    '/workspaces/$ws/notifications/$id',
    (d) => d['read'] == true,
  );
  expect(read['readAt'], isNotNull);
  final firstRead = read['readAt'];
  await request('/workspaces/$ws/notifications/$id/read', 'PATCH', null, token);
  expect(
    (await request(
      '/workspaces/$ws/notifications/$id',
      'GET',
      null,
      token,
    ))['readAt'],
    firstRead,
  );
  await tap(tester, find.byTooltip('Quay lại'));
  debugPrint('NOTICE_STAGE detail_back_delivered');
  await waitFor(tester, find.text('Thông báo gần đây'));
  final preview = await request(
    '/workspaces/$ws/notifications?limit=5',
    'GET',
    null,
    token,
  );
  expect(preview['hasMore'], true);
  expect((preview['items'] as List).length, 5);
  debugPrint('NOTICE_STAGE preview_visible_server_more');
  await waitForScrolled(
    tester,
    find.byKey(const Key('notifications_view_all')),
    find.byType(DurableNotificationsSurface),
  );
  debugPrint('NOTICE_STAGE inbox_cta_hit_testable');
  await tap(tester, find.byKey(const Key('notifications_view_all')));
  await waitFor(tester, find.text('Tất cả thông báo'));
  expect(
    ModalRoute.of(tester.element(find.byType(DurableNotificationsSurface))),
    same(route),
  );
  final inbox = await request(
    '/workspaces/$ws/notifications?limit=20',
    'GET',
    null,
    token,
  );
  expect((inbox['items'] as List).length, lessThanOrEqualTo(20));
  await tap(tester, find.byKey(const Key('hub_close')));
  await native_ui.awaitWithFrames(tester, route.completed.then<void>((_) {}));
  expect(route.isActive, false);
  expect(find.byType(DurableNotificationsSurface), findsNothing);
  await tap(tester, find.byKey(const Key('home_search')));
  final field = find.byKey(const Key('global_search_input'));
  await waitFor(tester, field);
  await tester.enterText(field, 'sua native');
  await dismissKeyboard(tester);
  final results = await request(
    '/workspaces/$ws/search?q=sua%20native&filter=inventory&limit=20',
    'GET',
    null,
    token,
  );
  final hit = (results['items'] as List).firstWhere(
    (dynamic x) => x['title'] == 'Sữa native E2E',
  );
  await tap(tester, find.byKey(Key("search_result_inventory_${hit['id']}")));
  await waitFor(tester, find.byType(HubEntityPage));
  expect(find.byType(DurableNotificationsSurface), findsNothing);
  await waitFor(tester, find.text('Sữa native E2E'));
  await back(tester);
  expect(find.byKey(const Key('home_plans')), findsNothing);
  expect(find.byKey(const Key('plan_card_cta')), findsNothing);
  expect(find.byType(BillingPage), findsNothing);
}

Future<void> openSecurity(WidgetTester tester) async {
  await tap(tester, find.byKey(const Key('nav_profile')));
  final row = find.byKey(const Key('profile_security'));
  final scrollable = find.descendant(
    of: find.byType(ProfilePage),
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(row, 350, scrollable: scrollable.first);
  await tap(tester, row);
}

Future<void> accountLifecycle(
  WidgetTester tester,
  Map<String, dynamic> actor,
) async {
  await openSecurity(tester);
  await tap(tester, find.byKey(const Key('account_password')));
  final prior = actor['accessToken'] as String, next = nonce();
  await fill(tester, 'account_current_password', actor['password'] as String);
  await fill(tester, 'account_new_password', next);
  await fill(tester, 'account_confirm_password', next);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 700));
  actor['candidatePassword'] = next;
  await journalOwned();
  await tap(tester, find.byKey(const Key('account_save')));
  await deliveredOtp(tester);
  await waitFor(tester, find.byKey(const Key('login_identifier')));
  actor['password'] = next;
  actor.remove('candidatePassword');
  await journalOwned();
  expect(await responseStatus('/me', 'GET', null, prior), 401);
  actor.addAll(
    await request('/auth/login', 'POST', {
      'identifier': actor['email'],
      'password': next,
    }),
  );
  await loginNative(tester, actor['email'] as String, next);
  await openSecurity(tester);
  await tap(tester, find.byKey(const Key('account_identifiers')));
  final oldEmail = actor['email'],
      email = '$runId+changed-${nonce().substring(0, 12)}@example.com';
  await fill(tester, 'account_email', email);
  await fill(tester, 'account_current_password', next);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 700));
  actor['candidateEmail'] = email;
  await journalOwned();
  await tap(tester, find.byKey(const Key('account_save')));
  await deliveredOtp(tester);
  await deliveredOtp(tester, newEmail: true);
  await waitFor(tester, find.byKey(const Key('login_identifier')));
  expect(
    await responseStatus('/auth/login', 'POST', {
      'identifier': oldEmail,
      'password': next,
    }),
    401,
  );
  actor['email'] = email;
  actor.remove('candidateEmail');
  await journalOwned();
  actor.addAll(
    await request('/auth/login', 'POST', {
      'identifier': email,
      'password': next,
    }),
  );
  expect(
    (await request(
      '/me',
      'GET',
      null,
      actor['accessToken'] as String,
    ))['email'],
    email,
  );
  await loginNative(tester, email, next);
}

Future<void> closeFlow(
  WidgetTester tester,
  Map<String, dynamic> actor, {
  required bool delete,
}) async {
  await openSecurity(tester);
  await tap(
    tester,
    find.byKey(Key(delete ? 'account_delete' : 'account_deactivate')),
  );
  await fill(tester, 'close_password', actor['password'] as String);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 700));
  await tap(tester, find.byKey(const Key('close_submit')));
  await waitFor(tester, find.byType(AlertDialog));
  await tap(tester, find.text('Hủy'));
  expect(
    await responseStatus('/me', 'GET', null, actor['accessToken'] as String),
    200,
  );
  await tap(tester, find.byKey(const Key('close_submit')));
  await tap(tester, find.text('Xác nhận'));
  await waitFor(tester, find.byKey(const Key('login_identifier')));
  expect(
    await responseStatus('/auth/login', 'POST', {
      'identifier': actor['email'],
      'password': actor['password'],
    }),
    403,
  );
  actor['closed'] = true;
  await journalOwned();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (const bool.fromEnvironment('E2E_REAL_PAYOS')) {
    nativeTest('PAYOS-QR real unpaid normal UI', (tester) async {
      const plan = String.fromEnvironment('E2E_PAYOS_PLAN');
      final actor = await start(
        tester,
        type: plan == 'micro_pos' ? 'store' : 'household',
      );
      actor['retained'] = true;
      await journalOwned();
      try {
        await tap(tester, find.byKey(const Key('nav_profile')));
        await tap(tester, find.byKey(const Key('profile_upgrade')));
        final amount = plan == 'micro_pos'
            ? 149000
            : plan == 'family'
            ? 59000
            : 29000;
        await tap(tester, find.byKey(Key('billing_plan_$plan')));
        await tap(tester, find.byKey(Key('billing_buy_$plan')));
        final create = find.text('Tạo đơn thanh toán');
        await waitFor(tester, create);
        await tester.ensureVisible(create.first);
        await tester.pump();
        await host('browser-arm');
        await tester.tap(create.first);
        await Future.wait([
          host('browser-result'),
          tester.pump(const Duration(milliseconds: 400)),
        ]);
        final qr = find.byKey(const Key('billing_official_qr'));
        await waitFor(tester, qr);
        await tester.ensureVisible(qr);
        await tester.pump();
        await host('payos-qr-observe');
        final overview = await request(
          '/workspaces/${actor['ws']}/billing/payments',
          'GET',
          null,
          actor['accessToken'] as String,
        );
        final payments = overview['payments'] as List;
        expect(payments.length, 1);
        final payment = payments.single as Map;
        expect(payment['price']['amount'], amount);
        expect(payment['origin'], 'REAL_PAYOS');
        expect(
          Uri.parse(payment['checkoutUrl'] as String).host,
          'pay.payos.vn',
        );
        expect(payment['financialState'], 'UNPAID');
        expect(
          (await request(
            '/me',
            'GET',
            null,
            actor['accessToken'] as String,
          ))['plan'],
          'free',
        );
        await tap(tester, find.text('Hủy đơn chưa thanh toán'));
        await waitFor(tester, find.text('Đã hủy đơn chưa thanh toán'));
      } finally {
        // Do not orphan an unknown live merchant link by deleting its account.
        final overview = await request(
          '/workspaces/${actor['ws']}/billing/payments',
          'GET',
          null,
          actor['accessToken'] as String,
        );
        final payments = overview['payments'] as List;
        var closed = payments.isEmpty;
        if (payments.length == 1) {
          var payment = payments.single as Map;
          if (payment['financialState'] == 'UNPAID' &&
              !['REVIEW', 'CANCELLED', 'EXPIRED'].contains(payment['status'])) {
            try {
              payment = await request(
                '/workspaces/${actor['ws']}/billing/payments/${payment['id']}/cancel',
                'POST',
                {},
                actor['accessToken'] as String,
              );
            } on StateError {
              /* Retain the owned journal for bounded reconciliation. */
            }
          }
          closed =
              ['CANCELLED', 'EXPIRED'].contains(payment['status']) &&
              payment['amountPaid'] == 0;
        }
        actor['retained'] = !closed;
        await journalOwned();
      }
    });
  }
  nativeTest(
    'PLATFORM-01 tabs, profile edit, language, account dialogs and billing',
    (tester) async {
      final actor = await start(tester);
      await tap(tester, find.byKey(const Key('nav_inventory')));
      await waitFor(tester, find.text('Sữa native E2E'));
      await tap(tester, find.byKey(const Key('nav_shopping')));
      await waitFor(tester, find.text('Trứng native E2E'));
      await tap(tester, find.byKey(const Key('nav_profile')));
      await tap(tester, find.byKey(const Key('profile_row_name')));
      await tester.enterText(
        find.byKey(const Key('profile_edit_field')),
        'E2E Native sửa',
      );
      await tap(tester, find.byKey(const Key('profile_save_button')));
      await waitFor(tester, find.text('E2E Native sửa'));
      final me = await request(
        '/me',
        'GET',
        null,
        actor['accessToken'] as String,
      );
      expect(me['displayName'], 'E2E Native sửa');
      // Contact is independent from login identifier; invalid input must leave
      // the committed server value untouched and retain the editor.
      await tap(tester, find.byKey(const Key('profile_row_phone')));
      await tester.enterText(
        find.byKey(const Key('profile_edit_field')),
        '091+2345678',
      );
      await tap(tester, find.byKey(const Key('profile_save_button')));
      expect(find.byKey(const Key('profile_edit_field')), findsOneWidget);
      expect(
        (await request(
          '/me',
          'GET',
          null,
          actor['accessToken'] as String,
        ))['phone'],
        isNull,
      );
      const contact =
          '091 234 5678'; // synthetic contact in an isolated owned DB
      await tester.enterText(
        find.byKey(const Key('profile_edit_field')),
        contact,
      );
      await tap(tester, find.byKey(const Key('profile_save_button')));
      await waitFor(tester, find.text(contact));
      await tap(tester, find.byKey(const Key('profile_row_address')));
      await tester.enterText(
        find.byKey(const Key('profile_edit_field')),
        'Địa chỉ E2E',
      );
      await tap(tester, find.byKey(const Key('profile_save_button')));
      await waitFor(tester, find.text('Địa chỉ E2E'));
      final committed = await request(
        '/me',
        'GET',
        null,
        actor['accessToken'] as String,
      );
      expect(committed['phone'] == contact, isTrue);
      expect(committed['address'], 'Địa chỉ E2E');
      expect(committed['loginPhone'], isNull);
      await tap(tester, find.byKey(const Key('profile_row_language')));
      await tap(tester, find.byKey(const Key('language_option_en')));
      expect(
        (await request(
          '/me',
          'GET',
          null,
          actor['accessToken'] as String,
        ))['language'],
        'en',
      );
      await tap(tester, find.byKey(const Key('profile_row_language')));
      await tap(tester, find.byKey(const Key('language_option_vi')));
      await tap(tester, find.byKey(const Key('profile_security')));
      await waitFor(tester, find.byKey(const Key('account_password')));
      await tap(tester, find.byKey(const Key('account_password')));
      await waitFor(tester, find.byKey(const Key('account_current_password')));
      await back(tester);
      await tap(tester, find.byKey(const Key('account_identifiers')));
      await waitFor(tester, find.byKey(const Key('account_email')));
      await back(tester);
      await back(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('profile_upgrade')), findsNothing);
      expect(find.byType(BillingPage), findsNothing);
      final logout = find.byKey(const Key('profile_logout'));
      await tester.scrollUntilVisible(
        logout,
        350,
        scrollable: find
            .descendant(
              of: find.byType(ProfilePage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tap(tester, logout);
      await tap(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Đăng xuất'),
        ),
      );
      await waitFor(tester, find.byKey(const Key('login_identifier')));
      await fill(tester, 'login_identifier', actor['email'] as String);
      await fill(tester, 'login_password', actor['password'] as String);
      await dismissKeyboard(tester);
      await tap(tester, find.byKey(const Key('login_submit')));
      await waitFor(tester, find.byKey(const Key('nav_profile')));
      await tap(tester, find.byKey(const Key('nav_profile')));
      await waitFor(tester, find.text(contact));
      expect(find.text('E2E Native sửa'), findsWidgets);
      expect(find.text('Địa chỉ E2E'), findsWidgets);
      // A fresh application root restores secure session and authoritative data.
      // This is not falsely labelled as Android process force-stop/relaunch.
      await tester.pumpWidget(const SizedBox.shrink());
      await app.main();
      await waitFor(tester, find.byKey(const Key('nav_profile')));
      await tap(tester, find.byKey(const Key('nav_profile')));
      await waitFor(tester, find.text(contact));
      await waitForScrolled(
        tester,
        find.text('0/15'),
        find.byType(ProfilePage),
      );
      // Keep the real UI's last known quota stale while another authenticated
      // client consumes the shared workspace ledger. The subsequent ordinary
      // UI submit must reach Nest and publish its authoritative 429 details.
      await tap(tester, find.byKey(const Key('nav_voice')));
      await waitFor(tester, find.byType(VoiceSheet));
      await native_ui.awaitWithFrames(tester, host('microphone-denied'));
      final typed = find.descendant(
        of: find.byType(VoiceSheet),
        matching: find.byType(TextField),
      );
      await tester.enterText(typed, 'Trong nhà còn gì?');
      await dismissKeyboard(tester);
      await native_ui.awaitWithFrames(tester, host('quota-exhaust-owned'));
      await tap(tester, find.text('Xong'));
      await waitFor(tester, find.text('Đã hết lượt trợ lý trong kỳ này.'));
      expect(find.byType(VoiceSheet), findsNothing);
      await waitFor(tester, find.text('15/15'));
      final rejected = await request(
        '/me',
        'GET',
        null,
        actor['accessToken'] as String,
      );
      expect(rejected['voiceQuota'], containsPair('used', 15));
      expect(rejected['voiceQuota'], containsPair('remaining', 0));
      await native_ui.awaitWithFrames(tester, host('background-resume'));
      await waitFor(tester, find.text('15/15'));
      await tap(tester, find.byKey(const Key('nav_voice')));
      await waitFor(
        tester,
        find.text('Gói đang dùng đã hết lượt trợ lý trong kỳ này.'),
      );
      expect(find.byType(VoiceSheet), findsNothing);
      expect(find.byType(SnackBarAction), findsNothing);
      expect(find.text('Xem gói hiện tại'), findsNothing);
      expect(find.byKey(const Key('billing_current')), findsNothing);
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(find.text('15/15'), findsOneWidget);
    },
  );
  nativeTest('PLATFORM-02 shopping search filters actual native rows', (
    tester,
  ) async {
    await start(tester);
    await tap(tester, find.byKey(const Key('nav_shopping')));
    await waitFor(tester, find.text('Trứng native E2E'));
    await tap(tester, find.byIcon(Icons.search_rounded));
    await waitFor(tester, find.byKey(const Key('shopping_search')), seconds: 4);
    await tester.enterText(find.byKey(const Key('shopping_search')), 'Trứng');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Trứng native E2E'), findsOneWidget);
    expect(find.text('Gạo native E2E'), findsNothing);
  });
  nativeTest('PLATFORM-01 store header uses current workspace', (tester) async {
    final actor = await start(tester, type: 'store');
    await tap(tester, find.byKey(const Key('nav_shopping')));
    await waitFor(tester, find.text('Trứng native E2E'));
    final me = await request(
      '/me',
      'GET',
      null,
      actor['accessToken'] as String,
    );
    await waitFor(tester, find.text(me['workspaceName'] as String));
    expect(find.text(me['workspaceName'] as String), findsWidgets);
    expect(find.text('Tạp Hóa Lan Anh'), findsNothing);
  });
  nativeTest('DATA-02 native receive, skip/restore and inventory repurchase', (
    tester,
  ) async {
    final actor = await start(tester);
    final shopping = await request(
      '/workspaces/${actor['ws']}/shopping-items',
      'GET',
      null,
      actor['accessToken'] as String,
    );
    final id = (shopping['items'] as List).firstWhere(
      (p) => p['name'] == 'Trứng native E2E',
    )['id'];
    await tap(tester, find.byKey(const Key('nav_shopping')));
    final card = find.byKey(Key('shopping_item_$id'));
    await tap(tester, find.descendant(of: card, matching: find.text('Bỏ qua')));
    await persisted(
      tester,
      actor,
      '/workspaces/${actor['ws']}/shopping-items?status=skipped',
      (r) => (r['items'] as List).any(
        (p) => p['id'] == id && p['status'] == 'skipped',
      ),
    );
    await tap(tester, find.textContaining('Đã bỏ qua ('));
    await tap(
      tester,
      find.descendant(of: card, matching: find.text('Khôi phục')),
    );
    await persisted(
      tester,
      actor,
      '/workspaces/${actor['ws']}/shopping-items',
      (r) => (r['items'] as List).any(
        (p) => p['id'] == id && p['status'] == 'needed',
      ),
    );
    await tap(tester, find.textContaining('Cần mua ('));
    await tap(tester, find.descendant(of: card, matching: find.text('Đã mua')));
    await waitFor(tester, find.byType(ReceiveSheet));
    await tester.enterText(find.byKey(const Key('receive_quantity')), '0');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 700));
    await tap(tester, find.byKey(const Key('receive_submit')));
    expect(
      find.text(
        'Số lượng chưa đúng (từ 0,001 đến 999.999.999,999; tối đa 3 số thập phân).',
      ),
      findsOneWidget,
    );
    expect(find.byType(ReceiveSheet), findsOneWidget);
    final invalidInventory = await request(
      '/workspaces/${actor['ws']}/inventory',
      'GET',
      null,
      actor['accessToken'] as String,
    );
    expect(
      (invalidInventory['items'] as List).any(
        (item) => item['name'] == 'Trứng native E2E',
      ),
      false,
    );
    // On a live binding, refocusing the same EditableText after unfocus must
    // go through its real tap handler to reopen the native input connection.
    await tap(tester, find.byKey(const Key('receive_quantity')));
    await tester.enterText(find.byKey(const Key('receive_quantity')), '3');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('receive_quantity')))
          .controller!
          .text,
      '3',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    for (var i = 0; i < 30 && tester.view.viewInsets.bottom > 0; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tap(tester, find.byKey(const Key('receive_submit')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(ReceiveSheet), findsNothing);
    final inv = await persisted(
      tester,
      actor,
      '/workspaces/${actor['ws']}/inventory',
      (r) => (r['items'] as List).any(
        (p) => p['name'] == 'Trứng native E2E' && p['quantity'] == 3,
      ),
    );
    final product = (inv['items'] as List).firstWhere(
      (p) => p['name'] == 'Trứng native E2E',
    );
    expect(
      (await request(
        '/workspaces/${actor['ws']}/shopping-items?status=bought',
        'GET',
        null,
        actor['accessToken'] as String,
      ))['items'],
      contains(
        predicate((dynamic p) => p['id'] == id && p['status'] == 'bought'),
      ),
    );
    await tap(tester, find.byKey(const Key('nav_inventory')));
    await tap(
      tester,
      find.descendant(
        of: find.byKey(Key("inventory_item_${product['productId']}")),
        matching: find.text('Đánh dấu Hết'),
      ),
    );
    await waitFor(tester, find.byType(RepurchaseDialog));
    await tap(tester, find.text('Thêm vào danh sách đi chợ'));
    await persisted(
      tester,
      actor,
      '/workspaces/${actor['ws']}/inventory',
      (r) => (r['items'] as List).any(
        (p) => p['productId'] == product['productId'] && p['quantity'] == 0,
      ),
    );
    await persisted(
      tester,
      actor,
      '/workspaces/${actor['ws']}/shopping-items',
      (r) => (r['items'] as List).any(
        (p) => p['name'] == 'Trứng native E2E' && p['status'] == 'needed',
      ),
    );
  });
  nativeTest(
    'AI-01 native typed draft cancel, separate confirm and scoped read',
    (tester) async {
      ai01Active = true;
      final actor = await start(tester);
      ai01Stage('AI01-01');
      ai01Stage('AI01-02');
      await say(tester, 'vừa mua 1 hộp Sữa native cancel');
      await waitFor(tester, find.text('Lưu'));
      await tap(tester, find.text('Huỷ'));
      await tester.pump(const Duration(milliseconds: 500));
      var inv = await request(
        '/workspaces/${actor['ws']}/inventory',
        'GET',
        null,
        actor['accessToken'] as String,
      );
      expect(
        (inv['items'] as List).any((p) => p['name'] == 'Sữa native cancel'),
        false,
      );
      await say(tester, 'vừa mua 1 hộp Sữa native confirm');
      await waitFor(tester, find.text('Lưu'));
      await tap(tester, find.text('Lưu'));
      await waitFor(tester, find.text('Cá nhân'));
      inv = await request(
        '/workspaces/${actor['ws']}/inventory',
        'GET',
        null,
        actor['accessToken'] as String,
      );
      expect(
        (inv['items'] as List)
            .where((p) => p['name'] == 'Sữa native confirm')
            .length,
        1,
      );
      await say(tester, 'Trong kho còn gì?');
      await waitFor(tester, find.text('HomeMind trả lời:'));
      expect(find.textContaining('Trong kho có 2 món'), findsWidgets);
      expect(find.textContaining('Sữa native E2E'), findsWidgets);
      expect(find.textContaining('Sữa native confirm'), findsWidgets);
      ai01Stage('AI01-12');
    },
  );
  nativeTest('AUTH-01 native register and forgot screens are reachable', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await const FlutterSecureStorage().deleteAll();
    await app.main();
    await tap(tester, find.text('Bỏ qua'));
    await tap(tester, find.byKey(const Key('login_forgot')));
    await waitFor(tester, find.byKey(const Key('forgot_identifier')));
    await fill(tester, 'forgot_identifier', '$runId+none@example.com');
    await tap(tester, find.byKey(const Key('forgot_submit')));
    await waitFor(tester, find.byKey(const Key('otp_code')));
    expect(find.byKey(const Key('reset_password')), findsNothing);
    await back(tester);
    await waitFor(
      tester,
      find.text(
        'Nếu tài khoản tồn tại, hướng dẫn đặt lại mật khẩu sẽ được gửi.',
      ),
    );
    expect(find.byKey(const Key('reset_password')), findsNothing);
    await back(tester);
    await tap(tester, find.byKey(const Key('login_register')));
    await waitFor(tester, find.byKey(const Key('register_name')));
    expect(find.byKey(const Key('register_submit')), findsOneWidget);
    expect(
      tester
          .widget<Checkbox>(find.byKey(const Key('register_legal_acceptance')))
          .value,
      false,
    );
    expect(
      tester
          .widget<ElevatedButton>(find.byKey(const Key('register_submit')))
          .onPressed,
      isNull,
    );
    for (final link in ['register_terms_link', 'register_privacy_link']) {
      await host('browser-arm');
      await tap(tester, find.byKey(Key(link)));
      await native_ui.awaitWithFrames(tester, host('browser-result'));
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(const Key('register_legal_acceptance')),
            )
            .value,
        false,
      );
    }
    final email = '$runId+n-${nonce().substring(0, 12)}@example.com',
        password = nonce();
    // This case runs only against the isolated local fixture (no SMS/provider).
    final phone = '091${(random.nextInt(9000000) + 1000000)}';
    final actor = <String, dynamic>{
      'email': email,
      'password': password,
      'registered': false,
    };
    owned.add(actor);
    await journalOwned();
    for (final entry in {
      'register_name': 'E2E UI đăng ký',
      'register_email': email,
      'register_phone': phone,
      'register_password': password,
      'register_confirm': password,
    }.entries) {
      await fill(tester, entry.key, entry.value);
    }
    await dismissKeyboard(tester);
    await tap(tester, find.byKey(const Key('register_legal_acceptance')));
    await tap(tester, find.byKey(const Key('register_submit')));
    await deliveredOtp(tester);
    try {
      await waitFor(tester, find.byKey(const Key('nav_home')));
    } catch (_) {
      debugPrint(
        'E2E_AUTH_REGISTER_DIAGNOSTIC networkError=${find.text('Không kết nối được HomeMind. Vui lòng thử lại.').evaluate().isNotEmpty} confirmationError=${find.text('Mật khẩu xác nhận chưa khớp.').evaluate().isNotEmpty} registerVisible=${find.byKey(const Key('register_submit')).evaluate().isNotEmpty}',
      );
      rethrow;
    }
    final session = await request('/auth/login', 'POST', {
      'identifier': email,
      'password': password,
    });
    final me = await request(
      '/me',
      'GET',
      null,
      session['accessToken'] as String,
    );
    actor.addAll({...session, 'ws': me['workspaceId'], 'registered': true});
    await journalOwned();
    expect(me['displayName'], 'E2E UI đăng ký');
    expect(me['loginPhone'], '+84${phone.substring(1)}');
    expect(me['phone'], me['loginPhone']);
    // Real HTTP/UI consumption-only reads and status-only account closure.
    // This case creates no checkout, even on the isolated synthetic fixture.
    await tap(tester, find.byKey(const Key('nav_profile')));
    expect(find.byKey(const Key('profile_upgrade')), findsNothing);
    expect(find.byType(BillingPage), findsNothing);
    expect(find.byKey(const Key('billing_official_qr')), findsNothing);
    await waitForScrolled(
      tester,
      find.byKey(const Key('voice_quota_used_total')),
      find.byType(ProfilePage),
      requirePointerTarget: false,
    );
    expect(find.byKey(const Key('profile_row_plan')), findsNothing);
    expect(find.textContaining('Miễn phí'), findsNothing);
    expect(find.text('Vĩnh viễn'), findsNothing);
    await closeFlow(tester, actor, delete: true);
    expect(
      await responseStatus('/me', 'GET', null, actor['accessToken'] as String),
      401,
    );
    expect(
      await responseStatus('/auth/refresh', 'POST', {
        'refreshToken': actor['refreshToken'],
      }),
      401,
    );
  });
  nativeTest(
    'NOTICE-01 native durable preview detail inbox and scoped search',
    (tester) async {
      final actor = await start(tester);
      await notificationFlow(tester, actor);
    },
  );
  nativeTest('AUTH-04 native password and identifier submissions', (
    tester,
  ) async {
    final actor = await start(tester);
    await accountLifecycle(tester, actor);
  });
  for (final delete in [false, true]) {
    nativeTest(
      'AUTH-04 native ${delete ? 'delete' : 'deactivate'} confirmation cancel and submit',
      (tester) async {
        final actor = await start(tester);
        await closeFlow(tester, actor, delete: delete);
      },
    );
  }
  nativeTest('PLATFORM-03 actual background resume and API outage recovery', (
    tester,
  ) async {
    await start(tester);
    await host('background-resume');
    await waitFor(tester, find.byKey(const Key('nav_home')));
    await host('offline');
    try {
      await tap(tester, find.byKey(const Key('home_notifications')));
      await waitFor(
        tester,
        find.byKey(const Key('notifications_error')),
        seconds: 50,
      );
      expect(find.byType(DurableNotificationsSurface), findsOneWidget);
      expect(find.byType(BillingPage), findsNothing);
    } finally {
      await host('online');
    }
    await tap(tester, find.byKey(const Key('notifications_retry')));
    await waitFor(tester, find.text('Thông báo gần đây'));
    expect(find.byKey(const Key('notifications_error')), findsNothing);
  });
  nativeTest(
    'BILL-03 native read-only billing preserves plan quota history without checkout',
    (tester) async {
      for (final type in ['household', 'store']) {
        final actor = await start(tester, type: type);
        await billingReadOnlyFlow(tester, actor);
      }
    },
  );
  tearDownAll(() async {
    // Delete through ordinary auth paths (tombstone). Host fixture owner then
    // verifies/removes owned audit rows before destroying the disposable DB.
    await cleanupOwned();
    ai01Stage('AI01-13');
    binding.reportData = {
      'suite': 'native-android',
      'ownedIdentityCount': owned.length,
      'audioTranscription': 'NOT_VERIFIED',
      'provider': const bool.fromEnvironment('E2E_REAL_PAYOS')
          ? 'real payOS unpaid links; no settlement'
          : 'synthetic external transport; real app/backend/database',
    };
  });
}

// End-to-end integration scenario assertion by Tran Gia Phu
