import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart' as plugin;
import 'package:speech_to_text/speech_to_text.dart';

import '../domain/speech_recognition_service.dart';

class NativeSpeechRecognitionService implements SpeechRecognitionService {
  NativeSpeechRecognitionService({SpeechToText? speechToText})
    : _speech = speechToText ?? SpeechToText();

  final SpeechToText _speech;
  String _localeId = 'vi-VN';
  SpeechStatusCallback? _statusCallback;
  SpeechErrorCallback? _errorCallback;

  @override
  bool get isListening => _speech.isListening;

  @override
  Future<SpeechInitialization> initialize() async {
    final available = await _speech.initialize(
      onStatus: _handleStatus,
      onError: _handleError,
      debugLogging: false,
    );

    if (!available) {
      return const SpeechInitialization(
        available: false,
        localeId: 'vi-VN',
        message:
            'Thiết bị không hỗ trợ nhận diện giọng nói hoặc chưa cấp quyền.',
      );
    }

    final locales = await _speech.locales();
    final vietnamese = locales.where((locale) {
      final id = locale.localeId.toLowerCase().replaceAll('_', '-');
      return id == 'vi-vn' || id.startsWith('vi-');
    });
    if (vietnamese.isNotEmpty) {
      _localeId = vietnamese.first.localeId;
    } else {
      final systemLocale = await _speech.systemLocale();
      _localeId = systemLocale?.localeId ?? _localeId;
    }

    return SpeechInitialization(
      available: true,
      localeId: _localeId,
      message: vietnamese.isEmpty
          ? 'Thiết bị chưa có vi-VN; đang dùng locale $_localeId.'
          : null,
    );
  }

  @override
  Future<void> startListening({
    required SpeechResultCallback onResult,
    required SpeechStatusCallback onStatus,
    required SpeechErrorCallback onError,
  }) async {
    _statusCallback = onStatus;
    _errorCallback = onError;
    onStatus(SpeechListeningStatus.listening);

    await _speech.listen(
      onResult: (plugin.SpeechRecognitionResult result) {
        onResult(
          SpeechRecognitionResult(
            text: result.recognizedWords,
            isFinal: result.finalResult,
          ),
        );
      },
      listenOptions: SpeechListenOptions(
        localeId: _localeId,
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: true,
      ),
    );
  }

  void _handleStatus(String status) {
    if (status == SpeechToText.listeningStatus) {
      _statusCallback?.call(SpeechListeningStatus.listening);
    } else if (status == SpeechToText.doneStatus ||
        status == SpeechToText.notListeningStatus) {
      _statusCallback?.call(SpeechListeningStatus.stopped);
    }
  }

  void _handleError(SpeechRecognitionError error) {
    _errorCallback?.call(_friendlyError(error.errorMsg));
    _statusCallback?.call(SpeechListeningStatus.error);
  }

  String _friendlyError(String code) {
    if (code.contains('permission')) {
      return 'HomeMind chưa được cấp quyền microphone. Hãy cấp quyền và thử lại.';
    }
    if (code.contains('network')) {
      return 'Dịch vụ nhận diện đang gặp lỗi mạng. Hãy kiểm tra kết nối và thử lại.';
    }
    if (code.contains('no_match')) {
      return 'Chưa nghe rõ nội dung. Bạn hãy nói lại gần microphone hơn.';
    }
    return 'Không thể nhận diện giọng nói ($code). Hãy thử lại.';
  }

  @override
  Future<void> stopListening() async {
    await _speech.stop();
    _statusCallback?.call(SpeechListeningStatus.stopped);
  }

  @override
  Future<void> cancelListening() async {
    await _speech.cancel();
    _statusCallback?.call(SpeechListeningStatus.stopped);
  }

  @override
  Future<void> dispose() async {
    await _speech.cancel();
  }
}
