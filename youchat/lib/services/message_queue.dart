import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Queued message — stores all data needed to resend a message.
class QueuedMessage {
  final String id;
  final String type; // 'message', 'group_message'
  final Map<String, dynamic> data; // Full WebSocket payload
  final DateTime queuedAt;
  int retryCount;

  QueuedMessage({
    required this.id,
    required this.type,
    required this.data,
    DateTime? queuedAt,
    this.retryCount = 0,
  }) : queuedAt = queuedAt ?? DateTime.now();
}

/// In-memory message queue for offline message sending.
///
/// When the WebSocket is disconnected, messages are stored here.
/// When the connection is restored, all queued messages are flushed
/// through the WebSocket in order.
///
/// Max queue size: 500 messages (prevents memory issues).
class MessageQueue extends ChangeNotifier {
  final Queue<QueuedMessage> _queue = Queue<QueuedMessage>();
  static const int maxQueueSize = 500;

  /// Number of messages in the queue.
  int get length => _queue.length;
  bool get isEmpty => _queue.isEmpty;
  bool get isNotEmpty => _queue.isNotEmpty;

  /// All queued messages (read-only).
  List<QueuedMessage> get messages => _queue.toList();

  /// Add a message to the queue.
  /// Returns true if added, false if queue is full.
  bool enqueue(QueuedMessage message) {
    // Check for duplicate message IDs
    if (_queue.any((m) => m.id == message.id)) {
      debugPrint('[MessageQueue] Duplicate message skipped: ${message.id}');
      return false;
    }

    if (_queue.length >= maxQueueSize) {
      debugPrint('[MessageQueue] Queue full ($maxQueueSize) — dropping oldest');
      _queue.removeFirst();
    }

    _queue.add(message);
    debugPrint('[MessageQueue] Enqueued: ${message.id} (type: ${message.type}, total: ${_queue.length})');
    notifyListeners();
    return true;
  }

  /// Remove a specific message from the queue (e.g., after successful send).
  void remove(String messageId) {
    _queue.removeWhere((m) => m.id == messageId);
    notifyListeners();
  }

  /// Take all messages out of the queue for sending.
  /// Returns the messages and clears the queue.
  List<QueuedMessage> drainAll() {
    final drained = _queue.toList();
    _queue.clear();
    if (drained.isNotEmpty) {
      debugPrint('[MessageQueue] Drained ${drained.length} messages for sending');
    }
    notifyListeners();
    return drained;
  }

  /// Check if a message is queued.
  bool contains(String messageId) {
    return _queue.any((m) => m.id == messageId);
  }

  /// Clear all queued messages (e.g., on logout).
  void clear() {
    _queue.clear();
    debugPrint('[MessageQueue] Queue cleared');
    notifyListeners();
  }
}
