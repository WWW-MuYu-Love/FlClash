import Foundation
import os

private enum AppCoreMethod: String {
  // Raw values are the Dart wire names; anything else silently routes to the tunnel core.
  case coreInit = "core.init"
  case coreInitialized = "core.initialized"
  case coreGc = "core.gc"
  case coreMemory = "core.memory"
  case coreCrash = "core.crash"
  case configValidate = "config.validate"
  case configDecrypt = "config.decrypt"
  case configRead = "config.read"
  case profileBase = "profile.base"
  case profileOutbounds = "profile.outbounds"
  case profileBuild = "profile.build"
  case shareLinkEncode = "shareLink.encode"
  case shareLinkDecode = "shareLink.decode"
  case filterValidate = "filter.validate"
  case proxyValidate = "proxy.validate"
  case proxyConvert = "proxy.convert"
  case ruleSetCompile = "ruleSet.compile"
  case ruleSetDump = "ruleSet.dump"
  case mitmValidate = "mitm.validate"
  case mitmIssueCertificate = "mitm.issueCertificate"
}

private enum ConfigurationCoreMethod: String {
  case setupConfig = "config.setup"
  case updateConfig = "config.update"
}

// The app core must never bind a listener: every listener belongs to the
// extension, so these go there with no app fallback.
private enum ExtensionOnlyMethod: String {
  case listenerStart = "listener.start"
  case listenerStop = "listener.stop"
}

private struct CoreRoutingError: LocalizedError {
  let code: String
  let message: String

  var errorDescription: String? {
    message
  }
}

