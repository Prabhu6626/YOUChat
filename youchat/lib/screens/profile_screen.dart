import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../auth/auth_manager.dart';
import '../encryption/signal_protocol_service.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/chat_service.dart';
import '../models/user_model.dart';
import '../utils/constants.dart';

/// Profile screen — view/edit own profile.
/// Shows UserID, bio, profile picture, change passcode, logout.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _bioController = TextEditingController();
  final _oldPasscodeController = TextEditingController();
  final _newPasscodeController = TextEditingController();
  final _confirmPasscodeController = TextEditingController();
  UserModel? _profile;
  bool _isLoading = true;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final token = context.read<AuthManager>().token;
    if (token == null) return;

    final userService = UserService(getToken: () => token);
    final profile = await userService.getMyProfile();

    if (mounted) {
      setState(() {
        _profile = profile;
        _bioController.text = profile?.bio ?? '';
        _isLoading = false;
      });
    }
  }

  Future<void> _updateBio() async {
    final token = context.read<AuthManager>().token;
    if (token == null) return;

    final userService = UserService(getToken: () => token);
    final success = await userService.updateBio(_bioController.text);

    if (mounted) {
      setState(() => _isEditing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Bio updated' : 'Failed to update bio'),
          backgroundColor: success ? const Color(0xFF00FF88) : const Color(0xFFFF3B3B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _changeProfilePicture() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );

    if (image == null) return;

    final token = context.read<AuthManager>().token;
    if (token == null) return;

    final userService = UserService(getToken: () => token);
    final result = await userService.uploadProfilePicture(image.path);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result ?? 'Failed to upload picture'),
          backgroundColor: result != null ? const Color(0xFF00FF88) : const Color(0xFFFF3B3B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      if (result != null) _loadProfile();
    }
  }

  void _showChangePasscodeDialog() {
    _oldPasscodeController.clear();
    _newPasscodeController.clear();
    _confirmPasscodeController.clear();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141416),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text(
          'Change Passcode',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDialogField(_oldPasscodeController, 'Old Passcode'),
            const SizedBox(height: 12),
            _buildDialogField(_newPasscodeController, 'New Passcode'),
            const SizedBox(height: 12),
            _buildDialogField(_confirmPasscodeController, 'Confirm New Passcode'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () async {
              if (_newPasscodeController.text != _confirmPasscodeController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Passcodes do not match'),
                    backgroundColor: const Color(0xFFFF3B3B),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
                return;
              }

              final authService = AuthService(
                authManager: context.read<AuthManager>(),
                signalService: context.read<SignalProtocolService>(),
              );

              final result = await authService.changePasscode(
                _oldPasscodeController.text,
                _newPasscodeController.text,
              );

              if (mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result['message']),
                    backgroundColor: result['success'] == true
                        ? const Color(0xFF00FF88)
                        : const Color(0xFFFF3B3B),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              }
            },
            child: Text(
              'Change',
              style: GoogleFonts.inter(
                color: const Color(0xFF00D2FF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141416),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text(
          'Logout',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'All encryption keys and messages will be destroyed. This cannot be undone.',
          style: GoogleFonts.inter(
            color: Colors.white54,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);

              final authService = AuthService(
                authManager: context.read<AuthManager>(),
                signalService: context.read<SignalProtocolService>(),
              );

              context.read<ChatService>().clearAll();
              await authService.logout();
            },
            child: Text(
              'Logout',
              style: GoogleFonts.inter(
                color: const Color(0xFFFF3B3B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _bioController.dispose();
    _oldPasscodeController.dispose();
    _newPasscodeController.dispose();
    _confirmPasscodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.read<AuthManager>().userId ?? '';

    return SafeArea(
      child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF8B0000)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    'Profile',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Avatar
                  GestureDetector(
                    onTap: _changeProfilePicture,
                    child: Stack(
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.rectangle,
                            borderRadius: BorderRadius.circular(8),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF4A0000), Color(0xFF8B0000)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF8B0000).withOpacity(0.4),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: (_profile?.profilePictureUrl.isNotEmpty ?? false)
                                ? Image.network(
                                    '${AppConstants.serverUrl}${_profile!.profilePictureUrl}',
                                    fit: BoxFit.cover,
                                    width: 100,
                                    height: 100,
                                    headers: const {'ngrok-skip-browser-warning': 'true'},
                                    errorBuilder: (ctx, err, stack) => Center(
                                      child: Text(
                                        userId.isNotEmpty ? userId[0].toUpperCase() : '?',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 40,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  )
                                : Center(
                                    child: Text(
                                      userId.isNotEmpty ? userId[0].toUpperCase() : '?',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 40,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B0000),
                              shape: BoxShape.rectangle,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: const Color(0xFF0A0A0C),
                                width: 3,
                              ),
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // UserID (not editable)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141416),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF8B0000).withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.alternate_email_rounded,
                          size: 16,
                          color: Color(0xFF8B0000),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          userId,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Settings sections
                  _buildSection([
                    _buildSettingItem(
                      icon: Icons.edit_rounded,
                      iconColor: const Color(0xFF8B0000),
                      title: 'Bio',
                      subtitle: _profile?.bio.isEmpty ?? true
                          ? 'Add a bio'
                          : _profile!.bio,
                      trailing: !_isEditing
                          ? IconButton(
                              icon: const Icon(Icons.edit, color: Colors.white38, size: 18),
                              onPressed: () => setState(() => _isEditing = true),
                            )
                          : null,
                    ),
                    if (_isEditing)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _bioController,
                                maxLength: 200,
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Write something about yourself...',
                                  hintStyle: GoogleFonts.inter(color: Colors.white30),
                                  filled: true,
                                  fillColor: const Color(0xFF0A0A1A),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(4),
                                    borderSide: const BorderSide(color: Color(0xFF8B0000)),
                                  ),
                                  counterStyle: const TextStyle(color: Colors.white30),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: _updateBio,
                              icon: const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFF00FF88),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ]),
                  const SizedBox(height: 16),

                  _buildSection([
                    _buildSettingItem(
                      icon: Icons.lock_rounded,
                      iconColor: const Color(0xFFFF8C00),
                      title: 'Change Passcode',
                      subtitle: 'Update your passcode',
                      onTap: _showChangePasscodeDialog,
                    ),
                  ]),
                  const SizedBox(height: 16),

                  _buildSection([
                    _buildSettingItem(
                      icon: Icons.shield_rounded,
                      iconColor: const Color(0xFF8B0000),
                      title: 'Encryption',
                      subtitle: 'Signal Protocol',
                    ),
                    _buildSettingItem(
                      icon: Icons.timer_rounded,
                      iconColor: const Color(0xFFD30000),
                      title: 'Auto-Delete',
                      subtitle: 'Off',
                    ),
                    _buildSettingItem(
                      icon: Icons.no_photography_rounded,
                      iconColor: const Color(0xFF4A0000),
                      title: 'Screenshot Prevention',
                      subtitle: 'Enabled',
                    ),
                  ]),
                  const SizedBox(height: 16),

                  // Logout button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _showLogoutDialog,
                      icon: const Icon(Icons.logout_rounded, size: 20),
                      label: Text(
                        'Logout',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF3B3B).withOpacity(0.15),
                        foregroundColor: const Color(0xFFFF3B3B),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildSection(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: const Color(0xFF8B0000).withOpacity(0.2),
        ),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(
        title,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(
          color: Colors.white38,
          fontSize: 12,
        ),
      ),
      trailing: trailing ??
          (onTap != null
              ? const Icon(Icons.chevron_right_rounded,
                  color: Colors.white30, size: 20)
              : null),
      onTap: onTap,
    );
  }

  Widget _buildDialogField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      obscureText: true,
      style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
        filled: true,
        fillColor: const Color(0xFF0A0A1A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}
