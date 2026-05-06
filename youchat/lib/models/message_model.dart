import 'dart:async';

/// Message delivery status — tracks the lifecycle of a message.
/// Displayed as tick marks in the UI (like WhatsApp).
enum MessageStatus {
  /// 🕐 Clock — message queued locally, not yet sent to server
  sending,
  /// ✓ Single tick — server received and stored the message
  sent,
  /// ✓✓ Double tick — message delivered to recipient's device
  delivered,
  /// ✓✓ Blue — recipient opened/read the message
  read,
  /// ❌ Failed — could not send after retries
  failed,
}

/// Represents a single message in a chat.
/// Messages are NEVER persisted to disk — in-memory only.
/// Supports text, images, videos, files, and voice messages.
class MessageModel {
  final String messageId;
  final String senderId;
  final String receiverId;
  final String content; // Text content (or caption for media)
  final DateTime timestamp;
  final String? groupId; // Non-null if this is a group message

  // Media fields
  final String? mediaUrl; // Server path e.g. /uploads/media/file.jpg
  final String? mediaType; // 'image', 'video', 'file', 'voice', 'gif', or 'sticker'
  final String? originalName; // Original filename for generic files
  final String? encryptedKey; // Base64 AES Key + IV for E2EE payload

  // Voice message fields
  final int? voiceDurationMs; // Duration of voice clip in milliseconds

  // Delivery tracking
  MessageStatus status;
  bool isDelivered; // True when server confirms delivery to recipient
  bool isRead;
  bool isDeleting; // True when deletion countdown is active
  int deleteCountdown; // Seconds remaining
  Timer? deleteTimer;

  MessageModel({
    required this.messageId,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.timestamp,
    this.groupId,
    this.mediaUrl,
    this.mediaType,
    this.originalName,
    this.encryptedKey,
    this.voiceDurationMs,
    this.status = MessageStatus.sending,
    this.isDelivered = false,
    this.isRead = false,
    this.isDeleting = false,
    this.deleteCountdown = 15,
    this.deleteTimer,
  });

  bool get isSentByMe => false; // Set dynamically based on current userId
  bool get isGroupMessage => groupId != null;
  bool get hasMedia => mediaUrl != null && mediaUrl!.isNotEmpty;
  bool get isImage => mediaType == 'image';
  bool get isVideo => mediaType == 'video';
  bool get isFile => mediaType == 'file';
  bool get isVoice => mediaType == 'voice';
  bool get isGif => mediaType == 'gif';
  bool get isSticker => mediaType == 'sticker';
  bool get isPending => status == MessageStatus.sending || status == MessageStatus.failed;

  /// Convert to a map for queue serialization.
  Map<String, dynamic> toQueueMap() {
    return {
      'messageId': messageId,
      'senderId': senderId,
      'receiverId': receiverId,
      'content': content,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'groupId': groupId,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'originalName': originalName,
      'encryptedKey': encryptedKey,
      'voiceDurationMs': voiceDurationMs,
    };
  }

  factory MessageModel.fromWebSocket(Map<String, dynamic> json, String decryptedContent) {
    return MessageModel(
      messageId: json['messageId'] ?? '',
      senderId: json['from'] ?? '',
      receiverId: '', // Set by the receiver
      content: decryptedContent,
      groupId: json['groupId'],
      mediaUrl: json['mediaUrl'],
      mediaType: json['mediaType'],
      originalName: json['originalName'],
      encryptedKey: json['encryptedKey'],
      voiceDurationMs: json['voiceDuration'] != null
          ? (json['voiceDuration'] as num).toInt()
          : null,
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'])
          : DateTime.now(),
      status: MessageStatus.delivered, // Received messages are already delivered
      isDelivered: true,
    );
  }

  void dispose() {
    deleteTimer?.cancel();
  }
}
