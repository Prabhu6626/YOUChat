import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../auth/auth_manager.dart';
import '../../encryption/signal_protocol_service.dart';
import '../../services/auth_service.dart';

/// Register screen — UserID + Passcode + Confirm Passcode.
/// Includes passcode strength indicator.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _userIdController = TextEditingController();
  final _passcodeController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePasscode = true;
  bool _obscureConfirm = true;
  double _passcodeStrength = 0;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _passcodeController.addListener(_updateStrength);
  }

  void _updateStrength() {
    final p = _passcodeController.text;
    double strength = 0;
    if (p.length >= 6) strength += 0.2;
    if (p.length >= 10) strength += 0.2;
    if (RegExp(r'[A-Z]').hasMatch(p)) strength += 0.2;
    if (RegExp(r'[0-9]').hasMatch(p)) strength += 0.2;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(p)) strength += 0.2;
    setState(() => _passcodeStrength = strength);
  }

  @override
  void dispose() {
    _animController.dispose();
    _userIdController.dispose();
    _passcodeController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Color _strengthColor() {
    if (_passcodeStrength <= 0.2) return const Color(0xFFFF1E1E);
    if (_passcodeStrength <= 0.4) return const Color(0xFFFF4500);
    if (_passcodeStrength <= 0.6) return const Color(0xFFA52A2A);
    if (_passcodeStrength <= 0.8) return const Color(0xFF8B0000);
    return const Color(0xFF5C0000);
  }

  String _strengthLabel() {
    if (_passcodeStrength <= 0.2) return 'Weak';
    if (_passcodeStrength <= 0.4) return 'Fair';
    if (_passcodeStrength <= 0.6) return 'Good';
    if (_passcodeStrength <= 0.8) return 'Strong';
    return 'Very Strong';
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    final authManager = context.read<AuthManager>();
    final signalService = context.read<SignalProtocolService>();
    final authService = AuthService(
      authManager: authManager,
      signalService: signalService,
    );

    final result = await authService.register(
      _userIdController.text.trim(),
      _passcodeController.text,
    );

    if (mounted) {
      if (result['success'] == true) {
        Navigator.of(context).popUntil((route) => route.isFirst);
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
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Back button
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.arrow_back_ios_rounded,
                            color: Colors.white54,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Icon
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.rectangle,
                          borderRadius: BorderRadius.circular(8),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF4A0000), Color(0xFF8B0000)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF8B0000).withOpacity(0.4),
                              blurRadius: 25,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.person_add_alt_1_rounded,
                          size: 36,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 20),

                      Text(
                        'Create Account',
                        style: GoogleFonts.outfit(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFE0E0E0),
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your messages. Your privacy.',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.white54,
                        ),
                      ),
                      const SizedBox(height: 36),

                      // UserID
                      _buildTextField(
                        controller: _userIdController,
                        label: 'Choose a UserID',
                        icon: Icons.alternate_email_rounded,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Enter a UserID';
                          if (v.length < 3) return 'At least 3 characters';
                          if (v.length > 30) return 'Max 30 characters';
                          if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(v)) {
                            return 'Only letters, numbers, and underscores';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Passcode
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
                          if (v == null || v.isEmpty) return 'Enter a passcode';
                          if (v.length < 6) return 'At least 6 characters';
                          return null;
                        },
                      ),

                      // Strength indicator
                      if (_passcodeController.text.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: _passcodeStrength,
                                    backgroundColor:
                                        Colors.white.withOpacity(0.1),
                                    valueColor: AlwaysStoppedAnimation(
                                        _strengthColor()),
                                    minHeight: 4,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _strengthLabel(),
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: _strengthColor(),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),

                      // Confirm passcode
                      _buildTextField(
                        controller: _confirmController,
                        label: 'Confirm Passcode',
                        icon: Icons.lock_rounded,
                        obscure: _obscureConfirm,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirm
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: Colors.white38,
                          ),
                          onPressed: () => setState(
                              () => _obscureConfirm = !_obscureConfirm),
                        ),
                        validator: (v) {
                          if (v != _passcodeController.text) {
                            return 'Passcodes do not match';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),

                      // Register button
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
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
                            onPressed:
                                authManager.isLoading ? null : _register,
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
                                    'Create Secure Account',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Security note
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141416),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: const Color(0xFF8B0000).withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              color: Color(0xFF8B0000),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Encryption keys will be generated automatically. No email or phone required.',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.white54,
                                  height: 1.4,
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}
