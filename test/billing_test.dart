import 'support/restored_plan_billing_ui.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:homemind_mobile/core/config/env_config.dart';
import 'package:homemind_mobile/core/l10n/app_text.dart';
import 'package:homemind_mobile/features/billing/billing_page.dart';
import 'package:homemind_mobile/features/billing/billing_service.dart';
import 'package:homemind_mobile/features/home/presentation/profile_page.dart';
import 'package:homemind_mobile/features/home/presentation/plan_card.dart';
import 'package:homemind_mobile/features/inventory/presentation/inventory_page.dart';
import 'package:homemind_mobile/features/shopping/presentation/shopping_page.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/assistant/presentation/confirm_page.dart';

import 'support/recording_plan_service.dart';

class PaidBillingService extends RecordingPlanService implements BillingSource {
  PaidBillingService() : super(plan: 'personal');
  @override
  final BillingGateway billing = FakeBilling();
  @override
  Future<void> refreshBillingEntitlements() async {}
}

class FakeBilling implements BillingGateway {
  Map<String, Object?>? payment;
  int reconciles = 0;
  @override
  Future<Map<String, Object?>> plans() async => {
    'checkoutEnabled': true,
    'plans': [
      {
        'id': 'personal-month-v2',
        'plan': 'personal',
        'amount': 29000,
        'productLimit': null,
        'workspaceTypes': ['household'],
        'durationSeconds': 2592000,
        'voiceLimit': 60,
      },
    ],
  };
  @override
  Future<Map<String, Object?>> overview({int offset = 0}) async => {
    'entitlement': {'plan': 'free', 'source': 'free'},
    'workspaceType': 'household',
    'eligibility': {
      'personal': null,
      'family': null,
      'micro_pos': 'PLAN_SEGMENT_MISMATCH',
    },
    'payments': [],
  };
  @override
  Future<Map<String, Object?>> create(String id) async => payment!;
  @override
  Future<Map<String, Object?>?> pending() async => payment;
  @override
  Future<Map<String, Object?>> reconcile(String id) async {
    reconciles++;
    return payment!;
  }

  @override
  Future<Map<String, Object?>> cancel(String id) async => {
    'id': id,
    'status': 'CANCELLED',
    'financialState': 'UNPAID',
    'fulfillment': 'NONE',
  };
  @override
  Future<void> clearPending() async {}
}

class BillingEntryService extends PaidBillingService {
  BillingEntryService() {
    plan = 'free';
    used = 30;
  }
  @override
  Future<List<InventoryItem>> getInventory() async => const [];
  @override
  Future<({List<ShoppingItem> items, List<Map<String, Object?>> suggestions})>
  getShoppingList() async => (
    items: const [
      ShoppingItem(
        id: 'owned-shopping',
        name: 'Owned new product',
        quantity: 1,
        unit: 'hộp',
        status: 'needed',
        source: 'manual',
      ),
    ],
    suggestions: const <Map<String, Object?>>[],
  );
}

class RecoveringBilling extends FakeBilling {
  bool offline = true;
  @override
  Future<Map<String, Object?>> plans() {
    if (offline) return Future.error(StateError('API unavailable'));
    return super.plans();
  }
}

