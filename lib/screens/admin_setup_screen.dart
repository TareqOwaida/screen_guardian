import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'pin_screen.dart';

/// First launch: the parent creates the master PIN that protects every
/// management action (creating profiles, ending sessions, permissions...).
class AdminSetupScreen extends StatelessWidget {
  const AdminSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Center(child: GuardianLogo(size: 104)),
              const SizedBox(height: 32),
              Text(
                'Welcome to\nScreen Guardian',
                textAlign: TextAlign.center,
                style: context.text.headlineLarge,
              ),
              const SizedBox(height: 12),
              Text(
                'Safe, time-boxed screen time for every child in the family.',
                textAlign: TextAlign.center,
                style: context.text.bodyLarge
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 36),
              const _Feature(
                icon: Icons.face_rounded,
                color: AppTheme.coral,
                title: 'A profile for each child',
                body: 'Their own avatar, PIN and allowed apps.',
              ),
              const SizedBox(height: 14),
              const _Feature(
                icon: Icons.hourglass_bottom_rounded,
                color: AppTheme.amber,
                title: 'Sessions that really end',
                body: 'When the timer hits zero, the phone locks until you unlock it.',
              ),
              const SizedBox(height: 14),
              const _Feature(
                icon: Icons.shield_rounded,
                color: AppTheme.teal,
                title: 'Harmful websites blocked',
                body: 'A built-in safe-browsing filter, on by default.',
              ),
              const Spacer(flex: 2),
              Text(
                'Start by choosing a parent PIN. You will need it to manage '
                'profiles or end a session.',
                textAlign: TextAlign.center,
                style: context.text.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                icon: const Icon(Icons.lock_rounded),
                label: const Text('Create parent PIN'),
                onPressed: () async {
                  final state = context.read<AppState>();
                  final pin = await PinScreen.collectNewPin(context,
                      title: 'Parent PIN');
                  if (pin != null) await state.setAdminPin(pin);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconBubble(icon: icon, color: color, size: 48),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.text.titleMedium),
              Text(body,
                  style: context.text.bodyMedium
                      ?.copyWith(color: context.scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}
