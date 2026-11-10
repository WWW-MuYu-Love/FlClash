import Foundation

/// Discovers the App Group at runtime from the install's own provisioning
/// profile instead of hardcoding a SideKite-generated identifier: every
/// install is signed with its own groups, so the identifier differs per
/// device and certificate. Keep in sync with AppGroupResolver in
/// ios/NECore/, which the extension compiles separately.
public enum AppGroupResolver {
  private static var cachedProfileGroups: [String]?
  private static var cachedResolvedIdentifiers: [String: String] = [:]

  /// App Groups listed in this bundle's embedded provisioning profile.
  public static func profileAppGroups() -> [String] {
    if let cached = cachedProfileGroups {
      return cached
    }
    let groups = readProfileAppGroups()
    cachedProfileGroups = groups
    return groups
  }

  /// The first App Group this process can reach: the group derived from
  /// the bundle ID, then the profile groups in order. Falls back to the
  /// derived identifier when none resolves, so UserDefaults suites still
  /// have a name to use.
  public static func resolveAppGroupIdentifier(
    bundleIdentifier: String
  ) -> String {
    if let cached = cachedResolvedIdentifiers[bundleIdentifier] {
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
    cachedResolvedIdentifiers[bundleIdentifier] = resolved
    return resolved
  }

  /// The container of the first resolvable App Group, or nil when none
  /// resolves and the caller should use its own container.
  public static func resolveAppGroupDirectory(
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
    guard let path = Bundle.main.path(
      forResource: "embedded",
      ofType: "mobileprovision"
    ),
      let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
      let plist = extractPlist(from: data),
      let entitlements = plist["Entitlements"] as? [String: Any],
      let groups = entitlements["com.apple.security.application-groups"]
        as? [String]
    else {
      return []
    }
    return groups
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
