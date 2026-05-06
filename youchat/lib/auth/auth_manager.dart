import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../services/fcm_service.dart';
import '../utils/constants.dart';

/// Manages authentication state — JWT token, login/logout.
class AuthManager extends ChangeNotifier {
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  String? _token;
  String? _userId;
  bool _isLoading = false;

  String? get token => _token;
  String? get userId => _userId;
  bool get isAuthenticated => _token != null;
  bool get isLoading => _isLoading;

  /// Initialize — check for existing token.
  Future<void> init() async {
    _token = await _storage.read(key: AppConstants.storageTokenKey);
    _userId = await _storage.read(key: AppConstants.storageUserIdKey);
    notifyListeners();
  }

  /// Register with userId and passcode.
  Future<Map<String, dynamic>> register(String userId, String passcode) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse(AppConstants.authRegister),
        headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'},
        body: jsonEncode({'userId': userId, 'passcode': passcode}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        await _saveAuth(data['token'], data['userId']);
        return {'success': true, 'message': 'Registration successful'};
      } else {
        return {'success': false, 'message': data['error'] ?? 'Registration failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error. Please try again.'};
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Login with userId and passcode.
  Future<Map<String, dynamic>> login(String userId, String passcode) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse(AppConstants.authLogin),
        headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'},
        body: jsonEncode({'userId': userId, 'passcode': passcode}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        await _saveAuth(data['token'], data['userId']);
        return {'success': true, 'message': 'Login successful'};
      } else {
        return {'success': false, 'message': data['error'] ?? 'Login failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error. Please try again.'};
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Save auth tokens securely.
  Future<void> _saveAuth(String token, String userId) async {
    _token = token;
    _userId = userId;
    await _storage.write(key: AppConstants.storageTokenKey, value: token);
    await _storage.write(key: AppConstants.storageUserIdKey, value: userId);
    notifyListeners();

    // After auth, try to sync FCM token to server
    try {
      final fcmService = FcmService();
      await fcmService.sendTokenToServer(token);
    } catch (_) {}
  }

  /// Logout — clear everything.
  Future<void> logout() async {
    _token = null;
    _userId = null;
    await _storage.delete(key: AppConstants.storageTokenKey);
    await _storage.delete(key: AppConstants.storageUserIdKey);
    notifyListeners();
  }
}
