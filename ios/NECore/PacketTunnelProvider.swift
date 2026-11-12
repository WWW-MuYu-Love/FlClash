import Foundation
import NetworkExtension
import WidgetKit
import os

final class PacketTunnelProvider: NEPacketTunnelProvider {
  private let sharedStateStore = PacketTunnelSharedStateStore()
  private let networkConfiguration = PacketTunnelNetworkConfiguration()
  private lazy var eventQueue = NECoreEventQueue(
    sharedStateStore: sharedStateStore
  )
  private lazy var ssidDirectController = SsidDirectController(
    sharedStateStore: sharedStateStore
  )
  private var cachedManager: NETunnelProviderManager?
  private let logger = Logger(
    subsystem: PacketTunnelEnvironment.extensionBundleIdentifier,
    category: "PacketTunnelProvider"
  )

  private func savedProtocolConfiguration() -> [String: NSObject]? {
    guard
      let proto = self.protocolConfiguration as? NETunnelProviderProtocol,
      let configuration = proto.providerConfiguration
    else {
      return nil
    }
    return configuration.compactMapValues { $0 as? NSObject }
  }

  override func startTunnel(
    options: [String: NSObject]?,
    completionHandler: @escaping (Error?) -> Void
  ) {
    logger.info("startTunnel begin")
    sharedStateStore.clearRunTime()
    sharedStateStore.clearLastError()
    sharedStateStore.saveStage("已启动")
    reloadWidgets()
    let snapshot: (options: PacketTunnelVPNOptions, data: Data)
    let setupParams: Data
    if let forwarded = sharedStateStore.loadForwardedConfig(
      from: options
    ) {
      snapshot = forwarded.snapshot
      setupParams = forwarded.setupParams
    } else if let forwarded = sharedStateStore.loadForwardedConfig(
      from: savedProtocolConfiguration()
    ) {
      sharedStateStore.saveStage("协议配置")
      snapshot = forwarded.snapshot
      setupParams = forwarded.setupParams
    } else if let loaded = sharedStateStore.loadVPNOptionsSnapshot() {
      snapshot = loaded
      setupParams = sharedStateStore.loadSetupParams()
    } else {
      logger.error("startTunnel failed: missing vpn options")
      // A decode failure above already saved the specific reason; only
      // fall back to the generic message when nothing was recorded.
      if sharedStateStore.loadLastError() == nil {
        sharedStateStore.saveLastError("缺少 VPN 配置")
      }
      completionHandler(PacketTunnelProviderError.missingVPNOptions)
      return
    }
    // The entry point cleared the previous error, so any error recorded here means the forwarded config failed and this start fell back to the cached snapshot.
    let stagedStartError = sharedStateStore.loadLastError()
    let vpnOptions = snapshot.options
    logger.info(
      "startTunnel options stack=\(vpnOptions.stack, privacy: .public) ipv6=\(vpnOptions.ipv6, privacy: .public) captureDns=\(vpnOptions.captureDns, privacy: .public) systemProxy=\(vpnOptions.systemProxy, privacy: .public)"
    )

    setTunnelNetworkSettings(
      networkConfiguration.makeSettings(for: vpnOptions)
    ) { error in
      if let error {
        self.logger.error(
          "setTunnelNetworkSettings failed: \(error.localizedDescription, privacy: .public)"
        )
        self.sharedStateStore.saveLastError(error.localizedDescription)
        completionHandler(error)
        return
      }
      self.logger.info("setTunnelNetworkSettings completed")
      self.sharedStateStore.saveStage("网络设置完成")
      guard
        let tunnelFileDescriptor =
          self.networkConfiguration.tunnelFileDescriptor()
      else {
        self.logger.error(
          "startTunnel failed: tunnel file descriptor missing"
        )
        self.sharedStateStore.saveLastError(
          "无法获取隧道文件描述符"
        )
        completionHandler(
          PacketTunnelProviderError.couldNotDetermineFileDescriptor
        )
        return
      }
      self.logger.debug(
        "startTunnel fileDescriptor=\(tunnelFileDescriptor, privacy: .public)"
      )
      self.eventQueue.start()
      let initParams = self.sharedStateStore.makeInitParams()
      self.logger.info(
        "quickSetup initParams=\(initParams, privacy: .public)"
      )
      self.sharedStateStore.saveStage("核心初始化中")
      let startGuard = TunnelStartGuard()
      let watchdog = DispatchWorkItem {
        guard startGuard.claim() else {
          return
        }
        self.sharedStateStore.saveLastError("核心初始化超时")
        completionHandler(PacketTunnelProviderError.couldNotStartCoreTun)
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: watchdog)
      NECoreBridge.quickSetup(
        withInitParams: initParams,
        setupParams: setupParams
      ) { result in
        watchdog.cancel()
        guard startGuard.claim() else {
          return
        }
        if let result,
          !result.isEmpty
        {
          let message = String(data: result, encoding: .utf8) ?? "unknown core error"
          self.logger.error(
            "quickSetup failed: \(message, privacy: .public)"
          )
          self.sharedStateStore.saveLastError(message)
          completionHandler(PacketTunnelProviderError.couldNotStartCoreTun)
          return
        }
        self.logger.info("quickSetup completed")
        self.sharedStateStore.saveStage("核心初始化完成")
        let coreTunOptions = CoreTunOptions(
          stack: vpnOptions.stack,
          address: self.networkConfiguration.tunAddress(for: vpnOptions),
          dns: self.networkConfiguration.tunDNS(for: vpnOptions),
          mtu: vpnOptions.mtu,
          disableIcmpForwarding: vpnOptions.disableIcmpForwarding,
          endpointIndependentNat: vpnOptions.endpointIndependentNat,
          congestionController: vpnOptions.congestionController,
          recvMsgX: vpnOptions.recvMsgX,
          sendMsgX: vpnOptions.sendMsgX
        )
        guard let coreTunOptionsData = try? JSONEncoder().encode(coreTunOptions)
        else {
          self.sharedStateStore.saveLastError("无法启动核心隧道")
          completionHandler(PacketTunnelProviderError.couldNotStartCoreTun)
          return
        }
        let started = NECoreBridge.startTun(
          withFileDescriptor: tunnelFileDescriptor,
          options: coreTunOptionsData
        )
        self.logger.info(
          "NECoreBridge.startTun result=\(started, privacy: .public)"
        )
        self.sharedStateStore.saveStage(
          started ? "隧道启动成功" : "隧道启动失败"
        )
        if started {
          if let stagedStartError {
            self.sharedStateStore.saveStage("转发配置失败，已用缓存配置")
            self.logger.error(
              "startTunnel using cached config after forwarded config failed: \(stagedStartError, privacy: .public)"
            )
          } else {
            self.sharedStateStore.clearLastError()
          }
          self.sharedStateStore.saveRunTime(vpnOptions: snapshot.data)
          // The core (and its 9090 controller) is up, so the SSID watcher
          // can switch the mode to direct on a direct SSID and restore it
          // on leaving, without the main app running.
          self.ssidDirectController.start()
          self.cacheManagerForStop()
        } else {
          self.sharedStateStore.saveLastError("无法启动核心隧道")
        }
        completionHandler(
          started ? nil : PacketTunnelProviderError.couldNotStartCoreTun
        )
      }
    }
  }

