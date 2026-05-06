import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';
import 'signal_protocol_service.dart';

/// Manages encryption sessions with remote users.
/// Fetches key bundles from server and establishes secure sessions.
class SessionManager {
  final SignalProtocolService _signalService;
  final String Function() _getToken;

  SessionManager({
    required SignalProtocolService signalService,
    required String Function() getToken,
  })  : _signalService = signalService,
        _getToken = getToken;

  /// Ensure a session exists with a remote user.
  /// If not, fetch their key bundle and establish one.
  Future<bool> ensureSession(String remoteUserId) async {
    // Check if session already exists
    if (await _signalService.hasSession(remoteUserId)) {
      debugPrint('[SessionManager] Session exists with $remoteUserId');
      return true;
    }

    debugPrint('[SessionManager] No session with $remoteUserId, fetching key bundle...');

    // Fetch key bundle from server
    try {
      final token = _getToken();
      debugPrint('[SessionManager] Token length: ${token.length}');

      final url = '${AppConstants.keysBundle}/$remoteUserId';
      debugPrint('[SessionManager] Fetching: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      debugPrint('[SessionManager] Response: ${response.statusCode} - ${response.body}');

      if (response.statusCode != 200) {
        debugPrint('[SessionManager] FAILED: Key bundle fetch returned ${response.statusCode}');
        return false;
      }

      final bundle = jsonDecode(response.body);
      debugPrint('[SessionManager] Key bundle received, establishing session...');

      await _signalService.establishSession(remoteUserId, bundle);
      debugPrint('[SessionManager] Session established with $remoteUserId');
      return true;
    } catch (e, stackTrace) {
      debugPrint('[SessionManager] ERROR establishing session: $e');
      debugPrint('[SessionManager] Stack: $stackTrace');
      return false;
    }
  }

  /// Upload key bundle to server.
  Future<bool> uploadKeyBundle(Map<String, dynamic> keyBundle) async {
    try {
      final token = _getToken();
      debugPrint('[SessionManager] Uploading key bundle, token length: ${token.length}');
      debugPrint('[SessionManager] Bundle has ${(keyBundle['preKeys'] as List?)?.length ?? 0} pre-keys');

      final response = await http.post(
        Uri.parse(AppConstants.keysBundle),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(keyBundle),
      );

      debugPrint('[SessionManager] Upload response: ${response.statusCode} - ${response.body}');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[SessionManager] ERROR uploading key bundle: $e');
      return false;
    }
  }

  /// Check and replenish pre-keys if running low.
  Future<void> checkPreKeyCount() async {
    try {
      final response = await http.get(
        Uri.parse(AppConstants.keysCount),
        headers: {
          'Authorization': 'Bearer ${_getToken()}',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final count = data['preKeyCount'] as int;
        debugPrint('[SessionManager] Pre-key count: $count');

        if (count < 20) {
          debugPrint('[SessionManager] Pre-keys low, regenerating...');
          final newKeys = await _signalService.generateKeys();
          await uploadKeyBundle(newKeys);
        }
      }
    } catch (e) {
      debugPrint('[SessionManager] Error checking pre-key count: $e');
    }
  }
}
