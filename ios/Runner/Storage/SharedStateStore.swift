import Foundation
import Shared
import WidgetKit

final class SharedStateStore {
  private let sharedStateKey = "sharedState"
  private let setupParamsKey = "setupParams"
  private let sharedStateVersionKey = "sharedStateVersion"
  private let sharedStatePreviousKey = "sharedStatePrevious"
  private let setupParamsPreviousKey = "setupParamsPrevious"
  private let runTimeKey = "runTime"

  // Fresh instance per call site, so the counter is static: two saves in one millisecond must still differ.
  private static let versionLock = NSLock()
  private static var lastVersion = 0

  private func nextVersion() -> Int {
    Self.versionLock.lock()
    defer { Self.versionLock.unlock() }
    let version = max(
      Int(Date().timeIntervalSince1970 * 1000),
      Self.lastVersion + 1
    )
    Self.lastVersion = version
    return version
  }

  private let eventQueueDirectoryName = "core-events"

  let appGroupIdentifier = NEHelper.appGroupIdentifier
  let eventNotificationName = "\(Bundle.main.bundleIdentifier!).NECore.event"

  func activeVpnOptions() -> String? {
    guard
      let data = UserDefaults(suiteName: appGroupIdentifier)?
        .data(forKey: "activeVpnOptions")
    else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  func saveSharedState(_ data: Data) -> Bool {
    guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
      return false
    }
    let previousData = userDefaults.data(forKey: sharedStateKey)
    let previousControlDisplayState = controlDisplayState(from: previousData)
    let previousStatusDisplayState = statusDisplayState(from: previousData)
    // Stamp one version into both payloads so readers can spot a torn write.
    var stampedData = data
    if var json = try? JSONSerialization.jsonObject(with: data)
      as? [String: Any]
    {
      let version = nextVersion()
      json[sharedStateVersionKey] = version
      if var setupParams = json[setupParamsKey] as? [String: Any] {
        setupParams[sharedStateVersionKey] = version
        json[setupParamsKey] = setupParams
      }
      if let stamped = try? JSONSerialization.data(withJSONObject: json) {
        stampedData = stamped
      }
    }
    if let previousData {
      userDefaults.set(previousData, forKey: sharedStatePreviousKey)
      if let previousSetupParams = userDefaults.data(forKey: setupParamsKey)
      {
        userDefaults.set(
          previousSetupParams,
          forKey: setupParamsPreviousKey
        )
      }
    }
    if let json = try? JSONSerialization.jsonObject(with: stampedData)
      as? [String: Any],
      let setupParams = json[setupParamsKey],
      !(setupParams is NSNull),
      JSONSerialization.isValidJSONObject(setupParams),
      let setupData = try? JSONSerialization.data(withJSONObject: setupParams)
    {
      userDefaults.set(setupData, forKey: setupParamsKey)
    }
    userDefaults.set(stampedData, forKey: sharedStateKey)
    userDefaults.synchronize()
    if previousControlDisplayState != controlDisplayState(from: stampedData),
      #available(iOS 18.0, *)
    {
      ControlCenter.shared.reloadControls(
        ofKind: "\(Bundle.main.bundleIdentifier!).Widget"
      )
    }
    if previousStatusDisplayState != statusDisplayState(from: stampedData) {
      WidgetCenter.shared.reloadTimelines(
        ofKind: "\(Bundle.main.bundleIdentifier!).Widget.Status"
      )
    }
    return true
  }

  private func sharedStateJSON(from data: Data?) -> [String: Any]? {
    guard let data else {
      return nil
    }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  }

  private func statusDisplayState(from data: Data?) -> NSDictionary {
    let json = sharedStateJSON(from: data)
    return [
      "currentProfileName": json?["currentProfileName"] ?? NSNull(),
      "widgetTheme": json?["widgetTheme"] ?? NSNull(),
    ]
  }

  private func controlDisplayState(
    from data: Data?
  ) -> (showProfileName: Bool, profileName: String?) {
    guard let json = sharedStateJSON(from: data) else {
      return (true, nil)
    }
    let showProfileName = json["showQuickSettingsProfileName"] as? Bool ?? true
    return (
      showProfileName,
      showProfileName ? json["currentProfileName"] as? String : nil
    )
  }

  func loadTunnelConfiguration() -> TunnelConfiguration {
    guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier),
      let data = userDefaults.data(forKey: sharedStateKey),
      let sharedState = try? JSONDecoder().decode(
        SharedStatePayload.self,
        from: data
      )
    else {
      return TunnelConfiguration()
    }
    return TunnelConfiguration(
      options: sharedState.vpnOptions?.networkExtensionOptions ?? NetworkExtensionOptions(),
      excludeSSIDs: sharedState.excludeSSIDs ?? [],
      alwaysOn: sharedState.alwaysOn ?? false
    )
  }

  func appGroupDirectory() -> URL? {
    AppGroupResolver.resolveAppGroupDirectory(
      bundleIdentifier: Bundle.main.bundleIdentifier!
    )
  }

  func eventQueueDirectory() -> URL? {
    appGroupDirectory()?.appendingPathComponent(
      eventQueueDirectoryName,
      isDirectory: true
    )
  }

  func runTime() -> Int {
    UserDefaults(suiteName: appGroupIdentifier)?
      .integer(forKey: runTimeKey) ?? 0
  }

  func tunnelLastError() -> String? {
    UserDefaults(suiteName: appGroupIdentifier)?
      .string(forKey: "tunnelLastError")
  }

  func clearTunnelLastError() {
    UserDefaults(suiteName: appGroupIdentifier)?
      .removeObject(forKey: "tunnelLastError")
  }

  func clearTunnelStage() {
    UserDefaults(suiteName: appGroupIdentifier)?
      .removeObject(forKey: "tunnelStage")
  }

  func tunnelStage() -> String? {
    UserDefaults(suiteName: appGroupIdentifier)?
      .string(forKey: "tunnelStage")
  }
}

struct TunnelConfiguration {
  let options: NetworkExtensionOptions
  let excludeSSIDs: [String]
  let alwaysOn: Bool

  init(
    options: NetworkExtensionOptions = NetworkExtensionOptions(),
    excludeSSIDs: [String] = [],
    alwaysOn: Bool = false
  ) {
    self.options = options
    self.excludeSSIDs = excludeSSIDs
    self.alwaysOn = alwaysOn
  }
}

struct NetworkExtensionOptions {
  var includeAllNetworks = false
  var excludeLocalNetworks = true
  var excludeAPNs = true
  var excludeCellularServices = true
  var enforceRoutes = false
  var excludeDeviceCommunication = true
}

private struct SharedStatePayload: Decodable {
  let vpnOptions: VpnOptionsPayload?
  let excludeSSIDs: [String]?
  let alwaysOn: Bool?
}

private struct VpnOptionsPayload: Decodable {
  let includeAllNetworks: Bool?
  let excludeLocalNetworks: Bool?
  let excludeAPNs: Bool?
  let excludeCellularServices: Bool?
  let enforceRoutes: Bool?
  let excludeDeviceCommunication: Bool?

  var networkExtensionOptions: NetworkExtensionOptions {
    NetworkExtensionOptions(
      includeAllNetworks: includeAllNetworks ?? false,
      excludeLocalNetworks: excludeLocalNetworks ?? true,
      excludeAPNs: excludeAPNs ?? true,
      excludeCellularServices: excludeCellularServices ?? true,
      enforceRoutes: enforceRoutes ?? false,
      excludeDeviceCommunication: excludeDeviceCommunication ?? true
    )
  }
}
