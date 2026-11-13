import Foundation

enum PacketTunnelEnvironment {
  static let extensionBundleIdentifier = Bundle.main.bundleIdentifier!
  static let baseBundleIdentifier = String(
    extensionBundleIdentifier.dropLast(".NECore".count)
  )
  static var appGroupIdentifier: String {
    AppGroupResolver.resolveAppGroupIdentifier(
      bundleIdentifier: baseBundleIdentifier
    )
  }
  static let widgetIdentifier = "\(baseBundleIdentifier).Widget"
  static let eventNotificationName =
    "\(extensionBundleIdentifier).event"
}

// Shared keys (App Group suite; Runner and NECore keep separate copies — change both): sharedState,
// setupParams, sharedStateVersion (stamped into both payloads; mismatch = torn write, retried once,
// then previous generation), sharedStatePrevious / setupParamsPrevious, runTime / activeVpnOptions,
// tunnelLastError / tunnelStage (Runner reads these for the start-failure banner). Start options:
// vpnOptions / setupParams / profile (TunnelStartOptions -> loadForwardedConfig).
final class PacketTunnelSharedStateStore {
  private static let emptySetupParams = Data("{}".utf8)

  private let sharedStateKey = "sharedState"
  private let setupParamsKey = "setupParams"
  private let sharedStateVersionKey = "sharedStateVersion"
  private let sharedStatePreviousKey = "sharedStatePrevious"
  private let setupParamsPreviousKey = "setupParamsPrevious"
  private let runTimeKey = "runTime"
  private let activeVpnOptionsKey = "activeVpnOptions"
  private let lastErrorKey = "tunnelLastError"
  private let stageKey = "tunnelStage"

  private var setupParamsValidatedWithSnapshot: Data?

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

  func saveStage(_ stage: String) {
    userDefaults?.set(stage, forKey: stageKey)
    userDefaults?.synchronize()
  }

  func loadVPNOptionsSnapshot() -> (options: PacketTunnelVPNOptions, data: Data)? {
    guard let pair = loadValidatedPair(),
      let rawOptions = pair.shared["vpnOptions"] as? [String: Any],
      let data = try? JSONSerialization.data(withJSONObject: rawOptions)
    else {
      return nil
    }
    do {
      let options = try JSONDecoder().decode(
        PacketTunnelVPNOptions.self,
        from: data
      )
      setupParamsValidatedWithSnapshot = pair.setupParams
      return (options, data)
    } catch {
      saveLastError("VPN 选项解析失败：\(error.localizedDescription)")
      return nil
    }
  }

  func loadSetupParams() -> Data {
    if let setupParamsValidatedWithSnapshot {
      self.setupParamsValidatedWithSnapshot = nil
      return setupParamsValidatedWithSnapshot
    }
    guard let userDefaults else {
      return Self.emptySetupParams
    }
    guard let pair = loadValidatedPair(recordMismatchError: false) else {
      return Self.emptySetupParams
    }
    if userDefaults.data(forKey: setupParamsKey) == nil,
      pair.setupParams != Self.emptySetupParams
    {
      userDefaults.set(pair.setupParams, forKey: setupParamsKey)
    }
    return pair.setupParams
  }

  private struct SharedPair {
    let shared: [String: Any]
    let setupParams: Data
    let sharedVersion: Int?
    let setupParamsVersion: Int?

    var consistent: Bool {
      guard let sharedVersion, let setupParamsVersion else {
        return true
      }
      return sharedVersion == setupParamsVersion
    }
  }

  private func loadValidatedPair(
    recordMismatchError: Bool = true
  ) -> SharedPair? {
    var sawMismatch = false
    // A fresh suite per attempt: the same instance can serve a cached snapshot.
    for _ in 0..<2 {
      guard let userDefaults = self.userDefaults,
        let pair = readPair(from: userDefaults)
      else {
        return nil
      }
      if pair.consistent {
        return pair
      }
      sawMismatch = true
    }
    if let userDefaults = self.userDefaults,
      let pair = readPreviousPair(from: userDefaults), pair.consistent
    {
      return pair
    }
    if sawMismatch, recordMismatchError {
      saveLastError("共享状态版本不一致，已放弃本次启动")
    }
    return nil
  }

