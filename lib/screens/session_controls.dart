import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/common.dart';
import 'pin_screen.dart';

/// One parent-authenticated action per sheet. The state layer checks the PIN
/// again and keeps the profile locked until the device confirms the change.
Future<void> showSessionControls(BuildContext context) async {
  final state = context.read<AppState>();
  final session = state.session;
  if (session == null || state.sessionBusy) return;
  final pin = await PinScreen.requestAdminPin(
    context,
    state,
    reason: 'End or extend this session',
  );
  if (pin == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final minutes = await showModalBottomSheet<int>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader(title: 'Session controls'),
          for (final minutes in [15, 30])
            SheetAction(
              icon: Icons.more_time_rounded,
              title: 'Add $minutes minutes',
              onTap: () => Navigator.pop(ctx, minutes),
            ),
          SheetAction(
            icon: Icons.stop_circle_rounded,
            title: 'End session',
            subtitle: 'Return to the profile picker',
            destructive: true,
            onTap: () => Navigator.pop(ctx, 0),
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
  if (minutes == null ||
      state.session?.profileId != session.profileId ||
      state.session?.startedAt != session.startedAt) {
    return;
  }
  final ok = minutes == 0
      ? await state.endSession(adminPin: pin)
      : await state.extendSession(minutes, adminPin: pin);
  if (!ok && messenger.mounted) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          state.sessionError ??
              'The session could not be changed. Please try again.',
        ),
      ),
    );
  }
}
