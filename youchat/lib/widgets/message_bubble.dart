import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/message_model.dart';
import '../services/chat_service.dart';
import '../utils/constants.dart';
import 'countdown_overlay.dart';
import 'voice_message_bubble.dart';
import '../screens/full_screen_media_viewer.dart';

/// Message bubble widget for the chat screen.
/// - Sender messages: right-aligned, crimson gradient
/// - Receiver messages: left-aligned, dark charcoal
/// - Shows sender name when showSenderName is true (group chats)
/// - Shows lock icon, read receipts
/// - Supports image and video media messages
/// - Text selection disabled (no copy)
/// - Fade-out animation on deletion
class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isSentByMe;
  final bool showSenderName;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isSentByMe,
    this.showSenderName = false,
  });

  /// Check if a message is emoji-only (1-3 emojis, no other text)
  bool _isEmojiOnly(String text) {
    if (text.isEmpty) return false;
    // Match emoji characters including modifiers, ZWJ sequences, flags
    final emojiRegex = RegExp(
      r'^(\p{Emoji_Presentation}|\p{Emoji}\uFE0F|[\u200D\uFE0F])+$',
      unicode: true,
    );
    if (!emojiRegex.hasMatch(text.trim())) return false;
    // Count actual emoji (grapheme clusters)
    final graphemes = text.trim().characters;
    return graphemes.length <= 3;
  }

  @override
  Widget build(BuildContext context) {
    final isEmoji = !message.hasMedia && _isEmojiOnly(message.content);

    return AnimatedOpacity(
      opacity: message.isDeleting && message.deleteCountdown <= 1 ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 500),
      child: AnimatedScale(
        scale: message.isDeleting && message.deleteCountdown <= 1 ? 0.8 : 1.0,
        duration: const Duration(milliseconds: 500),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            mainAxisAlignment:
                isSentByMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (isSentByMe) const Spacer(flex: 2),
              Flexible(
                flex: 5,
                child: isEmoji
                    ? _buildEmojiMessage()
                    : _buildBubbleMessage(context),
              ),
              if (!isSentByMe) const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }

  /// Large emoji without bubble container (WhatsApp-style)
  Widget _buildEmojiMessage() {
    return Column(
      crossAxisAlignment:
          isSentByMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (showSenderName && !isSentByMe)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              message.senderId,
              style: TextStyle(
                color: const Color(0xFFFF1E1E).withOpacity(0.8),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        Text(
          message.content,
          style: const TextStyle(fontSize: 48, height: 1.2),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock, size: 10, color: Colors.white.withOpacity(0.4)),
            const SizedBox(width: 4),
            Text(
              _formatTime(message.timestamp),
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
            ),
            if (isSentByMe) ...[
              const SizedBox(width: 4),
              _buildStatusIcon(),
            ],
          ],
        ),
      ],
    );
  }

  /// Helper to build the status icon based on the new MessageStatus enum
  Widget _buildStatusIcon() {
    IconData iconData;
    Color iconColor = Colors.white.withOpacity(0.5);

    switch (message.status) {
      case MessageStatus.sending:
        iconData = Icons.access_time; // Clock icon
        break;
      case MessageStatus.sent:
        iconData = Icons.check; // Single tick
        break;
      case MessageStatus.delivered:
        iconData = Icons.done_all; // Double tick (gray)
        break;
      case MessageStatus.read:
        iconData = Icons.done_all; // Double tick (blue)
        iconColor = const Color(0xFF34B7F1); // WhatsApp blue
        break;
      case MessageStatus.failed:
        iconData = Icons.error_outline; // Error icon
        iconColor = Colors.red;
        break;
    }

    return Icon(
      iconData,
      size: 14,
      color: iconColor,
    );
  }

  /// Standard bubble message with container
  Widget _buildBubbleMessage(BuildContext context) {
    return Stack(
      children: [
        Container(
          padding: message.hasMedia
              ? const EdgeInsets.all(4)
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: isSentByMe
                ? const LinearGradient(
                    colors: [Color(0xFF8B0000), Color(0xFF4A0000)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isSentByMe ? null : const Color(0xFF141416),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(8),
              topRight: const Radius.circular(8),
              bottomLeft: Radius.circular(isSentByMe ? 8 : 0),
              bottomRight: Radius.circular(isSentByMe ? 0 : 8),
            ),
            border: isSentByMe
                ? null
                : Border.all(
                    color: const Color(0xFF8B0000).withOpacity(0.2),
                  ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sender name (group chats only)
              if (showSenderName && !isSentByMe) ...[
                Padding(
                  padding: message.hasMedia
                      ? const EdgeInsets.fromLTRB(10, 6, 10, 2)
                      : EdgeInsets.zero,
                  child: Text(
                    message.senderId,
                    style: TextStyle(
                      color: const Color(0xFFFF1E1E).withOpacity(0.8),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!message.hasMedia) const SizedBox(height: 2),
              ],

              // Voice message
              if (message.isVoice)
                VoiceMessageBubble(
                  message: message,
                  isSentByMe: isSentByMe,
                  onPlaybackComplete: () {
                    if (!isSentByMe) {
                      final chatId = message.isGroupMessage ? message.groupId! : message.senderId;
                      Provider.of<ChatService>(context, listen: false).triggerVoiceDisappear(message, chatId);
                    }
                  },
                ),

              // Media content (image or video thumbnail)
              if (message.hasMedia && !message.isVoice) _buildMediaContent(context),

              // Message text / caption
              if (message.content.isNotEmpty)
                Padding(
                  padding: message.hasMedia
                      ? const EdgeInsets.fromLTRB(10, 6, 10, 0)
                      : EdgeInsets.zero,
                  child: Text(
                    message.content,
                    style: TextStyle(
                      color: isSentByMe ? Colors.white : Colors.white.withOpacity(0.85),
                      fontSize: 16.5,
                      height: 1.35,
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              // Bottom row: lock + time + read receipt
              Padding(
                padding: message.hasMedia
                    ? const EdgeInsets.fromLTRB(10, 0, 10, 6)
                    : EdgeInsets.zero,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock,
                      size: 10,
                      color: Colors.white.withOpacity(0.5),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatTime(message.timestamp),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 10,
                      ),
                    ),
                    if (isSentByMe) ...[
                      const SizedBox(width: 4),
                      _buildStatusIcon(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Build the media content (image or video thumbnail).
  Widget _buildMediaContent(BuildContext context) {
    final fullUrl = '${AppConstants.serverUrl}${message.mediaUrl}';

    // If it's an encrypted payload, ALWAYS show the secure tombstone regardless of mediaType
    if (message.encryptedKey != null) {
      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FullScreenMediaViewer(
                heroTag: message.messageId,
                mediaUrl: fullUrl,
                isVideo: message.isVideo,
                encryptedKey: message.encryptedKey,
                onViewed: () {
                  if (!isSentByMe) {
                    final chatId = message.isGroupMessage ? message.groupId! : message.senderId;
                    Provider.of<ChatService>(context, listen: false).triggerMediaDisappear(message, chatId);
                  }
                },
              ),
            ),
          );
        },
        child: Hero(
          tag: message.messageId,
          child: _buildEncryptedPlaceholder(),
        ),
      );
    }

    if (message.isFile) {
      return Container(
        width: 220,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF141416),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF8B0000).withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.insert_drive_file, color: Color(0xFF8B0000)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message.originalName ?? 'Document',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    if (message.isImage) {
      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FullScreenMediaViewer(
                heroTag: message.messageId,
                mediaUrl: fullUrl,
                isVideo: false,
              ),
            ),
          );
        },
        child: Hero(
          tag: message.messageId,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 250, maxHeight: 300),
              child: Image.network(
                fullUrl,
                fit: BoxFit.cover,
                headers: const {'ngrok-skip-browser-warning': 'true'},
                loadingBuilder: (ctx, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    width: 200,
                    height: 150,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: CircularProgressIndicator(
                        value: progress.expectedTotalBytes != null
                            ? progress.cumulativeBytesLoaded /
                                progress.expectedTotalBytes!
                            : null,
                        color: const Color(0xFF8B0000),
                        strokeWidth: 2,
                      ),
                    ),
                  );
                },
                errorBuilder: (ctx, err, stack) => Container(
                  width: 200,
                  height: 100,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Center(
                    child: Icon(Icons.broken_image, color: Colors.white30, size: 32),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Video thumbnail
    // Video thumbnail
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FullScreenMediaViewer(
              heroTag: message.messageId,
              mediaUrl: fullUrl,
              isVideo: true,
            ),
          ),
        );
      },
      child: Hero(
        tag: message.messageId,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 200,
            height: 150,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Dark background with play icon
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF4A0000).withOpacity(0.5),
                        const Color(0xFF0A0A0C),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B0000).withOpacity(0.8),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 32),
                ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam, color: Colors.white70, size: 12),
                        SizedBox(width: 4),
                        Text('Video',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 10)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEncryptedPlaceholder() {
    // Determine label and icon based on media type
    String label;
    IconData icon;
    if (message.isGif) {
      label = 'Secure GIF';
      icon = Icons.gif_box_outlined;
    } else if (message.isSticker) {
      label = 'Secure Sticker';
      icon = Icons.emoji_emotions_outlined;
    } else if (message.isVideo) {
      label = 'Secure Video';
      icon = Icons.videocam_outlined;
    } else {
      label = 'Secure Media';
      icon = Icons.lock_outline;
    }

    return Container(
      width: 200,
      height: 150,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white54, size: 32),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          const Text('Tap to decrypt & view (15s)', style: TextStyle(color: Colors.white30, fontSize: 10)),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
