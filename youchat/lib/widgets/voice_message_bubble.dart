import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/message_model.dart';
import '../encryption/media_encryption_service.dart';
import '../utils/constants.dart';

/// Voice message bubble — inline waveform player with play/pause, progress, and duration.
/// Triggers onPlaybackComplete when the user listens to 100%.
class VoiceMessageBubble extends StatefulWidget {
  final MessageModel message;
  final bool isSentByMe;
  final VoidCallback? onPlaybackComplete;

  const VoiceMessageBubble({
    super.key,
    required this.message,
    required this.isSentByMe,
    this.onPlaybackComplete,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  AudioPlayer? _player;
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _isExpired = false;
  bool _hasCompleted = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;

  @override
  void initState() {
    super.initState();
    final durationMs = widget.message.voiceDurationMs ?? 0;
    _duration = Duration(milliseconds: durationMs);
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _loadAndPlay() async {
    if (_hasCompleted || _isExpired) return;
    
    setState(() => _isLoading = true);
    
    try {
      final fullUrl = '${AppConstants.serverUrl}${widget.message.mediaUrl}';
      
      if (widget.message.encryptedKey != null) {
        // Fetch encrypted bytes, decrypt, write to temp file, play
        final response = await http.get(
          Uri.parse(fullUrl),
          headers: {'ngrok-skip-browser-warning': 'true'},
        ).timeout(const Duration(seconds: 30));
        
        if (response.statusCode != 200) throw Exception('Failed to fetch audio');
        
        final decrypted = await compute(
          MediaEncryptionService.decryptBytesCompute,
          {'encryptedData': response.bodyBytes, 'packedKey': widget.message.encryptedKey!},
        );
        
        // Write decrypted bytes to temp file for playback
        if (!kIsWeb) {
          final dir = await getTemporaryDirectory();
          final tempFile = File('${dir.path}/voice_${widget.message.messageId}.m4a');
          await tempFile.writeAsBytes(decrypted);
          
          _player = AudioPlayer();
          await _player!.setFilePath(tempFile.path);
        } else {
          // Web: use data URI
          _player = AudioPlayer();
          final uri = Uri.dataFromBytes(decrypted, mimeType: 'audio/mp4');
          await _player!.setUrl(uri.toString());
        }
      } else {
        _player = AudioPlayer();
        await _player!.setUrl(fullUrl);
      }

      // Get actual duration from audio
      final actualDuration = _player!.duration;
      if (actualDuration != null) {
        _duration = actualDuration;
      }

      // Listen to position updates
      _player!.positionStream.listen((pos) {
        if (mounted) {
          setState(() => _position = pos);
        }
      });

      // Listen for completion
      _player!.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed && mounted) {
          setState(() {
            _isPlaying = false;
            _hasCompleted = true;
          });
          // Trigger deletion after full playback
          widget.onPlaybackComplete?.call();
          // Show expired after a brief delay
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) setState(() => _isExpired = true);
          });
        }
      });

      await _player!.play();
      setState(() {
        _isPlaying = true;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _togglePlayPause() {
    if (_isLoading || _isExpired || _hasCompleted) return;
    
    if (_player == null) {
      _loadAndPlay();
      return;
    }

    if (_isPlaying) {
      _player!.pause();
      setState(() => _isPlaying = false);
    } else {
      _player!.play();
      setState(() => _isPlaying = true);
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isExpired) {
      return _buildExpiredPlaceholder();
    }

    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      width: 260,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          // Play/Pause button
          GestureDetector(
            onTap: _togglePlayPause,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: widget.isSentByMe
                      ? [const Color(0xFFFF3333), const Color(0xFFCC0000)]
                      : [const Color(0xFF8B0000), const Color(0xFF4A0000)],
                ),
              ),
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
            ),
          ),
          const SizedBox(width: 10),
          // Waveform + progress
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Waveform bars
                SizedBox(
                  height: 28,
                  child: CustomPaint(
                    painter: _WaveformPainter(
                      progress: progress,
                      activeColor: widget.isSentByMe 
                          ? Colors.white.withOpacity(0.9) 
                          : const Color(0xFF8B0000),
                      inactiveColor: widget.isSentByMe 
                          ? Colors.white.withOpacity(0.3) 
                          : const Color(0xFF8B0000).withOpacity(0.3),
                    ),
                    size: const Size(double.infinity, 28),
                  ),
                ),
                const SizedBox(height: 4),
                // Duration text
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(_position),
                      style: TextStyle(
                        color: (widget.isSentByMe ? Colors.white : Colors.white70).withOpacity(0.7),
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      _formatDuration(_duration),
                      style: TextStyle(
                        color: (widget.isSentByMe ? Colors.white : Colors.white70).withOpacity(0.7),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpiredPlaceholder() {
    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.mic_off_rounded, color: Colors.white.withOpacity(0.3), size: 20),
          const SizedBox(width: 8),
          Text(
            'Voice expired',
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom waveform painter with progress-based coloring
class _WaveformPainter extends CustomPainter {
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  _WaveformPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  // Predetermined waveform pattern (normalized 0-1 heights)
  static const List<double> _bars = [
    0.3, 0.5, 0.7, 0.4, 0.8, 0.6, 0.9, 0.5, 0.7, 0.3,
    0.6, 0.8, 0.4, 0.7, 0.5, 0.9, 0.6, 0.4, 0.7, 0.5,
    0.3, 0.6, 0.8, 0.5, 0.7, 0.4, 0.6, 0.3, 0.5, 0.7,
    0.4, 0.8, 0.6, 0.3, 0.5, 0.7, 0.4, 0.6, 0.8, 0.5,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / _bars.length;
    final gap = 1.5;
    final actualBarWidth = barWidth - gap;
    
    for (int i = 0; i < _bars.length; i++) {
      final barProgress = (i + 1) / _bars.length;
      final isActive = barProgress <= progress;
      
      final paint = Paint()
        ..color = isActive ? activeColor : inactiveColor
        ..strokeCap = StrokeCap.round;
      
      final barHeight = _bars[i] * size.height;
      final x = i * barWidth + actualBarWidth / 2;
      final top = (size.height - barHeight) / 2;
      
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top, actualBarWidth.clamp(1.5, 3.0), barHeight),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress || old.activeColor != activeColor;
}
