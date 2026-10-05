import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/platform_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class _PermItem {
  const _PermItem({
    required this.key,
    required this.title,
    required this.description,
    required this.icon,
    this.required = false,
  });
  final String key;
  final String title;
  final String description;
  final IconData icon;
  final bool required;
}

const List<_PermItem> _androidItems = [
  _PermItem(
    key: PermissionKeys.accessibility,
    title: 'Accessibility service',
    description:
        'Lets Screen Guardian see which app is open and instantly block apps '
        'that are not allowed. Without it a child can simply leave the app.',
    icon: Icons.accessibility_new_rounded,
    required: true,
  ),
  _PermItem(
    key: PermissionKeys.vpn,
    title: 'Safe DNS (local VPN)',
    description:
        'A local, on-device VPN that only handles DNS so harmful websites can '
        'be blocked. DNS queries are sent to a family-safe resolver.',
    icon: Icons.vpn_lock_rounded,
    required: true,
  ),
  _PermItem(
    key: PermissionKeys.overlay,
    title: 'Display over other apps',
    description: 'Lets the lock screen appear on top of a blocked app instantly.',
    icon: Icons.layers_rounded,
  ),
  _PermItem(
    key: PermissionKeys.usageAccess,
    title: 'Usage access',
    description:
        'Backup way to detect the foreground app if the accessibility '
        'service is interrupted.',
    icon: Icons.query_stats_rounded,
  ),
  _PermItem(
    key: PermissionKeys.notifications,
    title: 'Notifications',
    description: 'Shows the remaining session time in a persistent notification.',
    icon: Icons.notifications_active_rounded,
  ),
  _PermItem(
    key: PermissionKeys.deviceAdmin,
    title: 'Device administrator',
    description: 'Stops the app from being uninstalled while a session runs.',
    icon: Icons.admin_panel_settings_rounded,
  ),
  _PermItem(
    key: PermissionKeys.batteryOptimization,
    title: 'Ignore battery optimisation',
    description: 'Keeps the timer and DNS filter alive in the background.',
    icon: Icons.battery_saver_rounded,
  ),
];

const List<_PermItem> _iosItems = [
  _PermItem(
    key: PermissionKeys.screenTime,
    title: 'Screen Time access',
    description:
        'Apple Screen Time (Family Controls) shields every app except the '
        'ones you allow, and ends the session on time.',
    icon: Icons.hourglass_bottom_rounded,
    required: true,
  ),
  _PermItem(
    key: PermissionKeys.dns,
    title: 'Safe DNS profile',
    description:
        'Installs an encrypted, family-safe DNS configuration. Enable it in '
        'Settings ▸ General ▸ VPN, DNS & Device Management ▸ DNS.',
    icon: Icons.dns_rounded,
  ),
  _PermItem(
    key: PermissionKeys.notifications,
    title: 'Notifications',
    description: 'Alerts when a session is about to end.',
    icon: Icons.notifications_active_rounded,
  ),
];

