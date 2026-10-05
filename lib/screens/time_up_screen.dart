import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'session_controls.dart';

/// Session expired. Every app is blocked; only a parent PIN can unlock.
class TimeUpScreen extends StatelessWidget {
  const TimeUpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final g = context.guardian;
    final name = state.session?.profileName;
    return PopScope(
      canPop: false,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: g.heroTop,
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [g.heroTop, g.heroBottom],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    Center(
                      child: Container(
                        width: 260,
                        height: 260,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              AppTheme.amber.withValues(alpha: 0.22),
                              AppTheme.amber.withValues(alpha: 0.0),
                            ],
                            stops: const [0.35, 1],
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: g.heroTop.withValues(alpha: 0.6),
                            border: Border.all(
                              color: AppTheme.amber.withValues(alpha: 0.5),
                              width: 3,
                            ),
                          ),
                          child: const Icon(
                            Icons.bedtime_rounded,
                            size: 80,
                            color: AppTheme.amber,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),
                    Text(
                      "Time's up!",
                      textAlign: TextAlign.center,
                      style: context.text.displaySmall?.copyWith(
                        color: g.onHero,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${name == null || name.isEmpty ? 'Your' : "$name's"} screen '
                      'time for this session is over.\nAsk a parent if you need '
                      'more time.',
                      textAlign: TextAlign.center,
                      style: context.text.bodyLarge?.copyWith(
                        color: g.onHero.withValues(alpha: 0.75),
                      ),
                    ),
                    const Spacer(flex: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock_rounded,
                          size: 16,
                          color: g.onHero.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'All apps are locked',
                          style: context.text.labelLarge?.copyWith(
                            color: g.onHero.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: g.onHero,
                        side: BorderSide(
                          color: g.onHero.withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                      ),
                      icon: const Icon(Icons.lock_person_rounded),
                      label: const Text('Parent unlock'),
                      onPressed: () => showSessionControls(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
