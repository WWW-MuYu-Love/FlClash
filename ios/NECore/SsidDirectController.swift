import Foundation
import Network
import NetworkExtension
import os

/// Switches the extension core to direct mode while the phone is on an
/// excluded SSID whose action is direct, and restores the previous mode when
/// it leaves, without the main app running.
///
/// The main app cannot do this: it is killed in the background, so nobody
/// would watch the SSID. The extension is the process that stays alive while
/// the VPN is up, so it watches the network itself (NWPathMonitor plus
/// NEHotspotNetwork) and talks to its own core through the 9090 external
/// controller, the same PATCH /configs the app uses. The disconnect SSIDs do
/// not reach here: the system disconnects the VPN on those through the
/// on-demand rules, so the tunnel (and this controller) is gone while on one.
final class SsidDirectController {
  private static let requestTimeout: TimeInterval = 4
  private static let maxAttempts = 3
  private static let maxPendingRetries = 5

  private let sharedStateStore: PacketTunnelSharedStateStore
  private let logger = Logger(
    subsystem: PacketTunnelEnvironment.extensionBundleIdentifier,
    category: "SsidDirectController"
  )
  private let session: URLSession

  private let queue = DispatchQueue(label: "love.muyu.flclash.ssid-direct")
  private var monitor: NWPathMonitor?
  private var running = false

  /// The mode to restore when the phone leaves a direct SSID, nil while no
  /// direct override is active. Only cleared once the restore is issued
  /// or the user takes the mode over; a failed 9090 call never drops it.
  private var restoreMode: String?
  private var currentSsid: String?
  /// A direct SSID entered whose switch to direct is not confirmed yet.
  private var pendingEnterSsid: String?
  /// The mode recorded before an unconfirmed switch, moved into
  /// restoreMode once the switch is confirmed to have landed.
  private var pendingRestoreMode: String?
  private var pendingRetryWorkItem: DispatchWorkItem?
  private var pendingRetryCount = 0
  private var pendingRetryExhausted = false

  init(sharedStateStore: PacketTunnelSharedStateStore) {
    self.sharedStateStore = sharedStateStore
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = Self.requestTimeout
    self.session = URLSession(configuration: configuration)
  }

  func start() {
    queue.async { [weak self] in
      guard let self, !self.running else { return }
      self.running = true
      let monitor = NWPathMonitor()
      self.monitor = monitor
      monitor.pathUpdateHandler = { [weak self] _ in
        self?.refreshSsid()
      }
      monitor.start(queue: self.queue)
      self.refreshSsid()
      self.logger.info("ssid direct monitor started")
    }
  }

  func stop() {
    queue.async { [weak self] in
      guard let self, self.running else { return }
      self.running = false
      self.monitor?.cancel()
      self.monitor = nil
      self.restoreMode = nil
      self.currentSsid = nil
      self.pendingEnterSsid = nil
      self.pendingRestoreMode = nil
      self.resetPendingRetry()
      self.logger.info("ssid direct monitor stopped")
    }
  }

  private func refreshSsid() {
    // A Wi-Fi to Wi-Fi switch may not move the path, and the SSID read is
    // asynchronous, so always re-read rather than trusting the last value.
    NEHotspotNetwork.fetchCurrent { [weak self] network in
      guard let self else { return }
      self.queue.async {
        if let ssid = network?.ssid {
          self.apply(ssid: ssid)
          return
        }
        let path = self.monitor?.currentPath
        let onWifi =
          path?.status == .satisfied
          && (path?.usesInterfaceType(.wifi) ?? false)
        if onWifi {
          // On Wi-Fi but the SSID could not be read, likely for lack of
          // location permission: hold the current state, do not restore.
          self.logger.warning(
            "ssid direct: on Wi-Fi but SSID unreadable; holding current mode"
          )
          return
        }
        self.apply(ssid: nil)
      }
    }
  }

  private func apply(ssid: String?) {
    guard running else { return }
    let (directSSIDs, _) = sharedStateStore.loadDirectModeSettings()
    let direct = Set(directSSIDs)
    let previous = currentSsid
    currentSsid = ssid
    if previous == ssid {
      // The SSID did not change, but a switch or restore may still be
      // pending after a failed 9090 call; retry it on the next path update.
      retryPending()
      return
    }
    if let ssid, direct.contains(ssid) {
      enterDirect(ssid: ssid)
      return
    }
    leaveDirect()
  }

