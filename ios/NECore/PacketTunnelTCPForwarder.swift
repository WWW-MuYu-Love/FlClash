import Foundation
import Network
import os

/// Relays TCP from the LAN to the loopback proxy, so LAN devices can use
/// it while mihomo stays bound to loopback only. One relay per accepted
/// connection; a failed relay only closes that connection.
final class PacketTunnelTCPForwarder {
  private let logger = Logger(
    subsystem: PacketTunnelEnvironment.extensionBundleIdentifier,
    category: "PacketTunnelTCPForwarder"
  )
  private let queue = DispatchQueue(label: "PacketTunnelTCPForwarder")
  private let listenPort: NWEndpoint.Port
  private let targetPort: NWEndpoint.Port
  private var listener: NWListener?
  private var relays: [UUID: TCPForwarderRelay] = [:]

  init(listenPort: NWEndpoint.Port, targetPort: NWEndpoint.Port) {
    self.listenPort = listenPort
    self.targetPort = targetPort
  }

  func start() {
    queue.async { [weak self] in
      self?.startOnQueue()
    }
  }

  func stop() {
    // Strong capture so the stop runs after the caller drops its reference.
    queue.async { self.stopOnQueue() }
  }

  private func startOnQueue() {
    guard listener == nil else { return }
    guard let listener = NWListener(using: .tcp, on: listenPort) else {
      logger.error("tcp forwarder failed to create listener")
      return
    }
    listener.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      switch state {
      case .ready:
        self.logger.info("tcp forwarder listening")
      case .failed(let error):
        self.logger.error(
          "tcp forwarder failed: \(error, privacy: .public)"
        )
      case .cancelled:
        self.logger.info("tcp forwarder cancelled")
      default:
        break
      }
    }
    listener.newConnectionHandler = { [weak self] connection in
      self?.accept(connection)
    }
    self.listener = listener
    listener.start(queue: queue)
  }

  private func stopOnQueue() {
    listener?.cancel()
    listener = nil
    let current = relays
    relays.removeAll()
    current.values.forEach { $0.stop() }
  }

  private func accept(_ connection: NWConnection) {
    let relay = TCPForwarderRelay(
      inbound: connection,
      targetHost: "127.0.0.1",
      targetPort: targetPort,
      queue: queue
    )
    let id = UUID()
    relay.onDone = { [weak self] in
      self?.relays.removeValue(forKey: id)
    }
    relays[id] = relay
    relay.start()
  }
}

private final class TCPForwarderRelay {
  private let inbound: NWConnection
  private let outbound: NWConnection
  private let queue: DispatchQueue
  private var inboundReady = false
  private var outboundReady = false
  private var pumping = false
  private var stopped = false
  var onDone: (() -> Void)?

  init(
    inbound: NWConnection,
    targetHost: NWEndpoint.Host,
    targetPort: NWEndpoint.Port,
    queue: DispatchQueue
  ) {
    self.inbound = inbound
    self.outbound = NWConnection(
      host: targetHost,
      port: targetPort,
      using: .tcp
    )
    self.queue = queue
  }

  func start() {
    inbound.stateUpdateHandler = { [weak self] state in
      self?.connectionStateChanged(state, outbound: false)
    }
    outbound.stateUpdateHandler = { [weak self] state in
      self?.connectionStateChanged(state, outbound: true)
    }
    inbound.start(queue: queue)
    outbound.start(queue: queue)
  }

  func stop() {
    // Strong capture, same reason as the forwarder's stop.
    queue.async { self.stopOnQueue() }
  }

  private func connectionStateChanged(
    _ state: NWConnection.State,
    outbound: Bool
  ) {
    switch state {
    case .ready:
      if outbound {
        outboundReady = true
      } else {
        inboundReady = true
      }
      if inboundReady && outboundReady && !pumping {
        pumping = true
        pumpInbound()
        pumpOutbound()
      }
    case .failed, .cancelled:
      stopOnQueue()
    case .waiting, .preparing, .setup:
      break
    @unknown default:
      break
    }
  }

  private func pumpInbound() {
    guard !stopped else { return }
    inbound.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
      [weak self] data, _, isComplete, error in
      guard let self else { return }
      if error != nil {
        self.stopOnQueue()
        return
      }
      if let data, !data.isEmpty {
        self.outbound.send(content: data, completion: .contentProcessed {
          [weak self] _ in
          guard let self else { return }
          if isComplete {
            self.stopOnQueue()
          } else {
            self.pumpInbound()
          }
        })
      } else if isComplete {
        self.stopOnQueue()
      } else {
        self.pumpInbound()
      }
    }
  }

  private func pumpOutbound() {
    guard !stopped else { return }
    outbound.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
      [weak self] data, _, isComplete, error in
      guard let self else { return }
      if error != nil {
        self.stopOnQueue()
        return
      }
      if let data, !data.isEmpty {
        self.inbound.send(content: data, completion: .contentProcessed {
          [weak self] _ in
          guard let self else { return }
          if isComplete {
            self.stopOnQueue()
          } else {
            self.pumpOutbound()
          }
        })
      } else if isComplete {
        self.stopOnQueue()
      } else {
        self.pumpOutbound()
      }
    }
  }

  private func stopOnQueue() {
    guard !stopped else { return }
    stopped = true
    inbound.cancel()
    outbound.cancel()
    onDone?()
  }
}