  override func stopTunnel(
    with reason: NEProviderStopReason,
    completionHandler: @escaping () -> Void
  ) {
    logger.info("stopTunnel reason=\(reason.rawValue, privacy: .public)")
    sharedStateStore.clearRunTime()
    sharedStateStore.clearLastError()
    sharedStateStore.saveStage("已停止")
    reloadWidgets()
    eventQueue.stop()
    ssidDirectController.stop()
    NECoreBridge.stopTun()
    guard reason == .userInitiated else {
      completionHandler()
      return
    }
    NETunnelProviderManager.loadAllFromPreferences { managers, error in
      if let error {
        self.logger.error(
          "stopTunnel loadAllFromPreferences error=\(error.localizedDescription, privacy: .public)"
        )
        self.disableOnDemandRetrying(completionHandler: completionHandler)
        return
      }
      guard let manager = self.matchingManager(in: managers) else {
        completionHandler()
        return
      }
      self.cachedManager = manager
      self.disableOnDemand(manager: manager, completionHandler: completionHandler)
    }
  }

  private func matchingManager(
    in managers: [NETunnelProviderManager]?
  ) -> NETunnelProviderManager? {
    managers?.first(where: { manager in
      guard
        let proto = manager.protocolConfiguration
          as? NETunnelProviderProtocol
      else {
        return false
      }
      return proto.providerBundleIdentifier == PacketTunnelEnvironment.extensionBundleIdentifier
    })
  }

