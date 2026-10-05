import Foundation

/// Persisted description of the running session. Stored in the shared app
/// group so the DeviceActivity monitor extension can read it too.
struct SessionState: Codable {
  var profileId: String
  var profileName: String
  var startedAt: Date
  var endsAt: Date
  var dnsFilterEnabled: Bool

  var isExpired: Bool { Date() >= endsAt }

  func toMap() -> [String: Any] {
    [
      "active": true,
      "profileId": profileId,
      "profileName": profileName,
      "startedAt": Int(startedAt.timeIntervalSince1970 * 1000),
      "endsAt": Int(endsAt.timeIntervalSince1970 * 1000),
      "expired": isExpired,
    ]
  }
}

final class SessionStore {
  static let shared = SessionStore()

  /// App-group identifier shared with the monitor extension. Must match the
  /// value in Runner.entitlements and the extension's entitlements.
  static let appGroup = "group.com.tareq.screenGuardian"
  private static let key = "active_session"

  var onSessionEnded: (() -> Void)?
  private var timer: Timer?

  private var defaults: UserDefaults {
    UserDefaults(suiteName: SessionStore.appGroup) ?? .standard
  }

  private init() {}

  func load() -> SessionState? {
    guard let data = defaults.data(forKey: SessionStore.key) else { return nil }
    return try? JSONDecoder().decode(SessionState.self, from: data)
  }

  func save(_ state: SessionState) {
    if let data = try? JSONEncoder().encode(state) {
      defaults.set(data, forKey: SessionStore.key)
    }
    scheduleInAppTimer(for: state)
  }

  func extended(byMinutes minutes: Int) -> SessionState? {
    guard var s = load() else { return nil }
    let base = s.isExpired ? Date() : s.endsAt
    s.endsAt = base.addingTimeInterval(TimeInterval(minutes * 60))
    return s
  }

  func restoreTimer() {
    guard let state = load() else { return }
    scheduleInAppTimer(for: state)
  }

  func clear() {
    defaults.removeObject(forKey: SessionStore.key)
    timer?.invalidate()
    timer = nil
  }

  /// Fallback for when the app is alive at the deadline (the DeviceActivity
  /// extension handles the case where it is not).
  private func scheduleInAppTimer(for state: SessionState) {
    timer?.invalidate()
    timer = nil
    guard !state.isExpired else { return }
    let interval = max(0.5, state.endsAt.timeIntervalSinceNow)
    timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
      ScreenTimeBridge.shared.timeUp()
      self?.onSessionEnded?()
    }
  }
}
