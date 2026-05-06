class UserModel {
  final String userId;
  final String bio;
  final String profilePictureUrl;

  UserModel({
    required this.userId,
    this.bio = '',
    this.profilePictureUrl = '',
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      userId: json['userId'] ?? '',
      bio: json['bio'] ?? '',
      profilePictureUrl: json['profilePictureUrl'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'bio': bio,
      'profilePictureUrl': profilePictureUrl,
    };
  }
}
