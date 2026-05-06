import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../auth/auth_manager.dart';
import '../services/group_service.dart';
import '../services/chat_service.dart';
import '../services/user_service.dart';
import 'group_chat_screen.dart';

/// Create Group screen — enter name, search + add members, create.
/// Dark Evil themed.
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameController = TextEditingController();
  final _memberSearchController = TextEditingController();
  final List<String> _selectedMembers = [];
  bool _isSearching = false;
  bool _isCreating = false;
  String? _searchError;
  String? _searchResult;

  @override
  void dispose() {
    _nameController.dispose();
    _memberSearchController.dispose();
    super.dispose();
  }

  Future<void> _searchUser() async {
    final query = _memberSearchController.text.trim();
    if (query.isEmpty) return;

    final currentUserId = context.read<AuthManager>().userId ?? '';
    if (query == currentUserId) {
      setState(() => _searchError = 'You are already in the group');
      return;
    }
    if (_selectedMembers.contains(query)) {
      setState(() => _searchError = 'Already added');
      return;
    }

    setState(() {
      _isSearching = true;
      _searchError = null;
      _searchResult = null;
    });

    final token = context.read<AuthManager>().token;
    if (token == null) return;

    final userService = UserService(getToken: () => token);
    final result = await userService.searchUser(query);

    setState(() {
      _isSearching = false;
      if (result != null) {
        _searchResult = result.userId;
      } else {
        _searchError = 'User not found';
      }
    });
  }

  void _addMember(String userId) {
    setState(() {
      _selectedMembers.add(userId);
      _searchResult = null;
      _memberSearchController.clear();
    });
  }

  void _removeMember(String userId) {
    setState(() {
      _selectedMembers.remove(userId);
    });
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _searchError = 'Enter a group name');
      return;
    }
    if (_selectedMembers.isEmpty) {
      setState(() => _searchError = 'Add at least one member');
      return;
    }

    setState(() => _isCreating = true);

    final token = context.read<AuthManager>().token;
    if (token == null) return;

    final groupService = GroupService(getToken: () => token);
    final group = await groupService.createGroup(name, _selectedMembers);

    if (group != null && mounted) {
      // Register the group conversation in ChatService
      context.read<ChatService>().registerGroupConversation(
            groupId: group.groupId,
            groupName: group.name,
            members: group.members,
          );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => GroupChatScreen(
            groupId: group.groupId,
            groupName: group.name,
            members: group.members,
          ),
        ),
      );
    } else if (mounted) {
      setState(() {
        _isCreating = false;
        _searchError = 'Failed to create group';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
              _buildAppBar(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Group name
                      Text(
                        'Group Name',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF8B0000),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF141416),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: const Color(0xFF8B0000).withOpacity(0.2),
                          ),
                        ),
                        child: TextField(
                          controller: _nameController,
                          style: GoogleFonts.inter(
                              color: Colors.white, fontSize: 15),
                          decoration: InputDecoration(
                            hintText: 'Enter group name',
                            hintStyle:
                                GoogleFonts.inter(color: Colors.white30),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Add members
                      Text(
                        'Add Members',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF8B0000),
                        ),
                      ),
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
                                      .withOpacity(0.2),
                                ),
                              ),
                              child: TextField(
                                controller: _memberSearchController,
                                onSubmitted: (_) => _searchUser(),
                                style: GoogleFonts.inter(
                                    color: Colors.white, fontSize: 15),
                                decoration: InputDecoration(
                                  hintText: 'Enter exact UserID',
                                  hintStyle:
                                      GoogleFonts.inter(color: Colors.white30),
                                  prefixIcon: const Icon(
                                    Icons.alternate_email_rounded,
                                    color: Color(0xFF8B0000),
                                    size: 20,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 14),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF8B0000), Color(0xFF4A0000)],
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _isSearching ? null : _searchUser,
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  width: 50,
                                  height: 50,
                                  alignment: Alignment.center,
                                  child: _isSearching
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.search_rounded,
                                          color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Search result
                      if (_searchResult != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141416),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color:
                                  const Color(0xFF8B0000).withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF4A0000),
                                      Color(0xFF8B0000)
                                    ],
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    _searchResult![0].toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _searchResult!,
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => _addMember(_searchResult!),
                                icon: const Icon(Icons.add_circle_rounded,
                                    color: Color(0xFF8B0000)),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Error
                      if (_searchError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _searchError!,
                          style: GoogleFonts.inter(
                            color: const Color(0xFFFF3B3B),
                            fontSize: 12,
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Selected members
                      if (_selectedMembers.isNotEmpty) ...[
                        Text(
                          'Members (${_selectedMembers.length})',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF8B0000),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _selectedMembers.map((userId) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8B0000)
                                    .withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: const Color(0xFF8B0000)
                                      .withOpacity(0.4),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    userId,
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  GestureDetector(
                                    onTap: () => _removeMember(userId),
                                    child: const Icon(
                                      Icons.close_rounded,
                                      size: 16,
                                      color: Color(0xFFFF3B3B),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],

                      const SizedBox(height: 32),

                      // Create button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF8B0000), Color(0xFF4A0000)],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: ElevatedButton.icon(
                            onPressed: _isCreating ? null : _createGroup,
                            icon: _isCreating
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.group_add_rounded,
                                    size: 20),
                            label: Text(
                              _isCreating ? 'Creating...' : 'Create Group',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
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

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0C).withOpacity(0.9),
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFF8B0000).withOpacity(0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.arrow_back_ios_rounded,
              color: Colors.white70,
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Create Group',
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
