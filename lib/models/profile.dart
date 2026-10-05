import 'dart:convert';

/// A managed user profile (e.g. a child). Each profile has its own allowed
/// apps, screen-time session length, optional PIN and content-filter settings.
class Profile {
  Profile({
    required this.id,
    required this.name,
    this.emoji = '🙂',
    this.colorValue = 0xFF5C6BC0,
    this.pinHash,
    this.pinSalt,
    List<String>? allowedPackages,
    this.iosAllowedAppCount = 0,
    this.sessionMinutes = 30,
    this.dnsFilterEnabled = true,
    List<String>? blockedDomains,
    List<String>? blockedIps,
  }) : allowedPackages = allowedPackages ?? <String>[],
       blockedDomains = blockedDomains ?? <String>[],
       blockedIps = blockedIps ?? <String>[];

  final String id;
  String name;
  String emoji;
  int colorValue;

  /// Salted SHA-256 of the profile PIN. `null` means no PIN required.
  String? pinHash;
  String? pinSalt;

  /// Android package names the profile may open during a session.
  List<String> allowedPackages;

  /// iOS keeps the opaque Screen Time selection natively; we only mirror the
  /// number of chosen apps for display purposes.
  int iosAllowedAppCount;

  /// Length of a single screen-time session in minutes.
  int sessionMinutes;

  /// Route DNS through the child-safe filter while this profile is active.
  bool dnsFilterEnabled;

  /// Extra domains / IPs blocked in addition to the built-in list.
  List<String> blockedDomains;
  List<String> blockedIps;

  bool get hasPin => pinHash != null && pinSalt != null;

  Profile copy() => Profile.fromJson(toJson());

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'emoji': emoji,
    'colorValue': colorValue,
    'pinHash': pinHash,
    'pinSalt': pinSalt,
    'allowedPackages': allowedPackages,
    'iosAllowedAppCount': iosAllowedAppCount,
    'sessionMinutes': sessionMinutes,
    'dnsFilterEnabled': dnsFilterEnabled,
    'blockedDomains': blockedDomains,
    'blockedIps': blockedIps,
  };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    id: j['id'] as String,
    name: j['name'] as String,
    emoji: (j['emoji'] as String?) ?? '🙂',
    colorValue: (j['colorValue'] as int?) ?? 0xFF5C6BC0,
    pinHash: j['pinHash'] as String?,
    pinSalt: j['pinSalt'] as String?,
    allowedPackages:
        (j['allowedPackages'] as List?)?.cast<String>().toList() ?? <String>[],
    iosAllowedAppCount: (j['iosAllowedAppCount'] as int?) ?? 0,
    sessionMinutes: (j['sessionMinutes'] as int?) ?? 30,
    dnsFilterEnabled: (j['dnsFilterEnabled'] as bool?) ?? true,
    blockedDomains:
        (j['blockedDomains'] as List?)?.cast<String>().toList() ?? <String>[],
    blockedIps:
        (j['blockedIps'] as List?)?.cast<String>().toList() ?? <String>[],
  );

  static List<Profile> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return <Profile>[];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => Profile.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static String encodeList(List<Profile> profiles) =>
      jsonEncode(profiles.map((p) => p.toJson()).toList());
}