Future<void> expectDisabledCreates({
  bool saved = false,
  bool foreignIdentity = false,
  List<String> prices = const ['personal-month-v2'],
}) async {
  const pendingKey = 'homemind.billing.pending.a.x';
  FlutterSecureStorage.setMockInitialValues({
    'homemind.billing.pending.b.y': 'preserve-other-owner',
    if (saved)
      pendingKey: jsonEncode({
        'priceId': 'personal-month-v2',
        'key': '11111111-1111-4111-8111-111111111111',
      }),
  });
  var sends = 0;
  final service = RemoteBillingService(
    userId: 'a',
    workspaceId: 'x',
    externalBillingAllowed: () => true,
    isCurrentIdentity: () async => !foreignIdentity,
    request: (m, p, {body, idempotencyKey}) async {
      sends++;
      throw StateError('Transport must not be reached');
    },
  );
  await Future.wait(
    prices.map((price) => expectLater(service.create(price), throwsStateError)),
  );
  if (foreignIdentity) {
    await expectLater(service.pending(), throwsStateError);
  } else {
    expect(await service.pending(), isNull);
  }
  expect(sends, 0);
  final storage = await const FlutterSecureStorage().readAll();
  expect(storage[pendingKey], isNull);
  expect(storage['homemind.billing.pending.b.y'], 'preserve-other-owner');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    AppText.setLanguage('vi', persist: false);
  });
  tearDown(() => AppText.setLanguage('vi', persist: false));
  for (final locale in ['vi', 'en']) {
    testWidgets(
      '$locale old pending QR and copy controls are absent at 320px/text200',
      (tester) async {
        AppText.setLanguage(locale, persist: false);
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final copies = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copies.add((call.arguments as Map)['text'] as String);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final gateway = FakeBilling()
          ..payment = {
            'id': 'owned-copy',
            'orderCode': 'owned-copy',
            'status': 'PENDING',
            'financialState': 'UNPAID',
            'fulfillment': 'NONE',
            'createdAt': '2026-10-05T07:25:30Z',
            'expiresAt': '2026-10-05T08:25:30Z',
            'serverNow': '2026-10-05T07:55:30Z',
            'amountPaid': 0,
            'qr': {
              'payload': 'OWNED_SYNTHETIC_COPY_TEST_ONLY',
              'amount': 29000,
              'accountName': 'Owned receiver',
              'accountNumber': '0000000000',
              'description': 'OWNEDMEMO',
              'bin': '970422',
            },
          };
        await tester.pumpRestoredPlanBillingWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: BillingPage(
              gateway: gateway,
              refreshEntitlements: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('billing_transfer_details')), findsNothing);
        expect(find.byKey(const Key('billing_official_qr')), findsNothing);
        expect(find.byKey(const Key('billing_countdown')), findsNothing);
        expect(find.textContaining('OWNEDMEMO'), findsNothing);
        expect(copies, isEmpty);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('billing_verified')), findsNothing);
        await tester.pumpRestoredPlanBillingWidget(const SizedBox.shrink());
      },
    );
  }
  for (final entry in ['home', 'inventory', 'shopping', 'confirm']) {
    testWidgets(
      '$entry upgrade with the production BillingSource contract opens BillingPage without legacy acknowledgement',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final service = BillingEntryService();
        final home = await service.getHomeSummary();
        final Widget page = switch (entry) {
          'home' => PlanCard(home: home, service: service, isMerchant: false),
          'inventory' => InventoryPage(service: service),
          'shopping' => ShoppingPage(service: service),
          _ => ConfirmPage(
            service: service,
            draft: AssistantTurn.fromJson({
              'turnId': 'owned-draft',
              'kind': 'write_draft',
              'toolsProposed': [
                {
                  'toolId': 'inventory.add',
                  'arguments': {
                    'productName': 'Owned new product',
                    'quantity': 1,
                    'unit': 'hộp',
                  },
                },
              ],
            }),
          ),
        };
        await tester.pumpRestoredPlanBillingWidget(
          MaterialApp(home: Scaffold(body: page)),
        );
        await tester.pumpAndSettle();
        final action = switch (entry) {
          'home' => find.byKey(const Key('plan_card_cta')),
          'inventory' => find.text('Xem gói hiện tại'),
          'shopping' => find.text('Đã mua').first,
          _ => find.text('Xem gói hiện tại'),
        };
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(find.byType(BillingPage), findsOneWidget);
        expect(find.byKey(const Key('billing_current')), findsOneWidget);
        expect(find.byKey(const Key('billing_current')), findsOneWidget);
        expect(find.byKey(const Key('billing_buy_personal')), findsNothing);
        expect(service.calls, isEmpty);
        expect(find.textContaining('Đã ghi nhận'), findsNothing);
        await tester.pumpRestoredPlanBillingWidget(const SizedBox.shrink());
      },
    );
  }
  const pendingKey = 'homemind.billing.pending.a.x';
  const validKey = '11111111-1111-4111-8111-111111111111';
  const validId = '22222222-2222-4222-8222-222222222222';
  final invalidSaved = <Object?>[
    {},
    {'priceId': 'unknown-plan', 'key': validKey},
    [],
    null,
    {'priceId': 'personal-month-v2'},
    {'priceId': 4, 'key': validKey},
    {'priceId': '../foreign', 'key': validKey},
    {'priceId': 'personal-month-v2', 'key': false},
    {'priceId': 'personal-month-v2', 'key': 'invalid'},
    {'priceId': 'personal-month-v2', 'key': validKey, 'id': null},
    {'priceId': 'personal-month-v2', 'key': validKey, 'id': false},
    {'priceId': 'personal-month-v2', 'key': validKey, 'id': '../../foreign'},
  ];
  for (var i = 0; i < invalidSaved.length; i++) {
    test(
      'invalid saved billing contract $i is cleared without a request or foreign-key deletion',
      () async {
        FlutterSecureStorage.setMockInitialValues({
          pendingKey: jsonEncode(invalidSaved[i]),
          'homemind.billing.pending.b.y': 'preserve-other-owner',
        });
        int requests = 0;
        final service = RemoteBillingService(
          userId: 'a',
          workspaceId: 'x',
          request: (m, p, {body, idempotencyKey}) async {
            requests++;
            return {};
          },
        );
        expect(await service.pending(), isNull);
        expect(requests, 0);
        final saved = await const FlutterSecureStorage().readAll();
        expect(saved.containsKey(pendingKey), false);
        expect(saved['homemind.billing.pending.b.y'], 'preserve-other-owner');
      },
    );
  }
  test('valid saved payment is cleared without reviving a checkout', () async {
    FlutterSecureStorage.setMockInitialValues({
      pendingKey: jsonEncode({
        'priceId': 'personal-month-v2',
        'key': validKey,
        'id': validId,
      }),
    });
    final service = RemoteBillingService(
      userId: 'a',
      workspaceId: 'x',
      request: (m, p, {body, idempotencyKey}) async {
        expect(m, 'GET');
        expect(p, '/workspaces/x/billing/payments/$validId');
        expect(body, isNull);
        return {'id': validId};
      },
    );
    expect(await service.pending(), isNull);
    expect(await const FlutterSecureStorage().read(key: pendingKey), isNull);
  });
  test('Micro-POS saved price follows the backend contract', () async {
    FlutterSecureStorage.setMockInitialValues({
      pendingKey: jsonEncode({
        'priceId': 'micro_pos-month-v2',
        'key': validKey,
        'id': validId,
      }),
    });
    final service = RemoteBillingService(
      userId: 'a',
      workspaceId: 'x',
      request: (m, p, {body, idempotencyKey}) async {
        expect(m, 'GET');
        return {'id': validId};
      },
    );
    expect(await service.pending(), isNull);
    expect(await const FlutterSecureStorage().read(key: pendingKey), isNull);
  });
  test(
    'store release discards a pre-ID purchase intent without resuming checkout',
    () async {
      final saved = jsonEncode({
        'priceId': 'personal-month-v2',
        'key': validKey,
      });
      FlutterSecureStorage.setMockInitialValues({pendingKey: saved});
      var sends = 0;
      final service = RemoteBillingService(
        userId: 'a',
        workspaceId: 'x',
        externalBillingAllowed: () =>
            EnvConfig.externalBillingAllowedFor(debug: false),
        request: (m, p, {body, idempotencyKey}) async {
          sends++;
          return {};
        },
      );
      expect(await service.pending(), isNull);
      expect(sends, 0);
      expect(await const FlutterSecureStorage().read(key: pendingKey), isNull);
      await expectLater(service.create('personal-month-v2'), throwsStateError);
      expect(sends, 0);
      expect(await const FlutterSecureStorage().read(key: pendingKey), isNull);
    },
  );
  test('store release cannot revive an existing cached order', () async {
    FlutterSecureStorage.setMockInitialValues({
      pendingKey: jsonEncode({
        'priceId': 'personal-month-v2',
        'key': validKey,
        'id': validId,
      }),
    });
    final methods = <String>[];
    final service = RemoteBillingService(
      userId: 'a',
      workspaceId: 'x',
      externalBillingAllowed: () =>
          EnvConfig.externalBillingAllowedFor(debug: false),
      request: (m, p, {body, idempotencyKey}) async {
        methods.add(m);
        expect(p, '/workspaces/x/billing/payments/$validId');
        return {'id': validId};
      },
    );
    expect(await service.pending(), isNull);
    expect(methods, isEmpty);
    expect(await const FlutterSecureStorage().read(key: pendingKey), isNull);
  });
  for (final policy in ['debug', 'direct']) {
    test('$policy applies channel policy to intent recovery', () async {
      FlutterSecureStorage.setMockInitialValues({
        pendingKey: jsonEncode({
          'priceId': 'personal-month-v2',
          'key': validKey,
        }),
      });
      final methods = <String>[];
      final service = RemoteBillingService(
        userId: 'a',
        workspaceId: 'x',
        externalBillingAllowed: () => EnvConfig.externalBillingAllowedFor(
          debug: policy == 'debug',
          distribution: policy == 'direct' ? 'direct' : 'store',
        ),
        request: (m, p, {body, idempotencyKey}) async {
          methods.add(m);
          if (m == 'POST') expect(idempotencyKey, validKey);
          return {'id': validId};
        },
      );
      if (!EnvConfig.externalBillingAllowed ||
          !EnvConfig.externalBillingAllowedFor(
            debug: policy == 'debug',
            distribution: policy == 'direct' ? 'direct' : 'store',
          )) {
        expect(await service.pending(), isNull);
        await expectLater(
          service.create('personal-month-v2'),
          throwsStateError,
        );
        expect(methods, isEmpty);
      } else {
        expect((await service.pending())!['unresolvedIntent'], true);
        expect(methods, isEmpty);
        expect((await service.create('personal-month-v2'))['id'], validId);
        expect(await service.pending(), isNull);
        expect(
          await const FlutterSecureStorage().read(key: pendingKey),
          isNull,
        );
        expect(methods, ['POST', 'GET']);
      }
    });
  }
  for (final locale in ['vi', 'en']) {
    testWidgets(
      'billing catalog and confirmation respect $locale without creating on cancel',
      (tester) async {
        AppText.setLanguage(locale, persist: false);
        final english = locale == 'en';
        await tester.pumpRestoredPlanBillingWidget(
          MaterialApp(
            home: BillingPage(
              gateway: FakeBilling(),
              refreshEntitlements: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(english ? 'Plans & billing' : 'Gói & thanh toán'),
          findsOneWidget,
        );
        expect(find.text(english ? 'Free' : 'Miễn phí'), findsOneWidget);
        expect(find.byKey(const Key('billing_plan_personal')), findsNothing);
        expect(find.byKey(const Key('billing_buy_personal')), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          find.textContaining(
            english
                ? 'Plan payments are currently unavailable'
                : 'Thanh toán gói hiện chưa được hỗ trợ',
          ),
          findsOneWidget,
        );
        await tester.pumpRestoredPlanBillingWidget(const SizedBox.shrink());
      },
    );
    testWidgets('pending payment status and actions respect $locale', (
      tester,
    ) async {
      AppText.setLanguage(locale, persist: false);
      final english = locale == 'en';
      final gateway = FakeBilling()
        ..payment = {
          'id': validId,
          'orderCode': 123,
          'serverNow': DateTime.now().toUtc().toIso8601String(),
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 30))
              .toIso8601String(),
          'amountPaid': 0,
          'status': 'PENDING',
          'financialState': 'UNPAID',
          'fulfillment': 'NONE',
        };
      await tester.pumpRestoredPlanBillingWidget(
        MaterialApp(
          home: BillingPage(gateway: gateway, refreshEntitlements: () async {}),
        ),
      );
      await tester.pumpAndSettle();
      final receipt = find.byKey(Key('billing_history_$validId'));
      await tester.scrollUntilVisible(receipt, 200);
      await tester.tapAt(tester.getTopLeft(receipt) + const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(
        find.text(
          english
              ? 'Awaiting verification — plan not activated'
              : 'Đang chờ xác minh — chưa cấp gói',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('billing_transfer_details')), findsNothing);
      expect(find.byKey(const Key('billing_countdown')), findsNothing);
      expect(
        find.text(english ? 'Check status' : 'Kiểm tra trạng thái'),
        findsNothing,
      );
      expect(
        find.text(english ? 'Cancel unpaid order' : 'Hủy đơn chưa thanh toán'),
        findsNothing,
      );
      expect(gateway.reconciles, 0);
      expect(find.byKey(const Key('billing_verified')), findsNothing);
      await tester.pumpRestoredPlanBillingWidget(const SizedBox.shrink());
    });
  }
  testWidgets('successful billing retry clears the prior connectivity error', (
    tester,
  ) async {
    final gateway = RecoveringBilling();
    await tester.pumpRestoredPlanBillingWidget(
      MaterialApp(
        home: BillingPage(gateway: gateway, refreshEntitlements: () async {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('billing_error')), findsOneWidget);
    gateway.offline = false;
    await tester.tap(find.text('Tải lại'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('billing_current')), findsOneWidget);
    expect(find.byKey(const Key('billing_buy_personal')), findsNothing);
    expect(find.byKey(const Key('billing_error')), findsNothing);
  });
  testWidgets('paid profile opens billing history and renewal page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = PaidBillingService();
    await tester.pumpRestoredPlanBillingWidget(
      MaterialApp(
        home: ProfilePage(service: service, user: await service.getMe()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('profile_row_plan')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile_row_plan')));
    await tester.pumpAndSettle();
    expect(find.byType(BillingPage), findsOneWidget);
    expect(find.text('Lịch sử thanh toán'), findsOneWidget);
    await tester.pumpRestoredPlanBillingWidget(const SizedBox.shrink());
  });
  test('account switch during create cannot persist another identity pending intent', () async {
    bool current = true;
    Future<Map<String, Object?>> request(
      String m,
      String p, {
      Map<String, Object?>? body,
      String? idempotencyKey,
    }) async {
      current = false;
      return {'id': 'old-account-order'};
    }

    final service = RemoteBillingService(
      request: request,
      userId: 'old',
      workspaceId: 'old-workspace',
      isCurrentIdentity: () async => current,
    );
    await expectLater(service.create('personal-month-v2'), throwsStateError);
    expect(
      (await const FlutterSecureStorage().readAll()).keys.where(
        (key) => key.startsWith('homemind.billing.pending.'),
      ),
      isEmpty,
    );
  });
  test('restart cannot retry a disabled purchase or generate an idempotency request', () async {
    await expectDisabledCreates(
      saved: true,
      prices: ['personal-month-v2', 'personal-month-v2'],
    );
  });
  test(
    'disabled intent cannot transfer to another user or workspace',
    () async {
      await expectDisabledCreates(saved: true, foreignIdentity: true);
    },
  );
  test('concurrent taps send zero create requests', () async {
    await expectDisabledCreates(prices: List.filled(6, 'personal-month-v2'));
  });
  test('different prices cannot bypass payment-disabled policy', () async {
    await expectDisabledCreates(
      prices: ['personal-month-v2', 'family-month-v2', 'micro_pos-month-v2'],
    );
  });
  test(
    'persisted resume and repeated create remain blocked with zero POST',
    () async {
      await expectDisabledCreates(
        saved: true,
        prices: ['personal-month-v2', 'personal-month-v2', 'family-month-v2'],
      );
    },
  );
  test('direct distribution allows external billing while store remains disabled', () {
    expect(EnvConfig.externalBillingAllowedFor(debug: false), false);
    expect(
      EnvConfig.externalBillingAllowedFor(debug: false, distribution: 'direct'),
      true,
    );
    expect(
      EnvConfig.externalBillingAllowedFor(
        debug: false,
        distribution: 'untrusted',
      ),
      false,
    );
  });
  test('checkout launch only accepts official HTTPS merchant page', () {
    for (final url in [
      'http://pay.payos.vn/a',
      'https://pay.payos.vn.evil.test/a',
      'https://user@pay.payos.vn/a',
      'https://pay.payos.vn:444/a',
      'javascript:alert(1)',
    ]) {
      expect(() => billingCheckoutUri(url), throwsStateError);
    }
    expect(
      () => billingCheckoutUri('https://pay.payos.vn/web/owned'),
      throwsStateError,
    );
  });
  testWidgets(
    'pending checkout never claims activation; polling stops on dispose',
    (tester) async {
      final service = FakeBilling()
        ..payment = {
          'id': 'owned',
          'orderCode': 'owned',
          'amountPaid': 0,
          'status': 'PENDING',
          'financialState': 'UNPAID',
          'fulfillment': 'NONE',
        };
      int refreshes = 0;
      await tester.pumpRestoredPlanBillingWidget(
        MaterialApp(
          home: BillingPage(
            gateway: service,
            refreshEntitlements: () async {
              refreshes++;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const Key('billing_history_owned')),
        300,
      );
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const Key('billing_history_owned'))) +
            const Offset(20, 20),
      );
      await tester.pumpAndSettle();
      expect(find.text('Đang chờ xác minh — chưa cấp gói'), findsOneWidget);
      expect(find.byKey(const Key('billing_verified')), findsNothing);
      expect(refreshes, 0);
      await tester.pumpRestoredPlanBillingWidget(const SizedBox());
      final before = service.reconciles;
      await tester.pump(const Duration(minutes: 1));
      expect(service.reconciles, before);
    },
  );
  testWidgets('paid review has honest money status without activation', (
    tester,
  ) async {
    final service = FakeBilling()
      ..payment = {
        'id': 'owned',
        'orderCode': 'owned',
        'amountPaid': 30000,
        'status': 'PAID',
        'financialState': 'PAID',
        'fulfillment': 'REVIEW',
      };
    int refreshes = 0;
    await tester.pumpRestoredPlanBillingWidget(
      MaterialApp(
        home: BillingPage(
          gateway: service,
          refreshEntitlements: () async {
            refreshes++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('billing_history_owned')),
      300,
    );
    await tester.tapAt(
      tester.getTopLeft(find.byKey(const Key('billing_history_owned'))) +
          const Offset(20, 20),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Đã ghi nhận tiền — chờ kiểm tra trước khi cấp gói'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('billing_verified')), findsNothing);
    expect(refreshes, 0);
  });
  testWidgets(
    'activation requires both verified paid and granted; refreshes application data',
    (tester) async {
      final service = FakeBilling()
        ..payment = {
          'id': 'owned',
          'orderCode': 'owned',
          'amountPaid': 29000,
          'status': 'PAID',
          'financialState': 'PAID',
          'fulfillment': 'GRANTED',
        };
      int refreshes = 0;
      await tester.pumpRestoredPlanBillingWidget(
        MaterialApp(
          home: BillingPage(
            gateway: service,
            refreshEntitlements: () async {
              refreshes++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('billing_verified')), findsOneWidget);
      expect(refreshes, 1);
    },
  );
}
