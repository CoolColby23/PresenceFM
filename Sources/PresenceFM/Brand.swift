import SwiftUI

enum BrandColors {
    static let electricBlue = Color(red: 0.12, green: 0.40, blue: 1.00)
    static let cyan = Color(red: 0.08, green: 0.85, blue: 1.00)
    static let violet = Color(red: 0.49, green: 0.20, blue: 1.00)
    static let magenta = Color(red: 0.95, green: 0.16, blue: 0.72)
    static let coral = Color(red: 1.00, green: 0.43, blue: 0.35)

    static let signal = LinearGradient(
        colors: [cyan, electricBlue, violet, magenta, coral],
        startPoint: .leading,
        endPoint: .trailing
    )
}

/// The PresenceFM portal and signal, drawn natively so it remains crisp at every size.
struct BrandMark: View {
    var isPrivate = false
    var monochrome = false

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 64
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let stroke = max(2, 5 * scale)
            let ink: GraphicsContext.Shading = monochrome
                ? .color(.primary)
                : .linearGradient(
                    Gradient(colors: [BrandColors.cyan, BrandColors.electricBlue, BrandColors.violet, BrandColors.magenta]),
                    startPoint: CGPoint(x: 0, y: center.y),
                    endPoint: CGPoint(x: size.width, y: center.y)
                )

            var portal = Path()
            portal.addArc(center: center, radius: 22 * scale, startAngle: .degrees(42), endAngle: .degrees(318), clockwise: false)
            context.stroke(portal, with: ink, style: StrokeStyle(lineWidth: stroke, lineCap: .round))

            var signal = Path()
            let points: [(CGFloat, CGFloat)] = isPrivate
                ? [(4, 32), (17, 32), (23, 23), (28, 41)]
                : [(4, 32), (17, 32), (23, 23), (29, 42), (36, 18), (42, 32), (60, 32)]
            for (index, point) in points.enumerated() {
                let p = CGPoint(x: center.x + (point.0 - 32) * scale, y: center.y + (point.1 - 32) * scale)
                index == 0 ? signal.move(to: p) : signal.addLine(to: p)
            }
            context.stroke(signal, with: ink, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))

            if isPrivate {
                var slash = Path()
                slash.move(to: CGPoint(x: center.x + 4 * scale, y: center.y + 10 * scale))
                slash.addLine(to: CGPoint(x: center.x + 16 * scale, y: center.y - 10 * scale))
                context.stroke(slash, with: .color(.secondary), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct BrandHero: View {
    var body: some View {
        BrandMark()
            .frame(width: 112, height: 112)
            .padding(18)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 30))
            .overlay {
                RoundedRectangle(cornerRadius: 30)
                    .stroke(BrandColors.signal, lineWidth: 1)
                    .opacity(0.55)
            }
            .shadow(color: BrandColors.electricBlue.opacity(0.22), radius: 24, y: 10)
    }
}
