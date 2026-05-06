import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/message_model.dart';
import '../models/conversation_model.dart';
import '../encryption/signal_protocol_service.dart';
import '../encryption/session_manager.dart';
import '../socket/websocket_service.dart';
import '../services/group_service.dart';
import '../services/message_queue.dart';
import '../encryption/media_encryption_service.dart';
import '../utils/constants.dart';

/// Chat service — manages conversations, messages, and deletion.
/// Messages are stored IN-MEMORY ONLY — never persisted to disk.
/// Supports both 1:1 and group messaging.
///
/// Key behaviours:
/// - Conversations are PERSISTENT within a session (never removed when messages are deleted)
/// - Group messages delete PER-USER (each reader's copy vanishes 7s after they read it)
/// - Offline messages are QUEUED and auto-sent on reconnect
/// - Messages track delivery status (sending → sent → delivered → read)
class ChatService extends ChangeNotifier {
  final SignalProtocolService _signalService;
  final WebSocketService _wsService;
  final SessionManager _sessionManager;
  final String Function() _getCurrentUserId;
  final Uuid _uuid = const Uuid();
  final MessageQueue _messageQueue = MessageQueue();

  // In-memory message store — NEVER persisted
  final Map<String, List<MessageModel>> _messages = {};
  // Conversation list
  final Map<String, ConversationModel> _conversations = {};
  // Typing indicators
  final Map<String, bool> _typingStatus = {};
  // Error message for UI to display
  String? _lastError;

  ChatService({
    required SignalProtocolService signalService,
    required WebSocketService wsService,
    required SessionManager sessionManager,
    required String Function() getCurrentUserId,
  })  : _signalService = signalService,
        _wsService = wsService,
        _sessionManager = sessionManager,
        _getCurrentUserId = getCurrentUserId {
    _setupWebSocketHandlers();
  }

  MessageQueue get messageQueue => _messageQueue;

  List<ConversationModel> get conversations {
    final list = _conversations.values.toList();
    list.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
    return list;
  }

  List<MessageModel> getMessages(String chatId) {
    return _messages[chatId] ?? [];
  }

  bool isTyping(String chatId) => _typingStatus[chatId] ?? false;
  String? getTypingUser(String chatId) {
    final conv = _conversations[chatId];
    if (conv != null && conv.isPeerTyping) {
      return conv.typingUserId;
    }
    return null;
  }

  String? get lastError => _lastError;
  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  /// Setup WebSocket message handlers.
  void _setupWebSocketHandlers() {
    // 1:1
    _wsService.onMessage = _handlePlaintextMessage;
    _wsService.onReadReceipt = _handleReadReceipt;
    _wsService.onForceDelete = _handleForceDelete;
    _wsService.onMessageSent = _handleMessageSent;
    _wsService.onTypingIndicator = _handleTypingIndicator;
    _wsService.onPendingDeletions = _handlePendingDeletions;
    _wsService.onDeliveryReceipt = _handleDeliveryReceipt;
    _wsService.onUserStatus = _handleUserStatus;
    // Group
    _wsService.onGroupMessage = _handleGroupMessage;
    _wsService.onGroupReadReceipt = _handleGroupReadReceipt;
    _wsService.onGroupTypingIndicator = _handleGroupTypingIndicator;
    // Reconnect hook — flush queue + sync
    _wsService.onReconnected = _onReconnected;
  }

  /// Called when WebSocket reconnects — flush queued messages.
  void _onReconnected() {
    debugPrint('[ChatService] Reconnected — flushing ${_messageQueue.length} queued messages');
    _flushMessageQueue();
  }

  /// Flush all queued messages through the WebSocket.
  void _flushMessageQueue() {
    final queued = _messageQueue.drainAll();
    for (final msg in queued) {
      final sent = _wsService.sendRaw(msg.data);
      if (sent) {
        // Update message status from 'sending' to 'sent'
        _updateMessageStatus(msg.id, MessageStatus.sent);
      } else {
        // Re-queue if still can't send
        msg.retryCount++;
        if (msg.retryCount < 10) {
          _messageQueue.enqueue(msg);
        } else {
          _updateMessageStatus(msg.id, MessageStatus.failed);
        }
      }
    }
    notifyListeners();
  }

  /// Find and update a message's status across all chats.
  void _updateMessageStatus(String messageId, MessageStatus status) {
    for (final messages in _messages.values) {
      for (final msg in messages) {
        if (msg.messageId == messageId) {
          msg.status = status;
          if (status == MessageStatus.delivered) {
            msg.isDelivered = true;
          }
          return;
        }
      }
    }
  }

