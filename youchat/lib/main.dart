import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'auth/auth_manager.dart';
import 'encryption/signal_protocol_service.dart';
import 'encryption/session_manager.dart';
import 'socket/websocket_service.dart';
import 'services/chat_service.dart';

import 'package:firebase_core/firebase_core.dart';
import 'services/fcm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp();
    // Initialize FCM Service
    await FcmService().init();
  } catch (e) {
    debugPrint('Firebase initialization failed (missing google-services.json?): $e');
  }

  // Lock orientation to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style (dark status bar)
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A0A1A),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Initialize auth manager
  final authManager = AuthManager();
  await authManager.init();

  // Initialize encryption service
  final signalService = SignalProtocolService();

  // Initialize WebSocket service
  final wsService = WebSocketService();

  // Initialize session manager
  final sessionManager = SessionManager(
    signalService: signalService,
    getToken: () => authManager.token ?? '',
  );

  // Initialize chat service
  final chatService = ChatService(
    signalService: signalService,
    wsService: wsService,
    sessionManager: sessionManager,
    getCurrentUserId: () => authManager.userId ?? '',
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authManager),
        Provider.value(value: signalService),
        ChangeNotifierProvider.value(value: wsService),
        ChangeNotifierProvider.value(value: chatService),
      ],
      child: const YOUChatApp(),
    ),
  );
}
