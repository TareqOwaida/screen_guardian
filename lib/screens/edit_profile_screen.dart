import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../services/platform_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/profile_avatar.dart';
import 'app_picker_screen.dart';
import 'pin_screen.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.profile,
    required this.isNew,
  });
  final Profile profile;
  final bool isNew;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final Profile p = widget.profile;
  late final TextEditingController _name = TextEditingController(text: p.name);
  final TextEditingController _domain = TextEditingController();
  final TextEditingController _ip = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    _domain.dispose();
    _ip.dispose();
    super.dispose();
  }

  Future<void> _pickApps() async {
    final state = context.read<AppState>();
    if (PlatformService.isIOS) {
      final count = await state.platform.presentIosAppPicker(p.id);
      if (mounted) setState(() => p.iosAllowedAppCount = count);
      return;
    }
    final result = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => AppPickerScreen(initiallySelected: p.allowedPackages),
      ),
    );
    if (mounted && result != null) setState(() => p.allowedPackages = result);
  }

  Future<void> _setPin() async {
    final state = context.read<AppState>();
    final pin = await PinScreen.collectNewPin(
      context,
      title: '${p.name.isEmpty ? 'Profile' : p.name} PIN',
    );
    if (pin == null || !mounted) return;
    setState(() => state.setProfilePin(p, pin));
  }

  void _addDomain() {
    var d = _domain.text.trim().toLowerCase();
    d = d.replaceFirst(RegExp(r'^https?://'), '').split('/').first;
    if (d.isEmpty || p.blockedDomains.contains(d)) return;
    setState(() {
      p.blockedDomains.add(d);
      _domain.clear();
    });
  }

  void _addIp() {
    final ip = _ip.text.trim();
    final valid =
        RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(ip) &&
        ip.split('.').every((part) => int.parse(part) <= 255);
    if (!valid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid IPv4 address')),
      );
      return;
    }
    if (p.blockedIps.contains(ip)) return;
    setState(() {
      p.blockedIps.add(ip);
      _ip.clear();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    p.name = _name.text.trim();
    await context.read<AppState>().saveProfile(p);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final color = Color(p.colorValue);
    final appCount = PlatformService.isIOS
        ? p.iosAllowedAppCount
        : p.allowedPackages.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'New profile' : 'Edit profile'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            // ------------------------------------------------ identity
            Center(
              child: Column(
                children: [
                  ProfileAvatar(profile: p, size: 104),
                  const SizedBox(height: 12),
                  Text(
                    p.name.isEmpty ? 'New profile' : p.name,
                    style: context.text.headlineSmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.badge_rounded),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              onChanged: (v) => setState(() => p.name = v),
            ),
            const SizedBox(height: 24),
            const SectionHeader('Avatar'),
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: kProfileEmojis.map((e) {
                      final selected = p.emoji == e;
                      return _EmojiChoice(
                        emoji: e,
                        selected: selected,
                        color: color,
                        onTap: () => setState(() => p.emoji = e),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: kProfileColors.map((c) {
                      final selected = p.colorValue == c;
                      return _ColorDot(
                        color: Color(c),
                        selected: selected,
                        onTap: () => setState(() => p.colorValue = c),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // ---------------------------------------------- screen time
            const SectionHeader('Screen time'),
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconBubble(icon: Icons.timer_rounded, color: color),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Default session length',
                              style: context.text.titleMedium,
                            ),
                            Text(
                              'A parent can pick a different length each time.',
                              style: context.text.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${p.sessionMinutes} min',
                        style: context.text.titleLarge?.copyWith(color: color),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: color,
                      thumbColor: color,
                      overlayColor: color.withValues(alpha: 0.12),
                    ),
                    child: Slider(
                      value: p.sessionMinutes.toDouble(),
                      min: 5,
                      max: 240,
                      divisions: 47,
                      label: '${p.sessionMinutes} min',
                      onChanged: (v) =>
                          setState(() => p.sessionMinutes = v.round()),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // ---------------------------------------------- allowed apps
            const SectionHeader('Allowed apps'),
            _SettingTile(
              icon: Icons.apps_rounded,
              color: AppTheme.coral,
              title: '$appCount app${appCount == 1 ? '' : 's'} allowed',
              subtitle: PlatformService.isIOS
                  ? 'Uses Apple Screen Time – every other app is shielded'
                  : 'Every other app is blocked during a session',
              onTap: _pickApps,
            ),
            const SizedBox(height: 24),
            // ----------------------------------------------- profile pin
            const SectionHeader('Profile PIN'),
            _SettingTile(
              icon: p.hasPin ? Icons.lock_rounded : Icons.lock_open_rounded,
              color: AppTheme.amber,
              title: p.hasPin ? 'PIN is set' : 'No PIN',
              subtitle:
                  'Asked before this profile can start a session, so '
                  'siblings cannot use each other\'s time.',
              trailing: p.hasPin
                  ? TextButton(
                      onPressed: () => setState(
                        () => context.read<AppState>().setProfilePin(p, null),
                      ),
                      child: const Text('Remove'),
                    )
                  : null,
              onTap: _setPin,
            ),
            const SizedBox(height: 24),
            // ----------------------------------------------- content safety
            const SectionHeader('Content safety'),
            SoftCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                    secondary: IconBubble(
                      icon: Icons.security_rounded,
                      color: context.guardian.success,
                    ),
                    title: const Text('Safe DNS filter'),
                    subtitle: Text(
                      PlatformService.isIOS
                          ? 'Encrypted family-safe DNS + Apple web content filter'
                          : 'Blocks adult, gambling, malware & phishing domains '
                                'and your custom list',
                    ),
                    value: p.dnsFilterEnabled,
                    onChanged: (v) => setState(() => p.dnsFilterEnabled = v),
                  ),
                  if (p.dnsFilterEnabled) ...[
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ListEditor(
                            title: 'Extra blocked domains',
                            hint: 'example.com',
                            controller: _domain,
                            keyboardType: TextInputType.url,
                            items: p.blockedDomains,
                            onAdd: _addDomain,
                            onRemove: (d) =>
                                setState(() => p.blockedDomains.remove(d)),
                          ),
                          if (PlatformService.isAndroid) ...[
                            const SizedBox(height: 20),
                            _ListEditor(
                              title: 'Extra blocked IP addresses',
                              hint: '203.0.113.7',
                              controller: _ip,
                              keyboardType: TextInputType.number,
                              items: p.blockedIps,
                              onAdd: _addIp,
                              onRemove: (ip) =>
                                  setState(() => p.blockedIps.remove(ip)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(widget.isNew ? 'Create profile' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmojiChoice extends StatelessWidget {
  const _EmojiChoice({
    required this.emoji,
    required this.selected,
    required this.color,
    required this.onTap,
  });
  final String emoji;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? color.withValues(alpha: 0.16)
          : context.scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? color : Colors.transparent,
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Text(emoji, style: const TextStyle(fontSize: 24, height: 1)),
          ),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Profile colour',
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
              color: selected ? context.scheme.onSurface : Colors.transparent,
              width: 3,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.45),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: selected
              ? Icon(
                  Icons.check_rounded,
                  color: color.readableForeground,
                  size: 22,
                )
              : null,
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onTap: onTap,
      child: Row(
        children: [
          IconBubble(icon: icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleMedium),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: context.text.bodySmall?.copyWith(
                    color: context.scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing ??
              Icon(
                Icons.chevron_right_rounded,
                color: context.scheme.onSurfaceVariant,
              ),
        ],
      ),
    );
  }
}

class _ListEditor extends StatelessWidget {
  const _ListEditor({
    required this.title,
    required this.hint,
    required this.controller,
    required this.keyboardType,
    required this.items,
    required this.onAdd,
    required this.onRemove,
  });
  final String title;
  final String hint;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final List<String> items;
  final VoidCallback onAdd;
  final void Function(String) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.text.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: hint,
                  isDense: true,
                  fillColor: context.scheme.surfaceContainerLow,
                ),
                keyboardType: keyboardType,
                onSubmitted: (_) => onAdd(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        if (items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: items
                  .map(
                    (d) => InputChip(
                      label: Text(d),
                      deleteIcon: const Icon(Icons.close_rounded, size: 16),
                      onDeleted: () => onRemove(d),
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }
}