  private func retryPending() {
    if let pending = pendingEnterSsid, currentSsid == pending,
      restoreMode == nil
    {
      enterDirect(ssid: pending)
      return
    }
    if restoreMode != nil {
      let (directSSIDs, _) = sharedStateStore.loadDirectModeSettings()
      if let current = currentSsid, Set(directSSIDs).contains(current) {
        return
      }
      leaveDirect()
    }
  }

  private func enterDirect(ssid: String) {
    guard restoreMode == nil else { return }
    pendingEnterSsid = ssid
    fetchMode { [weak self] mode in
      guard let self else { return }
      self.queue.async {
        guard self.running else { return }
        guard let mode else {
          self.schedulePendingRetry()
          return
        }
        guard self.currentSsid == ssid, self.restoreMode == nil,
          self.pendingEnterSsid == ssid
        else {
          if self.currentSsid != ssid {
            self.pendingEnterSsid = nil
          }
          return
        }
        if mode == "direct" {
          // The switch landed on an earlier attempt whose reply was lost.
          if let pending = self.pendingRestoreMode {
            self.restoreMode = pending
          }
          self.pendingRestoreMode = nil
          self.pendingEnterSsid = nil
          self.resetPendingRetry()
          return
        }
        if let pending = self.pendingRestoreMode, pending != mode {
          // The user changed the mode while the switch was unconfirmed.
          self.pendingRestoreMode = nil
          self.pendingEnterSsid = nil
          self.resetPendingRetry()
          return
        }
        self.fetchMode { [weak self] current in
          guard let self else { return }
          self.queue.async {
            guard self.running, self.currentSsid == ssid,
              self.restoreMode == nil, self.pendingEnterSsid == ssid
            else {
              if self.currentSsid != ssid {
                self.pendingEnterSsid = nil
              }
              return
            }
            guard let current else {
              self.schedulePendingRetry()
              return
            }
            if current != mode {
              if current == "direct",
                let pending = self.pendingRestoreMode
              {
                self.restoreMode = pending
              } else {
                self.logger.info(
                  "ssid direct: mode changed while entering \(ssid, privacy: .public), abandoning switch"
                )
              }
              self.pendingRestoreMode = nil
              self.pendingEnterSsid = nil
              self.resetPendingRetry()
              return
            }
            self.pendingRestoreMode = mode
            self.setMode("direct") { [weak self] succeeded in
              guard let self else { return }
              self.queue.async {
                guard self.running else { return }
                if succeeded {
                  self.restoreMode = mode
                  self.pendingRestoreMode = nil
                  self.pendingEnterSsid = nil
                  self.resetPendingRetry()
                  self.logger.info(
                    "ssid direct: \(ssid, privacy: .public) mode \(mode, privacy: .public) -> direct"
                  )
                } else {
                  self.schedulePendingRetry()
                }
              }
            }
          }
        }
      }
    }
  }

  private func leaveDirect() {
    guard let restoreMode else { return }
    fetchMode { [weak self] mode in
      guard let self else { return }
      self.queue.async {
        guard self.running, self.restoreMode == restoreMode else { return }
        guard let mode else {
          self.schedulePendingRetry()
          return
        }
        // The phone may have entered another direct SSID while the mode
        // was being read; only restore when it is not on one now.
        let (directSSIDs, _) = self.sharedStateStore.loadDirectModeSettings()
        if let current = self.currentSsid, Set(directSSIDs).contains(current) {
          return
        }
        guard mode == "direct" else {
          // The user changed the mode themselves; their choice stands.
          self.restoreMode = nil
          self.resetPendingRetry()
          return
        }
        self.setMode(restoreMode) { [weak self] succeeded in
          guard let self else { return }
          self.queue.async {
            guard self.running else { return }
            if succeeded {
              if self.restoreMode == restoreMode {
                self.restoreMode = nil
              }
              self.resetPendingRetry()
              self.logger.info(
                "ssid direct: left, mode direct -> \(restoreMode, privacy: .public)"
              )
            } else {
              self.schedulePendingRetry()
            }
          }
        }
      }
    }
  }

