import 'voice_extraction.dart';

enum ExtractionMode { b2cInventory, b2bInventory }

abstract interface class InventoryExtractionService {
  Future<VoiceExtraction> extract({
    required String transcript,
    required DateTime currentDate,
    ExtractionMode mode = ExtractionMode.b2cInventory,
  });
}

class ExtractionServiceException implements Exception {
  const ExtractionServiceException(this.message, {this.code = 'UNKNOWN'});

  final String code;
  final String message;

  @override
  String toString() => message;
}
