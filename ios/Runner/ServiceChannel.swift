import Flutter
import Foundation
import Security
import Shared
import UIKit
import os

@MainActor
private final class CoreMessageRouterReference {
  weak var value: CoreMessageRouter?
}

enum QuickAction: String {
  case start
  case stop
  case toggle

  // Before the engine is up only the latest intent survives: a toggle flips a pending start or
  // stop, and two toggles cancel out.
  func folded(onto pending: QuickAction?) -> QuickAction? {
    guard self == .toggle, let pending else {
      return self
    }
    switch pending {
    case .start:
      return .stop
    case .stop:
      return .start
    case .toggle:
      return nil
    }
  }
}

@MainActor
final class ServiceChannel {
  private static var instance: ServiceChannel?
  private static var pendingQuickAction: QuickAction?

  private static let packageName = "com.follow.clash"
  private let channel: FlutterMethodChannel
  private let coreChannel: FlutterMethodChannel
  private let tileChannel: FlutterMethodChannel
  private let sharedStateStore: SharedStateStore
  private let tunnelController: TunnelController
  private let coreMessageRouter: CoreMessageRouter
  private let coreEventRelay: CoreEventRelay
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "love.muyu.flclash",
    category: "ServiceChannel"
  )

  static func register(with messenger: FlutterBinaryMessenger) {
    let serviceChannel = ServiceChannel(messenger: messenger)
    instance = serviceChannel
    guard let action = pendingQuickAction else {
      return
    }
    pendingQuickAction = nil
    serviceChannel.perform(action)
  }

  static func request(_ action: QuickAction) {
    guard let instance else {
      pendingQuickAction = action.folded(onto: pendingQuickAction)
      return
    }
    instance.perform(action)
  }

  private func perform(_ action: QuickAction) {
    switch action {
    case .start:
      tunnelController.start()
    case .stop:
      tunnelController.stop()
    case .toggle:
      tunnelController.toggle()
    }
  }

  private init(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "\(Self.packageName)/service",
      binaryMessenger: messenger
    )
    let coreChannel = FlutterMethodChannel(
      name: "\(Self.packageName)/core",
      binaryMessenger: messenger
    )
    let tileChannel = FlutterMethodChannel(
      name: "\(Self.packageName)/tile",
      binaryMessenger: messenger
    )
    let sharedStateStore = SharedStateStore()
    let routerReference = CoreMessageRouterReference()
    let tunnelController = TunnelController(
      sharedStateStore: sharedStateStore,
      onTunnelStateChanged: { state in
        routerReference.value?.updateTunnelState(state)
      },
      onConnectionStateChanged: { state in
        channel.invokeMethod("tunnelState", arguments: state)
      },
      onTunnelFailure: { message in
        channel.invokeMethod("tunnelError", arguments: message)
      },
      onTunnelDiagnostics: { details in
        channel.invokeMethod("tunnelDiagnostics", arguments: details)
      },
      onExternalStart: {
        tileChannel.invokeMethod("syncRunningState", arguments: [
          "running": true,
          "startTime": sharedStateStore.runTime(),
        ])
      },
      onExternalStop: {
        tileChannel.invokeMethod("syncRunningState", arguments: [
          "running": false,
          "startTime": 0,
        ])
      }
    )
    let coreMessageRouter = CoreMessageRouter(
      tunnelController: tunnelController
    )
    routerReference.value = coreMessageRouter
    let coreEventRelay = CoreEventRelay(
      sharedStateStore: sharedStateStore,
      sendEvent: { event, completion in
        // Upstream Dart decodes the event from bytes, not a String.
        guard let data = event.data(using: .utf8) else {
          completion(false)
          return
        }
        channel.invokeMethod("event", arguments: data) { callbackResult in
          completion(callbackResult == nil)
        }
      }
    )

    self.channel = channel
    self.coreChannel = coreChannel
    self.tileChannel = tileChannel
    self.sharedStateStore = sharedStateStore
    self.tunnelController = tunnelController
    self.coreMessageRouter = coreMessageRouter
    self.coreEventRelay = coreEventRelay

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.handle(call, result: result)
    }
    coreChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.handleCore(call, result: result)
    }
    coreEventRelay.start()
    tunnelController.startObserving()
  }

  // Upstream Dart sends core method calls on a separate `<package>/core`
  // channel and expects the reply as bytes; the reference fork folded them
  // into the service channel with a String reply.
  private func handleCore(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard call.method == "invokeMethod",
      let data = methodCallData(call)
    else {
      result(FlutterMethodNotImplemented)
      return
    }
    Task {
      let response = await coreMessageRouter.invoke(data)
      guard let bytes = response.data(using: .utf8) else {
        result(
          FlutterError(
            code: "CORE_ERROR",
            message: "Core response was not UTF-8",
            details: nil
          )
        )
        return
      }
      result(bytes)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    log("handle method=\(call.method)")
    switch call.method {
    case "invokeMethod":
      guard let data = methodCallData(call) else {
        result(invalidMethodCallResponse)
        return
      }
      Task {
        result(await coreMessageRouter.invoke(data))
      }
    case "start":
      // Upstream Dart sends the command revision (Int) here; the shared
      // state was already synced by syncState before start. Save a state
      // payload when one is sent, but never refuse the start for it.
      if let data = methodCallData(call) {
        _ = sharedStateStore.saveSharedState(data)
      }
      tunnelController.start()
      result(true)
    case "stop":
      tunnelController.stop()
      result(true)
    case "init":
      tunnelController.publishConnectionState()
      coreEventRelay.drainEventQueue()
      result("")
    case "syncState":
      syncState(call, result: result)
    case "shutdown":
      Task {
        result(await coreMessageRouter.shutdownAppCore())
      }
    case "getRunTime":
      Task {
        result(await tunnelController.getRunTime())
      }
    case "getProfileAppGroups":
      result(AppGroupResolver.profileAppGroups())
    case "getActiveVpnOptions":
      Task {
        let running = await tunnelController.getRunTime() > 0
        result(running ? sharedStateStore.activeVpnOptions() : nil)
      }
    case "setBackgroundKeepAlive":
      // Dart sends the mode name: "off", "silentAudio", "pictureInPicture".
      // Unknown values stop the keepalive.
      if let mode = call.arguments as? String {
        BackgroundKeepAlive.shared.setMode(mode)
        result(true)
      } else {
        result(false)
      }
    case "checkMitmCertificateTrust":
      checkMitmCertificateTrust(call, result: result)
    case "shareMitmCertificate":
      shareMitmCertificate(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // The leaf issued for the check host only validates against the system
  // trust store when the CA is installed and fully trusted. Evaluation can
  // consult revocation, so it runs off the main thread.
  private func checkMitmCertificateTrust(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard let args = call.arguments as? [String: Any],
      let leafPem = args["leafPem"] as? String,
      let caPem = args["caPem"] as? String,
      let host = args["host"] as? String,
      let leaf = Self.certificate(fromPem: leafPem),
      let ca = Self.certificate(fromPem: caPem)
    else {
      result("notInstalled")
      return
    }
    Task.detached {
      let policy = SecPolicyCreateSSL(true, host as CFString)
      var trust: SecTrust?
      guard SecTrustCreateWithCertificates(leaf, policy, &trust) == errSecSuccess,
        let trust
      else {
        result("notInstalled")
        return
      }
      var error: CFError?
      if SecTrustEvaluateWithError(trust, &error) {
        result("ready")
        return
      }
      result(Self.caCertificateInstalled(ca) ? "untrusted" : "notInstalled")
    }
  }

  private static func certificate(fromPem pem: String) -> SecCertificate? {
    let base64 = pem
      .components(separatedBy: .newlines)
      .filter { !$0.isEmpty && !$0.hasPrefix("-----") }
      .joined()
    guard let der = Data(base64Encoded: base64) else { return nil }
    return SecCertificateCreateWithData(nil, der as CFData)
  }

  // Best effort: the keychain may not expose installed certificates to the
  // app, in which case an installed-but-untrusted CA reads as not installed.
  private static func caCertificateInstalled(_ ca: SecCertificate) -> Bool {
    guard let caData = SecCertificateCopyData(ca) as Data? else {
      return false
    }
    let query: [String: Any] = [
      kSecClass as String: kSecClassCertificate,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitAll,
    ]
    var items: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess,
      let dataList = items as? [Data]
    else {
      return false
    }
    return dataList.contains(caData)
  }

  // Presents the share sheet with the CA file so the user can save it to
  // Files and install it from there.
  private func shareMitmCertificate(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard let args = call.arguments as? [String: Any],
      let pem = args["pem"] as? String,
      let fileName = args["fileName"] as? String,
      let rootViewController = topViewController()
    else {
      result(false)
      return
    }
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(fileName)
    do {
      try pem.write(to: tempURL, atomically: true, encoding: .utf8)
    } catch {
      result(false)
      return
    }
    let activity = UIActivityViewController(
      activityItems: [tempURL],
      applicationActivities: nil
    )
    if let popover = activity.popoverPresentationController {
      popover.sourceView = rootViewController.view
      popover.sourceRect = CGRect(
        x: rootViewController.view.bounds.midX,
        y: rootViewController.view.bounds.midY,
        width: 0,
        height: 0
      )
      popover.permittedArrowDirections = []
    }
    rootViewController.present(activity, animated: true)
    result(true)
  }

  private func topViewController() -> UIViewController? {
    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let window = scene.windows.first(where: { $0.isKeyWindow }),
      var top = window.rootViewController
    else {
      return nil
    }
    while let presented = top.presentedViewController {
      top = presented
    }
    return top
  }

  private func methodCallData(_ call: FlutterMethodCall) -> Data? {
    guard let message = call.arguments as? String else {
      return nil
    }
    return message.data(using: .utf8)
  }

  private func syncState(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard saveSharedState(call) else {
      result("failed to sync shared state")
      return
    }
    result("")
    Task {
      do {
        try await tunnelController.reloadOnDemandRules()
      } catch {
        log("syncState preferences failed: \(error.localizedDescription)")
      }
    }
  }

  private func saveSharedState(_ call: FlutterMethodCall) -> Bool {
    guard let data = methodCallData(call),
      sharedStateStore.saveSharedState(data)
    else {
      log("saveSharedState failed")
      return false
    }
    log("saveSharedState bytes=\(data.count)")
    return true
  }

  private var invalidMethodCallResponse: String {
    #"{"result":null,"error":{"code":"invalid_method_call","message":"invalid method call","details":null}}"#
  }

  private func log(_ message: String) {
    logger.debug("\(message, privacy: .public)")
  }
}
