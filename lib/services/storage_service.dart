import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/active_session.dart';
import '../models/profile.dart';

class AdminCredential {
  const AdminCredential({required this.hash, required this.salt});
  final String hash;
  final String salt;

  Map<String, String> toJson() => {'hash': hash, 'salt': salt};
  factory AdminCredential.fromJson(Map<String, dynamic> j) =>
      AdminCredential(hash: j['hash'] as String, salt: j['salt'] as String);
}

/// Thin persistence layer on top of SharedPreferences.
class StorageService {
  StorageService._(this._prefs);
  final SharedPreferences _prefs;

  static const _kProfiles = 'profiles';
  static const _kAdmin = 'admin_pin';
  static const _kSession = 'active_session';
  static const _kSetupDone = 'setup_completed';

  static Future<StorageService> create() async =>
      StorageService._(await SharedPreferences.getInstance());

  bool loadSetupCompleted() => _prefs.getBool(_kSetupDone) ?? false;

  Future<void> saveSetupCompleted(bool value) =>
      _prefs.setBool(_kSetupDone, value);

  List<Profile> loadProfiles() =>
      Profile.decodeList(_prefs.getString(_kProfiles));

  Future<void> saveProfiles(List<Profile> profiles) =>
      _prefs.setString(_kProfiles, Profile.encodeList(profiles));

  AdminCredential? loadAdmin() {
    final raw = _prefs.getString(_kAdmin);
    if (raw == null) return null;
    return AdminCredential.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map));
  }

  Future<void> saveAdmin(AdminCredential cred) =>
      _prefs.setString(_kAdmin, jsonEncode(cred.toJson()));

  ActiveSession? loadSession() =>
      ActiveSession.decode(_prefs.getString(_kSession));

  Future<void> saveSession(ActiveSession? session) => session == null
      ? _prefs.remove(_kSession)
      : _prefs.setString(_kSession, session.encode());
}
