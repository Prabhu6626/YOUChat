import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../auth/auth_manager.dart';
import '../services/chat_service.dart';
import '../services/user_service.dart';
import '../models/user_model.dart';
import 'chat_screen.dart';

/// Search screen — find users by exact UserID.
/// No suggestions, no recommendations, no contact syncing.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  UserModel? _searchResult;
  bool _isLoading = false;
  bool _hasSearched = false;
  String? _errorMessage;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _searchResult = null;
      _hasSearched = true;
      _errorMessage = null;
    });

    final token = context.read<AuthManager>().token;
    if (token == null) return;

    final userService = UserService(getToken: () => token);
    final result = await userService.searchUser(query);

    setState(() {
      _isLoading = false;
      _searchResult = result;
      if (result == null) {
        _errorMessage = 'User not found';
      }
    });
  }

  void _startChat(UserModel user) {
    context.read<ChatService>().startConversation(
          user.userId,
          bio: user.bio,
          profilePictureUrl: user.profilePictureUrl,
        );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(peerId: user.userId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Search',
              style: GoogleFonts.outfit(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Find users by exact UserID',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.white38,
              ),
            ),
            const SizedBox(height: 24),

            // Search bar
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF141416),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: const Color(0xFF8B0000).withOpacity(0.2),
                      ),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onSubmitted: (_) => _search(),
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 15,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Enter exact UserID',
                        hintStyle: GoogleFonts.inter(color: Colors.white30),
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
                      onTap: _isLoading ? null : _search,
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        width: 50,
                        height: 50,
                        alignment: Alignment.center,
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.search_rounded,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Search result
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(
                    color: Color(0xFF8B0000),
                  ),
                ),
              )
            else if (_searchResult != null)
              _buildUserCard(_searchResult!)
            else if (_hasSearched && _errorMessage != null)
              _buildEmptyState()
            else
              _buildInitialState(),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(UserModel user) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF8B0000).withOpacity(0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B0000).withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Avatar
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.rectangle,
              borderRadius: BorderRadius.circular(8),
              gradient: const LinearGradient(
                colors: [Color(0xFF4A0000), Color(0xFF8B0000)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8B0000).withOpacity(0.3),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Center(
              child: Text(
                user.userId[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            user.userId,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          if (user.bio.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              user.bio,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.white54,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 20),
          // Start Chat button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B0000), Color(0xFF4A0000)],
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: ElevatedButton.icon(
                onPressed: () => _startChat(user),
                icon: const Icon(Icons.lock_rounded, size: 18),
                label: Text(
                  'Start Encrypted Chat',
                  style: GoogleFonts.inter(
                    fontSize: 14,
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
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 40),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.rectangle,
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xFF141416),
              border: Border.all(
                color: const Color(0xFF8B0000).withOpacity(0.3),
              ),
            ),
            child: const Icon(
              Icons.person_off_rounded,
              size: 28,
              color: Colors.white30,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'User not found',
            style: GoogleFonts.inter(
              fontSize: 15,
              color: Colors.white54,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Check the UserID and try again',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.white30,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialState() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_rounded,
              size: 48,
              color: Colors.white.withOpacity(0.1),
            ),
            const SizedBox(height: 12),
            Text(
              'Search for a user',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.white30,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
