# Verification — 10 September 2026

## Automated checks

- `flutter analyze --no-pub`: no issues found.
- `flutter test --no-pub`: all 17 regression tests passed.
- `flutter build apk --debug --no-pub`: universal Android APK built successfully.
- `flutter build apk --debug --no-pub --split-per-abi`: ARM, ARM64 and x86_64 APKs built successfully.
- Xcode project structure parsed successfully: Runner includes the three native bridge/storage sources and depends on and embeds GuardianMonitor. All object references resolved.

## Android device checks

Tested on a temporary, read-only Android 16 / API 36 emulator, initially without device owner and then with device owner enabled in that temporary instance. The emulator was closed after verification.

| Check | Result |
|---|---|
| Create and confirm parent PIN, create profile, choose allowed Clock app | Passed |
| Permission gating, native session start, timer and VPN foreground services | Passed |
| Back during the active session | Profile stayed locked |
| Home and Recents without device owner | Accessibility redirected back to Screen Guardian |
| Allowed Clock app versus blocked Settings | Clock opened; Settings redirected back |
| Incorrect parent PIN | Rejected; session stayed locked |
| Task removal without device owner | Native service logged restoration; profile remained active |
| Device-owner session | Android reported `mLockTaskModeState=LOCKED` |
| Device-owner Home/Recents attempts | Did not escape the kiosk; injected Home could show Android's blocked-app screen |
| Allowed Clock app inside kiosk | Opened while lock-task remained `LOCKED` |
| Process death and restoration | New app process restored the profile and native timer |
| Native timer expiry | Time-up screen appeared; kiosk remained locked and Clock was blocked |
| Parent adds 15 minutes after expiry | Deadline updated; Clock reopened inside the kiosk |
| Parent ends session | Native session cleared; timer and VPN services stopped |
| Final kiosk exit after shutdown-order fix | `mLockTaskModeState=NONE`, empty kiosk list, normal Home navigation restored |

For the expiry/restoration check, the test instance's persisted native deadline was shortened to 25 seconds and its process restarted. The real foreground timer then reached that deadline. The production duration limits were unchanged. The final kiosk shutdown-order correction was rebuilt and verified with another start/end cycle.

Two runtime issues were caught and corrected during these checks: a bound Android VPN needed an explicit stop action to close its tunnel, and kiosk shutdown needed to release lock-task mode before clearing allowed packages.

Generated local evidence is in `build/guardian-device-verification.log`, `build/guardian-final-unlock.txt`, `build/guardian-check.png`, and `build/guardian-expired.png`. Build outputs are under `build/app/outputs/flutter-apk/`.

## Limits of this verification

iOS Swift compilation, signing, Device Activity scheduling, and Screen Time behavior require macOS/Xcode and an appropriately entitled physical iOS device; they were not run on this Windows machine. Android OEM behavior, reboot recovery, release distribution/signing, and comprehensive DNS filtering were not exhaustively tested. The browsing and OS force-close limits are documented in [README.md](README.md).
