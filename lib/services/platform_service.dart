import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/installed_app.dart';
import '../models/profile.dart';

/// Permission / capability keys shared with the native side.
class PermissionKeys {
  // Android
  static const accessibility = 'accessibility';
  static const usageAccess = 'usageAccess';
  static const overlay = 'overlay';
  static const notifications = 'notifications';
  static const deviceAdmin = 'deviceAdmin';
  static const batteryOptimization = 'batteryOptimization';
  static const vpn = 'vpn';
  // iOS
  static const screenTime = 'screenTime';
  static const dns = 'dns';
}

/// Bridge to the Kotlin / Swift implementation.
///
/// Read-only capability calls degrade gracefully. Session commands must report
/// errors, so the UI never claims enforcement succeeded when it did not.
class PlatformService {
  static const MethodChannel _m = MethodChannel(
    'com.tareq.screen_guardian/native',
  );
  static const EventChannel _e = EventChannel(
    'com.tareq.screen_guardian/events',
  );

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Stream<Map<String, dynamic>> get events => _e
      .receiveBroadcastStream()
      .map((e) => Map<String, dynamic>.from(e as Map))
      .handleError((Object err) => debugPrint('event channel error: $err'));

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _m.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('native $method failed: ${e.code} ${e.message}');
      return null;
    }
  }

  // ---------------------------------------------------------------- shared

  Future<Map<String, bool>> getPermissionStatus() async {
    final res = await _call<Map>('getPermissionStatus');
    if (res == null) return <String, bool>{};
    return res.map((k, v) => MapEntry(k as String, v == true));
  }

  Future<void> requestPermission(String key) =>
      _call<void>('requestPermission', {'key': key});

  /// Starts enforcement for [profile] for [minutes]. Native side persists the
  /// session so it survives process death and reboots.
  Future<Map<String, dynamic>> _sessionCommand(
    String method, [
    Object? args,
  ]) async {
    final result = await _m.invokeMapMethod<String, dynamic>(method, args);
    if (result == null || result['active'] is! bool) {
      throw PlatformException(
        code: 'invalid_session',
        message: 'The device did not confirm the session change.',
      );
    }
    return result;
  }

  Future<Map<String, dynamic>> startSession(
    Profile profile,
    int minutes,
    String profileId,
  ) => _sessionCommand('startSession', {
    'profileId': profileId,
    'profileName': profile.name,
    'allowedPackages': profile.allowedPackages,
    'durationMinutes': minutes,
    'dnsFilterEnabled': profile.dnsFilterEnabled,
    'blockedDomains': profile.blockedDomains,
    'blockedIps': profile.blockedIps,
  });

  Future<Map<String, dynamic>> extendSession(int minutes) =>
      _sessionCommand('extendSession', {'minutes': minutes});

  Future<Map<String, dynamic>> stopSession() => _sessionCommand('stopSession');

  /// `{active: bool, endsAt: int, profileId: String, profileName: String}`
  Future<Map<String, dynamic>?> getSessionState() async {
    final res = await _call<Map>('getSessionState');
    return res == null ? null : Map<String, dynamic>.from(res);
  }

  // --------------------------------------------------------------- android

  Future<List<InstalledApp>> getInstalledApps() async {
    final res = await _call<List>('getInstalledApps');
    if (res == null) return <InstalledApp>[];
    final apps = res.map((e) => InstalledApp.fromMap(e as Map)).toList();
    apps.sort(
      (a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()),
    );
    return apps;
  }

  Future<bool> launchApp(String packageName) async =>
      (await _call<bool>('launchApp', {'packageName': packageName})) ?? false;

  Future<bool> isDeviceOwner() async =>
      (await _call<bool>('isDeviceOwner')) ?? false;

  // ------------------------------------------------------------------- ios

  /// `notDetermined | denied | approved | unavailable`
  Future<String> screenTimeAuthorizationStatus() async =>
      (await _call<String>('screenTimeStatus')) ?? 'unavailable';

  Future<bool> requestScreenTimeAuthorization() async =>
      (await _call<bool>('requestScreenTime')) ?? false;

  /// Presents Apple's FamilyActivityPicker. Returns the number of apps chosen.
  Future<int> presentIosAppPicker(String profileId) async =>
      (await _call<int>('presentAppPicker', {'profileId': profileId})) ?? 0;

  Future<bool> configureSafeDns() async =>
      (await _call<bool>('configureSafeDns')) ?? false;

  Future<void> removeSafeDns() => _call<void>('removeSafeDns');
}
