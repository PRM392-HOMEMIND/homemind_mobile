import 'package:flutter/material.dart';

import '../../../core/config/plan_billing_visibility.dart';

import '../domain/speech_recognition_service.dart';
import '../domain/voice_command.dart';
import '../domain/voice_command_service.dart';
import '../domain/voice_conversation_controller.dart';

enum _AssistantView { capture, processing, command, success }

class VoiceAssistantPage extends StatefulWidget {
  const VoiceAssistantPage({
    required this.speechService,
    required this.conversationController,
    super.key,
  });

  final SpeechRecognitionService speechService;
  final VoiceConversationController conversationController;

  @override
  State<VoiceAssistantPage> createState() => _VoiceAssistantPageState();
}

class _VoiceAssistantPageState extends State<VoiceAssistantPage> {
  bool _initializing = true;
  bool _available = false;
  bool _listening = false;
  bool _autoSubmitFinal = false;
  String _transcript = '';
  String? _error;
  String _successTitle = '';
  String _successMessage = '';
  VoiceCommand? _command;
  _AssistantView _view = _AssistantView.capture;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final result = await widget.speechService.initialize();
    if (!mounted) return;
    setState(() {
      _initializing = false;
      _available = result.available;
      _error = result.message;
    });
  }

  Future<void> _startListening({bool autoSubmitFinal = false}) async {
    if (!_available || _listening) return;
    setState(() {
      _transcript = '';
      _error = null;
      _autoSubmitFinal = autoSubmitFinal;
    });
    await widget.speechService.startListening(
      onResult: (result) {
        if (!mounted) return;
        setState(() => _transcript = result.text);
        if (result.isFinal &&
            _autoSubmitFinal &&
            result.text.trim().isNotEmpty) {
          _submit(result.text);
        }
      },
      onStatus: (status) {
        if (!mounted) return;
        setState(() => _listening = status == SpeechListeningStatus.listening);
      },
      onError: (message) {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _error = message;
        });
      },
    );
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await widget.speechService.stopListening();
    } else {
      await _startListening(autoSubmitFinal: true);
    }
  }

  Future<void> _submit([String? spoken]) async {
    final text = (spoken ?? _transcript).trim();
    if (text.isEmpty) return;
    if (_listening) await widget.speechService.stopListening();
    if (!mounted) return;
    setState(() {
      _view = _AssistantView.processing;
      _error = null;
      _autoSubmitFinal = false;
    });
    try {
      final outcome = await widget.conversationController.handle(text);
      if (!mounted) return;
      switch (outcome.type) {
        case ConversationOutcomeType.command:
          final command = outcome.command!;
          setState(() {
            _command = command;
            _view = _AssistantView.command;
          });
        case ConversationOutcomeType.confirmed:
          setState(() {
            _successTitle = 'Đã xác nhận bằng giọng nói';
            _successMessage = 'Prototype đã xác nhận lệnh; chưa lưu database.';
            _view = _AssistantView.success;
          });
        case ConversationOutcomeType.rejected:
          setState(() {
            _successTitle = 'Đã hủy thao tác';
            _successMessage = 'Không có dữ liệu nào được thay đổi.';
            _view = _AssistantView.success;
          });
        case ConversationOutcomeType.noPendingCommand:
          setState(() {
            _error = outcome.message;
            _view = _AssistantView.capture;
          });
      }
    } on VoiceCommandServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _view = _AssistantView.capture;
      });
    }
  }

  void _reset() {
    widget.conversationController.clear();
    setState(() {
      _transcript = '';
      _command = null;
      _error = null;
      _view = _AssistantView.capture;
    });
  }

  @override
  void dispose() {
    widget.speechService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF7F8FA),
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      title: const Text('HomeMind Voice'),
      centerTitle: true,
    ),
    body: SafeArea(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: switch (_view) {
          _AssistantView.processing => _processing(),
          _AssistantView.command => _commandView(_command!),
          _AssistantView.success => _success(),
          _AssistantView.capture => _capture(),
        },
      ),
    ),
  );

  Widget _page(Widget child) => SingleChildScrollView(
    key: ValueKey(_view),
    padding: const EdgeInsets.all(20),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: child,
      ),
    ),
  );

  Widget _capture() => _page(
    Column(
      children: [
        const SizedBox(height: 20),
        const Icon(Icons.auto_awesome, size: 46, color: Color(0xFF2FBF71)),
        const SizedBox(height: 12),
        const Text(
          'Bạn muốn HomeMind làm gì?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Thêm hoặc cập nhật đồ, hỏi tồn kho, tạo danh sách mua và điều hướng bằng giọng nói.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF4B5563), height: 1.45),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                IconButton.filled(
                  key: const Key('assistantMicButton'),
                  onPressed: _initializing || !_available ? null : _toggleMic,
                  padding: const EdgeInsets.all(22),
                  iconSize: 44,
                  style: IconButton.styleFrom(
                    backgroundColor: _listening
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF2FBF71),
                  ),
                  icon: Icon(_listening ? Icons.stop : Icons.mic),
                ),
                const SizedBox(height: 12),
                Text(
                  _listening ? 'Đang nghe...' : 'Chạm để nói',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 120),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F8FA),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _transcript.isEmpty
                        ? 'Ví dụ: “Thêm hai hộp sữa”, “Tuần này có gì hết hạn?” hoặc “Mở danh sách mua”.'
                        : _transcript,
                    key: const Key('assistantTranscript'),
                    style: const TextStyle(fontSize: 16, height: 1.45),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    PlanBillingVisibility.message(context, _error!),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFB45309)),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('sendCommandButton'),
                  onPressed: _transcript.trim().isEmpty ? null : _submit,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Gửi yêu cầu'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [
            Chip(label: Text('“Tuần này có gì hết hạn?”')),
            Chip(label: Text('“Mở danh sách mua”')),
            Chip(label: Text('“Sữa tắm Dove hết rồi”')),
          ],
        ),
      ],
    ),
  );

  Widget _processing() => _page(
    const Column(
      children: [
        SizedBox(height: 110),
        CircularProgressIndicator(),
        SizedBox(height: 24),
        Text(
          'HomeMind đang hiểu yêu cầu...',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 8),
        Text('Đang xác định ý định và dữ liệu liên quan'),
      ],
    ),
  );

  Widget _commandView(VoiceCommand command) {
    if (command.needsClarification) {
      return _page(
        Column(
          children: [
            const Icon(Icons.help_outline, size: 54, color: Color(0xFFF59E0B)),
            const SizedBox(height: 16),
            const Text(
              'HomeMind cần hỏi thêm',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              command.clarification ?? command.assistantReply,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('answerByVoiceButton'),
              onPressed: () => _startListening(autoSubmitFinal: true),
              icon: const Icon(Icons.mic),
              label: const Text('Trả lời bằng giọng nói'),
            ),
            TextButton(onPressed: _reset, child: const Text('Hủy')),
          ],
        ),
      );
    }
    if (!command.requiresConfirmation) {
      return _page(
        Column(
          children: [
            const Icon(
              Icons.chat_bubble_outline,
              size: 54,
              color: Color(0xFF2FBF71),
            ),
            const SizedBox(height: 16),
            const Text(
              'HomeMind đã hiểu',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              command.assistantReply,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              'Intent: ${command.intent.wireValue} · ${command.processingTimeMs} ms',
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _reset,
              child: const Text('Nói yêu cầu khác'),
            ),
          ],
        ),
      );
    }
    return _page(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.verified_user_outlined,
            size: 54,
            color: Color(0xFF2FBF71),
          ),
          const SizedBox(height: 12),
          const Text(
            'Cần bạn xác nhận',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            command.assistantReply,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17),
          ),
          const SizedBox(height: 16),
          ...command.actions.map(
            (action) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.entities['productName']?.toString() ??
                          action.actionType.wireValue,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...action.entities.entries
                        .where((entry) => entry.key != 'productName')
                        .map((entry) => Text('${entry.key}: ${entry.value}')),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('voiceConfirmButton'),
            onPressed: () => _startListening(autoSubmitFinal: true),
            icon: const Icon(Icons.mic),
            label: const Text('Nói “đồng ý” hoặc “hủy”'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _reset,
                  child: const Text('Hủy'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => setState(() {
                    widget.conversationController.clear();
                    _successTitle = 'Đã xác nhận';
                    _successMessage =
                        'Prototype đã xác nhận lệnh; chưa lưu database.';
                    _view = _AssistantView.success;
                  }),
                  child: const Text('Xác nhận'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _success() => _page(
    Column(
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.check_circle, size: 70, color: Color(0xFF2FBF71)),
        const SizedBox(height: 16),
        Text(
          _successTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(_successMessage, textAlign: TextAlign.center),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _reset,
          child: const Text('Tiếp tục bằng giọng nói'),
        ),
      ],
    ),
  );
}