  private func schedulePendingRetry() {
    guard running else { return }
    if pendingRetryCount >= Self.maxPendingRetries {
      if !pendingRetryExhausted {
        pendingRetryExhausted = true
        logger.warning(
          "ssid direct: keeping pending switch/restore after \(Self.maxPendingRetries, privacy: .public) timer retries; will retry on the next network change"
        )
      }
      return
    }
    pendingRetryWorkItem?.cancel()
    let delay = min(TimeInterval(2 << pendingRetryCount), 30)
    pendingRetryCount += 1
    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.retryPending()
    }
    pendingRetryWorkItem = workItem
    queue.asyncAfter(deadline: .now() + delay, execute: workItem)
  }

  private func resetPendingRetry() {
    pendingRetryWorkItem?.cancel()
    pendingRetryWorkItem = nil
    pendingRetryCount = 0
    pendingRetryExhausted = false
  }

  private func fetchMode(completion: @escaping (String?) -> Void) {
    fetchMode(attempt: 1, completion: completion)
  }

  private func fetchMode(
    attempt: Int,
    completion: @escaping (String?) -> Void
  ) {
    guard let request = controllerRequest() else {
      logger.warning("ssid direct: cannot build controller request")
      completion(nil)
      return
    }
    session.dataTask(with: request) { [weak self] data, response, error in
      guard let self else { return }
      let status = (response as? HTTPURLResponse)?.statusCode
      if status == 401 {
        self.logger.warning(
          "ssid direct: fetch mode unauthorized (401); controller secret out of sync"
        )
        completion(nil)
        return
      }
      if let data,
        let json = try? JSONSerialization.jsonObject(with: data)
          as? [String: Any],
        let mode = json["mode"] as? String
      {
        completion(mode)
        return
      }
      self.logger.warning(
        "ssid direct: fetch mode failed attempt \(attempt, privacy: .public)/\(Self.maxAttempts, privacy: .public) status=\(status.map(String.init) ?? "none", privacy: .public) error=\(error?.localizedDescription ?? "none", privacy: .public)"
      )
      if attempt < Self.maxAttempts {
        let delay = TimeInterval(1 << (attempt - 1))
        self.queue.asyncAfter(deadline: .now() + delay) {
          self.fetchMode(attempt: attempt + 1, completion: completion)
        }
      } else {
        completion(nil)
      }
    }.resume()
  }

  private func setMode(_ mode: String, completion: ((Bool) -> Void)? = nil) {
    setMode(mode, attempt: 1, completion: completion)
  }

  private func setMode(
    _ mode: String,
    attempt: Int,
    completion: ((Bool) -> Void)?
  ) {
    guard var request = controllerRequest() else {
      completion?(false)
      return
    }
    request.httpMethod = "PATCH"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(
      withJSONObject: ["mode": mode]
    )
    session.dataTask(with: request) { [weak self] _, response, error in
      guard let self else { return }
      let status = (response as? HTTPURLResponse)?.statusCode
      if status == 401 {
        self.logger.warning(
          "ssid direct: set mode unauthorized (401); controller secret out of sync"
        )
        completion?(false)
        return
      }
      if let status, (200...299).contains(status) {
        completion?(true)
        return
      }
      self.logger.warning(
        "ssid direct: set mode \(mode, privacy: .public) failed attempt \(attempt, privacy: .public)/\(Self.maxAttempts, privacy: .public) status=\(status.map(String.init) ?? "none", privacy: .public) error=\(error?.localizedDescription ?? "none", privacy: .public)"
      )
      if attempt < Self.maxAttempts {
        let delay = TimeInterval(1 << (attempt - 1))
        self.queue.asyncAfter(deadline: .now() + delay) {
          self.setMode(mode, attempt: attempt + 1, completion: completion)
        }
      } else {
        completion?(false)
      }
    }.resume()
  }

  private func controllerRequest() -> URLRequest? {
    guard
      let url = URL(string: "http://127.0.0.1:9090/configs")
    else {
      return nil
    }
    var request = URLRequest(url: url)
    let (_, secret) = sharedStateStore.loadDirectModeSettings()
    if !secret.isEmpty {
      request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
    }
    return request
  }
}
