import Foundation

/// Discovers the App Group at runtime from the install's own provisioning
/// profile instead of hardcoding a SideKite-generated identifier: every
/// install is signed with its own groups, so the identifier differs per
/// device and certificate. The extension does not link the Shared module,
/// so this mirrors AppGroupResolver in ios/Shared/; keep the two in sync.
enum AppGroupResolver {
  private static let cacheLock = NSLock()
  private static var cachedProfileGroups: [String]?
  private static var cachedResolvedIdentifiers: [String: String] = [:]

  /// App Groups listed in this bundle's embedded provisioning profile.
  static func profileAppGroups() -> [String] {
    cacheLock.lock()
    let cached = cachedProfileGroups
    cacheLock.unlock()
    if let cached {
      return cached
    }
    let groups = readProfileAppGroups()
    cacheLock.lock()
    cachedProfileGroups = groups
    cacheLock.unlock()
    return groups
  }

  /// The first App Group this process can reach: the group derived from
  /// the bundle ID, then the profile groups in order. Falls back to the
  /// derived identifier when none resolves, so UserDefaults suites still
  /// have a name to use.
  static func resolveAppGroupIdentifier(
    bundleIdentifier: String
  ) -> String {
    cacheLock.lock()
    let cached = cachedResolvedIdentifiers[bundleIdentifier]
    cacheLock.unlock()
    if let cached {
      return cached
    }
    let resolved =
      candidateIdentifiers(bundleIdentifier: bundleIdentifier).first(
        where: { identifier in
          FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
          ) != nil
        }
      ) ?? "group.\(bundleIdentifier)"
    cacheLock.lock()
    cachedResolvedIdentifiers[bundleIdentifier] = resolved
    cacheLock.unlock()
    return resolved
  }

  /// The container of the first resolvable App Group, or nil when none
  /// resolves and the caller should use its own container.
  static func resolveAppGroupDirectory(
    bundleIdentifier: String
  ) -> URL? {
    for identifier in candidateIdentifiers(bundleIdentifier: bundleIdentifier)
    {
      if let url = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: identifier
      ) {
        return url
      }
    }
    return nil
  }

  private static func candidateIdentifiers(
    bundleIdentifier: String
  ) -> [String] {
    ["group.\(bundleIdentifier)"] + profileAppGroups()
  }

  private static func readProfileAppGroups() -> [String] {
    for path in profilePaths() {
      guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
        let plist = extractPlist(from: data),
        let entitlements = plist["Entitlements"] as? [String: Any],
        let groups = entitlements["com.apple.security.application-groups"]
          as? [String]
      else {
        continue
      }
      return groups
    }
    return []
  }

  /// Candidate provisioning profiles: the containing app bundle first.
  /// An extension at <App>.app/PlugIns/<Extension>.appex may not carry
  /// its own profile, and the shared App Group lives in the app's profile.
  private static func profilePaths() -> [String] {
    var paths: [String] = []
    let bundleURL = Bundle.main.bundleURL
    if bundleURL.pathExtension == "appex" {
      let appURL = bundleURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
      paths.append(
        appURL.appendingPathComponent("embedded.mobileprovision").path
      )
    }
    if let own = Bundle.main.path(
      forResource: "embedded",
      ofType: "mobileprovision"
    ) {
      paths.append(own)
    }
    return paths
  }

  /// The provisioning profile is a CMS envelope around a plist; extract
  /// the plist XML between its markers.
  private static func extractPlist(from data: Data) -> [String: Any]? {
    guard let start = data.range(of: Data("<plist".utf8)),
      let end = data.range(
        of: Data("</plist>".utf8),
        options: [],
        in: start.upperBound..<data.endIndex
      ),
      let plist = try? PropertyListSerialization.propertyList(
        from: data[start.lowerBound..<end.upperBound],
        format: nil
      ) as? [String: Any]
    else {
      return nil
    }
    return plist
  }
}
