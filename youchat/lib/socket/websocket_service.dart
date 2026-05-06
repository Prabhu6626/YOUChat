import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/constants.dart';
import '../services/notification_service.dart';

/// Connection state exposed to UI.
enum WsConnectionState {
  connected,
  connecting,
  disconnected,
}

/// WebSocket service for real-time message delivery.
///
/// Connection strategy — stays connected no matter what:
/// 1. Heartbeat pings every 20s keep the connection alive
/// 2. connectivity_plus detects network changes — reconnects instantly
/// 3. On app resume: force reconnect if disconnected
/// 4. Exponential backoff reconnect (1s → 2s → 4s → ... → 30s max)
/// 5. NEVER gives up reconnecting — only stops on explicit logout
/// 6. Periodic health check every 10s in foreground
/// 7. On reconnect: sync missed messages + flush message queue
class WebSocketService extends ChangeNotifier with WidgetsBindingObserver {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  StreamSubscription? _connectivitySubscription;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  Timer? _healthCheckTimer;

  bool _isConnected = false;
  bool _isDisconnectedByUser = false;
  bool _isConnecting = false;
  String? _token;
  int _reconnectAttempts = 0;
  static const Duration _heartbeatInterval = Duration(seconds: 20);
  static const Duration _healthCheckInterval = Duration(seconds: 10);

  // Connection state for UI
  WsConnectionState _connectionState = WsConnectionState.disconnected;
  WsConnectionState get connectionState => _connectionState;

  bool get isConnected => _isConnected;
  String? get currentToken => _token;

  // ── Reconnect callback — ChatService hooks into this ──
  VoidCallback? onReconnected;

  // 1:1 message handlers
  Function(Map<String, dynamic>)? onMessage;
  Function(Map<String, dynamic>)? onReadReceipt;
  Function(Map<String, dynamic>)? onForceDelete;
  Function(Map<String, dynamic>)? onMessageSent;
  Function(Map<String, dynamic>)? onTypingIndicator;
  Function(List<String>)? onPendingDeletions;
  Function(Map<String, dynamic>)? onDeliveryReceipt;
  Function(Map<String, dynamic>)? onUserStatus;

  // Group message handlers
  Function(Map<String, dynamic>)? onGroupMessage;
  Function(Map<String, dynamic>)? onGroupReadReceipt;
  Function(Map<String, dynamic>)? onGroupTypingIndicator;

  /// Connect to WebSocket server with JWT token.
  Future<void> connect(String token) async {
    _token = token;
    _isDisconnectedByUser = false;
    _reconnectAttempts = 0;

    WidgetsBinding.instance.addObserver(this);
    await NotificationService().init();
    _startConnectivityMonitoring();
    _startHealthCheck();

    await _connectInternal();
  }

  // ── Network connectivity monitoring ──

