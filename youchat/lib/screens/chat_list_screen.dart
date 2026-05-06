import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/chat_service.dart';
import '../widgets/chat_list_tile.dart';
import 'chat_screen.dart';
import 'group_chat_screen.dart';
import 'create_group_screen.dart';
import 'search_screen.dart';
import 'profile_screen.dart';
import '../widgets/connection_banner.dart';

/// Chat list screen — main page showing all conversations.
/// Bottom navigation: Chats | Search | Profile
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const _ChatsPage(),
      const SearchScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0A0A0C),
              Color(0xFF160A0A),
            ],
          ),
        ),
        child: pages[_currentIndex],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0C),
          border: Border(
            top: BorderSide(
              color: const Color(0xFF8B0000).withOpacity(0.3),
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: const Color(0xFFD30000),
          unselectedItemColor: Colors.white38,
          selectedLabelStyle: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: GoogleFonts.inter(fontSize: 11),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_rounded),
              label: 'Chats',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.search_rounded),
              label: 'Search',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatsPage extends StatelessWidget {
  const _ChatsPage();

  void _showComposeOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141416),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF8B0000).withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B0000).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.person_add_rounded,
                      color: Color(0xFF8B0000), size: 20),
                ),
                title: Text(
                  'New Chat',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  'Start a 1:1 conversation',
                  style: GoogleFonts.inter(
                    color: Colors.white38,
                    fontSize: 12,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  // Switch to search tab — find parent ChatListScreen
                  final state = context
                      .findAncestorStateOfType<_ChatListScreenState>();
                  if (state != null) {
                    state.setState(() => state._currentIndex = 1);
                  }
                },
              ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B0000).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.group_add_rounded,
                      color: Color(0xFF8B0000), size: 20),
                ),
                title: Text(
                  'New Group',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  'Create a group chat',
                  style: GoogleFonts.inter(
                    color: Colors.white38,
                    fontSize: 12,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CreateGroupScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ConnectionBanner(),
          
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Messages',
                      style: GoogleFonts.outfit(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF1E1E),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'S E C U R E   M E S S A G I N G',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF8B0000),
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF141416),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: const Color(0xFF8B0000).withOpacity(0.2)),
                  ),
                  child: IconButton(
                    onPressed: () => _showComposeOptions(context),
                    icon: const Icon(
                      Icons.edit_rounded,
                      color: Color(0xFFD30000),
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Conversation list
          Expanded(
            child: Consumer<ChatService>(
              builder: (context, chatService, _) {
                final conversations = chatService.conversations;

                if (conversations.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.rectangle,
                            borderRadius: BorderRadius.circular(8),
                            color: const Color(0xFF141416),
                            border: Border.all(
                              color:
                                  const Color(0xFF8B0000).withOpacity(0.3),
                            ),
                          ),
                          child: const Icon(
                            Icons.lock_rounded,
                            size: 36,
                            color: Color(0xFF8B0000),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No conversations yet',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            color: Colors.white54,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Search for a user to start\nan encrypted chat',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.white30,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(top: 4),
                  itemCount: conversations.length,
                  itemBuilder: (context, index) {
                    final conv = conversations[index];
                    return ChatListTile(
                      conversation: conv,
                      onTap: () {
                        if (conv.isGroup) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupChatScreen(
                                groupId: conv.groupId!,
                                groupName: conv.groupName ?? conv.peerId,
                                members: conv.members,
                              ),
                            ),
                          );
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ChatScreen(peerId: conv.peerId),
                            ),
                          );
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
