import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../auth/auth_manager.dart';
import '../../encryption/signal_protocol_service.dart';
import '../../services/auth_service.dart';
import 'register_screen.dart';

/// Login screen — minimal fields: UserID + Passcode.
/// Dark themed with animated gradient background and shield branding.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _userIdController = TextEditingController();
  final _passcodeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePasscode = true;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _userIdController.dispose();
    _passcodeController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final authManager = context.read<AuthManager>();
    final signalService = context.read<SignalProtocolService>();
    final authService = AuthService(
      authManager: authManager,
      signalService: signalService,
    );

    final result = await authService.login(
      _userIdController.text.trim(),
      _passcodeController.text,
    );

    if (mounted) {
      if (result['success'] == true) {
        // Navigation handled by auth state listener in app.dart
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: const Color(0xFFFF3B3B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authManager = context.watch<AuthManager>();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0A0A0C),
              Color(0xFF160A0A),
              Color(0xFF0A0A0C),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Logo
                        Image.asset(
                          'assets/logo.png',
                          width: 160,
                          height: 160,
                          errorBuilder: (context, error, stackTrace) => Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.rectangle,
                              borderRadius: BorderRadius.circular(8),
                              gradient: const LinearGradient(
                                colors: [Color(0xFF4A0000), Color(0xFF8B0000)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF8B0000).withOpacity(0.4),
                                  blurRadius: 30,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.security_rounded,
                              size: 42,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // App name
                        Text(
                          'YOUChat',
                          style: GoogleFonts.outfit(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFFE0E0E0),
                            letterSpacing: 2.0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'S E C U R E   M E S S A G I N G',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF8B0000),
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: 48),

                        // UserID field
                        _buildTextField(
                          controller: _userIdController,
                          label: 'UserID',
                          icon: Icons.person_outline_rounded,
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Enter your UserID';
                            if (v.length < 3) return 'UserID must be at least 3 characters';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Passcode field
                        _buildTextField(
                          controller: _passcodeController,
                          label: 'Passcode',
                          icon: Icons.lock_outline_rounded,
                          obscure: _obscurePasscode,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePasscode
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              color: Colors.white38,
                            ),
                            onPressed: () => setState(
                                () => _obscurePasscode = !_obscurePasscode),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Enter your passcode';
                            return null;
                          },
                        ),
                        const SizedBox(height: 32),

                        // Login button
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF7B2FFF), Color(0xFF00D2FF)],
                              ),
                              borderRadius: BorderRadius.circular(4),
                              color: const Color(0xFF8B0000),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF8B0000).withOpacity(0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: authManager.isLoading ? null : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              child: authManager.isLoading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      'Login',
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Register link
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const RegisterScreen(),
                              ),
                            );
                          },
                          child: RichText(
                            text: TextSpan(
                              style: GoogleFonts.inter(fontSize: 14),
                              children: const [
                                TextSpan(
                                  text: "Don't have an account? ",
                                  style: TextStyle(color: Colors.white54),
                                ),
                                TextSpan(
                                  text: 'Register',
                                  style: TextStyle(
                                    color: Color(0xFFD30000),
                                    fontWeight: FontWeight.w700,
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
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(color: Colors.white38),
        prefixIcon: Icon(icon, color: const Color(0xFF8B0000), size: 18),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFF141416),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: Color(0xFF8B0000), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: Color(0xFFFF1E1E), width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}
