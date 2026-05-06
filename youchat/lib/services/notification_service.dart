import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Callback for when a notification is tapped.
/// Passes the payload (senderId or groupId) to the app for navigation.
typedef NotificationTapCallback = void Function(String? payload);

/// Local notification service for YOUChat.
/// Shows notifications when messages arrive while the app is in the background.
///
/// Privacy-first:
/// - Only shows "New message from {userID}" — no message content
/// - Maintains E2EE privacy guarantee
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _isAppInForeground = true;

  /// Callback invoked when user taps a notification.
  NotificationTapCallback? onNotificationTap;

  /// Set of chat IDs currently open (don't notify for these).
  final Set<String> _activeChatIds = {};

  /// Initialize the notification plugin.
  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');

    const initSettings = InitializationSettings(
      android: androidSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Request notification permission (Android 13+)
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
    }

    _initialized = true;
    debugPrint('[NotificationService] Initialized');
  }

  /// Handle notification tap — extract payload and invoke callback.
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('[NotificationService] Notification tapped: ${response.payload}');
    if (response.payload != null && onNotificationTap != null) {
      onNotificationTap!(response.payload);
    }
  }

  /// Update foreground/background state.
  void setAppInForeground(bool inForeground) {
    _isAppInForeground = inForeground;
    debugPrint('[NotificationService] App in foreground: $inForeground');
  }

  /// Mark a chat as active (currently open on screen).
  void setActiveChat(String? chatId) {
    _activeChatIds.clear();
    if (chatId != null) {
      _activeChatIds.add(chatId);
    }
  }

  /// Clear active chat when leaving a chat screen.
  void clearActiveChat() {
    _activeChatIds.clear();
  }

  /// Show a notification for an incoming 1:1 message.
  /// Only shows when app is in background AND user is not in that chat.
  Future<void> showMessageNotification({
    required String senderId,
    String? senderName,
  }) async {
    if (!_initialized) return;

    // Don't notify if app is in foreground AND user is viewing this chat
    if (_isAppInForeground && _activeChatIds.contains(senderId)) {
      return;
    }

    // Don't notify if app is fully in foreground (user is using the app)
    if (_isAppInForeground) return;

    final displayName = senderName ?? senderId;
    final id = senderId.hashCode.abs() % 100000; // Unique notification ID per sender

    const androidDetails = AndroidNotificationDetails(
      'youchat_messages',
      'Messages',
      channelDescription: 'New message notifications',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/launcher_icon',
      color: Color(0xFF8B0000),
      enableVibration: true,
      playSound: true,
    );

    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      id,
      'YOUchat',
      'New message from $displayName',
      details,
      payload: 'chat:$senderId', // Used for navigation on tap
    );

    debugPrint('[NotificationService] Showed notification for message from $senderId');
  }

  /// Show a notification for an incoming group message.
  Future<void> showGroupMessageNotification({
    required String groupId,
    required String senderId,
    String? groupName,
    String? senderName,
  }) async {
    if (!_initialized) return;

    // Don't notify if app is in foreground AND user is viewing this group
    if (_isAppInForeground && _activeChatIds.contains(groupId)) {
      return;
    }

    if (_isAppInForeground) return;

    final displaySender = senderName ?? senderId;
    final displayGroup = groupName ?? 'Group';
    final id = groupId.hashCode.abs() % 100000;

    const androidDetails = AndroidNotificationDetails(
      'youchat_messages',
      'Messages',
      channelDescription: 'New message notifications',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/launcher_icon',
      color: Color(0xFF8B0000),
      enableVibration: true,
      playSound: true,
    );

    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      id,
      'YOUchat',
      'New message from $displaySender in $displayGroup',
      details,
      payload: 'group:$groupId', // Used for navigation on tap
    );

    debugPrint('[NotificationService] Showed group notification for $groupId from $senderId');
  }

  /// Cancel all notifications (e.g., when user opens the app).
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  /// Cancel notifications for a specific chat.
  Future<void> cancelForChat(String chatId) async {
    final id = chatId.hashCode.abs() % 100000;
    await _plugin.cancel(id);
  }
}
