import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  static let methodChannelName = "com.tareq.screen_guardian/native"
  static let eventChannelName = "com.tareq.screen_guardian/events"

  private var eventSink: FlutterEventSink?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()

    let events = FlutterEventChannel(name: AppDelegate.eventChannelName, binaryMessenger: messenger)
    events.setStreamHandler(self)

    let channel = FlutterMethodChannel(name: AppDelegate.methodChannelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }

    SessionStore.shared.onSessionEnded = { [weak self] in
      self?.eventSink?(["event": "sessionEnded"])
    }
    ScreenTimeBridge.shared.restoreSession()
  }

  // MARK: - Method channel

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    do {
    switch call.method {
    case "getPermissionStatus":
      permissionStatus(result)

    case "requestPermission":
      requestPermission(key: args["key"] as? String ?? "", result: result)

    case "screenTimeStatus":
      result(ScreenTimeBridge.shared.authorizationStatus())

    case "requestScreenTime":
      ScreenTimeBridge.shared.requestAuthorization { ok in result(ok) }

    case "presentAppPicker":
      guard let profileId = args["profileId"] as? String else {
        result(FlutterError(code: "bad_args", message: "profileId missing", details: nil))
        return
      }
      ScreenTimeBridge.shared.presentPicker(profileId: profileId, from: topViewController()) { count in
        result(count)
      }

    case "startSession":
      let minutes = args["durationMinutes"] as? Int ?? 30
      guard SessionStore.shared.load() == nil else {
        result(FlutterError(code: "session_locked", message: "End the current session with the parent PIN first.", details: nil))
        return
      }
      guard (15...240).contains(minutes), let profileId = args["profileId"] as? String, !profileId.isEmpty else {
        result(FlutterError(code: "bad_args", message: "Choose a saved profile and a session between 15 and 240 minutes.", details: nil))
        return
      }
      let now = Date()
      let state = SessionState(
        profileId: profileId,
        profileName: args["profileName"] as? String ?? "",
        startedAt: now,
        endsAt: now.addingTimeInterval(TimeInterval(minutes * 60)),
        dnsFilterEnabled: args["dnsFilterEnabled"] as? Bool ?? false
      )
      SessionStore.shared.save(state)
      do {
        try ScreenTimeBridge.shared.startSession(state)
      } catch {
        SessionStore.shared.clear()
        ScreenTimeBridge.shared.endSession()
        throw error
      }
      if state.dnsFilterEnabled {
        SafeDnsBridge.shared.configure { _ in }
      }
      result(state.toMap())

    case "extendSession":
      let minutes = args["minutes"] as? Int ?? 0
      guard (1...240).contains(minutes), let previous = SessionStore.shared.load(),
            let updated = SessionStore.shared.extended(byMinutes: minutes) else {
        result(FlutterError(code: "bad_args", message: "An active session and a positive extension are required.", details: nil))
        return
      }
      SessionStore.shared.save(updated)
      do {
        try ScreenTimeBridge.shared.startSession(updated)
      } catch {
        SessionStore.shared.save(previous)
        throw error
      }
      result(updated.toMap())

    case "stopSession":
      SessionStore.shared.clear()
      ScreenTimeBridge.shared.endSession()
      result(["active": false])

    case "getSessionState":
      ScreenTimeBridge.shared.restoreSession()
      result(SessionStore.shared.load()?.toMap() ?? ["active": false])

    case "configureSafeDns":
      SafeDnsBridge.shared.configure { enabled in result(enabled) }

    case "removeSafeDns":
      SafeDnsBridge.shared.remove { result(nil) }

    case "getInstalledApps":
      // iOS never exposes the installed app list; the FamilyActivityPicker is used instead.
      result([])

    case "launchApp", "isDeviceOwner":
      result(false)

    default:
      result(FlutterMethodNotImplemented)
    }
    } catch {
      result(FlutterError(code: "native_error", message: error.localizedDescription, details: nil))
    }
  }

  // MARK: - Permissions

  private func permissionStatus(_ result: @escaping FlutterResult) {
    let group = DispatchGroup()
    var dns = false
    var notifications = false

    group.enter()
    SafeDnsBridge.shared.isEnabled { enabled in
      dns = enabled
      group.leave()
    }
    group.enter()
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      notifications = settings.authorizationStatus == .authorized
      group.leave()
    }
    group.notify(queue: .main) {
      result([
        "screenTime": ScreenTimeBridge.shared.authorizationStatus() == "approved",
        "dns": dns,
        "notifications": notifications,
      ])
    }
  }

  private func requestPermission(key: String, result: @escaping FlutterResult) {
    switch key {
    case "screenTime":
      ScreenTimeBridge.shared.requestAuthorization { _ in result(nil) }
    case "dns":
      SafeDnsBridge.shared.configure { _ in
        // The user has to flip the switch in Settings; take them there.
        if let url = URL(string: UIApplication.openSettingsURLString) {
          DispatchQueue.main.async { UIApplication.shared.open(url) }
        }
        result(nil)
      }
    case "notifications":
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
        result(nil)
      }
    default:
      result(FlutterError(code: "unknown_permission", message: key, details: nil))
    }
  }

  // MARK: - Helpers

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}

// MARK: - FlutterStreamHandler

extension AppDelegate: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}
