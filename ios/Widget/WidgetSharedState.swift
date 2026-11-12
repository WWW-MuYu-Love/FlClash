import Foundation
import Shared
import SwiftUI

struct WidgetSharedState {
  let currentProfileName: String?
  let showQuickSettingsProfileName: Bool?
  let widgetTheme: WidgetTheme?

  static func load() -> WidgetSharedState? {
    guard
      let data = UserDefaults(suiteName: NEHelper.appGroupIdentifier)?
        .data(forKey: "sharedState"),
      let json = try? JSONSerialization.jsonObject(with: data)
        as? [String: Any]
    else {
      return nil
    }
    let themeData = (json["widgetTheme"] as? [String: Any]).flatMap {
      try? JSONSerialization.data(withJSONObject: $0)
    }
    return WidgetSharedState(
      currentProfileName: json["currentProfileName"] as? String,
      showQuickSettingsProfileName: json["showQuickSettingsProfileName"]
        as? Bool,
      widgetTheme: themeData.flatMap {
        try? JSONDecoder().decode(WidgetTheme.self, from: $0)
      },
    )
  }
}

struct WidgetTheme: Decodable {
  let themeMode: String
  let light: WidgetColors
  let dark: WidgetColors

  private enum CodingKeys: String, CodingKey {
    case themeMode, light, dark
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    themeMode =
      try container.decodeIfPresent(String.self, forKey: .themeMode)
      ?? "system"
    light = try container.decode(WidgetColors.self, forKey: .light)
    dark = try container.decode(WidgetColors.self, forKey: .dark)
  }

  func colors(for scheme: ColorScheme) -> WidgetColors {
    switch themeMode {
    case "light": light
    case "dark": dark
    default: scheme == .dark ? dark : light
    }
  }

  var forcedColorScheme: ColorScheme? {
    switch themeMode {
    case "light": .light
    case "dark": .dark
    default: nil
    }
  }
}

struct WidgetColors: Decodable {
  let background: UInt32
  let onBackground: UInt32
  let onBackgroundVariant: UInt32
  let primary: UInt32
  let onPrimary: UInt32
  let trackOff: UInt32
  let thumbOff: UInt32

  private enum CodingKeys: String, CodingKey {
    case background, onBackground, onBackgroundVariant, primary, onPrimary,
      trackOff, thumbOff
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    background =
      try container.decodeIfPresent(UInt32.self, forKey: .background) ?? 0
    onBackground =
      try container.decodeIfPresent(UInt32.self, forKey: .onBackground) ?? 0
    onBackgroundVariant =
      try container.decodeIfPresent(
        UInt32.self,
        forKey: .onBackgroundVariant
      ) ?? 0
    primary = try container.decodeIfPresent(UInt32.self, forKey: .primary) ?? 0
    onPrimary =
      try container.decodeIfPresent(UInt32.self, forKey: .onPrimary) ?? 0
    trackOff =
      try container.decodeIfPresent(UInt32.self, forKey: .trackOff) ?? 0
    thumbOff =
      try container.decodeIfPresent(UInt32.self, forKey: .thumbOff) ?? 0
  }
}

extension Color {
  init(argb: UInt32) {
    self.init(
      .sRGB,
      red: Double((argb >> 16) & 0xFF) / 255,
      green: Double((argb >> 8) & 0xFF) / 255,
      blue: Double(argb & 0xFF) / 255,
      opacity: Double(argb >> 24) / 255
    )
  }
}
