import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../auth/auth_manager.dart';
import '../services/group_service.dart';
import '../services/user_service.dart';
import '../services/chat_service.dart';
import '../utils/constants.dart';
import 'package:image_picker/image_picker.dart';
import '../widgets/avatar_zoom_viewer.dart';

/// Group Info Screen — WhatsApp-style group management.
/// Shows group name, member list with avatars, add/remove members, leave group.
class GroupInfoScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final List<String> members;
  final String creatorId;
  final List<String> admins;
  final Map<String, dynamic> settings;
  final String? groupPictureUrl;

  const GroupInfoScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.members,
    this.creatorId = '',
    this.admins = const [],
    this.settings = const {'editGroupInfo': 'all', 'sendMessages': 'all'},
    this.groupPictureUrl,
  });

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  late List<String> _members;
  late List<String> _admins;
  late Map<String, dynamic> _settings;
  String? _groupPictureUrl;
  
  final _addMemberController = TextEditingController();
  bool _isSearching = false;
  String? _searchResult;
  String? _error;

  @override
  void initState() {
    super.initState();
    _members = List<String>.from(widget.members);
    _admins = List<String>.from(widget.admins);
    _settings = Map<String, dynamic>.from(widget.settings);
    _groupPictureUrl = widget.groupPictureUrl;
  }

  @override
  void dispose() {
    _addMemberController.dispose();
    super.dispose();
  }

  Future<void> _searchAndAddMember() async {
    final query = _addMemberController.text.trim();
    if (query.isEmpty) return;

    final currentUserId = context.read<AuthManager>().userId ?? '';
    if (_members.contains(query)) {
      setState(() => _error = 'Already a member');
      return;
    }

    setState(() {
      _isSearching = true;
      _error = null;
      _searchResult = null;
    });

    final token = context.read<AuthManager>().token;
    if (token == null) return;

    final userService = UserService(getToken: () => token);
    final result = await userService.searchUser(query);

    if (result == null) {
      setState(() {
        _isSearching = false;
        _error = 'User not found';
      });
      return;
    }

    // Add to group via API
    final groupService = GroupService(getToken: () => token);
    final success = await groupService.addMembers(widget.groupId, [query]);

    setState(() {
      _isSearching = false;
      if (success) {
        _members.add(query);
        _addMemberController.clear();
        _searchResult = null;
        // Update the conversation in ChatService
        context.read<ChatService>().registerGroupConversation(
              groupId: widget.groupId,
              groupName: widget.groupName,
              members: _members,
            );
      } else {
        _error = 'Failed to add member';
      }
    });
  }

  Future<void> _updateGroupDp() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    final token = context.read<AuthManager>().token;
    if (token == null) return;

    final groupService = GroupService(getToken: () => token);
    final url = await groupService.updateGroupDp(widget.groupId, image.path);

    if (url != null && mounted) {
      setState(() {
        _groupPictureUrl = url;
      });
      // Updating chat service so ChatList reflects the new DP immediately
      context.read<ChatService>().registerGroupConversation(
            groupId: widget.groupId,
            groupName: widget.groupName,
            members: _members,
            admins: _admins,
            settings: _settings,
            groupPictureUrl: _groupPictureUrl,
          );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update group display picture. Ensure you have permission.')));
    }
  }

  Future<void> _toggleSetting(String settingType, String newValue) async {
    final token = context.read<AuthManager>().token;
    if (token == null) return;

    final groupService = GroupService(getToken: () => token);
    final success = await groupService.updateGroupSettings(widget.groupId, settingType, newValue);

    if (success && mounted) {
      setState(() {
        _settings[settingType] = newValue;
      });
      context.read<ChatService>().registerGroupConversation(
            groupId: widget.groupId,
            groupName: widget.groupName,
            members: _members,
            admins: _admins,
            settings: _settings,
            groupPictureUrl: _groupPictureUrl,
          );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update setting.')));
    }
  }

  Future<void> _toggleAdmin(String userId, bool promote) async {
    final token = context.read<AuthManager>().token;
    if (token == null) return;

    final groupService = GroupService(getToken: () => token);
    final action = promote ? 'add' : 'remove';
    final success = await groupService.updateGroupAdmins(widget.groupId, action, userId);

    if (success && mounted) {
      setState(() {
        if (promote) {
          if (!_admins.contains(userId)) _admins.add(userId);
        } else {
          _admins.remove(userId);
        }
      });
      context.read<ChatService>().registerGroupConversation(
            groupId: widget.groupId,
            groupName: widget.groupName,
            members: _members,
            admins: _admins,
            settings: _settings,
            groupPictureUrl: _groupPictureUrl,
          );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to change admin status.')));
    }
  }

  Future<void> _removeMember(String userId) async {
    final token = context.read<AuthManager>().token;
    if (token == null) return;

    final groupService = GroupService(getToken: () => token);
    final success = await groupService.removeMember(widget.groupId, userId);

    if (success && mounted) {
      setState(() {
        _members.remove(userId);
        context.read<ChatService>().registerGroupConversation(
              groupId: widget.groupId,
              groupName: widget.groupName,
              members: _members,
            );
      });
    }
  }

  Future<void> _leaveGroup() async {
    final currentUserId = context.read<AuthManager>().userId ?? '';
    final token = context.read<AuthManager>().token;
    if (token == null) return;

    final groupService = GroupService(getToken: () => token);
    final success =
        await groupService.removeMember(widget.groupId, currentUserId);

    if (success && mounted) {
      // Pop back to chat list
      Navigator.pop(context); // pop group info
      Navigator.pop(context); // pop group chat
    }
  }

  void _showLeaveDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141416),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text('Leave Group',
            style: GoogleFonts.inter(
                color: Colors.white, fontWeight: FontWeight.w600)),
        content: Text(
          'Are you sure you want to leave "${widget.groupName}"?',
          style: GoogleFonts.inter(color: Colors.white54, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                Text('Cancel', style: GoogleFonts.inter(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _leaveGroup();
            },
            child: Text('Leave',
                style: GoogleFonts.inter(
                    color: const Color(0xFFFF3B3B),
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showRemoveDialog(String userId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141416),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text('Remove Member',
            style: GoogleFonts.inter(
                color: Colors.white, fontWeight: FontWeight.w600)),
        content: Text(
          'Remove $userId from the group?',
          style: GoogleFonts.inter(color: Colors.white54, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                Text('Cancel', style: GoogleFonts.inter(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _removeMember(userId);
            },
            child: Text('Remove',
                style: GoogleFonts.inter(
                    color: const Color(0xFFFF3B3B),
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.read<AuthManager>().userId ?? '';
    final isCreator = widget.creatorId == currentUserId;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0A0C), Color(0xFF160A0A), Color(0xFF0A0A0C)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // App bar
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A0C).withOpacity(0.9),
                  border: Border(
                    bottom: BorderSide(
                        color: const Color(0xFF8B0000).withOpacity(0.3)),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_rounded,
                          color: Colors.white70, size: 20),
                    ),
                    const SizedBox(width: 8),
                    Text('Group Info',
                        style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Group header
                      Center(
                        child: Column(
                          children: [
                            GestureDetector(
                              onTap: () {
                                if (_groupPictureUrl != null && _groupPictureUrl!.isNotEmpty) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => AvatarZoomViewer(
                                        heroTag: 'group_avatar_${widget.groupId}',
                                        imageUrl: '${AppConstants.serverUrl}$_groupPictureUrl',
                                        title: widget.groupName,
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: Hero(
                                tag: 'group_avatar_${widget.groupId}',
                                child: Stack(
                                  children: [
                                    Container(
                                      width: 100,
                                      height: 100,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(50),
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF4A0000),
                                            Color(0xFF8B0000)
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF8B0000)
                                                .withOpacity(0.4),
                                            blurRadius: 20,
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(50),
                                        child: (_groupPictureUrl != null && _groupPictureUrl!.isNotEmpty)
                                            ? Image.network(
                                                '${AppConstants.serverUrl}$_groupPictureUrl',
                                                fit: BoxFit.cover,
                                                headers: const {'ngrok-skip-browser-warning': 'true'},
                                                errorBuilder: (ctx, err, stack) => const Icon(Icons.group_rounded, color: Colors.white, size: 40),
                                              )
                                            : const Icon(Icons.group_rounded, color: Colors.white, size: 40),
                                      ),
                                    ),
                                    if (_settings['editGroupInfo'] == 'all' || _admins.contains(currentUserId))
                                      Positioned(
                                        bottom: 0,
                                        right: 0,
                                        child: GestureDetector(
                                          onTap: _updateGroupDp,
                                          child: Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: const BoxDecoration(
                                              color: Color(0xFFD30000),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(widget.groupName,
                                style: GoogleFonts.inter(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                            const SizedBox(height: 4),
                            Text('${_members.length} members',
                                style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: const Color(0xFF8B0000))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Group Settings
                      if (_admins.contains(currentUserId)) ...[
                        Text('Group Settings',
                            style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF8B0000))),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF141416),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: const Color(0xFF8B0000).withOpacity(0.2)),
                          ),
                          child: Column(
                            children: [
                              ListTile(
                                title: Text('Edit group info', style: GoogleFonts.inter(color: Colors.white, fontSize: 14)),
                                trailing: DropdownButton<String>(
                                  value: _settings['editGroupInfo'],
                                  dropdownColor: const Color(0xFF141416),
                                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                                  underline: const SizedBox(),
                                  items: const [
                                    DropdownMenuItem(value: 'all', child: Text('All members')),
                                    DropdownMenuItem(value: 'admins', child: Text('Only admins')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) _toggleSetting('editGroupInfo', val);
                                  },
                                ),
                              ),
                              Divider(color: const Color(0xFF8B0000).withOpacity(0.1), height: 1),
                              ListTile(
                                title: Text('Send messages', style: GoogleFonts.inter(color: Colors.white, fontSize: 14)),
                                trailing: DropdownButton<String>(
                                  value: _settings['sendMessages'],
                                  dropdownColor: const Color(0xFF141416),
                                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                                  underline: const SizedBox(),
                                  items: const [
                                    DropdownMenuItem(value: 'all', child: Text('All members')),
                                    DropdownMenuItem(value: 'admins', child: Text('Only admins')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) _toggleSetting('sendMessages', val);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Add member section
                      Text('Add Member',
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF8B0000))),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF141416),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                    color: const Color(0xFF8B0000)
                                        .withOpacity(0.2)),
                              ),
                              child: TextField(
                                controller: _addMemberController,
                                onSubmitted: (_) => _searchAndAddMember(),
                                style: GoogleFonts.inter(
                                    color: Colors.white, fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: 'Enter UserID',
                                  hintStyle: GoogleFonts.inter(
                                      color: Colors.white30),
                                  prefixIcon: const Icon(
                                      Icons.alternate_email_rounded,
                                      color: Color(0xFF8B0000),
                                      size: 18),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF8B0000),
                                    Color(0xFF4A0000)
                                  ]),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _isSearching
                                    ? null
                                    : _searchAndAddMember,
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  width: 46,
                                  height: 46,
                                  alignment: Alignment.center,
                                  child: _isSearching
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2))
                                      : const Icon(Icons.person_add_rounded,
                                          color: Colors.white, size: 20),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 6),
                        Text(_error!,
                            style: GoogleFonts.inter(
                                color: const Color(0xFFFF3B3B),
                                fontSize: 12)),
                      ],
                      const SizedBox(height: 24),

                      // Members list
                      Text('Members',
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF8B0000))),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF141416),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: const Color(0xFF8B0000)
                                  .withOpacity(0.2)),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _members.length,
                          separatorBuilder: (_, __) => Divider(
                            color: const Color(0xFF8B0000).withOpacity(0.1),
                            height: 1,
                          ),
                          itemBuilder: (context, index) {
                            final member = _members[index];
                            final isSelf = member == currentUserId;
                            final memberIsCreator = member == widget.creatorId;
                            final memberIsAdmin = _admins.contains(member);
                            final currentUserIsAdmin = _admins.contains(currentUserId);
                            final canManageMember = currentUserIsAdmin && !isSelf && !memberIsCreator;

                            return ListTile(
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF4A0000), Color(0xFF8B0000)],
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    member[0].toUpperCase(),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Text(member, style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                                  if (isSelf) ...[
                                    const SizedBox(width: 6),
                                    Text('You', style: GoogleFonts.inter(color: Colors.white30, fontSize: 11)),
                                  ],
                                  if (memberIsAdmin) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF8B0000).withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: Text('Admin', style: GoogleFonts.inter(color: const Color(0xFFFF1E1E), fontSize: 10, fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ],
                              ),
                              trailing: canManageMember
                                  ? PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert, color: Colors.white54, size: 20),
                                      color: const Color(0xFF141416),
                                      onSelected: (action) {
                                        if (action == 'remove') {
                                          _showRemoveDialog(member);
                                        } else if (action == 'promote') {
                                          _toggleAdmin(member, true);
                                        } else if (action == 'demote') {
                                          _toggleAdmin(member, false);
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        if (!memberIsAdmin)
                                          PopupMenuItem(
                                            value: 'promote',
                                            child: Text('Make group admin', style: GoogleFonts.inter(color: Colors.white)),
                                          ),
                                        if (memberIsAdmin)
                                          PopupMenuItem(
                                            value: 'demote',
                                            child: Text('Dismiss as admin', style: GoogleFonts.inter(color: Colors.white)),
                                          ),
                                        PopupMenuItem(
                                          value: 'remove',
                                          child: Text('Remove from group', style: GoogleFonts.inter(color: const Color(0xFFFF3B3B))),
                                        ),
                                      ],
                                    )
                                  : null,
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Leave group button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _showLeaveDialog,
                          icon: const Icon(Icons.exit_to_app_rounded,
                              size: 20),
                          label: Text('Leave Group',
                              style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color(0xFFFF3B3B).withOpacity(0.15),
                            foregroundColor: const Color(0xFFFF3B3B),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4)),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
