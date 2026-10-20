import 'package:flutter/material.dart';

import '../../../core/config/plan_billing_visibility.dart';

import '../domain/inventory_extraction_service.dart';
import '../domain/speech_recognition_service.dart';
import '../domain/voice_extraction.dart';

enum _VoiceView { capture, processing, confirmation, success }

class VoiceTestPage extends StatefulWidget {
  const VoiceTestPage({
    required this.speechService,
    this.extractionService,
    super.key,
  });

  final SpeechRecognitionService speechService;
  final InventoryExtractionService? extractionService;

  @override
  State<VoiceTestPage> createState() => _VoiceTestPageState();
}

class _VoiceTestPageState extends State<VoiceTestPage>
    with SingleTickerProviderStateMixin {
  bool _initializing = true;
  bool _available = false;
  bool _listening = false;
  String _localeId = 'vi-VN';
  String _transcript = '';
  String? _message;
  _VoiceView _view = _VoiceView.capture;
  VoiceExtraction? _extraction;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.92,
      upperBound: 1.08,
    );
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final result = await widget.speechService.initialize();
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _available = result.available;
        _localeId = result.localeId;
        _message = result.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _available = false;
        _message = 'Không thể khởi tạo nhận diện giọng nói: $error';
      });
    }
  }

  Future<void> _toggleListening() async {
    if (!_available || _view != _VoiceView.capture) return;
    if (_listening) {
      await widget.speechService.stopListening();
      return;
    }
    setState(() => _message = null);
    await widget.speechService.startListening(
      onResult: (result) {
        if (!mounted) return;
        setState(() => _transcript = result.text);
      },
      onStatus: (status) {
        if (!mounted) return;
        final listening = status == SpeechListeningStatus.listening;
        setState(() => _listening = listening);
        if (listening) {
          _pulseController.repeat(reverse: true);
        } else {
          _pulseController.stop();
          _pulseController.value = 1;
        }
      },
      onError: (message) {
        if (!mounted) return;
        setState(() {
          _message = message;
          _listening = false;
        });
      },
    );
  }

  Future<void> _analyze() async {
    final service = widget.extractionService;
    if (service == null || _transcript.trim().isEmpty) return;
    if (_listening) await widget.speechService.stopListening();
    setState(() {
      _view = _VoiceView.processing;
      _message = null;
    });
    try {
      final result = await service.extract(
        transcript: _transcript,
        currentDate: DateTime.now(),
      );
      if (!mounted) return;
      setState(() {
        _extraction = result;
        _view = _VoiceView.confirmation;
      });
    } on ExtractionServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _view = _VoiceView.capture;
        _message = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _view = _VoiceView.capture;
        _message = 'Không thể phân tích dữ liệu. Hãy thử lại.';
      });
    }
  }

  void _clearTranscript() => setState(() {
    _transcript = '';
    _message = null;
    _extraction = null;
    _view = _VoiceView.capture;
  });

  void _retake() => setState(() {
    _transcript = '';
    _message = null;
    _extraction = null;
    _view = _VoiceView.capture;
  });

  @override
  void dispose() {
    _pulseController.dispose();
    widget.speechService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return switch (_view) {
      _VoiceView.processing => _buildProcessing(),
      _VoiceView.confirmation => _buildConfirmation(_extraction!),
      _VoiceView.success => _buildSuccess(),
      _VoiceView.capture => _buildCapture(),
    };
  }

  Widget _shell(Widget child) => Scaffold(
    body: SafeArea(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE8F8EF), Color(0xFFF7F8FA)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildCapture() {
    final theme = Theme.of(context);
    final statusText = _initializing
        ? 'Đang chuẩn bị...'
        : !_available
        ? 'Chưa sẵn sàng'
        : _listening
        ? 'Đang nghe...'
        : 'Sẵn sàng — Tiếng Việt ($_localeId)';
    return _shell(
      Column(
        children: [
          const Icon(
            Icons.inventory_2_rounded,
            color: Color(0xFF1B8450),
            size: 42,
          ),
          const SizedBox(height: 12),
          Text(
            'HomeMind Voice Test',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1F2933),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Bấm mic và nói thông tin tồn kho. Chữ sẽ cập nhật theo thời gian thực.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: const Color(0xFF4B5563),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 28),
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) => Transform.scale(
                      scale: _listening ? _pulseController.value : 1,
                      child: child,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _listening
                            ? const Color(0xFFFFE8E8)
                            : const Color(0xFFE8F8EF),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x382FBF71),
                            blurRadius: 24,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: IconButton(
                        key: const Key('microphoneButton'),
                        tooltip: _listening ? 'Dừng nghe' : 'Bắt đầu nghe',
                        onPressed: _initializing || !_available
                            ? null
                            : _toggleListening,
                        iconSize: 46,
                        padding: const EdgeInsets.all(22),
                        color: _listening
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF2FBF71),
                        icon: Icon(
                          _listening ? Icons.stop_rounded : Icons.mic_rounded,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    statusText,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: _listening
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF1B8450),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 130),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FA),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Text(
                      _transcript.isEmpty
                          ? 'Bấm mic rồi nói, ví dụ: “Tôi vừa mua hai hộp sữa chua, hạn bảy ngày”.'
                          : _transcript,
                      key: const Key('transcriptText'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: _transcript.isEmpty
                            ? const Color(0xFF6B7280)
                            : const Color(0xFF1F2933),
                        height: 1.5,
                      ),
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF5D6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        PlanBillingVisibility.message(context, _message!),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (widget.extractionService != null)
                    FilledButton.icon(
                      key: const Key('analyzeButton'),
                      onPressed: _transcript.trim().isEmpty ? null : _analyze,
                      icon: const Icon(Icons.auto_awesome),
                      label: Text(
                        _message == null
                            ? 'Phân tích bằng AI'
                            : 'Thử phân tích lại',
                      ),
                    ),
                  TextButton.icon(
                    key: const Key('clearTranscriptButton'),
                    onPressed: _transcript.isEmpty ? null : _clearTranscript,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Xóa và thử lại'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'M1 development · AI tạo bản nháp, người dùng luôn xác nhận trước khi lưu.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessing() => _shell(
    const Column(
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 24),
        Text(
          'HomeMind AI đang phân tích...',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 8),
        Text('Đang nhận diện sản phẩm, số lượng và hạn sử dụng'),
      ],
    ),
  );

  Widget _buildConfirmation(VoiceExtraction extraction) => _shell(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.auto_awesome, color: Color(0xFF2FBF71), size: 42),
        const SizedBox(height: 12),
        const Text(
          'AI đã hiểu như sau',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 20),
        _infoCard('Câu nói gốc', extraction.rawTranscript),
        const SizedBox(height: 12),
        _infoCard('Câu đã hiệu chỉnh', extraction.correctedTranscript),
        const SizedBox(height: 16),
        ...extraction.items.map(_itemCard),
        if (extraction.warnings.isNotEmpty)
          _infoCard('Cần kiểm tra', extraction.warnings.join('\n')),
        const SizedBox(height: 8),
        Text(
          'Xử lý trong ${extraction.processingTimeMs} ms',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF4B5563)),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _retake,
                child: const Text('Nói lại'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                key: const Key('confirmButton'),
                onPressed: () => setState(() => _view = _VoiceView.success),
                icon: const Icon(Icons.check),
                label: const Text('Xác nhận'),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _itemCard(ExtractedInventoryItem item) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.productName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text('Số lượng: ${item.quantity ?? 'Chưa xác định'}'),
          Text('Đơn vị: ${item.unit ?? 'Chưa xác định'}'),
          Text('Danh mục: ${item.category ?? 'Chưa xác định'}'),
          Text(
            'HSD: ${item.expiryDate?.toIso8601String().split('T').first ?? 'Chưa xác định'}',
          ),
          if (item.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              item.warnings.join('\n'),
              style: const TextStyle(color: Color(0xFF8A5A00)),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _infoCard(String title, String value) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE5E7EB)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF4B5563),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontSize: 16, height: 1.4)),
      ],
    ),
  );

  Widget _buildSuccess() => _shell(
    Column(
      children: [
        const Icon(Icons.check_circle, color: Color(0xFF2FBF71), size: 68),
        const SizedBox(height: 16),
        const Text(
          'Đã xác nhận bản nháp',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'M1 chưa lưu database. Khi có backend, bước này sẽ gửi dữ liệu đã xác nhận để lưu transaction.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: _retake, child: const Text('Thử câu khác')),
      ],
    ),
  );
}
