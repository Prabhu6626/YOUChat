import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'auth/auth_manager.dart';
import 'socket/websocket_service.dart';
import 'services/chat_service.dart';
import 'services/notification_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/chat_list_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/group_chat_screen.dart';
import 'widgets/secure_screen_wrapper.dart';

/// Global navigator key for notification-tap navigation.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// App shell — theme, routing, provider setup.
/// Dark theme with electric blue and violet accent palette.
class YOUChatApp extends StatelessWidget {
  const YOUChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YOUChat',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0C),
        primaryColor: const Color(0xFF8B0000),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF8B0000),
          secondary: Color(0xFFD30000),
          surface: Color(0xFF141416),
          error: Color(0xFFFF3B3B),
        ),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData.dark().textTheme,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A0A0C),
          elevation: 0,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
      home: const SecureScreenWrapper(
        child: _AuthGate(),
      ),
    );
  }
}

/// Auth gate — shows login or main screen based on auth state.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    final authManager = context.read<AuthManager>();

    if (authManager.isAuthenticated) {
      _connectWebSocket(authManager);
    }

    // Listen for auth changes
    authManager.addListener(() {
      if (authManager.isAuthenticated) {
        _connectWebSocket(authManager);
      } else {
        context.read<WebSocketService>().disconnect();
      }
    });

    // Setup notification tap handler — navigate to chat when tapped
    NotificationService().onNotificationTap = _handleNotificationTap;
  }

  void _connectWebSocket(AuthManager authManager) {
    if (authManager.token != null) {
      context.read<WebSocketService>().connect(authManager.token!);
      // Load groups from server so they persist across app restarts
      context.read<ChatService>().loadGroupsFromServer(authManager.token!);
    }
  }

  /// Handle notification tap — navigate to the relevant chat.
  void _handleNotificationTap(String? payload) {
    if (payload == null) return;

    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    if (payload.startsWith('chat:')) {
      final peerId = payload.substring(5);
      navigator.push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            peerId: peerId,
          ),
        ),
      );
    } else if (payload.startsWith('group:')) {
      final groupId = payload.substring(6);
      navigator.push(
        MaterialPageRoute(
          builder: (_) => GroupChatScreen(
            groupId: groupId,
            groupName: 'Group',
            members: const [],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthManager>(
      builder: (context, auth, _) {
        if (auth.isAuthenticated) {
          return const ChatListScreen();
        }
        return const LoginScreen();
      },
    );
  }
}
