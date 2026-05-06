import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../auth/auth_manager.dart';
import '../services/user_service.dart';
import '../models/user_model.dart';
import '../utils/constants.dart';

/// View another user's profile — avatar, UserID, bio.
class UserProfileScreen extends StatefulWidget {
  final String userId;

  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  UserModel? _user;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final token = context.read<AuthManager>().token;
    if (token == null) return;

    final userService = UserService(getToken: () => token);
    final result = await userService.searchUser(widget.userId);

    if (mounted) {
      setState(() {
        _user = result;
        _isLoading = false;
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
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                      icon: const Icon(Icons.arrow_back_ios_rounded,
                          color: Colors.white70, size: 20),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Profile',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF8B0000)))
                    : _user == null
                        ? Center(
                            child: Text(
                              'User not found',
                              style: GoogleFonts.inter(
                                  color: Colors.white54, fontSize: 16),
                            ),
                          )
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                const SizedBox(height: 24),

                                // Avatar
                                Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
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
                                        blurRadius: 24,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: _user!.profilePictureUrl.isNotEmpty
                                        ? Image.network(
                                            '${AppConstants.serverUrl}${_user!.profilePictureUrl}',
                                            fit: BoxFit.cover,
                                            headers: const {'ngrok-skip-browser-warning': 'true'},
                                            errorBuilder:
                                                (ctx, err, stack) =>
                                                    _buildInitial(),
                                          )
                                        : _buildInitial(),
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // UserID
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF141416),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: const Color(0xFF8B0000)
                                          .withOpacity(0.3),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                          Icons.alternate_email_rounded,
                                          size: 18,
                                          color: Color(0xFF8B0000)),
                                      const SizedBox(width: 8),
                                      Text(
                                        _user!.userId,
                                        style: GoogleFonts.inter(
                                          fontSize: 18,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Bio section
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF141416),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: const Color(0xFF8B0000)
                                          .withOpacity(0.2),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF8B0000)
                                                  .withOpacity(0.15),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: const Icon(
                                                Icons.info_outline_rounded,
                                                color: Color(0xFF8B0000),
                                                size: 16),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            'Bio',
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        _user!.bio.isNotEmpty
                                            ? _user!.bio
                                            : 'No bio set',
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          color: _user!.bio.isNotEmpty
                                              ? Colors.white70
                                              : Colors.white30,
                                          height: 1.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Encryption info
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF141416),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: const Color(0xFF8B0000)
                                          .withOpacity(0.2),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.lock_rounded,
                                          color: Color(0xFF8B0000),
                                          size: 18),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Messages with this user are secured',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: Colors.white38,
                                          ),
                                        ),
                                      ),
                                    ],
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

  Widget _buildInitial() {
    return Center(
      child: Text(
        _user!.userId.isNotEmpty ? _user!.userId[0].toUpperCase() : '?',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 48,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