  void _startConnectivityMonitoring() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);

      debugPrint('[WebSocket] Network changed: $results, hasNetwork: $hasNetwork');

      if (_isDisconnectedByUser || _token == null) return;

      if (hasNetwork && !_isConnected && !_isConnecting) {
        debugPrint('[WebSocket] Network restored — reconnecting immediately');
        _reconnectAttempts = 0;
        _reconnectTimer?.cancel();
        _connectInternal();
      } else if (!hasNetwork && _isConnected) {
        debugPrint('[WebSocket] Network lost');
        _setConnectionState(WsConnectionState.disconnected);
      }
    });
  }

  // ── Health check ──

  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (_) {
      if (_isDisconnectedByUser || _token == null) return;

      if (!_isConnected && !_isConnecting) {
        debugPrint('[WebSocket] Health check: disconnected — reconnecting');
        _reconnectAttempts = 0;
        _connectInternal();
      }
    });
  }

  // ── App lifecycle ──

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('[WebSocket] App lifecycle: $state');

    if (_isDisconnectedByUser || _token == null) return;

    switch (state) {
      case AppLifecycleState.resumed:
        NotificationService().setAppInForeground(true);
        NotificationService().cancelAll();

        if (!_isConnected) {
          debugPrint('[WebSocket] App resumed — reconnecting NOW');
          _reconnectAttempts = 0;
          _reconnectTimer?.cancel();
          _connectInternal();
        } else {
          _sendPing();
        }
        _startHealthCheck();
        break;

      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        NotificationService().setAppInForeground(false);
        break;

      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        NotificationService().setAppInForeground(false);
        break;
    }
  }

  // ── Core connection ──

  Future<void> _connectInternal() async {
    if (_token == null || _isDisconnectedByUser) return;
    if (_isConnecting) return;

    _isConnecting = true;
    _setConnectionState(WsConnectionState.connecting);

    try {
      _stopHeartbeat();
      await _subscription?.cancel();
      _subscription = null;
      try { await _channel?.sink.close(); } catch (_) {}
      _channel = null;

      final wsUrl = '${AppConstants.wsUrl}?token=$_token';
      debugPrint('[WebSocket] Connecting...');

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      try {
        await _channel!.ready;
      } catch (e) {
        debugPrint('[WebSocket] Connection FAILED: $e');
        _isConnected = false;
        _isConnecting = false;
        _setConnectionState(WsConnectionState.disconnected);
        _scheduleReconnect();
        return;
      }

      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          debugPrint('[WebSocket] Stream error: $error');
          _isConnected = false;
          _isConnecting = false;
          _stopHeartbeat();
          _setConnectionState(WsConnectionState.disconnected);
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('[WebSocket] Stream closed');
          _isConnected = false;
          _isConnecting = false;
          _stopHeartbeat();
          _setConnectionState(WsConnectionState.disconnected);
          if (!_isDisconnectedByUser) _scheduleReconnect();
        },
      );

      final wasDisconnected = !_isConnected;
      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _setConnectionState(WsConnectionState.connected);
      debugPrint('[WebSocket] ✅ Connected successfully');

      _startHeartbeat();

      // Request missed messages from server
      _send({'type': 'get_missed_messages'});

      // Notify ChatService to flush queue + sync
      if (wasDisconnected && onReconnected != null) {
        onReconnected!();
      }
    } catch (e) {
      debugPrint('[WebSocket] Connection error: $e');
      _isConnected = false;
      _isConnecting = false;
      _setConnectionState(WsConnectionState.disconnected);
      _scheduleReconnect();
    }
  }

  void _setConnectionState(WsConnectionState state) {
    if (_connectionState != state) {
      _connectionState = state;
      notifyListeners();
    }
  }

  // ── Heartbeat ──

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _sendPing());
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _sendPing() {
    if (_isConnected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode({'type': 'ping'}));
      } catch (e) {
        debugPrint('[WebSocket] Ping failed: $e');
        _isConnected = false;
        _stopHeartbeat();
        _setConnectionState(WsConnectionState.disconnected);
        _scheduleReconnect();
      }
    }
  }

  // ── Message handling ──

  void _handleMessage(dynamic rawData) {
    try {
      final data = jsonDecode(rawData.toString()) as Map<String, dynamic>;
      final type = data['type'] as String?;

      if (type == 'pong') return;

      switch (type) {
        case 'message':
          onMessage?.call(data);
          NotificationService().showMessageNotification(
            senderId: data['from'] as String? ?? 'Unknown',
          );
          break;
        case 'read_receipt':
          onReadReceipt?.call(data);
          break;
        case 'force_delete':
          onForceDelete?.call(data);
          break;
        case 'message_sent':
          onMessageSent?.call(data);
          break;
        case 'delivery_receipt':
          onDeliveryReceipt?.call(data);
          break;
        case 'typing_indicator':
          onTypingIndicator?.call(data);
          break;
        case 'pending_deletions':
          final messageIds = (data['messageIds'] as List<dynamic>)
              .map((e) => e.toString())
              .toList();
          onPendingDeletions?.call(messageIds);
          break;
        case 'group_message':
          onGroupMessage?.call(data);
          NotificationService().showGroupMessageNotification(
            groupId: data['groupId'] as String? ?? '',
            senderId: data['from'] as String? ?? 'Unknown',
          );
          break;
        case 'group_read_receipt':
          onGroupReadReceipt?.call(data);
          break;
        case 'group_typing_indicator':
          onGroupTypingIndicator?.call(data);
          break;
        case 'user_status':
          onUserStatus?.call(data);
          break;
        default:
          debugPrint('[WebSocket] Unknown type: $type');
      }
    } catch (e) {
      debugPrint('[WebSocket] Error handling message: $e');
    }
  }

  // ── Send methods ──

  void sendMessage({
    required String to,
    required String content,
    required String messageId,
    String? mediaUrl,
    String? mediaType,
    String? originalName,
    String? encryptedKey,
    int? voiceDuration,
  }) {
    final msg = <String, dynamic>{
      'type': 'message',
      'to': to,
      'content': content,
      'messageId': messageId,
    };
    if (mediaUrl != null) msg['mediaUrl'] = mediaUrl;
    if (mediaType != null) msg['mediaType'] = mediaType;
    if (originalName != null) msg['originalName'] = originalName;
    if (encryptedKey != null) msg['encryptedKey'] = encryptedKey;
    if (voiceDuration != null) msg['voiceDuration'] = voiceDuration;
    _send(msg);
  }

  void sendReadReceipt({required String messageId, required String to}) {
    _send({'type': 'read_receipt', 'messageId': messageId, 'to': to});
  }

  void sendDeleteAck(String messageId) {
    _send({'type': 'delete_ack', 'messageId': messageId});
  }

  void sendDeleteMedia(String mediaUrl) {
    _send({'type': 'delete_media', 'mediaUrl': mediaUrl});
  }

  void sendTypingIndicator({required String to, required bool isTyping}) {
    _send({'type': 'typing_indicator', 'to': to, 'isTyping': isTyping});
  }

  void sendDeliveryAck({required String messageId, required String senderId}) {
    _send({'type': 'delivery_ack', 'messageId': messageId, 'senderId': senderId});
  }

  void sendGroupMessage({
    required String groupId,
    required String content,
    required String messageId,
    String? mediaUrl,
    String? mediaType,
    String? originalName,
    String? encryptedKey,
    int? voiceDuration,
  }) {
    final msg = <String, dynamic>{
      'type': 'group_message',
      'groupId': groupId,
      'content': content,
      'messageId': messageId,
    };
    if (mediaUrl != null) msg['mediaUrl'] = mediaUrl;
    if (mediaType != null) msg['mediaType'] = mediaType;
    if (originalName != null) msg['originalName'] = originalName;
    if (encryptedKey != null) msg['encryptedKey'] = encryptedKey;
    if (voiceDuration != null) msg['voiceDuration'] = voiceDuration;
    _send(msg);
  }

  void sendGroupReadReceipt({
    required String messageId,
    required String groupId,
    required String senderId,
  }) {
    _send({
      'type': 'group_read_receipt',
      'messageId': messageId,
      'groupId': groupId,
      'senderId': senderId,
    });
  }

  void sendGroupTypingIndicator({required String groupId, required bool isTyping}) {
    _send({'type': 'group_typing_indicator', 'groupId': groupId, 'isTyping': isTyping});
  }

  /// Send data via WebSocket. Returns true if sent, false if queued/failed.
  bool _send(Map<String, dynamic> data) {
    if (_isConnected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode(data));
        return true;
      } catch (e) {
        debugPrint('[WebSocket] Send error: $e');
        _isConnected = false;
        _stopHeartbeat();
        _setConnectionState(WsConnectionState.disconnected);
        _scheduleReconnect();
        return false;
      }
    } else {
      debugPrint('[WebSocket] Cannot send — not connected');
      if (_token != null && !_isDisconnectedByUser && !_isConnecting) {
        _scheduleReconnect();
      }
      return false;
    }
  }

  /// Public send — used by ChatService to send raw data (for queue flush).
  bool sendRaw(Map<String, dynamic> data) => _send(data);

  // ── Reconnection ──

  void _scheduleReconnect() {
    if (_token == null || _isDisconnectedByUser || _isConnecting) return;

    _reconnectTimer?.cancel();
    final delaySec = (1 << _reconnectAttempts).clamp(1, 30);
    _reconnectAttempts++;
    if (_reconnectAttempts > 20) _reconnectAttempts = 5;

    debugPrint('[WebSocket] Reconnecting in ${delaySec}s (attempt $_reconnectAttempts)');
    _setConnectionState(WsConnectionState.connecting);

    _reconnectTimer = Timer(Duration(seconds: delaySec), () {
      if (!_isDisconnectedByUser && _token != null) {
        _connectInternal();
      }
    });
  }

  // ── Disconnect (logout only) ──

  void disconnect() {
    debugPrint('[WebSocket] Disconnecting (user logout)');
    _isDisconnectedByUser = true;
    _isConnecting = false;
    _reconnectTimer?.cancel();
    _stopHeartbeat();
    _healthCheckTimer?.cancel();
    _connectivitySubscription?.cancel();
    _subscription?.cancel();
    try { _channel?.sink.close(); } catch (_) {}
    _isConnected = false;
    _token = null;
    _setConnectionState(WsConnectionState.disconnected);

    WidgetsBinding.instance.removeObserver(this);
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
