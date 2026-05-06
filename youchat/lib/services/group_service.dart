import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/group_model.dart';
import '../utils/constants.dart';

/// HTTP service for group CRUD operations.
class GroupService {
  final String Function() getToken;

  GroupService({required this.getToken});

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${getToken()}',
        'ngrok-skip-browser-warning': 'true',
      };

  /// Create a new group.
  Future<GroupModel?> createGroup(String name, List<String> members) async {
    try {
      final response = await http.post(
        Uri.parse(AppConstants.groupsBase),
        headers: _headers,
        body: jsonEncode({'name': name, 'members': members}),
      );

      if (response.statusCode == 201) {
        return GroupModel.fromJson(jsonDecode(response.body));
      } else {
        final error = jsonDecode(response.body)['error'] ?? 'Unknown error';
        debugPrint('[GroupService] Create failed: $error');
        return null;
      }
    } catch (e) {
      debugPrint('[GroupService] Create error: $e');
      return null;
    }
  }

  /// Get all groups the user belongs to.
  Future<List<GroupModel>> getMyGroups() async {
    try {
      final response = await http.get(
        Uri.parse(AppConstants.groupsBase),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List<dynamic>;
        return list.map((g) => GroupModel.fromJson(g)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('[GroupService] List error: $e');
      return [];
    }
  }

  /// Get a single group's details.
  Future<GroupModel?> getGroup(String groupId) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.groupsBase}/$groupId'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        return GroupModel.fromJson(jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      debugPrint('[GroupService] Get error: $e');
      return null;
    }
  }

  /// Add members to a group.
  Future<bool> addMembers(String groupId, List<String> members) async {
    try {
      final response = await http.put(
        Uri.parse('${AppConstants.groupsBase}/$groupId/members'),
        headers: _headers,
        body: jsonEncode({'members': members}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[GroupService] Add members error: $e');
      return false;
    }
  }

  /// Remove a member from a group.
  Future<bool> removeMember(String groupId, String userId) async {
    try {
      final response = await http.delete(
        Uri.parse('${AppConstants.groupsBase}/$groupId/members/$userId'),
        headers: _headers,
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[GroupService] Remove member error: $e');
      return false;
    }
  }

  /// Update group settings (sendMessages, editGroupInfo).
  Future<bool> updateGroupSettings(String groupId, String settingType, String value) async {
    try {
      final response = await http.put(
        Uri.parse('${AppConstants.groupsBase}/$groupId/settings'),
        headers: _headers,
        body: jsonEncode({settingType: value}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[GroupService] Update settings error: $e');
      return false;
    }
  }

  /// Update group admins (add or remove).
  Future<bool> updateGroupAdmins(String groupId, String action, String userId) async {
    try {
      final response = await http.put(
        Uri.parse('${AppConstants.groupsBase}/$groupId/admins'),
        headers: _headers,
        body: jsonEncode({'action': action, 'userId': userId}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[GroupService] Update admins error: $e');
      return false;
    }
  }

  /// Update group display picture.
  Future<String?> updateGroupDp(String groupId, String imagePath) async {
    try {
      var request = http.MultipartRequest(
        'PUT',
        Uri.parse('${AppConstants.groupsBase}/$groupId/dp'),
      );
      request.headers['Authorization'] = 'Bearer ${getToken()}';
      request.headers['ngrok-skip-browser-warning'] = 'true';
      request.files.add(await http.MultipartFile.fromPath('groupPicture', imagePath));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['groupPictureUrl'];
      }
      return null;
    } catch (e) {
      debugPrint('[GroupService] Update DP error: $e');
      return null;
    }
  }
}
