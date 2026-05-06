import 'dart:io' show File;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class MediaPreviewScreen extends StatefulWidget {
  final String path;
  final String mediaType; // 'image', 'video', 'file'
  final String originalName;
  final Uint8List? fileBytes;
  final int? fileSize;

  const MediaPreviewScreen({
    super.key,
    required this.path,
    required this.mediaType,
    required this.originalName,
    this.fileBytes,
    this.fileSize,
  });

  @override
  State<MediaPreviewScreen> createState() => _MediaPreviewScreenState();
}

class _MediaPreviewScreenState extends State<MediaPreviewScreen> {
  final _captionController = TextEditingController();

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Widget _buildPreview() {
    if (widget.mediaType == 'image') {
      if (kIsWeb) {
        if (widget.fileBytes != null) {
          return Image.memory(
            widget.fileBytes!,
            fit: BoxFit.contain,
          );
        } else {
          return Image.network(
            widget.path,
            fit: BoxFit.contain,
          );
        }
      } else {
        return Image.file(
          File(widget.path),
          fit: BoxFit.contain,
        );
      }
    } else if (widget.mediaType == 'video') {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam, size: 64, color: Colors.white70),
              const SizedBox(height: 16),
              Text(
                widget.originalName,
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    } else {
      String sizeStr = '';
      if (widget.fileSize != null) {
        sizeStr = '${(widget.fileSize! / 1024).toStringAsFixed(1)} KB';
      } else if (!kIsWeb) {
        try {
          sizeStr = '${(File(widget.path).lengthSync() / 1024).toStringAsFixed(1)} KB';
        } catch (_) {}
      }

      return Container(
        color: const Color(0xFF141416),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insert_drive_file, size: 64, color: Colors.white70),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  widget.originalName,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              if (sizeStr.isNotEmpty)
                Text(
                  sizeStr,
                  style: const TextStyle(color: Colors.white54),
                ),
            ],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _buildPreview(),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: const Color(0xFF0A0A0C),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _captionController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Add a caption...',
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: const Color(0xFF1A1A1A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FloatingActionButton(
                    onPressed: () {
                      Navigator.pop(context, _captionController.text.trim());
                    },
                    backgroundColor: const Color(0xFF8B0000),
                    child: const Icon(Icons.send, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
