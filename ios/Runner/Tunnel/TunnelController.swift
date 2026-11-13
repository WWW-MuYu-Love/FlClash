import Foundation
import NetworkExtension
import UIKit
import os

@MainActor
final class TunnelController {
  private let sharedStateStore: SharedStateStore
  private let managerStore: TunnelManagerStore
  private let coordinator: TunnelCoordinator

  private var tunnelStatusObserver: NSObjectProtocol?
  private var appActiveObserver: NSObjectProtocol?
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "love.muyu.flclash",
    category: "TunnelController"
  )

  init(
    sharedStateStore: SharedStateStore,
    onTunnelStateChanged: @escaping (TunnelTarget) -> Void,
    onConnectionStateChanged: @escaping (String) -> Void,
    onTunnelFailure: @escaping (String) -> Void,
    onExternalStart: @escaping () -> Void,
    onExternalStop: @escaping () -> Void
  ) {
    let networkExtensionIdentifier =
      "\(Bundle.main.bundleIdentifier!).NECore"
    let managerStore = TunnelManagerStore(
      sharedStateStore: sharedStateStore,
      networkExtensionIdentifier: networkExtensionIdentifier,
      localizedDescription: "FlClash"
    )
    self.sharedStateStore = sharedStateStore
    self.managerStore = managerStore
    coordinator = TunnelCoordinator(
      managerStore: managerStore,
      onTunnelStateChanged: onTunnelStateChanged,
      onConnectionStateChanged: onConnectionStateChanged,
      onTunnelFailure: onTunnelFailure,
      onExternalStart: onExternalStart,
      onExternalStop: onExternalStop
    )
  }

  deinit {
    if let tunnelStatusObserver {
      NotificationCenter.default.removeObserver(tunnelStatusObserver)
    }
    if let appActiveObserver {
      NotificationCenter.default.removeObserver(appActiveObserver)
    }
  }

  func startObserving() {
    if tunnelStatusObserver == nil {
      tunnelStatusObserver = NotificationCenter.default.addObserver(
        forName: .NEVPNStatusDidChange,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        Task { @MainActor in
          self?.coordinator.handleTunnelStatusNotification(notification)
        }
      }
    }
    if appActiveObserver == nil {
      appActiveObserver = NotificationCenter.default.addObserver(
        forName: UIApplication.didBecomeActiveNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.coordinator.requestStatusRefresh(notifyExternal: true)
        }
      }
    }
    coordinator.requestStatusRefresh(notifyExternal: false)
  }

  func start() {
    coordinator.submitTunnelRequest(target: .running)
  }

  func publishConnectionState() {
    coordinator.publishConnectionState()
    coordinator.requestStatusRefresh(notifyExternal: false)
  }

  func stop() {
    coordinator.submitTunnelRequest(target: .stopped)
  }

  func toggle() {
    coordinator.toggleTunnelRequest()
  }

  func reloadOnDemandRules() async throws {
    try await coordinator.reloadOnDemandRules()
  }

  func sendProviderMessage(_ data: Data) async throws -> String {
    let manager: NETunnelProviderManager?
    do {
      manager = try await managerStore.loadManager(createIfNeeded: false)
    } catch {
      throw ProviderMessageError(
        code: "network_extension_error",
        message: error.localizedDescription
      )
    }
    guard let manager,
      manager.connection.status.tunnelState == .running,
      let session = manager.connection as? NETunnelProviderSession
    else {
      throw ProviderMessageError(
        code: "network_extension_unavailable",
        message: "network extension is not running"
      )
    }

    return try await withCheckedThrowingContinuation { continuation in
      let gate = ResumeGate()
      let timeout = DispatchWorkItem {
        guard gate.claim() else {
          return
        }
        continuation.resume(
          throwing: ProviderMessageError(
            code: "network_extension_timeout",
            message: "network extension did not answer in 30 seconds"
          )
        )
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
      do {
        try session.sendProviderMessage(data) { response in
          Task { @MainActor in
            timeout.cancel()
            guard gate.claim() else {
              return
            }
            guard let response,
              let message = String(data: response, encoding: .utf8)
            else {
              continuation.resume(
                throwing: ProviderMessageError(
                  code: "empty_response",
                  message: "empty network extension response"
                )
              )
              return
            }
            continuation.resume(returning: message)
          }
        }
      } catch {
        timeout.cancel()
        guard gate.claim() else {
          return
        }
        continuation.resume(
          throwing: ProviderMessageError(
            code: "network_extension_error",
            message: error.localizedDescription
          )
        )
      }
    }
  }

  func getRunTime() async -> Int {
    do {
      let manager = try await managerStore.loadManager(createIfNeeded: false)
      guard manager?.connection.status.tunnelState == .running else {
        return 0
      }
      let stored = sharedStateStore.runTime()
      if stored > 0 {
        return stored
      }
      if let connectedDate = manager?.connection.connectedDate {
        return Int(connectedDate.timeIntervalSince1970 * 1000)
      }
      return 0
    } catch {
      log("getRunTime failed: \(error.localizedDescription)")
      return 0
    }
  }

  private func log(_ message: String) {
    logger.debug("\(message, privacy: .public)")
  }
}
