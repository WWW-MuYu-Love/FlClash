import Foundation
import Shared
import WidgetKit

final class SharedStateStore {
  private let sharedStateKey = "sharedState"
  private let setupParamsKey = "setupParams"
  private let runTimeKey = "runTime"

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
    if let json = try? JSONSerialization.jsonObject(with: data)
      as? [String: Any],
      let setupParams = json[setupParamsKey],
      !(setupParams is NSNull),
      JSONSerialization.isValidJSONObject(setupParams),
      let setupData = try? JSONSerialization.data(withJSONObject: setupParams)
    {
      userDefaults.set(setupData, forKey: setupParamsKey)
    }
    userDefaults.set(data, forKey: sharedStateKey)
    userDefaults.synchronize()
    if previousControlDisplayState != controlDisplayState(from: data),
      #available(iOS 18.0, *)
    {
      ControlCenter.shared.reloadControls(
        ofKind: "\(Bundle.main.bundleIdentifier!).Widget"
      )
    }
    if previousStatusDisplayState != statusDisplayState(from: data) {
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
      directSSIDs: sharedState.directSSIDs ?? [],
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

  func tunnelStage() -> String? {
    UserDefaults(suiteName: appGroupIdentifier)?
      .string(forKey: "tunnelStage")
  }
}

struct TunnelConfiguration {
  let options: NetworkExtensionOptions
  let excludeSSIDs: [String]
  let directSSIDs: [String]
  let alwaysOn: Bool

  init(
    options: NetworkExtensionOptions = NetworkExtensionOptions(),
    excludeSSIDs: [String] = [],
    directSSIDs: [String] = [],
    alwaysOn: Bool = false
  ) {
    self.options = options
    self.excludeSSIDs = excludeSSIDs
    self.directSSIDs = directSSIDs
    self.alwaysOn = alwaysOn
  }

  /// SSIDs whose action is disconnect: excluded but not direct. Only these
  /// get an on-demand disconnect rule; a direct SSID must keep the tunnel
  /// up so the extension can switch the core to direct mode.
  var disconnectSSIDs: [String] {
    let direct = Set(directSSIDs)
    return excludeSSIDs.filter { !direct.contains($0) }
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
  let directSSIDs: [String]?
  let controllerSecret: String?
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
