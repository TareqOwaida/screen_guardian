import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:screen_guardian/main.dart';
import 'package:screen_guardian/models/profile.dart';
import 'package:screen_guardian/screens/active_session_screen.dart';
import 'package:screen_guardian/screens/profile_picker_screen.dart';
import 'package:screen_guardian/screens/time_up_screen.dart';
import 'package:screen_guardian/services/storage_service.dart';
import 'package:screen_guardian/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.tareq.screen_guardian/native');
  const events = MethodChannel('com.tareq.screen_guardian/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late AppState state;
  late StorageService storage;
  late Profile profile;
  late Map<String, dynamic> native;
  late Map<String, bool> permissions;
  late List<String> commands;
  var disposed = false;
  Future<Object?> Function(MethodCall)? intercept;

  Map<String, dynamic> running({bool expired = false}) {
    final now = DateTime.now();
    return {
      'active': true,
      'profileId': profile.id,
      'profileName': profile.name,
      'startedAt': now
          .subtract(const Duration(minutes: 30))
          .millisecondsSinceEpoch,
      'endsAt': now
          .add(Duration(minutes: expired ? -1 : 30))
          .millisecondsSinceEpoch,
    };
  }

  Future<void> initialize({bool active = false, bool expired = false}) async {
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.create();
    profile = Profile(
      id: 'child',
      name: 'Alex',
      allowedPackages: ['allowed.app'],
    );
    await storage.saveProfiles([profile]);
    state = AppState(storage);
    await state.setAdminPin('1234');
    if (active) native = running(expired: expired);
    await state.init();
  }

  setUp(() {
    disposed = false;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    native = {'active': false};
    permissions = {'accessibility': true, 'vpn': true, 'screenTime': true};
    commands = [];
    intercept = null;
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(channel, (call) async {
      commands.add(call.method);
      if (intercept != null) {
        final response = await intercept!(call);
        if (response != null) return response;
      }
      switch (call.method) {
        case 'getPermissionStatus':
          return permissions;
        case 'isDeviceOwner':
          return false;
        case 'getInstalledApps':
          return [];
        case 'getSessionState':
          return Map<String, dynamic>.of(native);
        case 'startSession':
          native = running();
          return native;
        case 'extendSession':
          native = {...native, 'endsAt': (native['endsAt'] as int) + 900000};
          return native;
        case 'stopSession':
          native = {'active': false};
          return native;
        case 'launchApp':
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    if (!disposed) state.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(events, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('starts only after the device confirms enforcement', () async {
    await initialize();
    final reply = Completer<Object?>();
    intercept = (call) async =>
        call.method == 'startSession' ? reply.future : null;
    final started = state.startSession(profile);
    await Future<void>.delayed(Duration.zero);
    expect(state.sessionLocked, isTrue);
    expect(state.session, isNull);
    reply.complete(running());
    expect(await started, isTrue);
    expect(state.sessionActive, isTrue);
    expect(storage.loadSession()?.profileId, profile.id);
  });

  test('rejects a second start while the first start is pending', () async {
    await initialize();
    final reply = Completer<Object?>();
    intercept = (call) async =>
        call.method == 'startSession' ? reply.future : null;
    final first = state.startSession(profile);
    expect(await state.startSession(profile), isFalse);
    reply.complete(running());
    expect(await first, isTrue);
    expect(commands.where((c) => c == 'startSession'), hasLength(1));
  });

  test('a running or expired session cannot be replaced or edited', () async {
    await initialize(active: true, expired: true);
    expect(state.sessionLocked, isTrue);
    expect(await state.startSession(profile), isFalse);
    await expectLater(state.deleteProfile(profile.id), throwsStateError);
    await expectLater(state.saveProfile(profile.copy()), throwsStateError);
    await expectLater(state.setAdminPin('5678'), throwsStateError);
    expect(commands, isNot(contains('startSession')));
  });

  test('both ending and extending require the parent PIN', () async {
    await initialize(active: true);
    expect(await state.endSession(adminPin: '0000'), isFalse);
    expect(await state.extendSession(15, adminPin: '0000'), isFalse);
    expect(state.sessionLocked, isTrue);
    expect(commands, isNot(contains('stopSession')));
    expect(commands, isNot(contains('extendSession')));
  });

  test(
    'failed native shutdown leaves the session and persistence locked',
    () async {
      await initialize(active: true);
      intercept = (call) async {
        if (call.method == 'stopSession') {
          throw PlatformException(
            code: 'failure',
            message: 'Could not stop protection',
          );
        }
        return null;
      };
      expect(await state.endSession(adminPin: '1234'), isFalse);
      expect(state.sessionLocked, isTrue);
      expect(storage.loadSession(), isNotNull);
      expect(state.sessionError, contains('Could not stop'));
    },
  );

  test(
    'successful parent shutdown unlocks only after native acknowledgement',
    () async {
      await initialize(active: true);
      final reply = Completer<Object?>();
      intercept = (call) async =>
          call.method == 'stopSession' ? reply.future : null;
      final ended = state.endSession(adminPin: '1234');
      expect(state.sessionLocked, isTrue);
      expect(storage.loadSession(), isNotNull);
      reply.complete({'active': false});
      expect(await ended, isTrue);
      expect(state.sessionLocked, isFalse);
      expect(storage.loadSession(), isNull);
    },
  );

  test(
    'native start failures are surfaced without a phantom session',
    () async {
      await initialize();
      intercept = (call) async {
        if (call.method == 'startSession') {
          throw PlatformException(
            code: 'failure',
            message: 'Permission revoked',
          );
        }
        return null;
      };
      expect(await state.startSession(profile), isFalse);
      expect(state.sessionLocked, isFalse);
      expect(storage.loadSession(), isNull);
      expect(state.sessionError, 'Permission revoked');
    },
  );

  test('a partially persisted native start failure retains the lock', () async {
    await initialize();
    intercept = (call) async {
      if (call.method == 'startSession') {
        native = running();
        throw PlatformException(code: 'failure');
      }
      return null;
    };
    expect(await state.startSession(profile), isFalse);
    expect(state.sessionLocked, isTrue);
    expect(storage.loadSession(), isNotNull);
  });

  test(
    'failed extension never changes the displayed or saved deadline',
    () async {
      await initialize(active: true);
      final deadline = state.session!.endsAt;
      intercept = (call) async {
        if (call.method == 'extendSession') {
          throw PlatformException(code: 'failure');
        }
        return null;
      };
      expect(await state.extendSession(15, adminPin: '1234'), isFalse);
      expect(state.session!.endsAt, deadline);
      expect(storage.loadSession()!.endsAt, deadline);
    },
  );

  test(
    'old resume response cannot re-lock a session after parent shutdown',
    () async {
      await initialize(active: true);
      final stale = Map<String, dynamic>.of(native);
      final reply = Completer<Object?>();
      intercept = (call) async =>
          call.method == 'getSessionState' ? reply.future : null;
      final sync = state.syncNativeSession();
      expect(await state.endSession(adminPin: '1234'), isTrue);
      reply.complete(stale);
      await sync;
      expect(state.sessionLocked, isFalse);
      expect(storage.loadSession(), isNull);
    },
  );

  test(
    'missing native state cannot silently unlock a stored session',
    () async {
      await initialize(active: true);
      native = {'active': false};
      await state.syncNativeSession();
      expect(state.sessionLocked, isTrue);
      expect(storage.loadSession(), isNotNull);
    },
  );

  test('checks accessibility and profile VPN consent again at start', () async {
    await initialize();
    permissions['accessibility'] = false;
    expect(await state.startSession(profile), isFalse);
    permissions['accessibility'] = true;
    permissions['vpn'] = false;
    expect(await state.startSession(profile), isFalse);
    expect(state.sessionError, contains('VPN'));
    expect(commands, isNot(contains('startSession')));
    profile.dnsFilterEnabled = false;
    expect(await state.startSession(profile), isTrue);
  });

  test(
    'iOS refuses sessions shorter than its background monitoring minimum',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await initialize();
      expect(await state.startSession(profile, minutes: 5), isFalse);
      expect(commands, isNot(contains('startSession')));
      expect(await state.startSession(profile, minutes: 15), isTrue);
    },
  );

  test('launcher refuses unapproved apps and all apps after expiry', () async {
    await initialize(active: true);
    expect(await state.launchApp('not.allowed'), isFalse);
    expect(await state.launchApp('allowed.app'), isTrue);
    native = running(expired: true);
    await state.syncNativeSession();
    expect(await state.launchApp('allowed.app'), isFalse);
    expect(commands.where((c) => c == 'launchApp'), hasLength(1));
  });

  test('copied profiles do not share app or filter lists', () async {
    await initialize();
    final copy = profile.copy();
    copy.allowedPackages.clear();
    copy.blockedDomains.add('example.com');
    copy.blockedIps.add('192.0.2.1');
    expect(profile.allowedPackages, ['allowed.app']);
    expect(profile.blockedDomains, isEmpty);
    expect(profile.blockedIps, isEmpty);
  });

  for (final expired in [false, true]) {
    testWidgets(
      'restored ${expired ? 'expired' : 'active'} session blocks Back and PIN cancellation returns to lock',
      (tester) async {
        tester.view.physicalSize = const Size(420, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await initialize(active: true, expired: expired);
        state.dispose();
        state = AppState(storage);
        await state.init();
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: state,
            child: const ScreenGuardianApp(),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        final screen = find.byType(
          expired ? TimeUpScreen : ActiveSessionScreen,
        );
        expect(screen, findsOneWidget);
        final navigator = tester.state<NavigatorState>(
          find.byType(Navigator).first,
        );
        expect(await navigator.maybePop(), isTrue);
        await tester.pump();
        expect(screen, findsOneWidget);
        expect(find.byType(ProfilePickerScreen), findsNothing);
        await tester.tap(
          expired ? find.text('Parent unlock') : find.byTooltip('Parent'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Parent PIN'), findsOneWidget);
        await tester.tap(find.byTooltip('Cancel'));
        await tester.pumpAndSettle();
        expect(screen, findsOneWidget);
        expect(state.sessionLocked, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        state.dispose();
        disposed = true;
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
