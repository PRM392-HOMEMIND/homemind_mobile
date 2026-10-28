import 'package:flutter/material.dart';
import 'package:homemind_mobile/app/homemind_theme.dart';
import 'package:homemind_mobile/core/l10n/app_text.dart';
import 'package:homemind_mobile/features/billing/billing_page.dart';
import 'package:homemind_mobile/features/billing/billing_service.dart';
import 'package:homemind_mobile/features/billing/billing_widgets.dart';

// Presentation fixtures only. No network, provider credentials or valid bank QR.
const visualQr = 'HOMEMIND_PRESENTATION_FIXTURE_NOT_A_PAYMENT';
Map<String, Object?> visualPayment(String status) => {
  'id': 'visual-$status',
  'orderCode': 'DEMO-$status',
  'origin': 'SIMULATED_TEST',
  'status': status,
  'financialState': status == 'PAID' ? 'PAID' : 'UNPAID',
  'fulfillment': status == 'PAID' ? 'GRANTED' : 'NONE',
  'amountPaid': status == 'PAID' ? 29000 : 0,
  'price': {'plan': 'personal', 'amount': 29000, 'currency': 'VND'},
  'createdAt': '2026-10-05T06:30:15Z',
  'expiresAt': '2026-10-05T07:00:15Z',
  'serverNow': '2026-10-05T06:30:15Z',
  if (status == 'PAID') 'paidAt': '2026-10-05T06:32:20Z',
  if (status == 'PAID')
    'grant': {
      'startsAt': '2026-10-05T06:32:20Z',
      'expiresAt': '2026-11-04T06:32:20Z',
    },
  'checkoutUrl': 'https://pay.payos.vn/web/presentation-fixture',
  if (status == 'PENDING')
    'qr': {
      'payload': visualQr,
      'amount': 29000,
      'bin': 'DEMO',
      'accountName': 'DEMO RECEIVER',
      'accountNumber': '0000000000',
      'description': 'DEMO ONLY NO PAYMENT',
    },
};

class VisualBilling implements BillingGateway {
  VisualBilling({
    this.plan = 'free',
    this.withPayment = false,
    this.withHistory = false,
  });
  final String plan;
  final bool withPayment, withHistory;
  int creates = 0, checks = 0, cancels = 0;
  @override
  Future<Map<String, Object?>> plans() async => {
    'checkoutEnabled': true,
    'plans': [
      for (final entry in [('personal', 29000, 60), ('family', 59000, 100)])
        {
          'id': '${entry.$1}-month-v2',
          'plan': entry.$1,
          'amount': entry.$2,
          'voiceLimit': entry.$3,
          'productLimit': null,
          'workspaceTypes': ['household'],
          'durationSeconds': 2592000,
        },
    ],
  };
  @override
  Future<Map<String, Object?>> overview({int offset = 0}) async => {
    'entitlement': {
      'plan': plan,
      'source': plan == 'free' ? 'free' : 'billing',
    },
    'workspaceType': 'household',
    'eligibility': plan == 'family'
        ? {
            'personal': 'PLAN_DOWNGRADE_BLOCKED',
            'family': 'PLAN_ALREADY_ACTIVE',
          }
        : {'personal': null, 'family': null},
    'payments': withHistory
        ? [
            visualPayment('PAID'),
            visualPayment('CANCELLED'),
            visualPayment('PENDING'),
          ]
        : [],
  };
  @override
  Future<Map<String, Object?>?> pending() async =>
      withPayment ? visualPayment('PENDING') : null;
  @override
  Future<Map<String, Object?>> create(String id) async {
    creates++;
    return visualPayment('PENDING');
  }

  @override
  Future<Map<String, Object?>> reconcile(String id) async {
    checks++;
    return visualPayment('PENDING');
  }

  @override
  Future<Map<String, Object?>> cancel(String id) async {
    cancels++;
    return visualPayment('CANCELLED');
  }

  @override
  Future<void> clearPending() async {}
}

Widget visualBillingApp(
  VisualBilling gateway, {
  double scale = 1,
  double? width,
}) => MaterialApp(
  theme: HomeMindTheme.themeData,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(width: width, child: child),
    ),
  ),
  home: BillingPage(
    gateway: gateway,
    refreshEntitlements: () async {},
    launchCheckout: (_) async => true,
    voiceUsage: BillingUsageCard(
      plan: gateway.plan,
      used: gateway.plan == 'family' ? 98 : 3,
      total: gateway.plan == 'family' ? 100 : 15,
      remaining: gateway.plan == 'family' ? 2 : 12,
      expiresAt: DateTime.utc(2026, 11, 4),
    ),
  ),
);

Widget visualComponents({double scale = 1, double? width}) => MaterialApp(
  theme: HomeMindTheme.themeData,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(width: width, child: child),
    ),
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BillingCurrentPlanCard(plan: 'family'),
            BillingUsageCard(
              plan: 'family',
              used: 100,
              total: 100,
              remaining: 0,
              expiresAt: DateTime.utc(2026, 11, 4),
            ),
            BillingPlanCard(
              plan: const {
                'plan': 'personal',
                'amount': 29000,
                'voiceLimit': 60,
              },
              current: false,
              canPurchase: false,
              onPurchase: () => throw StateError('Disabled action fired'),
            ),
            ComingSoonCard(
              title: tr('Gia hạn tự động'),
              description: tr('HomeMind đang hoàn thiện tính năng này'),
              icon: Icons.update_rounded,
            ),
            BillingPaymentCard(
              payment: visualPayment('PENDING'),
              stateText: tr('Đang chờ xác minh — chưa cấp gói'),
              pending: true,
              checkoutEnabled: true,
              busy: false,
              onCheck: () {},
              onOpen: () {},
              onCancel: () {},
            ),
            for (final status in ['PAID', 'CANCELLED', 'PENDING'])
              BillingHistoryCard(
                payment: visualPayment(status),
                stateText: status,
              ),
            const BillingEmptyHistory(),
          ],
        ),
      ),
    ),
  ),
);
