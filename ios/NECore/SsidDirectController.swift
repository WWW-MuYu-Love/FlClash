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
  private let sharedStateStore: PacketTunnelSharedStateStore
  private let logger = Logger(
    subsystem: PacketTunnelEnvironment.extensionBundleIdentifier,
    category: "SsidDirectController"
  )

  private let queue = DispatchQueue(label: "love.muyu.flclash.ssid-direct")
  private var monitor: NWPathMonitor?
  private var running = false

  /// The mode to restore when the phone leaves a direct SSID, nil while no
  /// direct override is active.
  private var restoreMode: String?
  private var currentSsid: String?

  init(sharedStateStore: PacketTunnelSharedStateStore) {
    self.sharedStateStore = sharedStateStore
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
      self.logger.info("ssid direct monitor stopped")
    }
  }

  private func refreshSsid() {
    // A Wi-Fi to Wi-Fi switch may not move the path, and the SSID read is
    // asynchronous, so always re-read rather than trusting the last value.
    NEHotspotNetwork.fetchCurrent { [weak self] network in
      guard let self else { return }
      self.queue.async {
        self.apply(ssid: network?.ssid)
      }
    }
  }

  private func apply(ssid: String?) {
    guard running else { return }
    let (directSSIDs, _) = sharedStateStore.loadDirectModeSettings()
    let direct = Set(directSSIDs)
    let previous = currentSsid
    currentSsid = ssid
    if previous == ssid { return }
    if let ssid, direct.contains(ssid) {
      enterDirect(ssid: ssid)
      return
    }
    leaveDirect()
  }

  private func enterDirect(ssid: String) {
    guard restoreMode == nil else { return }
    fetchMode { [weak self] mode in
      guard let self, let mode else { return }
      self.queue.async {
        guard self.running, self.currentSsid == ssid, self.restoreMode == nil
        else { return }
        if mode != "direct" {
          self.restoreMode = mode
        }
        self.setMode("direct")
        self.logger.info(
          "ssid direct: \(ssid, privacy: .public) mode \(mode, privacy: .public) -> direct"
        )
      }
    }
  }

  private func leaveDirect() {
    guard let restoreMode else { return }
    self.restoreMode = nil
    fetchMode { [weak self] mode in
      guard let self, let mode else { return }
      self.queue.async {
        guard self.running, self.restoreMode == nil else { return }
        // The phone may have entered another direct SSID while the mode
        // was being read; only restore when it is not on one now.
        let (directSSIDs, _) = self.sharedStateStore.loadDirectModeSettings()
        if let current = self.currentSsid, Set(directSSIDs).contains(current) {
          return
        }
        // Only restore when the user has not changed the mode themselves.
        guard mode == "direct" else { return }
        self.setMode(restoreMode)
        self.logger.info(
          "ssid direct: left, mode direct -> \(restoreMode, privacy: .public)"
        )
      }
    }
  }

  private func fetchMode(completion: @escaping (String?) -> Void) {
    guard let request = controllerRequest() else {
      completion(nil)
      return
    }
    URLSession.shared.dataTask(with: request) { data, _, _ in
      guard let data,
        let json = try? JSONSerialization.jsonObject(with: data)
          as? [String: Any],
        let mode = json["mode"] as? String
      else {
        completion(nil)
        return
      }
      completion(mode)
    }.resume()
  }

  private func setMode(_ mode: String) {
    guard var request = controllerRequest() else { return }
    request.httpMethod = "PATCH"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(
      withJSONObject: ["mode": mode]
    )
    URLSession.shared.dataTask(with: request) { _, response, _ in
      if let http = response as? HTTPURLResponse,
        !(200...299).contains(http.statusCode)
      {
        self.logger.warning(
          "ssid direct: set mode \(mode, privacy: .public) failed status=\(http.statusCode, privacy: .public)"
        )
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
