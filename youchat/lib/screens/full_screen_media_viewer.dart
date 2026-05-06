import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';
import '../encryption/media_encryption_service.dart';

class FullScreenMediaViewer extends StatefulWidget {
  final String heroTag;
  final String mediaUrl;
  final bool isVideo;
  final Uint8List? rawBytes; // For decrypted E2EE media payloads
  final String? encryptedKey; // If provided, fetches and decrypts on open
  final VoidCallback? onViewed; // Triggers the deletion cycle

  const FullScreenMediaViewer({
    super.key,
    required this.heroTag,
    required this.mediaUrl,
    this.isVideo = false, // Video play logic can be expanded later
    this.rawBytes,
    this.encryptedKey,
    this.onViewed,
  });

  @override
  State<FullScreenMediaViewer> createState() => _FullScreenMediaViewerState();
}

class _FullScreenMediaViewerState extends State<FullScreenMediaViewer> {
  Uint8List? _decryptedBytes;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.encryptedKey != null) {
      _fetchAndDecrypt();
    } else if (widget.rawBytes != null) {
      _decryptedBytes = widget.rawBytes;
    }
  }

  Future<void> _fetchAndDecrypt() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final response = await http.get(
        Uri.parse(widget.mediaUrl), 
        headers: {'ngrok-skip-browser-warning': 'true'}
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception('Failed to fetch media');
      
      final decrypted = await compute(
        MediaEncryptionService.decryptBytesCompute,
        {
          'encryptedData': response.bodyBytes,
          'packedKey': widget.encryptedKey!,
        },
      );
      setState(() {
        _decryptedBytes = decrypted;
        _isLoading = false;
      });
      
      // Successfully explicitly hit the decryption phase - trigger self-destruct cycle!
      widget.onViewed?.call();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white, shadows: [
          Shadow(blurRadius: 4, color: Colors.black54)
        ]),
      ),
      body: Center(
        child: InteractiveViewer(
          panEnabled: true, // Set it to false to prevent panning.
          minScale: 0.5,
          maxScale: 4,
          child: Hero(
            tag: widget.heroTag,
            child: widget.isVideo 
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam, size: 100, color: Colors.white54),
                    const SizedBox(height: 16),
                    const Text('Video playback currently unavailable', style: TextStyle(color: Colors.white)),
                  ],
                )
              : _buildImageContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildImageContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF8B0000)));
    }
    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 60),
          const SizedBox(height: 16),
          Text('Decryption Failed', style: const TextStyle(color: Colors.white)),
        ],
      );
    }
    if (_decryptedBytes != null) {
      return Image.memory(_decryptedBytes!, fit: BoxFit.contain);
    }
    
    return Image.network(
      widget.mediaUrl,
      fit: BoxFit.contain,
      headers: const {'ngrok-skip-browser-warning': 'true'},
      errorBuilder: (ctx, err, stack) => const Icon(
        Icons.broken_image,
        color: Colors.white54,
        size: 64,
      ),
    );
  }
}
