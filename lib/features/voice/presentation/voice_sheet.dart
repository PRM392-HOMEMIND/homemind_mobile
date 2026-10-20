import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/app_text.dart';

import '../../../app/homemind_theme.dart';
import '../domain/speech_recognition_service.dart';

class VoiceSheet extends StatefulWidget {
  const VoiceSheet({
    required this.speechService,
    required this.onDone,
    super.key,
  });

  final SpeechRecognitionService speechService;
  final ValueChanged<String> onDone;

  static Future<String?> show(
    BuildContext context, {
    required SpeechRecognitionService speechService,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => VoiceSheet(
        speechService: speechService,
        onDone: (text) => Navigator.of(context).pop(text),
      ),
    );
  }

  @visibleForTesting
  static bool enableInfiniteAnimation = true;

  @override
  State<VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<VoiceSheet>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  late final AnimationController _waveController;
  bool _listening = false;
  bool _available = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (VoiceSheet.enableInfiniteAnimation) {
      _waveController.repeat(reverse: true);
    }

    _initAndStart();
  }

  Future<void> _initAndStart() async {
    try {
      final initResult = await widget.speechService.initialize();
      if (!mounted) return;
      setState(() {
        _available = initResult.available;
      });
      if (_available) {
        _startListening();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _available = false;
        _listening = false;
        _status = tr('Không thể khởi tạo microphone: {0}', [error]);
      });
    }
  }

  Future<void> _startListening() async {
    setState(() {
      _listening = true;
      _status = null;
    });
    await widget.speechService.startListening(
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _controller.text = result.text;
        });
      },
      onStatus: (status) {
        if (!mounted) return;
        setState(() {
          _listening = status == SpeechListeningStatus.listening;
        });
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

  @override
  void dispose() {
    _waveController.dispose();
    _controller.dispose();
    widget.speechService.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 24,
              offset: Offset(0, -4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Grabber
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: HomeMindTheme.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 16),

            // Status label
            Text(
              _status ??
                  (_listening
                      ? tr('Đang nghe...')
                      : (_available
                            ? tr('Sẵn sàng')
                            : tr('Không thể dùng microphone'))),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: HomeMindTheme.textMain,
              ),
            ),
            const SizedBox(height: 14),

            // Waveform animation
            AnimatedBuilder(
              animation: _waveController,
              builder: (context, _) {
                final val = _waveController.value;
                return SizedBox(
                  height: 32,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(7, (index) {
                      final factor = (index - 3).abs() * 0.2;
                      final h = (12 + (val * 18 * (1.0 - factor))).clamp(
                        8.0,
                        30.0,
                      );
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: 4,
                        height: h,
                        decoration: BoxDecoration(
                          color: HomeMindTheme.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      );
                    }),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),

            // Transcript text area
            TextField(
              controller: _controller,
              maxLines: 3,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: HomeMindTheme.textMain,
                height: 1.4,
              ),
              decoration: InputDecoration(
                hintText: tr('Nói hoặc chọn câu gợi ý bên dưới...'),
                hintStyle: const TextStyle(
                  color: HomeMindTheme.textMuted,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
                filled: true,
                fillColor: HomeMindTheme.background,
                contentPadding: const EdgeInsets.all(14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
                  borderSide: const BorderSide(color: HomeMindTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
                  borderSide: const BorderSide(color: HomeMindTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(HomeMindTheme.radiusMd),
                  borderSide: const BorderSide(
                    color: HomeMindTheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: HomeMindTheme.border),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      tr('Huỷ'),
                      style: TextStyle(
                        color: HomeMindTheme.textSub,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final text = _controller.text.trim();
                      if (text.isNotEmpty) {
                        widget.onDone(text);
                      }
                    },
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text(
                      'Xong',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HomeMindTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: const StadiumBorder(),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
