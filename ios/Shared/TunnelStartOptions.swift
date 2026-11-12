import Foundation

/// Forwards the tunnel config through startVPNTunnel options; the extension may be signed without the App Group.
public enum TunnelStartOptions {
  public static let vpnOptionsKey = "vpnOptions"
  public static let setupParamsKey = "setupParams"
  public static let profileKey = "profile"

  // Full shared-key table: the header comment on PacketTunnelSharedStateStore.
  private static let sharedStateKey = "sharedState"
  private static let sharedStateVersionKey = "sharedStateVersion"
  private static let sharedStatePreviousKey = "sharedStatePrevious"
  private static let setupParamsPreviousKey = "setupParamsPrevious"

  /// Reads the current shared state and returns the start options, or nil when the config is not available.
  public static func build(appGroupIdentifier: String) -> [String: NSObject]? {
    guard UserDefaults(suiteName: appGroupIdentifier) != nil,
      let pair = loadValidatedPair(appGroupIdentifier: appGroupIdentifier),
      let rawOptions = pair.shared["vpnOptions"] as? [String: Any],
      let vpnOptionsData = try? JSONSerialization.data(
        withJSONObject: rawOptions
      ),
      let vpnOptions = String(data: vpnOptionsData, encoding: .utf8),
      let setupParamsData = pair.setupParams,
      let setupParams = String(data: setupParamsData, encoding: .utf8)
    else {
      return nil
    }
    var options: [String: NSObject] = [
      vpnOptionsKey: vpnOptions as NSString,
      setupParamsKey: setupParams as NSString,
    ]
    if let setupJson = try? JSONSerialization.jsonObject(
      with: setupParamsData
    ) as? [String: Any],
      let base = setupJson["base"] as? [String: Any]
    {
      // Unreadable profile: fall back to the group instead of starting with an incomplete config.
      guard let path = base["path"] as? String,
        let profile = try? String(contentsOfFile: path, encoding: .utf8),
        !profile.isEmpty
      else {
        return nil
      }
      options[profileKey] = profile as NSString
    }
    return options
  }

  private struct SharedPair {
    let shared: [String: Any]
    let setupParams: Data?
    let sharedVersion: Int?
    let setupParamsVersion: Int?

    var consistent: Bool {
      guard let sharedVersion, let setupParamsVersion else {
        return true
      }
      return sharedVersion == setupParamsVersion
    }
  }

  private static func loadValidatedPair(
    appGroupIdentifier: String
  ) -> SharedPair? {
    // Fresh suite per attempt, so the retry re-reads from the daemon
    // instead of the same instance's cached snapshot.
    for _ in 0..<2 {
      guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier),
        let pair = readPair(from: userDefaults)
      else {
        return nil
      }
      if pair.consistent {
        return pair
      }
    }
    guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier),
      let pair = readPreviousPair(from: userDefaults), pair.consistent
    else {
      return nil
    }
    return pair
  }

  private static func readPair(
    from userDefaults: UserDefaults
  ) -> SharedPair? {
    guard let sharedData = userDefaults.data(forKey: sharedStateKey),
      let shared = try? JSONSerialization.jsonObject(with: sharedData)
        as? [String: Any]
    else {
      return nil
    }
    let setupParams = setupParamsData(
      from: userDefaults,
      shared: shared,
      topLevelKey: setupParamsKey,
      embeddedKey: setupParamsKey
    )
    return SharedPair(
      shared: shared,
      setupParams: setupParams.data,
      sharedVersion: version(of: shared),
      setupParamsVersion: setupParams.version
    )
  }

  private static func readPreviousPair(
    from userDefaults: UserDefaults
  ) -> SharedPair? {
    guard let sharedData = userDefaults.data(forKey: sharedStatePreviousKey),
      let shared = try? JSONSerialization.jsonObject(with: sharedData)
        as? [String: Any]
    else {
      return nil
    }
    let setupParams = setupParamsData(
      from: userDefaults,
      shared: shared,
      topLevelKey: setupParamsPreviousKey,
      embeddedKey: setupParamsKey
    )
    return SharedPair(
      shared: shared,
      setupParams: setupParams.data,
      sharedVersion: version(of: shared),
      setupParamsVersion: setupParams.version
    )
  }

  private static func setupParamsData(
    from userDefaults: UserDefaults,
    shared: [String: Any],
    topLevelKey: String,
    embeddedKey: String
  ) -> (data: Data?, version: Int?) {
    if let data = userDefaults.data(forKey: topLevelKey) {
      var version: Int?
      if let json = try? JSONSerialization.jsonObject(with: data)
        as? [String: Any]
      {
        version = self.version(of: json)
      }
      return (data, version)
    }
    if let params = shared[embeddedKey],
      !(params is NSNull),
      JSONSerialization.isValidJSONObject(params),
      let data = try? JSONSerialization.data(withJSONObject: params),
      let json = try? JSONSerialization.jsonObject(with: data)
        as? [String: Any]
    {
      return (data, version(of: json))
    }
    return (nil, nil)
  }

  private static func version(of json: [String: Any]) -> Int? {
    (json[sharedStateVersionKey] as? NSNumber)?.intValue
  }
}