  private func disableOnDemand(
    manager: NETunnelProviderManager,
    completionHandler: @escaping () -> Void
  ) {
    manager.isOnDemandEnabled = false
    manager.saveToPreferences { error in
      if let error {
        self.logger.error(
          "stopTunnel saveToPreferences error=\(error.localizedDescription, privacy: .public)"
        )
      }
      completionHandler()
    }
  }

  // One fresh retry first: a freshly loaded manager carries the latest rules, while the cached one may predate an in-app save.
  private func disableOnDemandRetrying(
    completionHandler: @escaping () -> Void
  ) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      NETunnelProviderManager.loadAllFromPreferences { managers, _ in
        if let manager = self.matchingManager(in: managers) {
          self.cachedManager = manager
          self.disableOnDemand(
            manager: manager,
            completionHandler: completionHandler
          )
          return
        }
        guard let cachedManager = self.cachedManager else {
          completionHandler()
          return
        }
        self.disableOnDemand(
          manager: cachedManager,
          completionHandler: completionHandler
        )
      }
    }
  }

  private func cacheManagerForStop() {
    NETunnelProviderManager.loadAllFromPreferences { managers, _ in
      if let manager = self.matchingManager(in: managers) {
        self.cachedManager = manager
      }
    }
  }

  override func handleAppMessage(
    _ messageData: Data,
    completionHandler: ((Data?) -> Void)?
  ) {
    logger.debug(
      "handleAppMessage bytes=\(messageData.count, privacy: .public)"
    )
    guard let completionHandler else {
      logger.warning("handleAppMessage ignored: missing completion handler")
      return
    }

    NECoreBridge.invokeMethod(messageData) { response in
      guard let response else {
        self.logger.warning("handleAppMessage empty core response")
        completionHandler(
          self.methodErrorResponse(
            messageData: messageData,
            code: "empty_response",
            message: "empty core response"
          )
        )
        return
      }
      self.logger.debug(
        "handleAppMessage response bytes=\(response.count, privacy: .public)"
      )
      completionHandler(response)
    }
  }

  private func methodErrorResponse(
    messageData: Data,
    code: String,
    message: String
  ) -> Data? {
    var payload: [String: Any] = [
      "result": NSNull(),
      "error": [
        "code": code,
        "message": message,
        "details": NSNull(),
      ],
    ]
    if let id = methodCallID(messageData) {
      payload["id"] = id
    }
    return try? JSONSerialization.data(withJSONObject: payload)
  }

  private func methodCallID(_ messageData: Data) -> String? {
    guard
      let object = try? JSONSerialization.jsonObject(with: messageData)
        as? [String: Any]
    else {
      return nil
    }
    return object["id"] as? String
  }

  private func reloadWidgets() {
    WidgetCenter.shared.reloadAllTimelines()
    if #available(iOS 18.0, *) {
      ControlCenter.shared.reloadControls(
        ofKind: PacketTunnelEnvironment.widgetIdentifier
      )
    }
  }
}

private struct CoreTunOptions: Encodable {
  let stack: String
  let address: String
  let dns: String
  let mtu: Int
  let disableIcmpForwarding: Bool
  let endpointIndependentNat: Bool
  let congestionController: String
  let recvMsgX: Bool
  let sendMsgX: Bool
}

private enum PacketTunnelProviderError: LocalizedError {
  case missingVPNOptions
  case couldNotDetermineFileDescriptor
  case couldNotStartCoreTun

  var errorDescription: String? {
    switch self {
    case .missingVPNOptions:
      return "缺少 VPN 配置"
    case .couldNotDetermineFileDescriptor:
      return "无法获取隧道文件描述符"
    case .couldNotStartCoreTun:
      return "无法启动核心隧道"
    }
  }
}

// startTunnel's completion handler runs exactly once: the quickSetup callback and the watchdog race to claim it.
private final class TunnelStartGuard: @unchecked Sendable {
  private let lock = NSLock()
  private var done = false

  func claim() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !done else {
      return false
    }
    done = true
    return true
  }
}
