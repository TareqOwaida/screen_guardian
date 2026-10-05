# Screen Guardian

Flutter parental-control app for Android and iOS. A parent creates profiles with allowed apps, a session duration, an optional child PIN, and browsing-filter settings.

## Session behavior

- The profile stays locked while the timer runs and after time expires. A parent PIN is required to end or extend it.
- Back cannot close the session screen. Profiles cannot be replaced, edited, or deleted while a session is locked.
- Native enforcement confirms session changes before Flutter updates the timer or unlocks the profile. Failed commands show an error and retain an existing lock.
- Native session storage restores the active or expired profile after relaunch. Concurrent starts and stale resume responses cannot replace the session.
- Expiry blocks the allowed apps too; it does not return to the profile picker.

## Android

An accessibility service blocks unapproved apps and redirects the launcher to Screen Guardian. A foreground service maintains the timer, with Usage Access as a fallback. The task is hidden from Recents during a session, and the native activity also refuses app-driven close requests. Services are re-armed after task removal, accessibility reconnection, and reboot when Android permits it.

Sessions require the accessibility blocker to be connected. Profiles with safe browsing enabled also require VPN consent. Grant these through **Parent > Device protection**. Notifications, Usage Access, battery-optimization exemption, and device administrator improve operation on supported devices.

For an OS-enforced Home/Recents/notification lock, provision a dedicated test device as **device owner**. Device administrator alone is not equivalent. On a device eligible for provisioning (normally a fresh device without accounts):

```sh
adb shell dpm set-device-owner com.tareq.screen_guardian/.enforcement.GuardianDeviceAdminReceiver
```

Device-owner sessions use lock-task mode with system navigation disabled. Only the profile's approved apps can launch; at expiry, the kiosk allow-list narrows to Screen Guardian. Parent unlock releases the kiosk and restores the task to Recents.

Without device owner, accessibility enforcement is best effort: ordinary apps cannot guarantee protection against OS Force stop, permission revocation, safe mode, or manufacturer process management. A physical power-off cannot be prevented by this app. See [Android lock-task documentation](https://developer.android.com/work/dpc/dedicated-devices/lock-task-mode).

## iOS

The app uses Family Controls, Managed Settings, and Device Activity on iOS 16+. The Xcode project includes the native bridge sources and embeds the `GuardianMonitor` extension. The extension reads the shared session deadline before shielding apps, so an old callback does not intentionally lock a cancelled or extended session.

- Select a signing team for both Runner and GuardianMonitor in Xcode.
- Both targets require Family Controls and the App Group `group.com.tareq.screenGuardian`. Runner also requires the DNS Settings entitlement for encrypted safe DNS.
- Apple must approve the Family Controls distribution entitlement for App Store/TestFlight distribution.
- Sessions shorter than 15 minutes are refused because background Device Activity monitoring has a minimum interval. Scheduling failures are reported instead of silently delaying expiry.
- Test on a real iOS device with the required entitlements. Windows cannot compile or run the Swift targets.

Screen Time shields can remain when the app closes, but iOS does not let an ordinary app disable Home, the app switcher, or force quitting. Single-app locking requires [Guided Access](https://support.apple.com/en-us/111795) or a supervised-device configuration. This app requests individual Screen Time authorization; it does not provision supervised devices or Family Sharing parental authorization.

## Browsing filter limits

Android uses a DNS-only local VPN. DNS queries are forwarded to a family-safe upstream, with additional domain rules and IPv4 DNS-answer checks. It is not a full traffic firewall: direct-IP traffic, IPv6 answers, private DNS, and apps with their own encrypted DNS can bypass parts of this filter. No claim is made that all harmful content or direct-IP connections are blocked.

iOS uses Apple's content filtering plus an optional system encrypted-DNS profile. The parent must enable the DNS profile in Settings. Custom domain/IP lists are not enforced on iOS. A configured system DNS profile can remain enabled after a session ends.

## Development and verification

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter run
```

The regression suite covers duplicate starts, parent PIN enforcement, failed native commands, saved-session restoration, stale replies, expiry, app-launch restrictions, profile-copy isolation, and Back/PIN-cancel navigation.

Device verification should cover: create a parent PIN and profile; grant permissions; start a session; try Back, Home and Recents; open an allowed and a blocked app; relaunch during the session; verify expiry; extend with the parent PIN; end with the parent PIN and confirm normal navigation returns. Repeat with and without Android device-owner provisioning. Android device tests do not replace iOS testing.

## Project layout

- `lib/state/app_state.dart`: session state, profile persistence, permission checks, parent-protected session actions.
- `lib/screens/`: setup, profiles, allowed apps, session launcher, expiry, PIN entry.
- `lib/services/`: native channel, preferences, PIN hashing.
- `android/app/src/main/kotlin/com/tareq/screen_guardian/`: activity, enforcement services, session storage, DNS VPN.
- `ios/Runner/`: Screen Time and DNS bridges, shared session storage.
- `ios/GuardianMonitor/`: background session-expiry extension.
- `test/session_lock_test.dart`: Flutter regression tests.
