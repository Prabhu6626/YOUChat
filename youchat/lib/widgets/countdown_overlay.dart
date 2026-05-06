import 'package:flutter/material.dart';

/// Circular countdown overlay widget for the 7-second message deletion timer.
/// Shows a pulsing red animation in the last 3 seconds.
class CountdownOverlay extends StatefulWidget {
  final int secondsRemaining;

  const CountdownOverlay({super.key, required this.secondsRemaining});

  @override
  State<CountdownOverlay> createState() => _CountdownOverlayState();
}

class _CountdownOverlayState extends State<CountdownOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.secondsRemaining / 15.0;
    final isUrgent = widget.secondsRemaining <= 3;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        final scale = isUrgent ? _pulseAnimation.value : 1.0;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(0.5),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2.5,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isUrgent
                          ? const Color(0xFFFF3B3B)
                          : const Color(0xFF00D2FF),
                    ),
                  ),
                ),
                Text(
                  '${widget.secondsRemaining}',
                  style: TextStyle(
                    color: isUrgent
                        ? const Color(0xFFFF3B3B)
                        : Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
