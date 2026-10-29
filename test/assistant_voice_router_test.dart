import 'package:flutter_test/flutter_test.dart';

import 'support/fake_assistant_service.dart';

import 'package:homemind_mobile/features/assistant/domain/assistant_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Assistant Voice Router & Turn Tests', () {
    final service = FakeAssistantService(delay: Duration.zero);

    test('Querying shopping list / cart routes to shopping.list and keeps user input', () async {
      const userSpeech = 'tôi muốn mua đồ , kiểm tra giỏ hàng giúp tôi';
      final turn = await service.turn(text: userSpeech);

      expect(turn.kind, AssistantTurnKind.readResult);
      expect(turn.correctedInput, userSpeech);
      expect(turn.toolsUsed.first.toolId, 'shopping.list');
      expect(turn.message, contains('Trứng'));
    });

    test(
      'Querying expiring products routes to read_expiring and keeps user input',
      () async {
        const userSpeech = 'kiểm tra đồ sắp hết hạn trong nhà';
        final turn = await service.turn(text: userSpeech);

        expect(turn.kind, AssistantTurnKind.readResult);
        expect(turn.correctedInput, userSpeech);
        expect(turn.toolsUsed.first.toolId, 'inventory.expiring');
      },
    );

    test(
      'Adding products routes to write_add draft and keeps user input',
      () async {
        const userSpeech = 'mới mua 2 hộp sữa thêm vào tủ';
        final turn = await service.turn(text: userSpeech);

        expect(turn.kind, AssistantTurnKind.writeDraft);
        expect(turn.correctedInput, userSpeech);
        expect(turn.isWriteDraft, isTrue);
      },
    );

    test('Buying a pack of milk with expiry at end of month correctly routes to inventory.add', () async {
      const userSpeech =
          'tôi vừa mua một lốc sữa hạn sử dụng vào cuối tháng này';
      final turn = await service.turn(text: userSpeech);

      expect(turn.kind, AssistantTurnKind.writeDraft);
      expect(turn.correctedInput, userSpeech);
      expect(turn.isWriteDraft, isTrue);
      expect(turn.toolsProposed.first.toolId, 'inventory.add');

      final args = turn.toolsProposed.first.arguments;
      expect(args['productName'], 'Lốc sữa');
      expect(args['quantity'], 1);
      expect(args['unit'], 'lốc');
      expect(args['category'], 'Sữa & Bơ');
    });
  });
}
