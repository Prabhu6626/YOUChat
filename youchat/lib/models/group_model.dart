/// Represents a group in the app.
class GroupModel {
  final String groupId;
  final String name;
  final String creatorId;
  final List<String> members;
  final List<String> admins;
  final Map<String, dynamic> settings;
  final String? groupPictureUrl;
  final DateTime createdAt;

  GroupModel({
    required this.groupId,
    required this.name,
    required this.creatorId,
    required this.members,
    this.admins = const [],
    this.settings = const {'editGroupInfo': 'all', 'sendMessages': 'all'},
    this.groupPictureUrl,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory GroupModel.fromJson(Map<String, dynamic> json) {
    return GroupModel(
      groupId: json['groupId'] as String,
      name: json['name'] as String,
      creatorId: json['creatorId'] as String,
      members: (json['members'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      admins: (json['admins'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [json['creatorId'] as String],
      settings: json['settings'] as Map<String, dynamic>? ?? {'editGroupInfo': 'all', 'sendMessages': 'all'},
      groupPictureUrl: json['groupPictureUrl'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }
}
