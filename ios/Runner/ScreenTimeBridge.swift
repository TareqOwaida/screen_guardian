import DeviceActivity
import FamilyControls
import ManagedSettings
import SwiftUI
import UIKit

/// Wraps Apple's Screen Time API (iOS 16+).
///
/// * `FamilyControls`  – authorisation + the system app picker
/// * `ManagedSettings` – shields (blocks) every app except the allowed ones,
///                        enables the built-in adult web filter, prevents app
///                        removal and clock tampering
/// * `DeviceActivity`  – schedules the end of the session so the monitor
///                        extension can lock everything even if this app is
///                        not running
final class ScreenTimeBridge {
  static let shared = ScreenTimeBridge()

  static let storeName = ManagedSettingsStore.Name("guardian")
  static let activityName = DeviceActivityName("guardian.session")

  private let store = ManagedSettingsStore(named: ScreenTimeBridge.storeName)
  private let center = DeviceActivityCenter()

  private var defaults: UserDefaults {
    UserDefaults(suiteName: SessionStore.appGroup) ?? .standard
  }

  private init() {}

  // MARK: - Authorisation

  func authorizationStatus() -> String {
    switch AuthorizationCenter.shared.authorizationStatus {
    case .notDetermined: return "notDetermined"
    case .denied: return "denied"
    case .approved: return "approved"
    @unknown default: return "unavailable"
    }
  }

  func requestAuthorization(completion: @escaping (Bool) -> Void) {
    Task {
      do {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        await MainActor.run { completion(true) }
      } catch {
        NSLog("ScreenTime authorisation failed: \(error)")
        await MainActor.run { completion(false) }
      }
    }
  }

  // MARK: - Allowed-app selection (per profile)

  private func selectionKey(_ profileId: String) -> String { "selection_\(profileId)" }

  func selection(for profileId: String) -> FamilyActivitySelection {
    guard
      let data = defaults.data(forKey: selectionKey(profileId)),
      let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    else { return FamilyActivitySelection() }
    return sel
  }

  func saveSelection(_ selection: FamilyActivitySelection, for profileId: String) {
    if let data = try? JSONEncoder().encode(selection) {
      defaults.set(data, forKey: selectionKey(profileId))
    }
  }

  func presentPicker(profileId: String, from presenter: UIViewController?, completion: @escaping (Int) -> Void) {
    let current = selection(for: profileId)
    guard let presenter else {
      completion(current.applicationTokens.count)
      return
    }
    let view = AllowedAppsPickerView(initial: current) { [weak self] sel in
      self?.saveSelection(sel, for: profileId)
      completion(sel.applicationTokens.count)
    }
    let host = UIHostingController(rootView: view)
    host.modalPresentationStyle = .formSheet
    DispatchQueue.main.async { presenter.present(host, animated: true) }
  }

  // MARK: - Session enforcement

  func startSession(_ state: SessionState) throws {
    guard authorizationStatus() == "approved" else {
      throw NSError(domain: "Guardian", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "A parent must grant Screen Time access first."])
    }
    // Schedule before changing shields; failure preserves existing protection.
    try scheduleEnd(for: state)
    let sel = selection(for: state.profileId)

    // Block everything except the profile's allowed apps.
    store.shield.applicationCategories = .all(except: sel.applicationTokens)
    store.shield.webDomainCategories = nil
    store.shield.applications = nil

    // Content safety + tamper resistance.
    store.webContent.blockedByFilter = .auto()
    store.application.denyAppRemoval = true
    store.application.denyAppInstallation = true
    store.account.lockAccounts = true
    store.dateAndTime.requireAutomaticDateAndTime = true
  }

  func restoreSession() {
    guard let state = SessionStore.shared.load() else { return }
    if state.isExpired { timeUp() }
    SessionStore.shared.restoreTimer()
  }

  /// Called when the timer expires while the app is alive (the monitor
  /// extension does the same when it is not).
  func timeUp() {
    store.shield.applicationCategories = .all()
    store.shield.webDomainCategories = .all()
  }

  func endSession() {
    center.stopMonitoring([ScreenTimeBridge.activityName])
    store.clearAllSettings()
  }

  private func scheduleEnd(for state: SessionState) throws {
    let cal = Calendar.current
    // DateComponents drops fractional seconds. Round up so the monitor does
    // not reject its own callback as preceding the persisted deadline.
    let end = Date(timeIntervalSince1970: state.endsAt.timeIntervalSince1970.rounded(.up))
    // Preserve the original start and exact deadline across resume/extension.
    let schedule = DeviceActivitySchedule(
      intervalStart: cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: state.startedAt),
      intervalEnd: cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: end),
      repeats: false
    )
    try center.startMonitoring(ScreenTimeBridge.activityName, during: schedule)
  }
}

// MARK: - SwiftUI picker host

private struct AllowedAppsPickerView: View {
  @State private var selection: FamilyActivitySelection
  @State private var finished = false
  @Environment(\.dismiss) private var dismiss
  let onDone: (FamilyActivitySelection) -> Void

  init(initial: FamilyActivitySelection, onDone: @escaping (FamilyActivitySelection) -> Void) {
    _selection = State(initialValue: initial)
    self.onDone = onDone
  }

  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        Text("Pick the individual apps this profile may use. Everything else will be shielded during a session.")
          .font(.footnote)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .padding()
        FamilyActivityPicker(selection: $selection)
      }
      .navigationTitle("Allowed apps")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            finish()
            dismiss()
          }
        }
      }
    }
    .onDisappear { finish() }
  }

  private func finish() {
    guard !finished else { return }
    finished = true
    onDone(selection)
  }
}
