import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../utils/constants.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If you're going to use other Firebase services in the background, such as Firestore,
  // make sure you call `Firebase.initializeApp()` here too.
  debugPrint('[FCM] Handling a background message: ${message.messageId}');
  
  // Create a local notification for the background message
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  
  // NOTE: You would normally configure flutter_local_notifications here,
  // but let's assume it's already configured in main.dart or notification_service.dart.
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'youchat_messages',
    'Messages',
    importance: Importance.max,
    priority: Priority.high,
  );
  const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);

  await flutterLocalNotificationsPlugin.show(
    message.hashCode,
    message.notification?.title ?? 'YOUchat',
    message.notification?.body ?? 'New message',
    platformChannelSpecifics,
  );
}

class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  String? _fcmToken;

  /// Initialize FCM
  Future<void> init() async {
    // Request permission (Required for iOS, also good practice for Android 13+)
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    debugPrint('[FCM] User granted permission: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      // Get the token right away
      await _getToken();

      // Listen for token refresh
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        // Optionally re-send to server if we have the auth token available
      });

      // Register background handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('[FCM] Got a message whilst in the foreground!');
        debugPrint('[FCM] Message data: ${message.data}');

        if (message.notification != null) {
          debugPrint('[FCM] Message also contained a notification: ${message.notification}');
          // Note: In foreground, our WebSocket will likely process the message.
          // Depending on logic, we might suppress the FCM local notification here 
          // if we are actively looking at the chat.
        }
      });
    }
  }

  /// Gets the FCM token
  Future<String?> _getToken() async {
    try {
      _fcmToken = await _firebaseMessaging.getToken();
      debugPrint('[FCM] Token: $_fcmToken');
      return _fcmToken;
    } catch (e) {
      debugPrint('[FCM] Error getting token: $e');
      return null;
    }
  }

  /// Sends the FCM token to our Node.js backend
  Future<void> sendTokenToServer(String authToken) async {
    final token = await _getToken();
    if (token == null) return;

    try {
      final response = await http.post(
        Uri.parse('${AppConstants.serverUrl}/api/users/fcm-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'token': token}),
      );

      if (response.statusCode == 200) {
        debugPrint('[FCM] Token sent to backend successfully');
      } else {
        debugPrint('[FCM] Failed to send token to backend: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[FCM] Network error sending token to backend: $e');
    }
  }
}
