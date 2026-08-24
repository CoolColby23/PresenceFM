import SwiftUI
import UIKit

enum CompanionBrand {
    static let electricBlue = Color(red: 31.0 / 255.0, green: 102.0 / 255.0, blue: 1.0)
    static let signalCyan = Color(red: 20.0 / 255.0, green: 217.0 / 255.0, blue: 1.0)
    static let night = Color(red: 7.0 / 255.0, green: 20.0 / 255.0, blue: 47.0 / 255.0)
    static let ink = Color(red: 11.0 / 255.0, green: 16.0 / 255.0, blue: 32.0 / 255.0)
    static let cloud = Color(red: 247.0 / 255.0, green: 249.0 / 255.0, blue: 1.0)
    static let slate = Color(red: 77.0 / 255.0, green: 88.0 / 255.0, blue: 115.0 / 255.0)
    static let mist = Color(red: 174.0 / 255.0, green: 185.0 / 255.0, blue: 212.0 / 255.0)

    static let canvas = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 7 / 255, green: 20 / 255, blue: 47 / 255, alpha: 1) : UIColor(red: 247 / 255, green: 249 / 255, blue: 1, alpha: 1)
        }
    )
    static let surface = Color(
        uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? UIColor(red: 16 / 255, green: 31 / 255, blue: 61 / 255, alpha: 1) : .white }
    )
    static let secondaryText = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 174 / 255, green: 185 / 255, blue: 212 / 255, alpha: 1) : UIColor(red: 77 / 255, green: 88 / 255, blue: 115 / 255, alpha: 1)
        }
    )
    static let hairline = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.12) : UIColor(white: 0, alpha: 0.07)
        }
    )

    static let discGradient = LinearGradient(colors: [signalCyan, electricBlue], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Spacing and radius scales that mirror `BrandSpacing` and `BrandRadius` on
/// macOS so both apps share one rhythm.
enum CompanionSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 14
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
}

enum CompanionRadius {
    static let sm: CGFloat = 10
    static let md: CGFloat = 14
    static let lg: CGFloat = 20
}

/// The widest comfortable measure for the companion's single-column layouts.
/// Keeps onboarding and detail content from stretching edge to edge on iPad.
enum CompanionLayout {
    static let readableWidth: CGFloat = 560
}

struct CompanionBrandMark: View {
    var body: some View {
        Canvas { context, size in
            let diameter = min(size.width, size.height)
            let rect = CGRect(x: (size.width - diameter) / 2, y: (size.height - diameter) / 2, width: diameter, height: diameter)
            var disc = Path(ellipseIn: rect.insetBy(dx: diameter * 0.08, dy: diameter * 0.08))
            disc.addEllipse(in: rect.insetBy(dx: diameter * 0.39, dy: diameter * 0.39))
            context.fill(
                disc,
                with: .linearGradient(
                    Gradient(colors: [CompanionBrand.signalCyan, CompanionBrand.electricBlue]), startPoint: rect.origin,
                    endPoint: CGPoint(x: rect.maxX, y: rect.maxY)), style: FillStyle(eoFill: true))

            // The same specular arc the Mac app draws, so the disc reads as one
            // brand mark across platforms.
            var highlight = Path()
            highlight.addArc(
                center: CGPoint(x: rect.midX, y: rect.midY),
                radius: diameter * 0.36,
                startAngle: .degrees(218),
                endAngle: .degrees(298),
                clockwise: false
            )
            context.stroke(
                highlight,
                with: .color(Color(red: 0.97, green: 0.98, blue: 1.00).opacity(0.55)),
                style: StrokeStyle(lineWidth: max(1, diameter * 0.031), lineCap: .round)
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("PresenceFM")
    }
}

extension View {
    func companionCanvas() -> some View {
        scrollContentBackground(.hidden)
            .background(CompanionBrand.canvas.ignoresSafeArea())
    }

    /// The companion's standard surface: a padded card on the app canvas.
    func companionCard(padding: CGFloat = CompanionSpacing.md) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CompanionBrand.surface, in: RoundedRectangle(cornerRadius: CompanionRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CompanionRadius.lg, style: .continuous)
                    .strokeBorder(CompanionBrand.hairline, lineWidth: 1)
            )
    }

    /// Constrains a single column of content to a comfortable reading width and
    /// centers it, which matters on iPad and landscape iPhone.
    func companionReadableColumn() -> some View {
        frame(maxWidth: CompanionLayout.readableWidth)
            .frame(maxWidth: .infinity)
    }
}
