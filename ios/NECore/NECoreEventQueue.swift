import Foundation
import os
import UserNotifications

final class NECoreEventQueue {
  private let sharedStateStore: PacketTunnelSharedStateStore
  private let eventQueueDirectoryName = "core-events"
  private let maxEventQueueFiles = 10
  private let logger = Logger(
    subsystem: PacketTunnelEnvironment.extensionBundleIdentifier,
    category: "NECoreEventQueue"
  )

  private var eventsSincePrune = 0
  private var droppedEventCount = 0
  private let droppedCountFileName = "dropped-count"

  init(sharedStateStore: PacketTunnelSharedStateStore) {
    self.sharedStateStore = sharedStateStore
  }

  func start() {
    NECoreBridge.setEventListener { [weak self] event in
      guard let self,
        let event,
        !event.isEmpty
      else {
        return
      }
      // A script notification is consumed here, in the extension, so it fires with the app closed.
      guard let remaining = self.postScriptNotifications(from: event) else {
        return
      }
      self.enqueue(remaining)
    }
  }

  func stop() {
    NECoreBridge.setEventListener(nil)
  }

  // Posts the scriptNotification messages in a batch and returns the batch
  // without them, or nil when nothing is left for the app.
  private func postScriptNotifications(from event: Data) -> Data? {
    guard
      let batch = try? JSONSerialization.jsonObject(with: event) as? [String: Any],
      let arguments = batch["arguments"] as? [[String: Any]]
    else {
      return event
    }
    var kept: [[String: Any]] = []
    var posted = false
    for argument in arguments {
      guard argument["type"] as? String == "scriptNotification" else {
        kept.append(argument)
        continue
      }
      posted = true
      if let data = argument["data"] as? [String: Any] {
        postNotification(
          title: data["title"] as? String ?? "",
          subtitle: data["subtitle"] as? String ?? "",
          body: data["body"] as? String ?? ""
        )
      }
    }
    guard posted else {
      return event
    }
    guard !kept.isEmpty else {
      return nil
    }
    var stripped = batch
    stripped["arguments"] = kept
    return (try? JSONSerialization.data(withJSONObject: stripped)) ?? event
  }

  private func postNotification(title: String, subtitle: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.subtitle = subtitle
    content.body = body
    content.threadIdentifier = "flclash-mitm-script"
    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request) { [weak self] error in
      if let error {
        self?.logger.error(
          "script notification failed: \(error.localizedDescription, privacy: .public)"
        )
      }
    }
  }

  private func enqueue(_ event: Data) {
    guard let directory = eventQueueDirectory() else {
      logger.error("enqueue failed: missing app group dir")
      return
    }
    do {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
      let timestamp = UInt64(Date().timeIntervalSince1970 * 1_000_000)
      let fileName = "\(timestamp)-\(UUID().uuidString)"
      let fileURL = directory.appendingPathComponent("\(fileName).json")
      let temporaryURL = directory.appendingPathComponent(".\(fileName).tmp")
      do {
        try event.write(to: temporaryURL)
        try FileManager.default.moveItem(at: temporaryURL, to: fileURL)
      } catch {
        try? FileManager.default.removeItem(at: temporaryURL)
        throw error
      }
      eventsSincePrune += 1
      if eventsSincePrune >= maxEventQueueFiles {
        eventsSincePrune = 0
        prune(in: directory)
      }
      notifyEventAvailable()
    } catch {
      logger.error(
        "enqueue failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  private func prune(in directory: URL) {
    var files = eventFiles(in: directory)
    var overflowCount = files.count - maxEventQueueFiles
    if overflowCount > 0 {
      droppedEventCount += overflowCount
      logger.warning(
        "prune overflow=\(overflowCount, privacy: .public), dropped total=\(self.droppedEventCount, privacy: .public)"
      )
      saveDroppedCount(in: directory)
    }

    while overflowCount > 0 && !files.isEmpty {
      removeOldestEventFile(&files)
      overflowCount -= 1
    }
    removeStaleTemporaryFiles(in: directory)
  }

  private func saveDroppedCount(in directory: URL) {
    let fileURL = directory.appendingPathComponent(droppedCountFileName)
    try? "\(droppedEventCount)".write(
      to: fileURL,
      atomically: true,
      encoding: .utf8
    )
  }

  // Only files older than a minute go, so a write still in flight is never removed.
  private func removeStaleTemporaryFiles(in directory: URL) {
    guard let fileURLs = try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.contentModificationDateKey]
    ) else {
      return
    }
    let staleBefore = Date().addingTimeInterval(-60)
    for fileURL in fileURLs where fileURL.pathExtension == "tmp" {
      guard
        let modified = try? fileURL.resourceValues(
          forKeys: [.contentModificationDateKey]
        ).contentModificationDate,
        modified < staleBefore
      else {
        continue
      }
      try? FileManager.default.removeItem(at: fileURL)
    }
  }

  private func eventFiles(in directory: URL) -> [URL] {
    guard let fileURLs = try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey]
    ) else {
      return []
    }
    return fileURLs.filter { fileURL in
      fileURL.pathExtension == "json" &&
        (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?
          .isRegularFile == true
    }.sorted { lhs, rhs in
      lhs.lastPathComponent < rhs.lastPathComponent
    }
  }

  private func removeOldestEventFile(_ files: inout [URL]) {
    let fileURL = files.removeFirst()
    do {
      try FileManager.default.removeItem(at: fileURL)
    } catch {
      logger.warning(
        "prune failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  private func eventQueueDirectory() -> URL? {
    sharedStateStore.homeDirectory()?.appendingPathComponent(
      eventQueueDirectoryName,
      isDirectory: true
    )
  }

  private func notifyEventAvailable() {
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(
        PacketTunnelEnvironment.eventNotificationName as CFString
      ),
      nil,
      nil,
      true
    )
  }
}
