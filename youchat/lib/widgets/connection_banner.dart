import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../socket/websocket_service.dart';

/// Animated connection status banner.
///
/// Shows at the top of chat screens:
/// - 🟢 Connected → hidden (no banner)
/// - 🟡 Reconnecting → yellow banner with spinner
/// - 🔴 Disconnected → red banner with warning
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<WebSocketService>(
      builder: (context, wsService, _) {
        final state = wsService.connectionState;

        // Don't show banner when connected
        if (state == WsConnectionState.connected) {
          return const SizedBox.shrink();
        }

        final isReconnecting = state == WsConnectionState.connecting;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isReconnecting
                  ? [const Color(0xFF8B6914), const Color(0xFF6B4F0A)]
                  : [const Color(0xFF8B1A1A), const Color(0xFF5C0E0E)],
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isReconnecting)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                  ),
                )
              else
                const Icon(
                  Icons.cloud_off_rounded,
                  color: Colors.white70,
                  size: 16,
                ),
              const SizedBox(width: 8),
              Text(
                isReconnecting ? 'Reconnecting...' : 'No internet connection',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
