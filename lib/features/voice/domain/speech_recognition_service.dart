enum SpeechListeningStatus { ready, listening, stopped, unavailable, error }

class SpeechInitialization {
  const SpeechInitialization({
    required this.available,
    required this.localeId,
    this.message,
  });

  final bool available;
  final String localeId;
  final String? message;
}

class SpeechRecognitionResult {
  const SpeechRecognitionResult({required this.text, required this.isFinal});

  final String text;
  final bool isFinal;
}

typedef SpeechResultCallback = void Function(SpeechRecognitionResult result);
typedef SpeechStatusCallback = void Function(SpeechListeningStatus status);
typedef SpeechErrorCallback = void Function(String message);

abstract interface class SpeechRecognitionService {
  bool get isListening;

  Future<SpeechInitialization> initialize();

  Future<void> startListening({
    required SpeechResultCallback onResult,
    required SpeechStatusCallback onStatus,
    required SpeechErrorCallback onError,
  });

  Future<void> stopListening();
  Future<void> cancelListening();
  Future<void> dispose();
}

class UnavailableSpeechRecognitionService implements SpeechRecognitionService {
  const UnavailableSpeechRecognitionService();

  @override
  bool get isListening => false;

  @override
  Future<SpeechInitialization> initialize() async => const SpeechInitialization(
    available: false,
    localeId: 'vi-VN',
    message: 'Nền tảng này chưa hỗ trợ nhận diện giọng nói.',
  );

  @override
  Future<void> startListening({
    required SpeechResultCallback onResult,
    required SpeechStatusCallback onStatus,
    required SpeechErrorCallback onError,
  }) async {
    onStatus(SpeechListeningStatus.unavailable);
  }

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> cancelListening() async {}

  @override
  Future<void> dispose() async {}
}

// Handled by Tran Gia Phu
