import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Voice recorder overlay — handles recording with tap-to-record/stop.
/// Returns the file path and duration on completion.
class VoiceRecorderResult {
  final String filePath;
  final int durationMs;

  VoiceRecorderResult({required this.filePath, required this.durationMs});
}

class VoiceRecorderWidget extends StatefulWidget {
  final void Function(VoiceRecorderResult result) onRecordingComplete;
  final VoidCallback onCancel;

  const VoiceRecorderWidget({
    super.key,
    required this.onRecordingComplete,
    required this.onCancel,
  });

  @override
  State<VoiceRecorderWidget> createState() => _VoiceRecorderWidgetState();
}

class _VoiceRecorderWidgetState extends State<VoiceRecorderWidget>
    with SingleTickerProviderStateMixin {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _isRecorderReady = false;
  bool _isRecording = false;
  Timer? _durationTimer;
  int _recordingSeconds = 0;
  String? _recordingPath;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _initRecorder();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _pulseController.dispose();
    if (_isRecorderReady) {
      _recorder.closeRecorder();
    }
    super.dispose();
  }

  Future<void> _initRecorder() async {
    try {
      // Request microphone permission
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        debugPrint('[VoiceRecorder] Microphone permission denied');
        widget.onCancel();
        return;
      }

      await _recorder.openRecorder();
      _isRecorderReady = true;
      _startRecording();
    } catch (e) {
      debugPrint('[VoiceRecorder] Init error: $e');
      widget.onCancel();
    }
  }

  Future<void> _startRecording() async {
    if (!_isRecorderReady) return;

    try {
      String path;
      if (kIsWeb) {
        path = 'voice_recording.aac';
      } else {
        final dir = await getTemporaryDirectory();
        path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.aac';
      }
      _recordingPath = path;

      await _recorder.startRecorder(
        toFile: path,
        codec: Codec.aacADTS,
        sampleRate: 44100,
        bitRate: 128000,
      );

      setState(() => _isRecording = true);
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordingSeconds++);
      });
    } catch (e) {
      debugPrint('[VoiceRecorder] Start error: $e');
      widget.onCancel();
    }
  }

  Future<void> _stopAndSend() async {
    try {
      _durationTimer?.cancel();
      await _recorder.stopRecorder();

      if (_recordingPath != null && _recordingSeconds >= 1) {
        widget.onRecordingComplete(VoiceRecorderResult(
          filePath: _recordingPath!,
          durationMs: _recordingSeconds * 1000,
        ));
      } else {
        widget.onCancel();
      }
    } catch (e) {
      debugPrint('[VoiceRecorder] Stop error: $e');
      widget.onCancel();
    }
  }

  Future<void> _cancelRecording() async {
    try {
      _durationTimer?.cancel();
      if (_isRecording) {
        await _recorder.stopRecorder();
      }
    } catch (_) {}
    widget.onCancel();
  }

  String _formatTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(1, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0C),
        border: Border(
          top: BorderSide(color: const Color(0xFF8B0000).withOpacity(0.5)),
        ),
      ),
      child: Row(
        children: [
          // Cancel button
          GestureDetector(
            onTap: _cancelRecording,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: const Color(0xFF141416),
              ),
              child: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 22),
            ),
          ),
          const SizedBox(width: 10),

          // Recording indicator + timer
          Expanded(
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF141416),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF8B0000).withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  // Pulsing red dot
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.red.withOpacity(0.5 + _pulseController.value * 0.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withOpacity(0.3 * _pulseController.value),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Recording',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatTime(_recordingSeconds),
                    style: const TextStyle(
                      color: Color(0xFF8B0000),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Send button
          GestureDetector(
            onTap: _stopAndSend,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B0000), Color(0xFF4A0000)],
                ),
              ),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
