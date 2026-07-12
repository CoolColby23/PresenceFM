import SwiftUI

enum BrandColors {
    static let electricBlue = Color(red: 0.12, green: 0.40, blue: 1.00)
    static let cyan = Color(red: 0.08, green: 0.85, blue: 1.00)
    static let violet = electricBlue
    static let magenta = electricBlue
    static let coral = Color(red: 1.00, green: 0.43, blue: 0.35)

    static let signal = LinearGradient(
        colors: [cyan, electricBlue],
        startPoint: .leading,
        endPoint: .trailing
    )
}

/// The PresenceFM disc, drawn natively so it remains crisp at every size.
struct BrandMark: View {
    var isPrivate = false
    var monochrome = false

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 64
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let stroke = max(2, 9 * scale)
            let ink: GraphicsContext.Shading = monochrome
                ? .color(.primary)
                : .linearGradient(
                    Gradient(colors: [BrandColors.cyan, BrandColors.electricBlue]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: size.width, y: size.height)
                )

            var disc = Path()
            disc.addEllipse(in: CGRect(x: center.x - 21 * scale, y: center.y - 21 * scale, width: 42 * scale, height: 42 * scale))
            context.stroke(disc, with: ink, style: StrokeStyle(lineWidth: stroke))

            if isPrivate {
                var slash = Path()
                slash.move(to: CGPoint(x: center.x - 18 * scale, y: center.y + 18 * scale))
                slash.addLine(to: CGPoint(x: center.x + 18 * scale, y: center.y - 18 * scale))
                context.stroke(slash, with: .color(.primary), style: StrokeStyle(lineWidth: max(2, 4 * scale), lineCap: .round))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("PresenceFM")
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
