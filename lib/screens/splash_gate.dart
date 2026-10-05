import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'active_session_screen.dart';
import 'admin_setup_screen.dart';
import 'permissions_screen.dart';
import 'profile_picker_screen.dart';
import 'time_up_screen.dart';

/// Root widget. Decides which screen to show purely from [AppState], so the
/// app always lands on the right place after being killed / relaunched.
class SplashGate extends StatelessWidget {
  const SplashGate({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final Widget child;
    if (!state.ready) {
      child = const _Splash(key: ValueKey('splash'));
    } else if (state.sessionExpired) {
      child = const TimeUpScreen(key: ValueKey('timeUp'));
    } else if (state.sessionActive) {
      child = const ActiveSessionScreen(key: ValueKey('session'));
    } else if (!state.hasAdmin) {
      child = const AdminSetupScreen(key: ValueKey('admin'));
    } else if (state.needsSetup) {
      child = const PermissionsScreen(key: ValueKey('setup'), firstRun: true);
    } else {
      child = const ProfilePickerScreen(key: ValueKey('picker'));
    }
    // Do not retain an outgoing picker with enabled controls during a lock.
    return PopScope(canPop: state.ready && !state.sessionLocked, child: child);
  }
}

class _Splash extends StatelessWidget {
  const _Splash({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const GuardianLogo(size: 88),
            const SizedBox(height: 20),
            Text('Screen Guardian', style: context.text.headlineSmall),
            const SizedBox(height: 28),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: context.scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
