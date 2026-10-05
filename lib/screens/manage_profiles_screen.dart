import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../services/platform_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/profile_avatar.dart';
import 'edit_profile_screen.dart';

/// Parent-only: list, add, edit and delete profiles.
class ManageProfilesScreen extends StatelessWidget {
  const ManageProfilesScreen({super.key});

  void _edit(BuildContext context, Profile? existing) {
    final state = context.read<AppState>();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(
          profile: existing?.copy() ?? state.newProfileTemplate(),
          isNew: existing == null,
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, Profile p) async {
    final state = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${p.name}?'),
        content: const Text('This profile and its settings will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                backgroundColor: ctx.scheme.error,
                foregroundColor: ctx.scheme.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await state.deleteProfile(p.id);
  }

  Future<void> _options(BuildContext context, Profile p) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(title: p.name),
            SheetAction(
              icon: Icons.edit_rounded,
              title: 'Edit profile',
              onTap: () {
                Navigator.pop(ctx);
                _edit(context, p);
              },
            ),
            SheetAction(
              icon: Icons.delete_rounded,
              title: 'Delete profile',
              destructive: true,
              onTap: () {
                Navigator.pop(ctx);
                _delete(context, p);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = context.scheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Profiles')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('New profile'),
      ),
      body: state.profiles.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconBubble(
                        icon: Icons.face_rounded,
                        size: 88,
                        circular: true,
                        color: scheme.primary),
                    const SizedBox(height: 16),
                    Text('No profiles yet', style: context.text.titleLarge),
                    const SizedBox(height: 6),
                    Text('Tap "New profile" to add your first child.',
                        style: context.text.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
              itemCount: state.profiles.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final p = state.profiles[i];
                final apps = PlatformService.isIOS
                    ? p.iosAllowedAppCount
                    : p.allowedPackages.length;
                final color = Color(p.colorValue);
                return SoftCard(
                  onTap: () => _edit(context, p),
                  child: Row(
                    children: [
                      ProfileAvatar(profile: p, size: 56),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name, style: context.text.titleLarge),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                StatusPill('${p.sessionMinutes} min',
                                    icon: Icons.timer_rounded,
                                    background: color.withValues(alpha: 0.14),
                                    foreground: color.darken(0.12)),
                                StatusPill('$apps app${apps == 1 ? '' : 's'}',
                                    icon: Icons.apps_rounded),
                                if (p.hasPin)
                                  const StatusPill('PIN',
                                      icon: Icons.lock_rounded),
                                if (p.dnsFilterEnabled)
                                  StatusPill('Safe DNS',
                                      icon: Icons.shield_rounded,
                                      background:
                                          context.guardian.successContainer,
                                      foreground:
                                          context.guardian.onSuccessContainer),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'More',
                        icon: const Icon(Icons.more_vert_rounded),
                        onPressed: () => _options(context, p),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
