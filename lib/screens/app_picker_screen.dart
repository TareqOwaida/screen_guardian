import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/installed_app.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Android: choose the apps a profile may open.
class AppPickerScreen extends StatefulWidget {
  const AppPickerScreen({super.key, required this.initiallySelected});
  final List<String> initiallySelected;

  @override
  State<AppPickerScreen> createState() => _AppPickerScreenState();
}

class _AppPickerScreenState extends State<AppPickerScreen> {
  late final Set<String> _selected = widget.initiallySelected.toSet();
  String _query = '';
  bool _showSystem = false;
  List<InstalledApp>? _apps;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().loadInstalledApps().then((apps) {
      if (mounted) setState(() => _apps = apps);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final apps = _apps;
    final filtered = apps
        ?.where((a) =>
            _showSystem || !a.isSystem || _selected.contains(a.packageName))
        .where((a) => _query.isEmpty ||
            a.appName.toLowerCase().contains(_query) ||
            a.packageName.toLowerCase().contains(_query))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Allowed apps'),
        actions: [
          IconButton(
            tooltip: _showSystem ? 'Hide system apps' : 'Show system apps',
            icon: Icon(_showSystem
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded),
            onPressed: () => setState(() => _showSystem = !_showSystem),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(68),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Search apps',
                isDense: true,
                fillColor: context.guardian.card,
              ),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
        ),
      ),
      body: apps == null
          ? const Center(child: CircularProgressIndicator())
          : filtered!.isEmpty
              ? Center(
                  child: Text('No apps found',
                      style: context.text.bodyLarge
                          ?.copyWith(color: scheme.onSurfaceVariant)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final a = filtered[i];
                    final checked = _selected.contains(a.packageName);
                    return SoftCard(
                      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                      borderColor: checked ? scheme.primary : null,
                      onTap: () => setState(() {
                        if (checked) {
                          _selected.remove(a.packageName);
                        } else {
                          _selected.add(a.packageName);
                        }
                      }),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: a.icon != null
                                ? Image.memory(a.icon!)
                                : Icon(Icons.android_rounded,
                                    color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(a.appName,
                                    style: context.text.titleMedium),
                                Text(a.packageName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.text.bodySmall?.copyWith(
                                        color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          Checkbox(
                            value: checked,
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _selected.add(a.packageName);
                              } else {
                                _selected.remove(a.packageName);
                              }
                            }),
                          ),
                        ],
                      ),
                    );
                  },
                ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: FilledButton.icon(
          icon: const Icon(Icons.check_rounded),
          label: Text('Done · ${_selected.length} selected'),
          onPressed: () => Navigator.of(context).pop(_selected.toList()),
        ),
      ),
    );
  }
}
