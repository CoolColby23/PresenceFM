import AppKit
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        }
    }
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// A curated, immutable theme. Presets are intentionally code-owned so a
/// synced preference can never import executable or malformed theme data.
struct AppTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let primaryHex: String
    let secondaryHex: String
    let darkBackgroundHex: String
    let lightBackgroundHex: String

    var primaryColor: Color { Color(hex: primaryHex) ?? BrandColors.electricBlue }
    var secondaryColor: Color { Color(hex: secondaryHex) ?? BrandColors.cyan }
    var darkBackground: Color { Color(hex: darkBackgroundHex) ?? BrandColors.ink }
    var lightBackground: Color { Color(hex: lightBackgroundHex) ?? BrandColors.cloud }
    var accentGradient: LinearGradient {
        LinearGradient(colors: [secondaryColor, primaryColor], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    func canvas(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkBackground : lightBackground
    }

    func surface(for scheme: ColorScheme, elevated: Bool = false) -> Color {
        if scheme == .dark {
            return darkBackground.mixed(with: .white, amount: elevated ? 0.105 : 0.065)
        }
        return lightBackground.mixed(with: elevated ? .white : .black, amount: elevated ? 0.78 : 0.025)
    }

    func subtleAccent(for scheme: ColorScheme) -> Color {
        primaryColor.opacity(scheme == .dark ? 0.18 : 0.11)
    }

    func readablePrimary(for scheme: ColorScheme) -> Color {
        let background = canvas(for: scheme)
        let target: Color = scheme == .dark ? .white : .black
        var candidate = primaryColor
        for step in 0...10 {
            candidate = primaryColor.mixed(with: target, amount: CGFloat(step) * 0.08)
            if candidate.contrastRatio(with: background) >= 4.5 { return candidate }
        }
        return target
    }

    var onPrimaryColor: Color {
        Color.white.contrastRatio(with: primaryColor) >= Color.black.contrastRatio(with: primaryColor)
            ? .white : .black
    }

    static let defaultID = "presence"
    static let presets: [AppTheme] = [
        .init(id: "presence", name: "Presence", description: "Electric blue and cyan", primaryHex: "#1F66FF", secondaryHex: "#14D9FF", darkBackgroundHex: "#0B1020", lightBackgroundHex: "#F7F9FF"),
        .init(id: "midnight", name: "Midnight", description: "Indigo after dark", primaryHex: "#6366F1", secondaryHex: "#818CF8", darkBackgroundHex: "#090B1A", lightBackgroundHex: "#F5F6FF"),
        .init(id: "grove", name: "Grove", description: "Emerald and sage", primaryHex: "#0F9F6E", secondaryHex: "#34D399", darkBackgroundHex: "#071C15", lightBackgroundHex: "#F0FDF4"),
        .init(id: "ocean", name: "Ocean", description: "Abyss and sky blue", primaryHex: "#0284C7", secondaryHex: "#38BDF8", darkBackgroundHex: "#071923", lightBackgroundHex: "#F0F9FF"),
        .init(id: "ember", name: "Ember", description: "Copper and amber", primaryHex: "#EA580C", secondaryHex: "#F59E0B", darkBackgroundHex: "#251006", lightBackgroundHex: "#FFF7ED"),
        .init(id: "iris", name: "Iris", description: "Violet and lavender", primaryHex: "#7C3AED", secondaryHex: "#C084FC", darkBackgroundHex: "#190B2B", lightBackgroundHex: "#FAF5FF"),
        .init(id: "rose", name: "Rose", description: "Pink and rosewater", primaryHex: "#DB2777", secondaryHex: "#FB7185", darkBackgroundHex: "#260B17", lightBackgroundHex: "#FFF1F2"),
        .init(id: "cherry", name: "Cherry", description: "Crimson and coral", primaryHex: "#DC2626", secondaryHex: "#FB7185", darkBackgroundHex: "#260909", lightBackgroundHex: "#FFF5F5"),
        .init(id: "sunset", name: "Sunset", description: "Magenta and tangerine", primaryHex: "#E11D48", secondaryHex: "#FB923C", darkBackgroundHex: "#290B13", lightBackgroundHex: "#FFF7ED"),
        .init(id: "lemon", name: "Lemon", description: "Gold and citrus", primaryHex: "#CA8A04", secondaryHex: "#FACC15", darkBackgroundHex: "#211A05", lightBackgroundHex: "#FEFCE8"),
        .init(id: "mint", name: "Mint", description: "Fresh teal and seafoam", primaryHex: "#0D9488", secondaryHex: "#5EEAD4", darkBackgroundHex: "#061D1B", lightBackgroundHex: "#F0FDFA"),
        .init(id: "aqua", name: "Aqua", description: "Cyan and turquoise", primaryHex: "#0891B2", secondaryHex: "#22D3EE", darkBackgroundHex: "#061C24", lightBackgroundHex: "#ECFEFF"),
        .init(id: "cobalt", name: "Cobalt", description: "Royal blue and ice", primaryHex: "#2563EB", secondaryHex: "#60A5FA", darkBackgroundHex: "#08142C", lightBackgroundHex: "#EFF6FF"),
        .init(id: "plum", name: "Plum", description: "Purple and fuchsia", primaryHex: "#9333EA", secondaryHex: "#E879F9", darkBackgroundHex: "#200B2C", lightBackgroundHex: "#FDF4FF"),
        .init(id: "mocha", name: "Mocha", description: "Coffee and caramel", primaryHex: "#A16207", secondaryHex: "#D6A96C", darkBackgroundHex: "#1E160E", lightBackgroundHex: "#FAF7F2"),
        .init(id: "slate", name: "Slate", description: "Cool monochrome", primaryHex: "#475569", secondaryHex: "#94A3B8", darkBackgroundHex: "#0F172A", lightBackgroundHex: "#F8FAFC"),
        .init(id: "orchid", name: "Orchid", description: "Soft lilac and bloom", primaryHex: "#A855F7", secondaryHex: "#F0ABFC", darkBackgroundHex: "#21102D", lightBackgroundHex: "#FDF4FF"),
        .init(id: "lime", name: "Lime", description: "Bright green and chartreuse", primaryHex: "#65A30D", secondaryHex: "#A3E635", darkBackgroundHex: "#142005", lightBackgroundHex: "#F7FEE7")
    ]

    static func find(_ id: String?) -> AppTheme {
        presets.first(where: { $0.id == id }) ?? presets[0]
    }

    static func validatedID(_ id: String?) -> String {
        find(id).id
    }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.find(AppTheme.defaultID)
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

extension Color {
    init?(hex: String) {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") { clean.removeFirst() }
        guard clean.count == 6, let value = UInt64(clean, radix: 16) else { return nil }
        self.init(
            red: Double((value & 0xFF0000) >> 16) / 255,
            green: Double((value & 0x00FF00) >> 8) / 255,
            blue: Double(value & 0x0000FF) / 255
        )
    }

    func mixed(with other: Color, amount: CGFloat) -> Color {
        guard let lhs = NSColor(self).usingColorSpace(.sRGB),
              let rhs = NSColor(other).usingColorSpace(.sRGB),
              let blended = lhs.blended(withFraction: max(0, min(1, amount)), of: rhs)
        else { return self }
        return Color(nsColor: blended)
    }

    func contrastRatio(with other: Color) -> Double {
        guard let lhs = NSColor(self).usingColorSpace(.sRGB),
              let rhs = NSColor(other).usingColorSpace(.sRGB) else { return 1 }
        let high = max(lhs.relativeLuminance, rhs.relativeLuminance)
        let low = min(lhs.relativeLuminance, rhs.relativeLuminance)
        return (high + 0.05) / (low + 0.05)
    }
}

private extension NSColor {
    var relativeLuminance: Double {
        func channel(_ value: CGFloat) -> Double {
            let value = Double(value)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(redComponent)
            + 0.7152 * channel(greenComponent)
            + 0.0722 * channel(blueComponent)
    }
}
