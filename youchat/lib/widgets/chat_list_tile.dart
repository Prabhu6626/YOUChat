import 'package:flutter/material.dart';
import '../models/conversation_model.dart';
import '../utils/constants.dart';
import 'avatar_zoom_viewer.dart';

/// Chat list tile widget.
/// Shows avatar/group icon, name, message preview, unread badge, timestamp.
/// Supports both 1:1 and group conversations.
class ChatListTile extends StatelessWidget {
  final ConversationModel conversation;
  final VoidCallback onTap;

  const ChatListTile({
    super.key,
    required this.conversation,
    required this.onTap,
  });

  Widget _buildInitials() {
    return Center(
      child: Text(
        conversation.peerId.isNotEmpty
            ? conversation.peerId[0].toUpperCase()
            : '?',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF141416),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: const Color(0xFF8B0000).withOpacity(0.2),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Avatar or group icon
                GestureDetector(
                  onTap: () {
                    final imageUrl = conversation.isGroup
                        ? (conversation.groupPictureUrl?.isNotEmpty == true
                            ? '${AppConstants.serverUrl}${conversation.groupPictureUrl}'
                            : null)
                        : (conversation.peerProfilePictureUrl.isNotEmpty
                            ? '${AppConstants.serverUrl}${conversation.peerProfilePictureUrl}'
                            : null);

                    if (imageUrl != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AvatarZoomViewer(
                            heroTag: 'avatar_${conversation.peerId}',
                            imageUrl: imageUrl,
                            title: conversation.displayName,
                          ),
                        ),
                      );
                    }
                  },
                  child: Hero(
                    tag: 'avatar_${conversation.peerId}',
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.rectangle,
                        borderRadius: BorderRadius.circular(4),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4A0000), Color(0xFF8B0000)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF8B0000).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: conversation.isGroup
                            ? (conversation.groupPictureUrl?.isNotEmpty == true
                                ? Image.network(
                                    '${AppConstants.serverUrl}${conversation.groupPictureUrl}',
                                    fit: BoxFit.cover,
                                    headers: const {'ngrok-skip-browser-warning': 'true'},
                                    errorBuilder: (ctx, err, stack) => const Icon(Icons.group_rounded, color: Colors.white, size: 24),
                                  )
                                : const Icon(Icons.group_rounded, color: Colors.white, size: 24))
                            : (conversation.peerProfilePictureUrl.isNotEmpty
                                ? Image.network(
                                    '${AppConstants.serverUrl}${conversation.peerProfilePictureUrl}',
                                    fit: BoxFit.cover,
                                    headers: const {'ngrok-skip-browser-warning': 'true'},
                                    errorBuilder: (ctx, err, stack) => _buildInitials(),
                                  )
                                : _buildInitials()),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Name and message preview
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              conversation.displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            _formatTime(conversation.lastMessageTime),
                            style: TextStyle(
                              color: conversation.unreadCount > 0
                                  ? const Color(0xFFFF1E1E)
                                  : Colors.white.withOpacity(0.4),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            conversation.isGroup
                                ? Icons.group_rounded
                                : Icons.lock,
                            size: 12,
                            color: const Color(0xFF8B0000),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              conversation.isPeerTyping
                                  ? conversation.isGroup
                                      ? '${conversation.typingUserId} is typing...'
                                      : 'typing...'
                                  : conversation.lastMessagePreview,
                              style: TextStyle(
                                color: conversation.isPeerTyping
                                    ? const Color(0xFFFF1E1E)
                                    : Colors.white.withOpacity(0.5),
                                fontSize: 13,
                                fontStyle: conversation.isPeerTyping
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Unread badge
                          if (conversation.unreadCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8B0000),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${conversation.unreadCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inDays > 0) {
      return '${time.day}/${time.month}';
    }

    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
