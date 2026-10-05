import Foundation
import NetworkExtension

/// Installs a system-wide encrypted DNS configuration that points at a
/// family-safe resolver (Cloudflare for Families – blocks malware, phishing
/// and adult content). iOS does not allow third-party apps to intercept DNS
/// the way Android does, so the OS-level DNS settings profile is the supported
/// route. After `configure` the user must enable the profile once in
/// Settings ▸ General ▸ VPN, DNS & Device Management ▸ DNS.
///
/// Requires the `com.apple.developer.networking.networkextension` entitlement
/// with the `dns-settings` value (see Runner.entitlements).
final class SafeDnsBridge {
  static let shared = SafeDnsBridge()

  private let manager = NEDNSSettingsManager.shared()
  private init() {}

  func configure(completion: @escaping (Bool) -> Void) {
    manager.loadFromPreferences { [manager] loadError in
      if let loadError {
        NSLog("DNS load failed: \(loadError)")
      }
      let settings = NEDNSOverHTTPSSettings(servers: ["1.1.1.3", "1.0.0.3"])
      settings.serverURL = URL(string: "https://family.cloudflare-dns.com/dns-query")
      manager.dnsSettings = settings
      manager.localizedDescription = "Screen Guardian Safe DNS"
      manager.saveToPreferences { saveError in
        if let saveError {
          NSLog("DNS save failed: \(saveError)")
          completion(false)
          return
        }
        completion(manager.isEnabled)
      }
    }
  }

  func isEnabled(completion: @escaping (Bool) -> Void) {
    manager.loadFromPreferences { [manager] error in
      completion(error == nil && manager.dnsSettings != nil && manager.isEnabled)
    }
  }

  func remove(completion: @escaping () -> Void) {
    manager.loadFromPreferences { [manager] _ in
      manager.removeFromPreferences { _ in completion() }
    }
  }
}