  private func readPair(from userDefaults: UserDefaults) -> SharedPair? {
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

  private func readPreviousPair(from userDefaults: UserDefaults) -> SharedPair? {
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

  private func setupParamsData(
    from userDefaults: UserDefaults,
    shared: [String: Any],
    topLevelKey: String,
    embeddedKey: String
  ) -> (data: Data, version: Int?) {
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
    return (Self.emptySetupParams, nil)
  }

  private func version(of json: [String: Any]) -> Int? {
    (json[sharedStateVersionKey] as? NSNumber)?.intValue
  }

  func makeInitParams() -> String {
    let homeDirectory = homeDirectory()?.path ?? ""
    // version stays 0: on iOS both Go uid lookups return -1 (procfs stub in
    // core/platform/ios.go and NECoreResolveUid in NECoreBridge.m).
    let params: [String: Any] = ["home-dir": homeDirectory, "version": 0]
    guard let data = try? JSONSerialization.data(withJSONObject: params),
      let json = String(data: data, encoding: .utf8)
    else {
      return "{\"home-dir\":\"\",\"version\":0}"
    }
    return json
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
      let setupParamsString = options[Self.forwardedSetupParamsKey]
        as? String,
      let initialSetupParamsData = setupParamsString.data(using: .utf8)
    else {
      return nil
    }
    let vpnOptions: PacketTunnelVPNOptions
    do {
      vpnOptions = try JSONDecoder().decode(
        PacketTunnelVPNOptions.self,
        from: vpnOptionsData
      )
    } catch {
      saveLastError("VPN 选项解析失败：\(error.localizedDescription)")
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
    guard let home = homeDirectory() else {
      saveLastError("转发配置失败：无法确定扩展主目录")
      return nil
    }
    guard var setupJson = try? JSONSerialization.jsonObject(
      with: setupParamsData
    ) as? [String: Any],
      var base = setupJson["base"] as? [String: Any]
    else {
      saveLastError("转发配置失败：setupParams 无法解析")
      return nil
    }
    guard base["path"] is String else {
      saveLastError("转发配置失败：setupParams 缺少 base.path")
      return nil
    }
    let stagedURL = home.appendingPathComponent(
      "tunnel-profile.yaml",
      isDirectory: false
    )
    do {
      try profile.write(to: stagedURL, atomically: true, encoding: .utf8)
    } catch {
      saveLastError("转发配置失败：配置写盘失败：\(error.localizedDescription)")
      return nil
    }
    base["path"] = stagedURL.path
    setupJson["base"] = base
    guard let staged = try? JSONSerialization.data(withJSONObject: setupJson)
    else {
      saveLastError("转发配置失败：setupParams 重组失败")
      return nil
    }
    return staged
  }

  // Start-option keys mirror TunnelStartOptions in the Shared module; keep the two in sync.
  private static let forwardedVpnOptionsKey = "vpnOptions"
  private static let forwardedSetupParamsKey = "setupParams"
  private static let forwardedProfileKey = "profile"

  func appGroupDirectory() -> URL? {
    AppGroupResolver.resolveAppGroupDirectory(
      bundleIdentifier: PacketTunnelEnvironment.baseBundleIdentifier
    )
  }

  func saveRunTime(vpnOptions: Data) {
    let milliseconds = Int(Date().timeIntervalSince1970 * 1000)
    userDefaults?.set(vpnOptions, forKey: activeVpnOptionsKey)
    userDefaults?.set(milliseconds, forKey: runTimeKey)
    userDefaults?.synchronize()
  }

  func clearRunTime() {
    userDefaults?.removeObject(forKey: runTimeKey)
    userDefaults?.removeObject(forKey: activeVpnOptionsKey)
    userDefaults?.synchronize()
  }

  // The direct-mode SSIDs and the external-controller secret, synced by the
  // app into the shared state. The extension reads them to switch the core
  // to direct on a direct SSID and restore the previous mode on leaving,
  // without the main app running.
  func loadDirectModeSettings() -> (directSSIDs: [String], controllerSecret: String) {
    guard let pair = loadValidatedPair(recordMismatchError: false) else {
      return ([], "")
    }
    return (
      pair.shared["directSSIDs"] as? [String] ?? [],
      pair.shared["controllerSecret"] as? String ?? ""
    )
  }

  // The direct-mode SSIDs and the external-controller secret, synced by the
  // app into the shared state. The extension reads them to switch the core
  // to direct on a direct SSID and restore the previous mode on leaving,
  // without the main app running.
  func loadDirectModeSettings() -> (directSSIDs: [String], controllerSecret: String) {
    guard let sharedData = userDefaults?.data(forKey: sharedStateKey),
      let shared = try? JSONSerialization.jsonObject(with: sharedData)
        as? [String: Any]
    else {
      return ([], "")
    }
    return (
      shared["directSSIDs"] as? [String] ?? [],
      shared["controllerSecret"] as? String ?? ""
    )
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
    // A missing field falls back to the Dart-side default instead of
    // failing the whole decode: an upstream rename must not break tunnel
    // start with a misleading "缺少 VPN 选项" error.
    port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 7890
    ipv6 = try container.decodeIfPresent(Bool.self, forKey: .ipv6) ?? false
    captureDns = try container.decodeIfPresent(
      Bool.self,
      forKey: .dnsHijacking
    ) ?? false
    systemProxy = try container.decodeIfPresent(
      Bool.self,
      forKey: .systemProxy
    ) ?? true
    bypassDomain = try container.decodeIfPresent(
      [String].self,
      forKey: .bypassDomain
    ) ?? []
    stack = try container.decodeIfPresent(
      String.self,
      forKey: .stack
    ) ?? "mips"
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
