import Foundation

enum PacketTunnelEnvironment {
  static let extensionBundleIdentifier = Bundle.main.bundleIdentifier!
  static let baseBundleIdentifier = String(
    extensionBundleIdentifier.dropLast(".NECore".count)
  )
  static let appGroupIdentifier = "group.\(baseBundleIdentifier)"
  static let widgetIdentifier = "\(baseBundleIdentifier).Widget"
  static let eventNotificationName =
    "\(extensionBundleIdentifier).event"
}

final class PacketTunnelSharedStateStore {
  private static let emptySetupParams = Data("{}".utf8)

  private let sharedStateKey = "sharedState"
  private let setupParamsKey = "setupParams"
  private let runTimeKey = "runTime"
  private let activeVpnOptionsKey = "activeVpnOptions"
  private let lastErrorKey = "tunnelLastError"

  // The app reads this when a start fails: the extension's own log is not
  // visible to the app, so the failure reason crosses over through the
  // shared defaults instead.
  func saveLastError(_ message: String) {
    userDefaults?.set(message, forKey: lastErrorKey)
    userDefaults?.synchronize()
  }

  func loadLastError() -> String? {
    userDefaults?.string(forKey: lastErrorKey)
  }

  func clearLastError() {
    userDefaults?.removeObject(forKey: lastErrorKey)
  }

  func loadVPNOptionsSnapshot() -> (options: PacketTunnelVPNOptions, data: Data)? {
    guard let sharedData = userDefaults?.data(forKey: sharedStateKey),
      let shared = try? JSONSerialization.jsonObject(with: sharedData) as? [String: Any],
      let rawOptions = shared["vpnOptions"] as? [String: Any],
      let data = try? JSONSerialization.data(withJSONObject: rawOptions),
      let options = try? JSONDecoder().decode(PacketTunnelVPNOptions.self, from: data)
    else {
      return nil
    }
    return (options, data)
  }

  func loadSetupParams() -> Data {
    guard let userDefaults else {
      return Self.emptySetupParams
    }
    if let data = userDefaults.data(forKey: setupParamsKey) {
      return data
    }
    guard let sharedStateData = userDefaults.data(forKey: sharedStateKey),
      let json = try? JSONSerialization.jsonObject(with: sharedStateData)
        as? [String: Any],
      let setupParams = json[setupParamsKey],
      !(setupParams is NSNull),
      JSONSerialization.isValidJSONObject(setupParams),
      let data = try? JSONSerialization.data(withJSONObject: setupParams)
    else {
      return Self.emptySetupParams
    }
    userDefaults.set(data, forKey: setupParamsKey)
    return data
  }

  func makeInitParams() -> String {
    let homeDirectory = homeDirectory()?.path ?? ""
    return "{\"home-dir\":\"\(homeDirectory)\",\"version\":0}"
  }

  /// The core's home directory: the group container when the extension can reach it, otherwise its own container.
  func homeDirectory() -> URL? {
    let directory: URL?
    if let group = appGroupDirectory() {
      directory = group
    } else {
      directory = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    }
    if let directory {
      try? FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
    }
    return directory
  }

  /// Resolves the tunnel config forwarded through the start options; nil when the options carry no usable config.
  func loadForwardedConfig(
    from options: [String: NSObject]?
  ) -> (
    snapshot: (options: PacketTunnelVPNOptions, data: Data),
    setupParams: Data
  )? {
    guard let options,
      let vpnOptionsString = options[Self.forwardedVpnOptionsKey] as? String,
      let vpnOptionsData = vpnOptionsString.data(using: .utf8),
      let vpnOptions = try? JSONDecoder().decode(
        PacketTunnelVPNOptions.self,
        from: vpnOptionsData
      ),
      let setupParamsString = options[Self.forwardedSetupParamsKey]
        as? String,
      let initialSetupParamsData = setupParamsString.data(using: .utf8)
    else {
      return nil
    }
    var setupParamsData = initialSetupParamsData
    if let profile = options[Self.forwardedProfileKey] as? String {
      guard
        let staged = stageForwardedProfile(
          profile,
          setupParamsData: setupParamsData
        )
      else {
        return nil
      }
      setupParamsData = staged
    }
    return (
      snapshot: (options: vpnOptions, data: vpnOptionsData),
      setupParams: setupParamsData
    )
  }

  private func stageForwardedProfile(
    _ profile: String,
    setupParamsData: Data
  ) -> Data? {
    guard let home = homeDirectory(),
      var setupJson = try? JSONSerialization.jsonObject(
        with: setupParamsData
      ) as? [String: Any],
      var base = setupJson["base"] as? [String: Any],
      base["path"] is String
    else {
      return nil
    }
    let stagedURL = home.appendingPathComponent(
      "tunnel-profile.yaml",
      isDirectory: false
    )
    do {
      try profile.write(to: stagedURL, atomically: true, encoding: .utf8)
    } catch {
      return nil
    }
    base["path"] = stagedURL.path
    setupJson["base"] = base
    return try? JSONSerialization.data(withJSONObject: setupJson)
  }