  // ══════════════════════════════════════════
  //  1:1 MESSAGING
  // ══════════════════════════════════════════

  /// Upload a media file to the server.
  Future<Map<String, dynamic>?> _uploadMedia(String filePath, {Uint8List? fileBytes, String? fileName}) async {
    try {
      final token = _wsService.currentToken;
      if (token == null) {
        _lastError = 'Authentication token missing.';
        return null;
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse(AppConstants.mediaUpload),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['ngrok-skip-browser-warning'] = 'true';
      
      Uint8List rawBytes;
      String actualFileName = fileName ?? filePath.split('/').last.split('?').first;
      if (actualFileName.isEmpty) actualFileName = 'upload.jpg';
      
      if (kIsWeb) {
        if (fileBytes != null) {
          rawBytes = fileBytes;
        } else {
          try {
            final fetchResponse = await http.get(Uri.parse(filePath));
            rawBytes = fetchResponse.bodyBytes;
          } catch (e) {
            throw Exception('Failed to load web media bytes: $e');
          }
        }
      } else {
         rawBytes = fileBytes ?? await File(filePath).readAsBytes();
      }

      final encryptedPayload = await compute(MediaEncryptionService.encryptBytes, rawBytes);
      request.files.add(http.MultipartFile.fromBytes('file', encryptedPayload.encryptedBytes, filename: actualFileName));

      final response = await request.send().timeout(const Duration(seconds: 30));
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode == 201) {
        final body = jsonDecode(responseBody);
        return {
          'mediaUrl': body['mediaUrl'],
          'mediaType': body['mediaType'],
          'encryptedKey': encryptedPayload.keyBase64,
        };
      }
      _lastError = 'HTTP ${response.statusCode}: $responseBody';
      return null;
    } catch (e) {
      _lastError = 'Network error: $e';
      return null;
    }
  }

