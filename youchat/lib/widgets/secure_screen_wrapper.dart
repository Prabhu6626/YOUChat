import 'package:flutter/material.dart';
import 'package:no_screenshot/no_screenshot.dart';

/// Wrapper widget that enables screenshot and screen recording prevention.
/// Uses FLAG_SECURE on Android and secure text field overlay on iOS.
class SecureScreenWrapper extends StatefulWidget {
  final Widget child;

  const SecureScreenWrapper({super.key, required this.child});

  @override
  State<SecureScreenWrapper> createState() => _SecureScreenWrapperState();
}

class _SecureScreenWrapperState extends State<SecureScreenWrapper>
    with WidgetsBindingObserver {
  final _noScreenshot = NoScreenshot.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enableProtection();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _enableProtection() async {
    await _noScreenshot.screenshotOff();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-enable protection when app comes back to foreground
    if (state == AppLifecycleState.resumed) {
      _enableProtection();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
