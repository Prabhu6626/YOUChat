import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';
import '../models/user_model.dart';

/// User service — profile management and user search.
class UserService {
  final String Function() _getToken;

  UserService({required String Function() getToken}) : _getToken = getToken;

  /// Search for a user by exact userId.
  Future<UserModel?> searchUser(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.usersSearch}?userId=$userId'),
        headers: {
          'Authorization': 'Bearer ${_getToken()}',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (response.statusCode == 200) {
        return UserModel.fromJson(jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get own profile.
  Future<UserModel?> getMyProfile() async {
    try {
      final response = await http.get(
        Uri.parse(AppConstants.usersMe),
        headers: {
          'Authorization': 'Bearer ${_getToken()}',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (response.statusCode == 200) {
        return UserModel.fromJson(jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Update bio.
  Future<bool> updateBio(String bio) async {
    try {
      final response = await http.put(
        Uri.parse(AppConstants.usersProfile),
        headers: {
          'Authorization': 'Bearer ${_getToken()}',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({'bio': bio}),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Upload profile picture.
  Future<String?> uploadProfilePicture(String filePath) async {
    try {
      final request = http.MultipartRequest(
        'PUT',
        Uri.parse(AppConstants.usersProfile),
      );
      request.headers['Authorization'] = 'Bearer ${_getToken()}';
      request.headers['ngrok-skip-browser-warning'] = 'true';
      request.files.add(
        await http.MultipartFile.fromPath('profilePicture', filePath),
      );

      final response = await request.send();
      if (response.statusCode == 200) {
        return 'Profile picture updated';
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
