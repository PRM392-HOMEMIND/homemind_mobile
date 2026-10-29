import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemind_mobile/core/config/plan_billing_visibility.dart';
import 'package:homemind_mobile/features/shopping/presentation/shopping_page.dart';
import 'package:homemind_mobile/app/app_shell.dart';
import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';
import 'package:homemind_mobile/features/assistant/presentation/confirm_page.dart';
import 'package:homemind_mobile/features/voice/domain/speech_recognition_service.dart';
import 'package:homemind_mobile/features/voice/presentation/voice_sheet.dart';

import 'support/billing_concealment_scenarios.dart';
import 'support/load_app_fonts.dart';

class _ProductReadService extends ConcealmentService {
  static const reply = 'Trong kho có 1 món: Premium gói trà (2 hộp).';
  @override
  Future<AssistantTurn> turn({
    required String text,
    String inputType = 'voice_transcript',
  }) async => AssistantTurn.fromJson({
    'turnId': 'synthetic-read',
    'kind': 'read_result',
    'message': reply,
    'toolsUsed': [
      {'toolId': 'inventory.list', 'arguments': {}},
    ],
    'data': {
      'items': [
        {'name': 'Premium gói trà', 'quantity': 2, 'unit': 'hộp'},
      ],
    },
  });
}

void main() {
  setUpAll(loadAppFonts);
  test('machine billing messages are concealed too', () {
    for (final text in [
      'BILLING_DISABLED',
      'PAYMENT_NOT_CONFIGURED',
      'PLAN_LIMIT',
      'PAYOS_PROVIDER_ERROR',
    ]) {
      expect(PlanBillingVisibility.isBillingText(text), isTrue, reason: text);
    }
  });
  test('entity labels do not conceal unrelated system billing copy', () {
    const labels = ['Premium gói trà'];
    expect(
      PlanBillingVisibility.isBillingText(
        _ProductReadService.reply,
        preservedValues: labels,
      ),
      isFalse,
    );
    for (final message in [
      'Premium gói trà: vui lòng nâng cấp gói dịch vụ.',
      'Premium gói trà. PAYMENT_NOT_CONFIGURED',
      'Premium gói trà. Mở lịch sử thanh toán.',
    ]) {
      expect(
        PlanBillingVisibility.isBillingText(message, preservedValues: labels),
        isTrue,
        reason: message,
      );
    }
    expect(
      PlanBillingVisibility.entityLabels({
        'items': [
          {'name': 'Premium gói trà'},
        ],
        'message': 'nâng cấp gói',
      }),
      ['Premium gói trà'],
    );
    expect(
      PlanBillingVisibility.isBillingText(
        'payment',
        preservedValues: ['pay', 'a', 'ment'],
      ),
      isTrue,
    );
  });
  testWidgets(
    'ordinary shopping success preserves a product containing Premium',
    (tester) async {
      final service = ConcealmentService();
      await tester.pumpWidget(
        concealmentApp(service, Scaffold(body: ShoppingPage(service: service))),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('shopping_quick_add')),
        'Premium gói trà',
      );
      await tester.tap(find.byKey(const Key('shopping_quick_add_button')));
      await tester.pumpAndSettle();
      expect(
        find.text('Đã thêm "Premium gói trà" vào danh sách cần mua.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'assistant read preserves the complete answer containing a product name',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final service = _ProductReadService();
      await tester.pumpWidget(
        concealmentApp(
          service,
          AppShell(
            assistantService: service,
            speechService: const UnavailableSpeechRecognitionService(),
            profile: service.profile,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_voice')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(VoiceSheet), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(VoiceSheet),
          matching: find.byType(TextField),
        ),
        'Trong kho còn gì?',
      );
      tester.testTextInput.hide();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Xong').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Xong'));
      // The shell's busy indicator continues behind the open result sheet.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('HomeMind trả lời:'), findsOneWidget);
      expect(find.text(_ProductReadService.reply), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('confirmation keeps a summary containing the user product name', (
    tester,
  ) async {
    final service = ConcealmentService();
    final draft = AssistantTurn.fromJson({
      'turnId': 'synthetic-draft',
      'kind': 'write_draft',
      'message': 'Đã tạo bản nháp.',
      'warnings': [
        'Premium gói trà sắp hết hạn.',
        'Premium gói trà: vui lòng nâng cấp gói dịch vụ.',
      ],
      'toolsProposed': [
        {
          'toolId': 'inventory.add',
          'arguments': {
            'productName': 'Premium gói trà',
            'quantity': 2,
            'unit': 'hộp',
          },
        },
      ],
    });
    await tester.pumpWidget(
      concealmentApp(service, ConfirmPage(service: service, draft: draft)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Thêm 2 hộp Premium gói trà'), findsOneWidget);
    expect(find.textContaining('Premium gói trà sắp hết hạn.'), findsOneWidget);
    expect(find.textContaining('vui lòng nâng cấp'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
