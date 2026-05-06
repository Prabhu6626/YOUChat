import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';
import '../auth/auth_manager.dart';
import '../encryption/signal_protocol_service.dart';
import '../encryption/session_manager.dart';

/// Auth service — handles registration and login with encryption key setup.
class AuthService {
  final AuthManager _authManager;
  final SignalProtocolService _signalService;

  AuthService({
    required AuthManager authManager,
    required SignalProtocolService signalService,
  })  : _authManager = authManager,
        _signalService = signalService;

  /// Register and generate encryption keys.
  Future<Map<String, dynamic>> register(String userId, String passcode) async {
    // 1. Register on server
    final result = await _authManager.register(userId, passcode);

    // Keys are bypassed in plaintext mode
    return result;
  }

  /// Login and initialize encryption if needed.
  Future<Map<String, dynamic>> login(String userId, String passcode) async {
    // 1. Login on server
    final result = await _authManager.login(userId, passcode);

    // Keys are bypassed in plaintext mode
    return result;
  }


  /// Change passcode.
  Future<Map<String, dynamic>> changePasscode(
      String oldPasscode, String newPasscode) async {
    try {
      final response = await http.put(
        Uri.parse(AppConstants.usersProfile),
        headers: {
          'Authorization': 'Bearer ${_authManager.token}',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({
          'oldPasscode': oldPasscode,
          'newPasscode': newPasscode,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'message': 'Passcode changed successfully'};
      } else {
        return {'success': false, 'message': data['error'] ?? 'Failed to change passcode'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error'};
    }
  }

  /// Logout — destroy all keys and sessions.
  Future<void> logout() async {
    await _signalService.clearAll();
    await _authManager.logout();
  }
}
