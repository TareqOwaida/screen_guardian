import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/active_session.dart';
import '../models/installed_app.dart';
import '../models/profile.dart';
import '../services/pin_service.dart';
import '../services/platform_service.dart';
import '../services/storage_service.dart';

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState(this._storage);

  final StorageService _storage;
  final PlatformService platform = PlatformService();
  static const _uuid = Uuid();

  bool ready = false;
  List<Profile> profiles = <Profile>[];
  AdminCredential? admin;
  ActiveSession? _session;
  ActiveSession? get session => _session;
  bool _sessionBusy = false;
  bool _syncing = false;
  bool _disposed = false;
  int _sessionRevision = 0;
  String? sessionError;

  /// Expiry keeps the profile locked until a parent explicitly ends it.
  bool get sessionLocked => session != null || _sessionBusy;
  bool get sessionBusy => _sessionBusy;
  Map<String, bool> permissions = <String, bool>{};
  List<InstalledApp>? installedApps;
  bool isDeviceOwner = false;

  /// True once the parent has walked through (or explicitly skipped) the
  /// first-run device setup. Sessions are still gated on [enforcementReady].
  bool setupCompleted = false;

  Timer? _ticker;
  StreamSubscription<Map<String, dynamic>>? _events;

  bool get hasAdmin => admin != null;
  bool get sessionActive => session != null && !session!.isExpired;
  bool get sessionExpired => session != null && session!.isExpired;

  /// First-run setup is shown until the required permissions are granted or
  /// the parent chooses to skip it.
  bool get needsSetup => hasAdmin && !setupCompleted && !enforcementReady;

  Profile? profileById(String id) {
    for (final p in profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  Profile? get activeProfile =>
      session == null ? null : profileById(session!.profileId);

  // ------------------------------------------------------------ lifecycle

  Future<void> init() async {
    profiles = _storage.loadProfiles();
    admin = _storage.loadAdmin();
    _session = _storage.loadSession();
    setupCompleted = _storage.loadSetupCompleted();
    WidgetsBinding.instance.addObserver(this);
    _events = platform.events.listen(_onNativeEvent);
    await syncNativeSession();
    await refreshPermissions();
    isDeviceOwner = await platform.isDeviceOwner();
    if (_disposed) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    ready = true;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      syncNativeSession();
      refreshPermissions();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _events?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  void _tick() {
    if (session != null) notifyListeners();
  }

  void _onNativeEvent(Map<String, dynamic> e) {
    switch (e['event']) {
      case 'sessionEnded':
      case 'tick':
        syncNativeSession();
        break;
    }
  }

  /// The native side is the source of truth while a session is running (it
  /// keeps enforcing even if the Flutter process was killed).
  Future<void> syncNativeSession() async {
    if (_sessionBusy || _syncing || _disposed) return;
    _syncing = true;
    final revision = _sessionRevision;
    try {
      final native = await platform.getSessionState();
      if (_disposed || revision != _sessionRevision || native == null) return;
      if (native['active'] == true) {
        await _applyNativeSession(native);
      } else if (session != null) {
        // Losing native state is not parent authorization to unlock the UI.
        sessionError =
            'Device protection was interrupted. Ask a parent to end the session and restore protection.';
        notifyListeners();
      }
    } finally {
      _syncing = false;
    }
  }

  Future<void> _applyNativeSession(Map<String, dynamic> native) async {
    if (native['active'] == true) {
      final endsAt = DateTime.fromMillisecondsSinceEpoch(
        native['endsAt'] as int,
      );
      final startedAt = native['startedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(native['startedAt'] as int)
          : (session?.startedAt ?? DateTime.now());
      _session = ActiveSession(
        profileId: (native['profileId'] as String?) ?? session?.profileId ?? '',
        profileName:
            (native['profileName'] as String?) ?? session?.profileName ?? '',
        startedAt: startedAt,
        endsAt: endsAt,
      );
    } else if (native['active'] == false) {
      _session = null;
    }
    await _storage.saveSession(session);
    notifyListeners();
  }

  // ---------------------------------------------------------- permissions

  Future<void> refreshPermissions() async {
    permissions = await platform.getPermissionStatus();
    notifyListeners();
  }

  Future<void> requestPermission(String key) async {
    await platform.requestPermission(key);
    await refreshPermissions();
  }

  bool granted(String key) => permissions[key] == true;

  /// Permissions without which enforcement cannot work at all.
  bool get enforcementReady {
    if (PlatformService.isAndroid) {
      return granted(PermissionKeys.accessibility);
    }
    if (PlatformService.isIOS) {
      return granted(PermissionKeys.screenTime);
    }
    return false;
  }

  /// A session may only start when the OS can actually enforce it; otherwise
  /// the child could simply leave the app.
  bool get canStartSession =>
      ready && hasAdmin && enforcementReady && !sessionLocked;

  bool canStartProfile(Profile profile) =>
      canStartSession &&
      (!PlatformService.isAndroid ||
          !profile.dnsFilterEnabled ||
          granted(PermissionKeys.vpn));

  Future<void> completeSetup() async {
    setupCompleted = true;
    await _storage.saveSetupCompleted(true);
    notifyListeners();
  }

  // ---------------------------------------------------------------- admin

  Future<void> setAdminPin(String pin) async {
    if (sessionLocked) {
      throw StateError('End the session before changing the parent PIN.');
    }
    final salt = PinService.newSalt();
    admin = AdminCredential(hash: PinService.hash(pin, salt), salt: salt);
    await _storage.saveAdmin(admin!);
    notifyListeners();
  }

  bool verifyAdminPin(String pin) =>
      PinService.verify(pin, admin?.hash, admin?.salt);

  bool verifyProfilePin(Profile p, String pin) =>
      !p.hasPin || PinService.verify(pin, p.pinHash, p.pinSalt);

  // ------------------------------------------------------------- profiles

  Profile newProfileTemplate() => Profile(id: _uuid.v4(), name: '');

  Future<void> saveProfile(Profile p) async {
    if (sessionLocked) {
      throw StateError('End the session before editing profiles.');
    }
    final idx = profiles.indexWhere((e) => e.id == p.id);
    if (idx == -1) {
      profiles.add(p);
    } else {
      profiles[idx] = p;
    }
    await _storage.saveProfiles(profiles);
    notifyListeners();
  }

  Future<void> deleteProfile(String id) async {
    if (sessionLocked) {
      throw StateError('End the session before deleting profiles.');
    }
    profiles.removeWhere((e) => e.id == id);
    await _storage.saveProfiles(profiles);
    notifyListeners();
  }

  void setProfilePin(Profile p, String? pin) {
    if (pin == null) {
      p.pinHash = null;
      p.pinSalt = null;
    } else {
      final salt = PinService.newSalt();
      p.pinSalt = salt;
      p.pinHash = PinService.hash(pin, salt);
    }
  }

  // -------------------------------------------------------------- session

  /// Returns `false` (and does nothing) when enforcement is not available.
  Future<bool> startSession(Profile p, {int? minutes}) async {
    if (sessionLocked) {
      return _sessionFailure(
        'A profile is already locked. Ask a parent to end its session first.',
      );
    }
    final mins = minutes ?? p.sessionMinutes;
    if (!ready || !hasAdmin || profileById(p.id) == null) {
      return _sessionFailure(
        'Set up a parent PIN and save this profile first.',
      );
    }
    final minimum = PlatformService.isIOS ? 15 : 1;
    if (mins < minimum || mins > 240) {
      return _sessionFailure(
        'Choose a session between $minimum and 240 minutes.',
      );
    }
    _beginSessionChange();
    try {
      await refreshPermissions();
      if (!enforcementReady) {
        return _sessionFailure(
          'Protection is off. A parent must finish device setup first.',
        );
      }
      if (PlatformService.isAndroid &&
          p.dnsFilterEnabled &&
          !granted(PermissionKeys.vpn)) {
        return _sessionFailure(
          'A parent must grant Safe DNS (VPN) access before starting this profile.',
        );
      }
      final native = await platform.startSession(p, mins, p.id);
      if (native['active'] != true || native['profileId'] != p.id) {
        throw StateError('The device did not start the requested profile.');
      }
      await _applyNativeSession(native);
      return true;
    } catch (error) {
      // A native command can fail after persistence; keep any native lock.
      final native = await platform.getSessionState();
      if (native?['active'] == true) await _applyNativeSession(native!);
      return _sessionFailure(_sessionErrorMessage(error));
    } finally {
      _finishSessionChange();
    }
  }

  Future<bool> extendSession(int minutes, {required String adminPin}) async {
    if (!verifyAdminPin(adminPin)) {
      return _sessionFailure('The parent PIN is incorrect.');
    }
    if (session == null || _sessionBusy) return false;
    if (minutes < 1 || minutes > 240) {
      return _sessionFailure('Choose between 1 and 240 extra minutes.');
    }
    _beginSessionChange();
    try {
      final native = await platform.extendSession(minutes);
      if (native['active'] != true ||
          native['profileId'] != session!.profileId) {
        throw StateError('The device did not confirm the session extension.');
      }
      await _applyNativeSession(native);
      return true;
    } catch (error) {
      return _sessionFailure(_sessionErrorMessage(error));
    } finally {
      _finishSessionChange();
    }
  }

  Future<bool> endSession({required String adminPin}) async {
    if (!verifyAdminPin(adminPin)) {
      return _sessionFailure('The parent PIN is incorrect.');
    }
    if (_sessionBusy) return false;
    _beginSessionChange();
    try {
      final native = await platform.stopSession();
      if (native['active'] != false) {
        throw StateError('The device is still enforcing this session.');
      }
      await _applyNativeSession(native);
      return true;
    } catch (error) {
      return _sessionFailure(_sessionErrorMessage(error));
    } finally {
      _finishSessionChange();
    }
  }

  void _beginSessionChange() {
    _sessionBusy = true;
    _sessionRevision++;
    sessionError = null;
    notifyListeners();
  }

  void _finishSessionChange() {
    _sessionBusy = false;
    notifyListeners();
  }

  bool _sessionFailure(String message) {
    sessionError = message;
    notifyListeners();
    return false;
  }

  String _sessionErrorMessage(Object error) => error is PlatformException
      ? error.message ??
            'The device could not update protection. Please try again.'
      : 'The device could not confirm the session change. Please try again.';

  // ---------------------------------------------------------------- apps

  Future<List<InstalledApp>> loadInstalledApps({bool force = false}) async {
    if (installedApps == null || force) {
      installedApps = await platform.getInstalledApps();
      notifyListeners();
    }
    return installedApps!;
  }

  Future<bool> launchApp(String packageName) async {
    if (!sessionActive ||
        _sessionBusy ||
        !(activeProfile?.allowedPackages.contains(packageName) ?? false)) {
      return false;
    }
    return platform.launchApp(packageName);
  }
}