/// Parent-only checklist of everything the OS needs to grant.
///
/// With [firstRun] it acts as the guided onboarding step shown right after
/// the parent PIN is created; "Continue" only unlocks once the required
/// permissions are granted.
class PermissionsScreen extends StatelessWidget {
  const PermissionsScreen({super.key, this.firstRun = false});
  final bool firstRun;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = context.scheme;
    final items = PlatformService.isIOS ? _iosItems : _androidItems;
    final required = items.where((i) => i.required).toList();
    final optional = items.where((i) => !i.required).toList();
    final grantedCount = items.where((i) => state.granted(i.key)).length;
    final requiredDone = required.every((i) => state.granted(i.key));
    final allDone = grantedCount == items.length;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !firstRun,
        title: Text(firstRun ? 'Set up protection' : 'Device permissions'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: state.refreshPermissions,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: state.refreshPermissions,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
          children: [
            _ProgressCard(
              granted: grantedCount,
              total: items.length,
              requiredDone: requiredDone,
              allDone: allDone,
            ),
            if (PlatformService.isAndroid) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    state.isDeviceOwner
                        ? Icons.verified_rounded
                        : Icons.info_outline_rounded,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      state.isDeviceOwner
                          ? 'Device-owner mode active: full kiosk lock enabled.'
                          : 'Tip: provision the app as device owner for a '
                              'kiosk lock (Home & Recents disabled). See README.',
                      style: context.text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            const SectionHeader('Required'),
            ...required.map((i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PermCard(item: i, granted: state.granted(i.key)),
                )),
            const SizedBox(height: 14),
            const SectionHeader('Recommended'),
            ...optional.map((i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PermCard(item: i, granted: state.granted(i.key)),
                )),
          ],
        ),
      ),
      bottomNavigationBar: firstRun
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    icon: Icon(requiredDone
                        ? Icons.check_circle_rounded
                        : Icons.lock_rounded),
                    label: Text(requiredDone
                        ? 'Continue'
                        : 'Grant the required permissions'),
                    onPressed: requiredDone ? state.completeSetup : null,
                  ),
                  TextButton(
                    onPressed: () => _confirmSkip(context, state),
                    style: TextButton.styleFrom(
                        foregroundColor: scheme.onSurfaceVariant),
                    child: const Text('Do this later'),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  Future<void> _confirmSkip(BuildContext context, AppState state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Skip setup?'),
        content: const Text(
            'Sessions cannot start until the required permissions are '
            'granted. You can finish this any time from the parent menu.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep going')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Skip for now')),
        ],
      ),
    );
    if (ok == true) await state.completeSetup();
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.granted,
    required this.total,
    required this.requiredDone,
    required this.allDone,
  });

  final int granted;
  final int total;
  final bool requiredDone;
  final bool allDone;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final g = context.guardian;
    final Color accent;
    final IconData icon;
    final String title;
    final String body;
    if (allDone) {
      accent = g.success;
      icon = Icons.verified_rounded;
      title = 'Fully protected';
      body = 'Every permission is granted. Sessions cannot be escaped.';
    } else if (requiredDone) {
      accent = scheme.primary;
      icon = Icons.shield_rounded;
      title = 'Protection is on';
      body = 'The essentials are ready. Grant the recommended items for the '
          'most reliable experience.';
    } else {
      accent = scheme.secondary;
      icon = Icons.shield_outlined;
      title = 'Protection is off';
      body = 'Screen Guardian needs the required permissions before a child '
          'session can start.';
    }
    return SoftCard(
      color: accent.withValues(alpha: 0.10),
      borderColor: accent.withValues(alpha: 0.25),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBubble(icon: icon, color: accent, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.titleLarge),
                    Text('$granted of $total permissions granted',
                        style: context.text.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : granted / total,
              minHeight: 8,
              color: accent,
              backgroundColor: accent.withValues(alpha: 0.18),
            ),
          ),
          const SizedBox(height: 12),
          Text(body,
              style: context.text.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _PermCard extends StatelessWidget {
  const _PermCard({required this.item, required this.granted});
  final _PermItem item;
  final bool granted;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final scheme = context.scheme;
    final g = context.guardian;
    final accent = granted ? g.success : scheme.primary;
    return SoftCard(
      onTap: granted ? null : () => state.requestPermission(item.key),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBubble(icon: item.icon, color: accent, size: 46),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(item.title,
                            style: context.text.titleMedium)),
                    if (granted)
                      StatusPill('Granted',
                          icon: Icons.check_rounded,
                          background: g.successContainer,
                          foreground: g.onSuccessContainer)
                    else if (item.required)
                      StatusPill('Required',
                          background: scheme.secondaryContainer,
                          foreground: scheme.onSecondaryContainer),
                  ],
                ),
                const SizedBox(height: 4),
                Text(item.description,
                    style: context.text.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                if (!granted) ...[
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Grant'),
                    onPressed: () => state.requestPermission(item.key),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
