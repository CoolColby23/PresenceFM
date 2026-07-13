import AppKit
import SwiftUI

enum BrandColors {
    static let electricBlue = Color(red: 31.0 / 255.0, green: 102.0 / 255.0, blue: 1.0)
    static let cyan = Color(red: 20.0 / 255.0, green: 217.0 / 255.0, blue: 1.0)
    static let success = Color(red: 36.0 / 255.0, green: 138.0 / 255.0, blue: 61.0 / 255.0)
    static let warning = Color(red: 184.0 / 255.0, green: 92.0 / 255.0, blue: 0.0)
    static let error = Color(red: 200.0 / 255.0, green: 34.0 / 255.0, blue: 50.0 / 255.0)
    static let neutral = Color(red: 102.0 / 255.0, green: 112.0 / 255.0, blue: 133.0 / 255.0)
}

/// The PresenceFM disc, drawn natively so it remains crisp at every size.
struct BrandMark: View {
    var monochrome = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 64
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let ink: GraphicsContext.Shading = monochrome
                ? .color(.primary)
                : .linearGradient(
                    Gradient(colors: [BrandColors.cyan, BrandColors.electricBlue]),
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
