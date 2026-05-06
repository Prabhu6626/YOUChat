/// Represents a conversation in the chat list.
/// Supports both 1:1 and group conversations.
/// Stored in-memory only.
class ConversationModel {
  final String peerId; // The other user's userId (for 1:1) or groupId (for groups)
  String peerBio;
  String peerProfilePictureUrl;
  String lastMessagePreview;
  DateTime lastMessageTime;
  int unreadCount;
  bool isPeerOnline;
  bool isPeerTyping;
  String typingUserId; // Who is typing (for groups)

  // Group fields
  final bool isGroup;
  final String? groupId;
  String? groupName;
  List<String> members;
  List<String> admins;
  Map<String, dynamic> settings;
  String? groupPictureUrl;

  ConversationModel({
    required this.peerId,
    this.peerBio = '',
    this.peerProfilePictureUrl = '',
    this.lastMessagePreview = '🔒 Encrypted message',
    DateTime? lastMessageTime,
    this.unreadCount = 0,
    this.isPeerOnline = false,
    this.isPeerTyping = false,
    this.typingUserId = '',
    this.isGroup = false,
    this.groupId,
    this.groupName,
    List<String>? members,
    List<String>? admins,
    Map<String, dynamic>? settings,
    this.groupPictureUrl,
  })  : lastMessageTime = lastMessageTime ?? DateTime.now(),
        members = members ?? [],
        admins = admins ?? [],
        settings = settings ?? {'editGroupInfo': 'all', 'sendMessages': 'all'};

  void updateLastMessage(DateTime time) {
    lastMessagePreview = '🔒 Encrypted message';
    lastMessageTime = time;
  }

  /// Display name — group name for groups, peerId for 1:1
  String get displayName => isGroup ? (groupName ?? peerId) : peerId;
}
