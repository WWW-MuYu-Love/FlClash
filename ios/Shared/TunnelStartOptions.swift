import Foundation

/// Forwards the tunnel config through startVPNTunnel options; the extension may be signed without the App Group.
public enum TunnelStartOptions {
  public static let vpnOptionsKey = "vpnOptions"
  public static let setupParamsKey = "setupParams"
  public static let profileKey = "profile"

  /// Reads the current shared state and returns the start options, or nil when the config is not available.
  public static func build(appGroupIdentifier: String) -> [String: NSObject]? {
    guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier),
      let sharedData = userDefaults.data(forKey: "sharedState"),
      let shared = try? JSONSerialization.jsonObject(with: sharedData)
        as? [String: Any],
      let rawOptions = shared["vpnOptions"] as? [String: Any],
      let vpnOptionsData = try? JSONSerialization.data(
        withJSONObject: rawOptions
      ),
      let vpnOptions = String(data: vpnOptionsData, encoding: .utf8)
    else {
      return nil
    }
    var setupParamsData: Data?
    if let data = userDefaults.data(forKey: "setupParams") {
      setupParamsData = data
    } else if let params = shared["setupParams"],
      !(params is NSNull),
      JSONSerialization.isValidJSONObject(params),
      let data = try? JSONSerialization.data(withJSONObject: params)
    {
      setupParamsData = data
    }
    guard let setupParamsData,
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
}
