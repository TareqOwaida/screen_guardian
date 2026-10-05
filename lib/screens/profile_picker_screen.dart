import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../services/platform_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/profile_avatar.dart';
import 'manage_profiles_screen.dart';
import 'permissions_screen.dart';
import 'pin_screen.dart';

/// Launch screen when nothing is running: pick who is going to use the device.
class ProfilePickerScreen extends StatelessWidget {
  const ProfilePickerScreen({super.key});

  Future<void> _parentMenu(BuildContext context) async {
    final state = context.read<AppState>();
    if (!await PinScreen.verifyAdmin(context, state, reason: 'Parent area')) {
      return;
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHeader(
              title: 'Parent area',
              subtitle:
                  'Only you can see this. Nothing here is visible to children.',
            ),
            SheetAction(
              icon: Icons.manage_accounts_rounded,
              title: 'Manage profiles',
              subtitle: 'Add children, allowed apps, PINs and filters',
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ManageProfilesScreen(),
                  ),
                );
              },
            ),
            SheetAction(
              icon: Icons.verified_user_rounded,
              title: 'Device protection',
              subtitle: state.enforcementReady
                  ? 'All required permissions granted'
                  : 'Action needed: protection is off',
              color: state.enforcementReady ? null : context.scheme.secondary,
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PermissionsScreen()),
                );
              },
            ),
            SheetAction(
              icon: Icons.password_rounded,
              title: 'Change parent PIN',
              onTap: () async {
                Navigator.pop(ctx);
                final pin = await PinScreen.collectNewPin(
                  context,
                  title: 'New parent PIN',
                );
                if (pin == null) return;
                await state.setAdminPin(pin);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Parent PIN updated')),
                  );
                }
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _fixProtection(BuildContext context) async {
    final state = context.read<AppState>();
    if (!await PinScreen.verifyAdmin(
      context,
      state,
      reason: 'Device protection',
    )) {
      return;
    }
    if (!context.mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PermissionsScreen()));
  }

  Future<void> _pick(BuildContext context, Profile p) async {
    final state = context.read<AppState>();
    if (p.hasPin) {
      final ok = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => PinScreen(
            title: 'Hi ${p.name}!',
            subtitle: 'Enter your PIN to start playing',
            accent: Color(p.colorValue),
            onSubmit: (pin) async => state.verifyProfilePin(p, pin),
          ),
        ),
      );
      if (ok == null) return;
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _StartSessionSheet(
        profile: p,
        onFixProtection: () => _fixProtection(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = context.scheme;
    final profiles = state.profiles;
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const GuardianLogo(size: 36),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Screen Guardian',
                            style: context.text.titleMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        _ParentButton(
                          alert: !state.enforcementReady,
                          onTap: () => _parentMenu(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Text(
                      _greeting(),
                      style: context.text.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Who is using\nthe phone?',
                      style: context.text.headlineLarge,
                    ),
                    const SizedBox(height: 20),
                    if (!state.enforcementReady) ...[
                      NoticeCard(
                        icon: Icons.shield_outlined,
                        color: scheme.secondary,
                        title: 'Protection is off',
                        message: PlatformService.isIOS
                            ? 'Screen Time access has not been granted. '
                                  'Sessions cannot start until a parent finishes setup.'
                            : 'The accessibility service is off, so apps cannot '
                                  'be blocked. Sessions cannot start until a parent '
                                  'finishes setup.',
                        action: FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          icon: const Icon(Icons.lock_open_rounded, size: 18),
                          label: const Text('Fix as parent'),
                          onPressed: () => _fixProtection(context),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              ),
            ),
            if (profiles.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(onAdd: () => _parentMenu(context)),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.82,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _ProfileTile(
                      profile: profiles[i],
                      onTap: () => _pick(context, profiles[i]),
                    ),
                    childCount: profiles.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Up late?';
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }
}

class _ParentButton extends StatelessWidget {
  const _ParentButton({required this.onTap, required this.alert});
  final VoidCallback onTap;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Material(
      color: context.guardian.card,
      shape: StadiumBorder(
        side: BorderSide(color: context.guardian.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Badge(
                isLabelVisible: alert,
                smallSize: 8,
                child: Icon(
                  Icons.lock_person_rounded,
                  size: 20,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text('Parent', style: context.text.labelLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({required this.profile, required this.onTap});
  final Profile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(profile.colorValue);
    final scheme = context.scheme;
    return SoftCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      radius: 24,
      child: Stack(
        children: [
          Positioned(
            top: -30,
            right: -30,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.12),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProfileAvatar(profile: profile, size: 64),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        profile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleLarge,
                      ),
                    ),
                    if (profile.hasPin)
                      Tooltip(
                        message: 'PIN protected',
                        child: Icon(
                          Icons.lock_rounded,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: StatusPill(
                    '${profile.sessionMinutes} min',
                    icon: Icons.timer_rounded,
                    background: color.withValues(alpha: 0.14),
                    foreground: color.darken(0.12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBubble(
              icon: Icons.family_restroom_rounded,
              color: scheme.primary,
              size: 96,
              circular: true,
            ),
            const SizedBox(height: 20),
            Text('No profiles yet', style: context.text.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Create a profile for each child. Each one gets its own allowed '
              'apps, session length, PIN and content filter.',
              textAlign: TextAlign.center,
              style: context.text.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create first profile'),
            ),
          ],
        ),
      ),
    );
  }
}

const List<int> _quickMinutes = [15, 30, 45, 60, 90, 120];

class _StartSessionSheet extends StatefulWidget {
  const _StartSessionSheet({
    required this.profile,
    required this.onFixProtection,
  });
  final Profile profile;
  final VoidCallback onFixProtection;

  @override
  State<_StartSessionSheet> createState() => _StartSessionSheetState();
}

class _StartSessionSheetState extends State<_StartSessionSheet> {
  late int _minutes = widget.profile.sessionMinutes.clamp(
    PlatformService.isIOS ? 15 : 5,
    240,
  );
  bool _starting = false;

  Future<void> _start() async {
    final state = context.read<AppState>();
    setState(() => _starting = true);
    final ok = await state.startSession(widget.profile, minutes: _minutes);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _starting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(state.sessionError ?? 'The session could not start.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = widget.profile;
    final color = Color(p.colorValue);
    final scheme = context.scheme;
    final appCount = PlatformService.isIOS
        ? p.iosAllowedAppCount
        : p.allowedPackages.length;
    final ready = state.canStartProfile(p);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ProfileAvatar(profile: p, size: 60),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ready, ${p.name}?',
                        style: context.text.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          StatusPill(
                            '$appCount app${appCount == 1 ? '' : 's'}',
                            icon: Icons.apps_rounded,
                          ),
                          StatusPill(
                            p.dnsFilterEnabled ? 'Safe browsing' : 'Filter off',
                            icon: p.dnsFilterEnabled
                                ? Icons.shield_rounded
                                : Icons.shield_outlined,
                            background: p.dnsFilterEnabled
                                ? context.guardian.successContainer
                                : null,
                            foreground: p.dnsFilterEnabled
                                ? context.guardian.onSuccessContainer
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Session length', style: context.text.titleMedium),
                const Spacer(),
                Text(
                  _fmtMinutes(_minutes),
                  style: context.text.headlineSmall?.copyWith(color: color),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickMinutes
                  .map(
                    (m) => ChoiceChip(
                      label: Text(_fmtMinutes(m)),
                      selected: _minutes == m,
                      selectedColor: color.withValues(alpha: 0.18),
                      labelStyle: context.text.labelLarge?.copyWith(
                        color: _minutes == m ? color.darken(0.15) : null,
                      ),
                      side: BorderSide(
                        color: _minutes == m
                            ? color
                            : context.guardian.cardBorder,
                      ),
                      onSelected: (_) => setState(() => _minutes = m),
                    ),
                  )
                  .toList(),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: color,
                thumbColor: color,
                overlayColor: color.withValues(alpha: 0.12),
              ),
              child: Slider(
                value: _minutes.toDouble(),
                min: PlatformService.isIOS ? 15 : 5,
                max: 240,
                divisions: PlatformService.isIOS ? 45 : 47,
                label: _fmtMinutes(_minutes),
                onChanged: (v) => setState(() => _minutes = v.round()),
              ),
            ),
            const SizedBox(height: 8),
            if (!ready) ...[
              NoticeCard(
                icon: Icons.shield_outlined,
                color: scheme.secondary,
                title: 'Protection is off',
                message:
                    'A session cannot start until a parent grants the required '
                    'permissions, otherwise ${p.name} could simply leave the app.',
                action: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  icon: const Icon(Icons.lock_open_rounded, size: 18),
                  label: const Text('Fix as parent'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onFixProtection();
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: color.readableForeground,
              ),
              icon: _starting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: color.readableForeground,
                      ),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 26),
              label: Text(ready ? 'Start session' : 'Setup required'),
              onPressed: (_starting || !ready) ? null : _start,
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtMinutes(int m) {
    if (m < 60) return '$m min';
    final h = m ~/ 60;
    final r = m % 60;
    return r == 0 ? '$h h' : '$h h $r min';
  }
}
