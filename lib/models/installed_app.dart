import 'dart:typed_data';

/// An application installed on the device (Android only – iOS never exposes
/// the installed-app list; the Screen Time picker is used there instead).
class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.appName,
    required this.isSystem,
    this.icon,
  });

  final String packageName;
  final String appName;
  final bool isSystem;
  final Uint8List? icon;

  factory InstalledApp.fromMap(Map<dynamic, dynamic> m) => InstalledApp(
        packageName: m['packageName'] as String,
        appName: (m['appName'] as String?) ?? m['packageName'] as String,
        isSystem: (m['isSystem'] as bool?) ?? false,
        icon: m['icon'] as Uint8List?,
      );
}
