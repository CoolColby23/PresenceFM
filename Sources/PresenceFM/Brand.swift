import AppKit
import SwiftUI

enum BrandColors {
    static let electricBlue = Color(red: 31.0 / 255.0, green: 102.0 / 255.0, blue: 1.0)
    static let electricBlueSoft = Color(red: 31.0 / 255.0, green: 102.0 / 255.0, blue: 1.0).opacity(0.18)
    static let cyan = Color(red: 20.0 / 255.0, green: 217.0 / 255.0, blue: 1.0)
    static let cyanSoft = Color(red: 20.0 / 255.0, green: 217.0 / 255.0, blue: 1.0).opacity(0.18)
    static let night = Color(red: 7.0 / 255.0, green: 20.0 / 255.0, blue: 47.0 / 255.0)
    static let ink = Color(red: 11.0 / 255.0, green: 16.0 / 255.0, blue: 32.0 / 255.0)
    static let cloud = Color(red: 247.0 / 255.0, green: 249.0 / 255.0, blue: 1.0)
    static let fog = Color(red: 237.0 / 255.0, green: 241.0 / 255.0, blue: 249.0 / 255.0)
    static let slate = Color(red: 77.0 / 255.0, green: 88.0 / 255.0, blue: 115.0 / 255.0)
    static let mist = Color(red: 174.0 / 255.0, green: 185.0 / 255.0, blue: 212.0 / 255.0)
    static let steel = Color(red: 120.0 / 255.0, green: 132.0 / 255.0, blue: 162.0 / 255.0)
    static let success = Color(red: 36.0 / 255.0, green: 138.0 / 255.0, blue: 61.0 / 255.0)
    static let warning = Color(red: 184.0 / 255.0, green: 92.0 / 255.0, blue: 0.0)
    static let error = Color(red: 200.0 / 255.0, green: 34.0 / 255.0, blue: 50.0 / 255.0)
    static let neutral = Color(red: 102.0 / 255.0, green: 112.0 / 255.0, blue: 133.0 / 255.0)

    static let discGradient = LinearGradient(
        colors: [cyan, electricBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let softSurfaceLight = Color.white.opacity(0.72)
    static let softSurfaceDark = Color.white.opacity(0.06)

    static let heroBackdropDark = LinearGradient(
        colors: [night, ink, Color.black],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroBackdropLight = LinearGradient(
        colors: [cloud, fog, Color.white],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accentRibbon = LinearGradient(
        colors: [cyan, electricBlue],
        startPoint: .leading,
        endPoint: .trailing
    )
}

enum BrandSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 14
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
    static let xxl: CGFloat = 36
    static let xxxl: CGFloat = 48
}

enum BrandRadius {
    static let sm: CGFloat = 10
    static let md: CGFloat = 14
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
    static let xxl: CGFloat = 36
}

enum BrandTypography {
    static let heroTitle = Font.system(size: 38, weight: .bold, design: .rounded)
    static let sectionTitle = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let cardTitle = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 15, weight: .regular, design: .rounded)
    static let caption = Font.system(size: 12, weight: .medium, design: .rounded)
}

/// The PresenceFM disc, drawn natively so it remains crisp at every size.
struct BrandMark: View {
    var monochrome = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appTheme) private var theme

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 64
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let ink: GraphicsContext.Shading = monochrome
                ? .color(.primary)
                : .linearGradient(
                    Gradient(colors: [theme.secondaryColor, theme.primaryColor]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: size.width, y: size.height)
                )

            var disc = Path()
            disc.addEllipse(in: circle(center: center, radius: 26 * scale))
            disc.addEllipse(in: circle(center: center, radius: 7 * scale))
            context.fill(disc, with: ink, style: FillStyle(eoFill: true))

            if !monochrome {
                let edgeColor = colorScheme == .dark
                    ? Color(red: 0.97, green: 0.98, blue: 1.00).opacity(0.30)
                    : Color(red: 0.04, green: 0.06, blue: 0.13).opacity(0.12)

                var outerEdge = Path()
                outerEdge.addEllipse(in: circle(center: center, radius: 25.5 * scale))
                context.stroke(outerEdge, with: .color(edgeColor), lineWidth: max(0.75, scale))

                var holeEdge = Path()
                holeEdge.addEllipse(in: circle(center: center, radius: 7.5 * scale))
                context.stroke(holeEdge, with: .color(edgeColor.opacity(0.67)), lineWidth: max(0.75, scale))

                var highlight = Path()
                highlight.addArc(
                    center: center,
                    radius: 23 * scale,
                    startAngle: .degrees(218),
                    endAngle: .degrees(298),
                    clockwise: false
                )
                context.stroke(
                    highlight,
                    with: .color(Color(red: 0.97, green: 0.98, blue: 1.00).opacity(0.55)),
                    style: StrokeStyle(lineWidth: max(1.5, 2 * scale), lineCap: .round)
                )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("PresenceFM")
    }

    private func circle(center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}

/// Slow continuous disc rotation while music is playing. Freezes when Reduce Motion is on.
struct SpinningBrandMark: View {
    var isSpinning = false
    var monochrome = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: reduceMotion || !isSpinning ? 1_000_000 : 1.0 / 30.0,
                paused: reduceMotion || !isSpinning
            )
        ) { context in
            let angle = rotationDegrees(at: context.date)
            BrandMark(monochrome: monochrome)
                .rotationEffect(.degrees(angle))
        }
        .accessibilityHidden(true)
    }

    private func rotationDegrees(at date: Date) -> Double {
        guard isSpinning, !reduceMotion else { return 0 }
        // One revolution every 12 seconds — brand motion signature.
        return (date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 12) / 12) * 360
    }
}

/// A template image for macOS status items.
///
/// `MenuBarExtra` labels are hosted by AppKit, so use an image-backed view here
/// instead of `Canvas`. Marking the image as a template lets macOS apply the
/// correct menu-bar tint for the current appearance and selection state.
struct MenuBarBrandMark: View {
    var body: some View {
        Image(nsImage: Self.image)
    }

    private static let statusItemSize = NSSize(width: 18, height: 18)

    static let image: NSImage = {
        guard
            let url = Bundle.module.url(
                forResource: "presencefm-symbol-mono",
                withExtension: "svg"
            ),
            let image = NSImage(contentsOf: url)
        else {
            let fallback = NSImage(systemSymbolName: "waveform", accessibilityDescription: "PresenceFM")
                ?? NSImage(size: statusItemSize)
            fallback.size = statusItemSize
            fallback.isTemplate = true
            return fallback
        }

        // MenuBarExtra uses the NSImage's intrinsic point size when sizing its
        // AppKit status item. The SVG is authored on a 64 × 64 canvas, so a
        // SwiftUI frame alone leaves AppKit with an oversized 64-point label.
        image.size = statusItemSize
        image.isTemplate = true
        return image
    }()
}