@MainActor
final class CoreMessageRouter {
  private let tunnelController: TunnelController
  private var currentRoute = CoreRoute.app
  private lazy var notificationCoordinator = CoreNotificationCoordinator(
    sendMessage: { [weak self] data, route in
      guard let self else {
        throw CoreRoutingError(
          code: "core_router_unavailable",
          message: "core router is unavailable"
        )
      }
      return try await self.sendCoreMessage(data, route: route)
    }
  )
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "love.muyu.flclash",
    category: "CoreMessageRouter"
  )

  init(tunnelController: TunnelController) {
    self.tunnelController = tunnelController
  }

  func updateTunnelState(_ state: TunnelTarget) {
    currentRoute = state == .running ? .networkExtension : .app
    notificationCoordinator.setDesiredRoute(currentRoute)
  }

  func invoke(_ data: Data) async -> String {
    let method = methodCallName(data)
    let action = notificationCoordinator.action(for: data)
    await notificationCoordinator.prepare(for: action)
    defer {
      notificationCoordinator.finish(action)
    }

    let selectedRoute = currentRoute
    let networkExtensionActive = selectedRoute == .networkExtension

    do {
      if case .stop(let kind) = action {
        return try await sendNotificationStop(
          data,
          kind: kind,
          defaultRoute: selectedRoute
        )
      }

      let routedResult: (response: String, route: CoreRoute)
      if let method,
        let configurationMethod = ConfigurationCoreMethod(rawValue: method)
      {
        let response = try await sendConfigurationMessage(
          data,
          method: configurationMethod,
          networkExtensionActive: networkExtensionActive
        )
        routedResult = (
          response,
          networkExtensionActive ? .networkExtension : .app
        )
      } else if let method,
        ExtensionOnlyMethod(rawValue: method) != nil
      {
        routedResult = (
          try await sendCoreMessage(data, route: .networkExtension),
          .networkExtension
        )
      } else {
        routedResult = try await sendRoutedCoreMessage(
          data,
          selectedRoute: route(
            method: method,
            defaultRoute: selectedRoute
          )
        )
      }
      if case .start(let kind) = action,
        methodResponseSucceeded(routedResult.response)
      {
        notificationCoordinator.recordSuccessfulStart(
          kind,
          data: data,
          route: routedResult.route
        )
      }
      return routedResult.response
    } catch let error as CoreRoutingError {
      return methodErrorResponse(
        data: data,
        code: error.code,
        message: error.message
      )
    } catch let error as ProviderMessageError {
      return methodErrorResponse(
        data: data,
        code: error.code,
        message: error.message
      )
    } catch {
      return methodErrorResponse(
        data: data,
        code: "core_routing_error",
        message: error.localizedDescription
      )
    }
  }

  func shutdownAppCore() async -> Bool {
    let methodCall = #"{"method":"core.shutdown","arguments":null}"#
    return await withCheckedContinuation { continuation in
      let gate = ResumeGate()
      let timeout = DispatchWorkItem {
        guard gate.claim() else {
          return
        }
        continuation.resume(returning: false)
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeout)
      IOSCoreBridge.invokeMethod(methodCall) { [weak self] response in
        timeout.cancel()
        guard gate.claim() else {
          return
        }
        guard let response,
          let data = response.data(using: .utf8),
          let payload = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any],
          let success = payload["result"] as? Bool
        else {
          self?.log("shutdownAppCore invalid response")
          continuation.resume(returning: false)
          return
        }
        self?.log("shutdownAppCore result=\(success)")
        continuation.resume(returning: success)
      }
    }
  }

  private func sendRoutedCoreMessage(
    _ data: Data,
    selectedRoute: CoreRoute
  ) async throws -> (response: String, route: CoreRoute) {
    do {
      let response = try await sendCoreMessage(data, route: selectedRoute)
      return (response, selectedRoute)
    } catch {
      guard selectedRoute == .networkExtension else {
        throw error
      }
      log(
        "route fallback networkExtension -> app: \(error.localizedDescription)"
      )
      let response = try await sendCoreMessage(data, route: .app)
      return (response, .app)
    }
  }

  private func sendNotificationStop(
    _ data: Data,
    kind: CoreNotificationKind,
    defaultRoute: CoreRoute
  ) async throws -> String {
    let routes = notificationCoordinator.beginStop(
      kind,
      data: data,
      defaultRoute: defaultRoute
    )
    var successfulResponse: String?
    var failedResponse: String?
    var firstError: Error?

    for route in routes {
      do {
        let response = try await sendCoreMessage(data, route: route)
        guard methodResponseSucceeded(response) else {
          if failedResponse == nil {
            failedResponse = response
          }
          continue
        }
        notificationCoordinator.recordSuccessfulStop(
          kind,
          route: route
        )
        if successfulResponse == nil {
          successfulResponse = response
        }
      } catch {
        if firstError == nil {
          firstError = error
        }
      }
    }

    if let failedResponse {
      return failedResponse
    }
    if let firstError {
      throw firstError
    }
    guard let successfulResponse else {
      throw CoreRoutingError(
        code: "notification_stop_failed",
        message: "failed to stop Core notifications"
      )
    }
    return successfulResponse
  }

  private func sendConfigurationMessage(
    _ data: Data,
    method: ConfigurationCoreMethod,
    networkExtensionActive: Bool
  ) async throws -> String {
    var appData = data
    if networkExtensionActive && method == .updateConfig {
      appData = try replacingArgument(
        in: appData,
        key: "external-controller",
        with: ""
      )
      appData = try replacingArgument(
        in: appData,
        key: "geo-auto-update",
        with: false
      )
    }
    if networkExtensionActive && method == .setupConfig {
      // The extension owns geo updates while it routes; the app copy must not run its own.
      appData = try replacingArgument(
        in: appData,
        key: "geo-auto-update",
        with: false
      )
    }

    let appResponse = try await sendCoreMessage(appData, route: .app)
    if isConfigRejected(appResponse) {
      // The app core fell back to its built-in default, so the extension keeps its previous config; say so in the error.
      return appResponseWithForkNote(appResponse)
    }
    guard networkExtensionActive,
      currentRoute == .networkExtension,
      methodResponseSucceeded(appResponse)
    else {
      return appResponse
    }

    var extensionData = data
    if method == .setupConfig {
      extensionData = try replacingArgument(
        in: extensionData,
        key: "skip-dns-listen",
        with: false
      )
      extensionData = try replacingArgument(
        in: extensionData,
        key: "skip-external-controller",
        with: false
      )
    }

    do {
      return try await sendCoreMessage(
        extensionData,
        route: .networkExtension
      )
    } catch let error as ProviderMessageError
      where error.code == "network_extension_unavailable"
    {
      // The extension is not running, so there is nothing to push to. The
      // tunnel start reads the same config from the shared state, so the
      // setup still succeeds instead of aborting the start.
      return appResponse
    } catch {
      throw CoreRoutingError(
        code: "extension_config_failed",
        message:
          "App core applied the config, but the extension core did not receive it: \(error.localizedDescription)"
      )
    }
  }

  private func sendCoreMessage(
    _ data: Data,
    route: CoreRoute
  ) async throws -> String {
    switch route {
    case .app:
      guard let methodCall = String(data: data, encoding: .utf8) else {
        throw CoreRoutingError(
          code: "invalid_method_call",
          message: "invalid method call"
        )
      }
      return try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<String, Error>) in
        let gate = ResumeGate()
        let timeout = DispatchWorkItem {
          guard gate.claim() else {
            return
          }
          continuation.resume(
            throwing: CoreRoutingError(
              code: "core_timeout",
              message: "app core did not answer in 30 seconds"
            )
          )
        }
        DispatchQueue.main.asyncAfter(
          deadline: .now() + 30,
          execute: timeout
        )
        IOSCoreBridge.invokeMethod(methodCall) { value in
          timeout.cancel()
          guard gate.claim() else {
            return
          }
          guard let value else {
            continuation.resume(
              throwing: CoreRoutingError(
                code: "empty_response",
                message: "empty app core response"
              )
            )
            return
          }
          continuation.resume(returning: value)
        }
      }
    case .networkExtension:
      return try await tunnelController.sendProviderMessage(data)
    }
  }

  private func route(
    method: String?,
    defaultRoute: CoreRoute
  ) -> CoreRoute {
    guard let method,
      AppCoreMethod(rawValue: method) != nil
    else {
      return defaultRoute
    }
    return .app
  }

  private func replacingArgument(
    in data: Data,
    key: String,
    with value: Any
  ) throws -> Data {
    guard var object = methodCallObject(data),
      var arguments = object["arguments"] as? [String: Any]
    else {
      throw CoreRoutingError(
        code: "invalid_arguments",
        message: "invalid configuration arguments"
      )
    }
    arguments[key] = value
    object["arguments"] = arguments
    do {
      return try JSONSerialization.data(withJSONObject: object)
    } catch {
      throw CoreRoutingError(
        code: "invalid_arguments",
        message: error.localizedDescription
      )
    }
  }

  private func isConfigRejected(_ response: String) -> Bool {
    guard let data = response.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data)
        as? [String: Any],
      let error = object["error"] as? [String: Any]
    else {
      return false
    }
    return error["code"] as? String == "config_rejected"
  }

  private func appResponseWithForkNote(_ response: String) -> String {
    guard let data = response.data(using: .utf8),
      var object = try? JSONSerialization.jsonObject(with: data)
        as? [String: Any],
      var error = object["error"] as? [String: Any],
      let message = error["message"] as? String
    else {
      return response
    }
    error["message"] =
      "\(message); the extension core keeps its previous config"
    object["error"] = error
    guard let forked = try? JSONSerialization.data(withJSONObject: object),
      let forkedResponse = String(data: forked, encoding: .utf8)
    else {
      return response
    }
    return forkedResponse
  }

  private func methodResponseSucceeded(_ response: String) -> Bool {
    guard let data = response.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data)
        as? [String: Any]
    else {
      return false
    }
    return methodResponseSucceeded(object)
  }

  private func methodResponseSucceeded(
    _ object: [String: Any]
  ) -> Bool {
    object["error"] == nil || object["error"] is NSNull
  }

  private func methodCallObject(_ data: Data) -> [String: Any]? {
    try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  }

  private func methodCallName(_ data: Data) -> String? {
    methodCallObject(data)?["method"] as? String
  }

  private func methodCallID(_ data: Data?) -> String? {
    guard let data,
      let object = methodCallObject(data)
    else {
      return nil
    }
    return object["id"] as? String
  }

  private func methodErrorResponse(
    data: Data?,
    code: String,
    message: String
  ) -> String {
    var payload: [String: Any] = [
      "result": NSNull(),
      "error": [
        "code": code,
        "message": message,
        "details": NSNull(),
      ],
    ]
    if let id = methodCallID(data) {
      payload["id"] = id
    }

    guard let responseData = try? JSONSerialization.data(withJSONObject: payload),
      let response = String(data: responseData, encoding: .utf8)
    else {
      return #"{"result":null,"error":{"code":"serialization_error","message":"failed to serialize method response","details":null}}"#
    }
    return response
  }

  private func log(_ message: String) {
    logger.debug("\(message, privacy: .public)")
  }
}

// A continuation resumed by at most one of the response and the timeout;
// the timeout only stops waiting, never cancels the underlying call.
final class ResumeGate: @unchecked Sendable {
  private let lock = NSLock()
  private var claimed = false

  func claim() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !claimed else {
      return false
    }
    claimed = true
    return true
  }
}
