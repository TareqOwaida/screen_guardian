import 'dart:convert';

/// The currently running screen-time session.
class ActiveSession {
  ActiveSession({
    required this.profileId,
    required this.profileName,
    required this.startedAt,
    required this.endsAt,
  });

  final String profileId;
  final String profileName;
  final DateTime startedAt;
  DateTime endsAt;

  Duration get remaining {
    final d = endsAt.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  Duration get total => endsAt.difference(startedAt);

  bool get isExpired => !DateTime.now().isBefore(endsAt);

  Map<String, dynamic> toJson() => {
        'profileId': profileId,
        'profileName': profileName,
        'startedAt': startedAt.millisecondsSinceEpoch,
        'endsAt': endsAt.millisecondsSinceEpoch,
      };

  factory ActiveSession.fromJson(Map<String, dynamic> j) => ActiveSession(
        profileId: j['profileId'] as String,
        profileName: j['profileName'] as String,
        startedAt: DateTime.fromMillisecondsSinceEpoch(j['startedAt'] as int),
        endsAt: DateTime.fromMillisecondsSinceEpoch(j['endsAt'] as int),
      );

  String encode() => jsonEncode(toJson());

  static ActiveSession? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return ActiveSession.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map));
  }
}
