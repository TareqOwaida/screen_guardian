import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/installed_app.dart';
import '../models/profile.dart';
import '../services/platform_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/profile_avatar.dart';
import 'session_controls.dart';

/// Shown to the child while a session runs. Acts as a mini launcher that only
/// exposes the allowed apps. Cannot be dismissed with the back button.
class ActiveSessionScreen extends StatefulWidget {
  const ActiveSessionScreen({super.key});

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen> {
  @override
  void initState() {
    super.initState();
    if (PlatformService.isAndroid) {
      context.read<AppState>().loadInstalledApps();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final session = state.session;
    final profile =
        state.activeProfile ??
        Profile(id: session?.profileId ?? '', name: session?.profileName ?? '');
    final color = Color(profile.colorValue);
    final remaining = session?.remaining ?? Duration.zero;
    final total = session?.total ?? const Duration(minutes: 1);
    final progress = total.inSeconds == 0
        ? 0.0
        : (remaining.inSeconds / total.inSeconds).clamp(0.0, 1.0);
    final lowTime = remaining.inMinutes < 5;
    final fg = color.readableForeground;

    return PopScope(
      canPop: false,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: fg == Colors.white
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: color,
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [color.darken(0.10), color, color.lighten(0.04)],
                stops: const [0, 0.55, 1],
              ),
            ),
            child: Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                    child: Row(
                      children: [
                        ProfileAvatar(profile: profile, size: 46, ring: true),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hi ${profile.name}!',
                                style: context.text.titleLarge?.copyWith(
                                  color: fg,
                                ),
                              ),
                              Text(
                                'Have fun and stay safe',
                                style: context.text.bodySmall?.copyWith(
                                  color: fg.withValues(alpha: 0.75),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _GlassButton(
                          icon: Icons.lock_person_rounded,
                          tooltip: 'Parent',
                          foreground: fg,
                          onTap: () => showSessionControls(context),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _TimerRing(
                  progress: progress,
                  remaining: remaining,
                  foreground: fg,
                  lowTime: lowTime,
                ),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: lowTime
                      ? StatusPill(
                          key: const ValueKey('low'),
                          'Almost done – wrap up soon',
                          icon: Icons.hourglass_bottom_rounded,
                          background: AppTheme.amber,
                          foreground: AppTheme.ink,
                        )
                      : StatusPill(
                          key: const ValueKey('ok'),
                          'Session running',
                          icon: Icons.play_circle_rounded,
                          background: fg.withValues(alpha: 0.16),
                          foreground: fg,
                        ),
                ),
                const SizedBox(height: 22),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: context.scheme.surface,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(32),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 24,
                          offset: const Offset(0, -6),
                        ),
                      ],
                    ),
                    child: PlatformService.isIOS
                        ? _IosHint(profile: profile)
                        : _AndroidLauncher(profile: profile),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.onTap,
    required this.foreground,
    this.tooltip,
  });
  final IconData icon;
  final VoidCallback onTap;
  final Color foreground;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: foreground.withValues(alpha: 0.16),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: Tooltip(
        message: tooltip ?? '',
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, color: foreground, size: 24),
          ),
        ),
      ),
    );
  }
}

class _TimerRing extends StatelessWidget {
  const _TimerRing({
    required this.progress,
    required this.remaining,
    required this.foreground,
    required this.lowTime,
  });
  final double progress;
  final Duration remaining;
  final Color foreground;
  final bool lowTime;

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final size = math.min(MediaQuery.sizeOf(context).width * 0.56, 240.0);
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: progress),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => CustomPaint(
          painter: _RingPainter(
            progress: value,
            track: foreground.withValues(alpha: 0.18),
            fill: lowTime ? AppTheme.amber : foreground,
            stroke: size * 0.075,
          ),
          child: child,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _fmt(remaining),
                style: context.text.displayMedium?.copyWith(
                  color: foreground,
                  fontSize: remaining.inHours > 0 ? 40 : 48,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                'left',
                style: context.text.titleMedium?.copyWith(
                  color: foreground.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.track,
    required this.fill,
    required this.stroke,
  });
  final double progress;
  final Color track;
  final Color fill;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final fillPaint = Paint()
      ..color = fill
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, math.pi * 2, false, trackPaint);
    if (progress > 0) {
      canvas.drawArc(r, -math.pi / 2, math.pi * 2 * progress, false, fillPaint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.track != track ||
      old.fill != fill ||
      old.stroke != stroke;
}

class _AndroidLauncher extends StatelessWidget {
  const _AndroidLauncher({required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = context.scheme;
    final all = state.installedApps;
    if (all == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final byPkg = {for (final a in all) a.packageName: a};
    final apps =
        profile.allowedPackages
            .map(
              (p) =>
                  byPkg[p] ??
                  InstalledApp(packageName: p, appName: p, isSystem: false),
            )
            .toList()
          ..sort(
            (a, b) =>
                a.appName.toLowerCase().compareTo(b.appName.toLowerCase()),
          );

    if (apps.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconBubble(
                icon: Icons.apps_rounded,
                size: 72,
                circular: true,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text('No apps yet', style: context.text.titleLarge),
              const SizedBox(height: 6),
              Text(
                'A parent has not allowed any apps for this profile.',
                textAlign: TextAlign.center,
                style: context.text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 4),
          child: Row(
            children: [
              Text('Your apps', style: context.text.titleLarge),
              const SizedBox(width: 8),
              StatusPill('${apps.length}'),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 104,
              mainAxisSpacing: 14,
              crossAxisSpacing: 10,
              childAspectRatio: 0.74,
            ),
            itemCount: apps.length,
            itemBuilder: (context, i) {
              final a = apps[i];
              return _AppTile(
                app: a,
                onTap: () => state.launchApp(a.packageName),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({required this.app, required this.onTap});
  final InstalledApp app;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open ${app.appName}',
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: context.guardian.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.guardian.cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(10),
              child: app.icon != null
                  ? Image.memory(app.icon!)
                  : Icon(
                      Icons.android_rounded,
                      color: context.scheme.onSurfaceVariant,
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              app.appName,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _IosHint extends StatelessWidget {
  const _IosHint({required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final n = profile.iosAllowedAppCount;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconBubble(
            icon: Icons.phone_iphone_rounded,
            size: 80,
            circular: true,
            color: scheme.primary,
          ),
          const SizedBox(height: 18),
          Text('Press Home to play', style: context.text.titleLarge),
          const SizedBox(height: 8),
          Text(
            '$n app${n == 1 ? ' is' : 's are'} available. Every other app is '
            'shielded by Screen Time until the timer ends.',
            textAlign: TextAlign.center,
            style: context.text.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