  // Start-option keys mirror TunnelStartOptions in the Shared module; keep the two in sync.
  private static let forwardedVpnOptionsKey = "vpnOptions"
  private static let forwardedSetupParamsKey = "setupParams"
  private static let forwardedProfileKey = "profile"

  func appGroupDirectory() -> URL? {
    FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier:
        PacketTunnelEnvironment.appGroupIdentifier
    )
  }

  func saveRunTime(vpnOptions: Data) {
    let milliseconds = Int(Date().timeIntervalSince1970 * 1000)
    userDefaults?.set(vpnOptions, forKey: activeVpnOptionsKey)
    userDefaults?.set(milliseconds, forKey: runTimeKey)
  }

  func clearRunTime() {
    userDefaults?.removeObject(forKey: runTimeKey)
    userDefaults?.removeObject(forKey: activeVpnOptionsKey)
  }

  private var userDefaults: UserDefaults? {
    UserDefaults(
      suiteName: PacketTunnelEnvironment.appGroupIdentifier
    )
  }
}

struct PacketTunnelVPNOptions: Decodable {
  let port: Int
  let ipv6: Bool
  // Upstream Dart's VpnOptions serializes this as `dnsHijacking`; the
  // reference fork renamed the field to `captureDns` on both sides, which
  // upstream did not. Decode upstream's key into this property.
  let captureDns: Bool
  let systemProxy: Bool
  let bypassDomain: [String]
  let stack: String
  let mtu: Int
  let routeAddress: [String]
  let disableIcmpForwarding: Bool
  let endpointIndependentNat: Bool
  let congestionController: String
  let recvMsgX: Bool
  let sendMsgX: Bool
  let includeAllNetworks: Bool
  let excludeLocalNetworks: Bool
  let excludeAPNs: Bool
  let excludeCellularServices: Bool
  let enforceRoutes: Bool
  let excludeDeviceCommunication: Bool

  private enum CodingKeys: String, CodingKey {
    case port
    case ipv6
    case dnsHijacking
    case systemProxy
    case bypassDomain
    case stack
    case mtu
    case routeAddress
    case disableIcmpForwarding
    case endpointIndependentNat
    case congestionController
    case recvMsgX
    case sendMsgX
    case includeAllNetworks
    case excludeLocalNetworks
    case excludeAPNs
    case excludeCellularServices
    case enforceRoutes
    case excludeDeviceCommunication
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    port = try container.decode(Int.self, forKey: .port)
    ipv6 = try container.decode(Bool.self, forKey: .ipv6)
    captureDns = try container.decode(Bool.self, forKey: .dnsHijacking)
    systemProxy = try container.decode(Bool.self, forKey: .systemProxy)
    bypassDomain = try container.decodeIfPresent(
      [String].self,
      forKey: .bypassDomain
    ) ?? []
    stack = try container.decode(String.self, forKey: .stack)
    mtu = try container.decodeIfPresent(Int.self, forKey: .mtu) ?? 9000
    routeAddress = try container.decodeIfPresent(
      [String].self,
      forKey: .routeAddress
    ) ?? []
    disableIcmpForwarding = try container.decodeIfPresent(
      Bool.self,
      forKey: .disableIcmpForwarding
    ) ?? false
    endpointIndependentNat = try container.decodeIfPresent(
      Bool.self,
      forKey: .endpointIndependentNat
    ) ?? false
    congestionController = try container.decodeIfPresent(
      String.self,
      forKey: .congestionController
    ) ?? ""
    recvMsgX = try container.decodeIfPresent(Bool.self, forKey: .recvMsgX) ?? true
    sendMsgX = try container.decodeIfPresent(Bool.self, forKey: .sendMsgX) ?? false
    includeAllNetworks = try container.decodeIfPresent(
      Bool.self,
      forKey: .includeAllNetworks
    ) ?? false
    excludeLocalNetworks = try container.decodeIfPresent(
      Bool.self,
      forKey: .excludeLocalNetworks
    ) ?? true
    excludeAPNs = try container.decodeIfPresent(
      Bool.self,
      forKey: .excludeAPNs
    ) ?? true
    excludeCellularServices = try container.decodeIfPresent(
      Bool.self,
      forKey: .excludeCellularServices
    ) ?? true
    enforceRoutes = try container.decodeIfPresent(
      Bool.self,
      forKey: .enforceRoutes
    ) ?? false
    excludeDeviceCommunication = try container.decodeIfPresent(
      Bool.self,
      forKey: .excludeDeviceCommunication
    ) ?? true
  }
}
