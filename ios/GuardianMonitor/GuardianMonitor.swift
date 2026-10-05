import DeviceActivity
import ManagedSettings
import Foundation

/// DeviceActivity monitor extension.
///
/// iOS launches this extension in the background when the scheduled session
/// interval ends – even if Screen Guardian itself was killed – so every app can
/// be shielded exactly on time. It uses the same named ManagedSettingsStore as
/// the main app so the main app can clear the shield when a parent unlocks.
///
/// Included in the GuardianMonitor target embedded by Runner. Both targets
/// need the same App Group and Family Controls signing entitlements.
class GuardianMonitor: DeviceActivityMonitor {
  private let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("guardian"))

  override func intervalDidEnd(for activity: DeviceActivityName) {
    super.intervalDidEnd(for: activity)
    // A cancelled/replaced schedule may deliver a late callback. Only lock
    // when the persisted current session is actually expired.
    guard activity == DeviceActivityName("guardian.session"),
          let defaults = UserDefaults(suiteName: "group.com.tareq.screenGuardian"),
          let data = defaults.data(forKey: "active_session"),
          let session = try? JSONDecoder().decode(MonitoredSession.self, from: data),
          Date() >= session.endsAt else { return }
    store.shield.applicationCategories = .all()
    store.shield.webDomainCategories = .all()
  }
}

private struct MonitoredSession: Decodable {
  let endsAt: Date
}
