import 'package:flutter/material.dart';

import '../../../core/config/plan_billing_visibility.dart';

import '../../voice/domain/speech_recognition_service.dart';
import '../domain/assistant_models.dart';
import '../domain/assistant_service.dart';
import 'confirm_page.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage({
    required this.service,
    required this.speechService,
    super.key,
  });

  final AssistantService service;
  final SpeechRecognitionService speechService;

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final _textController = TextEditingController();
  bool _initializing = true;
  bool _available = false;
  bool _listening = false;
  bool _processing = false;
  String? _status;
  AssistantTurn? _lastTurn;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    final result = await widget.speechService.initialize();
    if (!mounted) return;
    setState(() {
      _initializing = false;
      _available = result.available;
      _status = result.message;
    });
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await widget.speechService.stopListening();
      return;
    }
    setState(() => _status = null);
    await widget.speechService.startListening(
      onResult: (result) {
        if (!mounted) return;
        setState(() => _textController.text = result.text);
      },
      onStatus: (status) {
        if (!mounted) return;
        setState(() => _listening = status == SpeechListeningStatus.listening);
      },
      onError: (message) {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _status = message;
        });
      },
    );
  }

  Future<void> _submit([String? preset]) async {
    final text = (preset ?? _textController.text).trim();
    if (text.isEmpty || _processing) return;
    if (_listening) await widget.speechService.stopListening();
    setState(() {
      _processing = true;
      _status = null;
      _textController.text = text;
    });
    try {
      final turn = await widget.service.turn(text: text);
      if (!mounted) return;
      setState(() {
        _lastTurn = turn;
        _processing = false;
      });
      if (turn.isWriteDraft) {
        final committed = await Navigator.of(context).push<AssistantTurn>(
          MaterialPageRoute(
            builder: (_) => ConfirmPage(service: widget.service, draft: turn),
          ),
        );
        if (committed != null && mounted) {
          setState(() => _lastTurn = committed);
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _status = '$error';
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    widget.speechService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        const Text(
          'Trợ lý HomeMind',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'HomeMind AI Router · dữ liệu trực tiếp từ backend',
          style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _textController,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'Nói hoặc gõ yêu cầu…',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton.filled(
              onPressed: _initializing || !_available ? null : _toggleMic,
              style: IconButton.styleFrom(
                backgroundColor: _listening
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF2FBF71),
              ),
              icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: _processing ? null : () => _submit(),
                child: Text(_processing ? 'Đang phân tích…' : 'Gửi yêu cầu'),
              ),
            ),
          ],
        ),
        if (_status != null) ...[
          const SizedBox(height: 8),
          Text(
            PlanBillingVisibility.message(context, _status!),
            style: const TextStyle(color: Color(0xFF8A5A00)),
          ),
        ],
        if (_lastTurn != null) ...[
          const SizedBox(height: 20),
          _TurnCard(turn: _lastTurn!),
        ],
      ],
    );
  }
}

class _TurnCard extends StatelessWidget {
  const _TurnCard({required this.turn});
  final AssistantTurn turn;

  @override
  Widget build(BuildContext context) {
    final tools = [
      ...turn.toolsUsed.map((t) => t.toolId),
      ...turn.toolsProposed.map((t) => t.toolId),
    ];
    return Container(
      width: double.infinity,
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
            'kind: ${turn.kind.wireValue}',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF1B8450),
            ),
          ),
          if (tools.isNotEmpty)
            Text(
              'tool: ${tools.join(', ')}',
              style: const TextStyle(color: Color(0xFF4B5563)),
            ),
          const SizedBox(height: 8),
          Text(
            PlanBillingVisibility.message(
              context,
              turn.message,
              preservedValues: PlanBillingVisibility.entityLabels([
                turn.data,
                ...turn.toolsProposed.map((tool) => tool.arguments),
              ]),
            ),
            style: const TextStyle(height: 1.4),
          ),
          if (turn.data != null && turn.data!['items'] is List) ...[
            const SizedBox(height: 12),
            ...((turn.data!['items'] as List).whereType<Map>().take(5).map((
              raw,
            ) {
              final name = raw['name']?.toString() ?? '';
              final extra = [
                if (raw['quantity'] != null) '${raw['quantity']}',
                if (raw['unit'] != null) '${raw['unit']}',
                if (raw['expiryDate'] != null) 'HSD ${raw['expiryDate']}',
              ].join(' · ');
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• $name${extra.isEmpty ? '' : ' ($extra)'}'),
              );
            })),
          ],
          const SizedBox(height: 8),
          Text(
            '${turn.processingTimeMs} ms · backend',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}