  /// Send a plaintext message (1:1).
  /// If offline, queues the message and shows it with a clock icon.
  Future<void> sendMessage(String recipientId, String plaintext) async {
    try {
      final messageId = _uuid.v4();

      final message = MessageModel(
        messageId: messageId,
        senderId: _getCurrentUserId(),
        receiverId: recipientId,
        content: plaintext,
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
      );

      _messages.putIfAbsent(recipientId, () => []);
      _messages[recipientId]!.add(message);
      _ensureConversation(recipientId);
      _conversations[recipientId]!.updateLastMessage(message.timestamp);
      notifyListeners();

      final wsPayload = <String, dynamic>{
        'type': 'message',
        'to': recipientId,
        'content': plaintext,
        'messageId': messageId,
      };

      if (_wsService.isConnected) {
        _wsService.sendMessage(
          to: recipientId,
          content: plaintext,
          messageId: messageId,
        );
      } else {
        // Queue for sending on reconnect
        _messageQueue.enqueue(QueuedMessage(
          id: messageId,
          type: 'message',
          data: wsPayload,
        ));
        debugPrint('[ChatService] Message queued (offline): $messageId');
      }
    } catch (e) {
      _lastError = 'Failed to send message: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Send a media message (1:1).
  Future<void> sendMediaMessage(String recipientId, String filePath, String caption, {Uint8List? fileBytes, String? fileName, String? mediaType}) async {
    try {
      if (!_wsService.isConnected) {
        _lastError = 'Not connected to server. Please wait for reconnection.';
        notifyListeners();
        return;
      }

      final uploadResult = await _uploadMedia(filePath, fileBytes: fileBytes, fileName: fileName);
      if (uploadResult == null) {
        notifyListeners();
        return;
      }

      final messageId = _uuid.v4();
      final mediaUrl = uploadResult['mediaUrl'] as String;
      final serverMediaType = uploadResult['mediaType'] as String;
      final finalMediaType = mediaType ?? serverMediaType;

      final message = MessageModel(
        messageId: messageId,
        senderId: _getCurrentUserId(),
        receiverId: recipientId,
        content: caption,
        timestamp: DateTime.now(),
        mediaUrl: mediaUrl,
        mediaType: finalMediaType,
        originalName: uploadResult['originalName'] as String?,
        encryptedKey: uploadResult['encryptedKey'] as String?,
        status: MessageStatus.sending,
      );

      _messages.putIfAbsent(recipientId, () => []);
      _messages[recipientId]!.add(message);
      _ensureConversation(recipientId);
      _conversations[recipientId]!.lastMessagePreview =
          finalMediaType == 'video' ? '🎬 Video' : (finalMediaType == 'file' ? '📄 File' : '📷 Photo');
      _conversations[recipientId]!.lastMessageTime = message.timestamp;
      notifyListeners();

      _wsService.sendMessage(
        to: recipientId,
        content: caption,
        messageId: messageId,
        mediaUrl: mediaUrl,
        mediaType: finalMediaType,
        originalName: uploadResult['originalName'] as String?,
        encryptedKey: uploadResult['encryptedKey'] as String?,
      );
    } catch (e) {
      _lastError = 'Failed to send media.';
      notifyListeners();
    }
  }

  /// Send a voice message (1:1).
  Future<void> sendVoiceMessage(String recipientId, String filePath, int durationMs) async {
    try {
      if (!_wsService.isConnected) {
        _lastError = 'Not connected to server.';
        notifyListeners();
        return;
      }

      final uploadResult = await _uploadMedia(filePath, fileName: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
      if (uploadResult == null) {
        notifyListeners();
        return;
      }

      final messageId = _uuid.v4();
      final mediaUrl = uploadResult['mediaUrl'] as String;

      final message = MessageModel(
        messageId: messageId,
        senderId: _getCurrentUserId(),
        receiverId: recipientId,
        content: '',
        timestamp: DateTime.now(),
        mediaUrl: mediaUrl,
        mediaType: 'voice',
        encryptedKey: uploadResult['encryptedKey'] as String?,
        voiceDurationMs: durationMs,
        status: MessageStatus.sending,
      );

      _messages.putIfAbsent(recipientId, () => []);
      _messages[recipientId]!.add(message);
      _ensureConversation(recipientId);
      _conversations[recipientId]!.lastMessagePreview = '🎤 Voice message';
      _conversations[recipientId]!.lastMessageTime = message.timestamp;
      notifyListeners();

      _wsService.sendMessage(
        to: recipientId,
        content: '',
        messageId: messageId,
        mediaUrl: mediaUrl,
        mediaType: 'voice',
        encryptedKey: uploadResult['encryptedKey'] as String?,
        voiceDuration: durationMs,
      );
    } catch (e) {
      _lastError = 'Failed to send voice message.';
      notifyListeners();
    }
  }

  /// Send a voice message in a group.
  Future<void> sendGroupVoiceMessage(String groupId, String filePath, int durationMs) async {
    try {
      if (!_wsService.isConnected) {
        _lastError = 'Not connected to server.';
        notifyListeners();
        return;
      }

      final uploadResult = await _uploadMedia(filePath, fileName: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
      if (uploadResult == null) {
        notifyListeners();
        return;
      }

      final messageId = _uuid.v4();
      final mediaUrl = uploadResult['mediaUrl'] as String;

      final message = MessageModel(
        messageId: messageId,
        senderId: _getCurrentUserId(),
        receiverId: groupId,
        content: '',
        timestamp: DateTime.now(),
        groupId: groupId,
        mediaUrl: mediaUrl,
        mediaType: 'voice',
        encryptedKey: uploadResult['encryptedKey'] as String?,
        voiceDurationMs: durationMs,
        status: MessageStatus.sending,
      );

      _messages.putIfAbsent(groupId, () => []);
      _messages[groupId]!.add(message);
      _ensureGroupConversation(groupId);
      _conversations[groupId]!.lastMessagePreview = '🎤 Voice message';
      _conversations[groupId]!.lastMessageTime = message.timestamp;
      notifyListeners();

      _wsService.sendGroupMessage(
        groupId: groupId,
        content: '',
        messageId: messageId,
        mediaUrl: mediaUrl,
        mediaType: 'voice',
        encryptedKey: uploadResult['encryptedKey'] as String?,
        voiceDuration: durationMs,
      );
    } catch (e) {
      _lastError = 'Failed to send voice message.';
      notifyListeners();
    }
  }

  /// Trigger voice message deletion — timer matches audio duration.
  void triggerVoiceDisappear(MessageModel message, String chatId) {
    if (message.isRead) return;
    
    message.isRead = true;
    message.status = MessageStatus.read;
    
    if (message.isGroupMessage) {
      _wsService.sendGroupReadReceipt(
        messageId: message.messageId,
        groupId: chatId,
        senderId: message.senderId,
      );
    } else {
      _wsService.sendReadReceipt(
        messageId: message.messageId,
        to: chatId,
      );
    }

    final deleteDurationMs = message.voiceDurationMs ?? 15000;
    final deleteSeconds = (deleteDurationMs / 1000).ceil();
    
    message.isDeleting = true;
    message.deleteCountdown = deleteSeconds;
    notifyListeners();

    message.deleteTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      message.deleteCountdown--;
      notifyListeners();
      if (message.deleteCountdown <= 0) {
        timer.cancel();
        _deleteMessage(message, chatId);
      }
    });
  }

  /// Send media from keyboard (GIFs/stickers) in 1:1 chat.
  Future<void> sendKeyboardMedia(String recipientId, Uint8List mediaBytes, String fileName, String mediaType) async {
    try {
      if (!_wsService.isConnected) {
        _lastError = 'Not connected to server.';
        notifyListeners();
        return;
      }

      final uploadResult = await _uploadMedia(fileName, fileBytes: mediaBytes);
      if (uploadResult == null) {
        notifyListeners();
        return;
      }

      final messageId = _uuid.v4();
      final mediaUrl = uploadResult['mediaUrl'] as String;

      final message = MessageModel(
        messageId: messageId,
        senderId: _getCurrentUserId(),
        receiverId: recipientId,
        content: '',
        timestamp: DateTime.now(),
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        encryptedKey: uploadResult['encryptedKey'] as String?,
        status: MessageStatus.sending,
      );

      _messages.putIfAbsent(recipientId, () => []);
      _messages[recipientId]!.add(message);
      _ensureConversation(recipientId);
      _conversations[recipientId]!.lastMessagePreview = mediaType == 'gif' ? '🎬 GIF' : '🏷️ Sticker';
      _conversations[recipientId]!.lastMessageTime = message.timestamp;
      notifyListeners();

      _wsService.sendMessage(
        to: recipientId,
        content: '',
        messageId: messageId,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        encryptedKey: uploadResult['encryptedKey'] as String?,
      );
    } catch (e) {
      _lastError = 'Failed to send media.';
      notifyListeners();
    }
  }

  /// Send media from keyboard (GIFs/stickers) in group chat.
  Future<void> sendGroupKeyboardMedia(String groupId, Uint8List mediaBytes, String fileName, String mediaType) async {
    try {
      if (!_wsService.isConnected) {
        _lastError = 'Not connected to server.';
        notifyListeners();
        return;
      }

      final uploadResult = await _uploadMedia(fileName, fileBytes: mediaBytes);
      if (uploadResult == null) {
        notifyListeners();
        return;
      }

      final messageId = _uuid.v4();
      final mediaUrl = uploadResult['mediaUrl'] as String;

      final message = MessageModel(
        messageId: messageId,
        senderId: _getCurrentUserId(),
        receiverId: groupId,
        content: '',
        timestamp: DateTime.now(),
        groupId: groupId,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        encryptedKey: uploadResult['encryptedKey'] as String?,
        status: MessageStatus.sending,
      );

      _messages.putIfAbsent(groupId, () => []);
      _messages[groupId]!.add(message);
      _ensureGroupConversation(groupId);
      _conversations[groupId]!.lastMessagePreview = mediaType == 'gif' ? '🎬 GIF' : '🏷️ Sticker';
      _conversations[groupId]!.lastMessageTime = message.timestamp;
      notifyListeners();

      _wsService.sendGroupMessage(
        groupId: groupId,
        content: '',
        messageId: messageId,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        encryptedKey: uploadResult['encryptedKey'] as String?,
      );
    } catch (e) {
      _lastError = 'Failed to send media.';
      notifyListeners();
    }
  }

  /// Handle incoming plaintext message (1:1).
  Future<void> _handlePlaintextMessage(Map<String, dynamic> data) async {
    try {
      final senderId = data['from'] as String;
      final plaintext = (data['content'] ?? '') as String;
      final messageId = data['messageId'] as String;
      final mediaUrl = data['mediaUrl'] as String?;
      final mediaType = data['mediaType'] as String?;
      final originalName = data['originalName'] as String?;
      final voiceDuration = data['voiceDuration'] != null
          ? (data['voiceDuration'] as num).toInt()
          : null;

      // Deduplicate — skip if we already have this message
      final existing = _messages[senderId];
      if (existing != null && existing.any((m) => m.messageId == messageId)) {
        debugPrint('[ChatService] Duplicate message skipped: $messageId');
        return;
      }

      final message = MessageModel(
        messageId: messageId,
        senderId: senderId,
        receiverId: _getCurrentUserId(),
        content: plaintext,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        originalName: originalName,
        encryptedKey: data['encryptedKey'] as String?,
        voiceDurationMs: voiceDuration,
        timestamp: data['timestamp'] != null
            ? DateTime.fromMillisecondsSinceEpoch(data['timestamp'])
            : DateTime.now(),
        status: MessageStatus.delivered,
        isDelivered: true,
      );

      _messages.putIfAbsent(senderId, () => []);
      _messages[senderId]!.add(message);

      _ensureConversation(senderId);
      if (mediaUrl != null) {
        if (mediaType == 'voice') {
          _conversations[senderId]!.lastMessagePreview = '🎤 Voice message';
        } else if (mediaType == 'gif') {
          _conversations[senderId]!.lastMessagePreview = '🎬 GIF';
        } else if (mediaType == 'sticker') {
          _conversations[senderId]!.lastMessagePreview = '🏷️ Sticker';
        } else {
          _conversations[senderId]!.lastMessagePreview =
              mediaType == 'video' ? '🎬 Video' : '📷 Photo';
        }
        _conversations[senderId]!.lastMessageTime = message.timestamp;
      } else {
        _conversations[senderId]!.updateLastMessage(message.timestamp);
      }
      _conversations[senderId]!.unreadCount++;

      // Send delivery acknowledgment to server
      _wsService.sendDeliveryAck(messageId: messageId, senderId: senderId);

      notifyListeners();
    } catch (e, stackTrace) {
      debugPrint('[ChatService] ERROR handling message: $e');
      debugPrint('[ChatService] Stack: $stackTrace');
    }
  }

  /// Mark messages as read and trigger deletion timer (1:1).
  void markAsRead(String peerId) {
    final messages = _messages[peerId];
    if (messages == null) return;

    for (final msg in messages) {
      if (!msg.isRead && msg.senderId == peerId) {
        if (msg.encryptedKey != null && msg.hasMedia) {
          continue; 
        }
        
        msg.isRead = true;
        msg.status = MessageStatus.read;

        _wsService.sendReadReceipt(
          messageId: msg.messageId,
          to: peerId,
        );

        // SAFE DELIVERY: Only start deletion if message is delivered
        if (msg.isDelivered) {
          _startDeletionTimer(msg, peerId);
        }
      }
    }

    _conversations[peerId]?.unreadCount = 0;
    notifyListeners();
  }

  /// Handle read receipt from server (1:1).
  void _handleReadReceipt(Map<String, dynamic> data) {
    final messageId = data['messageId'] as String;
    final from = data['from'] as String;

    final messages = _messages[from];
    if (messages == null) return;

    for (final msg in messages) {
      if (msg.messageId == messageId) {
        msg.isRead = true;
        msg.status = MessageStatus.read;
        // SAFE DELIVERY: Only start deletion if delivered
        if (msg.isDelivered) {
          _startDeletionTimer(msg, from);
        }
        break;
      }
    }

    notifyListeners();
  }

  /// Handle delivery receipt — server confirms message reached recipient.
  void _handleDeliveryReceipt(Map<String, dynamic> data) {
    final messageId = data['messageId'] as String;
    debugPrint('[ChatService] Delivery receipt: $messageId');

    for (final entry in _messages.entries) {
      for (final msg in entry.value) {
        if (msg.messageId == messageId) {
          msg.isDelivered = true;
          msg.status = MessageStatus.delivered;
          // If already read, NOW start the deletion timer
          if (msg.isRead && !msg.isDeleting) {
            _startDeletionTimer(msg, entry.key);
          }
          notifyListeners();
          return;
        }
      }
    }
  }

  /// Handle user online/offline status.
  void _handleUserStatus(Map<String, dynamic> data) {
    final userId = data['userId'] as String?;
    final isOnline = data['isOnline'] as bool? ?? false;
    if (userId == null) return;

    if (_conversations.containsKey(userId)) {
      _conversations[userId]!.isPeerOnline = isOnline;
      notifyListeners();
    }
  }

  // ══════════════════════════════════════════
  //  GROUP MESSAGING
  // ══════════════════════════════════════════

  /// Send a group message.
  Future<void> sendGroupMessage(String groupId, String plaintext) async {
    try {
      final messageId = _uuid.v4();

      final message = MessageModel(
        messageId: messageId,
        senderId: _getCurrentUserId(),
        receiverId: groupId,
        content: plaintext,
        timestamp: DateTime.now(),
        groupId: groupId,
        status: MessageStatus.sending,
      );

      _messages.putIfAbsent(groupId, () => []);
      _messages[groupId]!.add(message);
      _ensureGroupConversation(groupId);
      _conversations[groupId]!.updateLastMessage(message.timestamp);
      notifyListeners();

      final wsPayload = <String, dynamic>{
        'type': 'group_message',
        'groupId': groupId,
        'content': plaintext,
        'messageId': messageId,
      };

      if (_wsService.isConnected) {
        _wsService.sendGroupMessage(
          groupId: groupId,
          content: plaintext,
          messageId: messageId,
        );
      } else {
        _messageQueue.enqueue(QueuedMessage(
          id: messageId,
          type: 'group_message',
          data: wsPayload,
        ));
        debugPrint('[ChatService] Group message queued (offline): $messageId');
      }
    } catch (e) {
      _lastError = 'Failed to send message: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Send a media message in a group.
  Future<void> sendGroupMediaMessage(String groupId, String filePath, String caption, {Uint8List? fileBytes, String? fileName, String? mediaType}) async {
    try {
      if (!_wsService.isConnected) {
        _lastError = 'Not connected to server.';
        notifyListeners();
        return;
      }

      final uploadResult = await _uploadMedia(filePath, fileBytes: fileBytes, fileName: fileName);
      if (uploadResult == null) {
        notifyListeners();
        return;
      }

      final messageId = _uuid.v4();
      final mediaUrl = uploadResult['mediaUrl'] as String;
      final serverMediaType = uploadResult['mediaType'] as String;
      final finalMediaType = mediaType ?? serverMediaType;

      final message = MessageModel(
        messageId: messageId,
        senderId: _getCurrentUserId(),
        receiverId: groupId,
        content: caption,
        timestamp: DateTime.now(),
        groupId: groupId,
        mediaUrl: mediaUrl,
        mediaType: finalMediaType,
        originalName: uploadResult['originalName'] as String?,
        encryptedKey: uploadResult['encryptedKey'] as String?,
        status: MessageStatus.sending,
      );

      _messages.putIfAbsent(groupId, () => []);
      _messages[groupId]!.add(message);
      _ensureGroupConversation(groupId);
      _conversations[groupId]!.lastMessagePreview =
          finalMediaType == 'video' ? '🎬 Video' : (finalMediaType == 'file' ? '📄 File' : '📷 Photo');
      _conversations[groupId]!.lastMessageTime = message.timestamp;
      notifyListeners();

      _wsService.sendGroupMessage(
        groupId: groupId,
        content: caption,
        messageId: messageId,
        mediaUrl: mediaUrl,
        mediaType: finalMediaType,
        originalName: uploadResult['originalName'] as String?,
        encryptedKey: uploadResult['encryptedKey'] as String?,
      );
    } catch (e) {
      _lastError = 'Failed to send media.';
      notifyListeners();
    }
  }

  /// Handle incoming group message.
  Future<void> _handleGroupMessage(Map<String, dynamic> data) async {
    try {
      final senderId = data['from'] as String;
      final plaintext = (data['content'] ?? '') as String;
      final messageId = data['messageId'] as String;
      final groupId = data['groupId'] as String;
      final mediaUrl = data['mediaUrl'] as String?;
      final mediaType = data['mediaType'] as String?;
      final originalName = data['originalName'] as String?;
      final voiceDuration = data['voiceDuration'] != null
          ? (data['voiceDuration'] as num).toInt()
          : null;

      // Deduplicate
      final existing = _messages[groupId];
      if (existing != null && existing.any((m) => m.messageId == messageId)) {
        debugPrint('[ChatService] Duplicate group message skipped: $messageId');
        return;
      }

      final message = MessageModel(
        messageId: messageId,
        senderId: senderId,
        receiverId: groupId,
        content: plaintext,
        groupId: groupId,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        originalName: originalName,
        encryptedKey: data['encryptedKey'] as String?,
        voiceDurationMs: voiceDuration,
        timestamp: data['timestamp'] != null
            ? DateTime.fromMillisecondsSinceEpoch(data['timestamp'])
            : DateTime.now(),
        status: MessageStatus.delivered,
        isDelivered: true,
      );

      _messages.putIfAbsent(groupId, () => []);
      _messages[groupId]!.add(message);

      _ensureGroupConversation(groupId);
      if (mediaUrl != null) {
        if (mediaType == 'voice') {
          _conversations[groupId]!.lastMessagePreview = '🎤 Voice message';
        } else if (mediaType == 'gif') {
          _conversations[groupId]!.lastMessagePreview = '🎬 GIF';
        } else if (mediaType == 'sticker') {
          _conversations[groupId]!.lastMessagePreview = '🏷️ Sticker';
        } else {
          _conversations[groupId]!.lastMessagePreview =
              mediaType == 'video' ? '🎬 Video' : '📷 Photo';
        }
        _conversations[groupId]!.lastMessageTime = message.timestamp;
      } else {
        _conversations[groupId]!.updateLastMessage(message.timestamp);
      }
      _conversations[groupId]!.unreadCount++;

      // Send delivery ack
      _wsService.sendDeliveryAck(messageId: messageId, senderId: senderId);

      notifyListeners();
    } catch (e, stackTrace) {
      debugPrint('[ChatService] ERROR handling group message: $e');
      debugPrint('[ChatService] Stack: $stackTrace');
    }
  }

  /// Mark group messages as read — per-user deletion.
  void markGroupAsRead(String groupId) {
    final messages = _messages[groupId];
    if (messages == null) return;

    final currentUserId = _getCurrentUserId();

    for (final msg in messages) {
      if (!msg.isRead && msg.senderId != currentUserId) {
        if (msg.encryptedKey != null && msg.hasMedia) {
          continue; 
        }

        msg.isRead = true;
        msg.status = MessageStatus.read;

        _wsService.sendGroupReadReceipt(
          messageId: msg.messageId,
          groupId: groupId,
          senderId: msg.senderId,
        );

        // SAFE DELIVERY: only delete after delivered + read
        if (msg.isDelivered) {
          _startDeletionTimer(msg, groupId);
        }
      }
    }

    _conversations[groupId]?.unreadCount = 0;
    notifyListeners();
  }

  /// Handle group read receipt.
  void _handleGroupReadReceipt(Map<String, dynamic> data) {
    final messageId = data['messageId'] as String;
    final groupId = data['groupId'] as String;

    final messages = _messages[groupId];
    if (messages == null) return;

    for (final msg in messages) {
      if (msg.messageId == messageId) {
        msg.isRead = true;
        msg.status = MessageStatus.read;
        break;
      }
    }

    notifyListeners();
  }

  /// Handle group typing indicator.
  void _handleGroupTypingIndicator(Map<String, dynamic> data) {
    final from = data['from'] as String;
    final groupId = data['groupId'] as String;
    final isTyping = data['isTyping'] as bool;

    _typingStatus[groupId] = isTyping;
    if (_conversations.containsKey(groupId)) {
      _conversations[groupId]!.isPeerTyping = isTyping;
      _conversations[groupId]!.typingUserId = isTyping ? from : '';
    }
    notifyListeners();
  }

  /// Send group typing indicator.
  void setGroupTyping(String groupId, bool isTyping) {
    _wsService.sendGroupTypingIndicator(groupId: groupId, isTyping: isTyping);
  }

  /// Explicitly trigger the read receipt and deletion cycle for E2EE media.
  void triggerMediaDisappear(MessageModel message, String chatId) {
    if (message.isRead) return;
    
    message.isRead = true;
    message.status = MessageStatus.read;
    
    if (message.isGroupMessage) {
      _wsService.sendGroupReadReceipt(
        messageId: message.messageId,
        groupId: chatId,
        senderId: message.senderId,
      );
    } else {
      _wsService.sendReadReceipt(
        messageId: message.messageId,
        to: chatId,
      );
    }
    
    _startDeletionTimer(message, chatId);
    notifyListeners();
  }

  // ══════════════════════════════════════════
  //  DELETION (shared by 1:1 and group)
  // ══════════════════════════════════════════

  /// Start the deletion countdown.
  /// SAFE DELIVERY: Only call this after message is both delivered AND read.
  void _startDeletionTimer(MessageModel message, String chatId) {
    if (message.isDeleting) return;

    message.isDeleting = true;
    message.deleteCountdown = AppConstants.deleteTimerSeconds;

    message.deleteTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      message.deleteCountdown--;
      notifyListeners();

      if (message.deleteCountdown <= 0) {
        timer.cancel();
        _deleteMessage(message, chatId);
      }
    });
  }

  /// Delete a message locally.
  void _deleteMessage(MessageModel message, String chatId) {
    if (message.encryptedKey != null && message.hasMedia) {
      _wsService.sendDeleteMedia(message.mediaUrl!);
    }
    message.dispose();
    _messages[chatId]?.removeWhere((m) => m.messageId == message.messageId);

    _wsService.sendDeleteAck(message.messageId);

    if (_messages[chatId]?.isEmpty ?? true) {
      _conversations[chatId]?.lastMessagePreview = 'No messages';
    }

    notifyListeners();
  }

  /// Handle force delete from server.
  void _handleForceDelete(Map<String, dynamic> data) {
    final messageId = data['messageId'] as String;

    for (final entry in _messages.entries) {
      final idx = entry.value.indexWhere((m) => m.messageId == messageId);
      if (idx != -1) {
        final existingMsg = entry.value[idx];
        if (existingMsg.encryptedKey != null && existingMsg.hasMedia) {
          _wsService.sendDeleteMedia(existingMsg.mediaUrl!);
        }
        existingMsg.dispose();
        entry.value.removeAt(idx);
        _wsService.sendDeleteAck(messageId);

        if (entry.value.isEmpty) {
          _conversations[entry.key]?.lastMessagePreview = 'No messages';
        }
        break;
      }
    }

    notifyListeners();
  }

  /// Handle message sent confirmation — update status to 'sent'.
  void _handleMessageSent(Map<String, dynamic> data) {
    final messageId = data['messageId'] as String?;
    if (messageId == null) return;

    debugPrint('[ChatService] Message sent confirmed: $messageId');
    _updateMessageStatus(messageId, MessageStatus.sent);
    notifyListeners();
  }

  /// Handle typing indicator (1:1).
  void _handleTypingIndicator(Map<String, dynamic> data) {
    final from = data['from'] as String;
    final isTyping = data['isTyping'] as bool;
    _typingStatus[from] = isTyping;
    _conversations[from]?.isPeerTyping = isTyping;
    _conversations[from]?.typingUserId = from;
    notifyListeners();
  }

  /// Handle pending deletions.
  void _handlePendingDeletions(List<String> messageIds) {
    for (final messageId in messageIds) {
      for (final entry in _messages.entries) {
        final idx = entry.value.indexWhere((m) => m.messageId == messageId);
        if (idx != -1) {
          entry.value[idx].dispose();
          entry.value.removeAt(idx);
          _wsService.sendDeleteAck(messageId);
          break;
        }
      }
    }
    notifyListeners();
  }

  /// Send typing indicator (1:1).
  void setTyping(String peerId, bool isTyping) {
    _wsService.sendTypingIndicator(to: peerId, isTyping: isTyping);
  }

  // ══════════════════════════════════════════
  //  CONVERSATION MANAGEMENT
  // ══════════════════════════════════════════

  void _ensureConversation(String peerId) {
    if (!_conversations.containsKey(peerId)) {
      _conversations[peerId] = ConversationModel(peerId: peerId);
    }
  }

  void _ensureGroupConversation(String groupId) {
    if (!_conversations.containsKey(groupId)) {
      _conversations[groupId] = ConversationModel(
        peerId: groupId,
        isGroup: true,
        groupId: groupId,
      );
    }
  }

  void startConversation(String peerId,
      {String bio = '', String profilePictureUrl = ''}) {
    _ensureConversation(peerId);
    _conversations[peerId]!.peerBio = bio;
    _conversations[peerId]!.peerProfilePictureUrl = profilePictureUrl;
    notifyListeners();
  }

  void registerGroupConversation({
    required String groupId,
    required String groupName,
    required List<String> members,
    List<String>? admins,
    Map<String, dynamic>? settings,
    String? groupPictureUrl,
  }) {
    if (!_conversations.containsKey(groupId)) {
      _conversations[groupId] = ConversationModel(
        peerId: groupId,
        isGroup: true,
        groupId: groupId,
        groupName: groupName,
        members: members,
        admins: admins,
        settings: settings,
        groupPictureUrl: groupPictureUrl,
        lastMessagePreview: 'Group created',
      );
    } else {
      _conversations[groupId]!.groupName = groupName;
      _conversations[groupId]!.members = members;
      if (admins != null) _conversations[groupId]!.admins = admins;
      if (settings != null) _conversations[groupId]!.settings = settings;
      if (groupPictureUrl != null) _conversations[groupId]!.groupPictureUrl = groupPictureUrl;
    }
    _messages.putIfAbsent(groupId, () => []);
    notifyListeners();
  }

  Future<void> loadGroupsFromServer(String token) async {
    try {
      final groupService = GroupService(getToken: () => token);
      final groups = await groupService.getMyGroups();

      for (final group in groups) {
        registerGroupConversation(
          groupId: group.groupId,
          groupName: group.name,
          members: group.members,
          admins: group.admins,
          settings: group.settings,
          groupPictureUrl: group.groupPictureUrl,
        );
      }

      debugPrint('[ChatService] Loaded ${groups.length} groups from server');
    } catch (e) {
      debugPrint('[ChatService] Error loading groups: $e');
    }
  }

  void clearAll() {
    for (final messages in _messages.values) {
      for (final msg in messages) {
        msg.dispose();
      }
    }
    _messages.clear();
    _conversations.clear();
    _typingStatus.clear();
    _messageQueue.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    clearAll();
    super.dispose();
  }
}
