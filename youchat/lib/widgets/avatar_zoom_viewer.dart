import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class AvatarZoomViewer extends StatelessWidget {
  final String heroTag;
  final String imageUrl;
  final String title;

  const AvatarZoomViewer({
    super.key,
    required this.heroTag,
    required this.imageUrl,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
      body: Center(
        child: Hero(
          tag: heroTag,
          child: InteractiveViewer(
            panEnabled: true,
            minScale: 0.5,
            maxScale: 4.0,
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              placeholder: (context, url) => const CircularProgressIndicator(color: Color(0xFF8B0000)),
              errorWidget: (context, url, error) => const Icon(Icons.person, color: Colors.white54, size: 100),
              httpHeaders: const {'ngrok-skip-browser-warning': 'true'},
            ),
          ),
        ),
      ),
    );
  }
}
