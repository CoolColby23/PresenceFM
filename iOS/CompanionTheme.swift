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

    static let discGradient = LinearGradient(colors: [signalCyan, electricBlue], startPoint: .topLeading, endPoint: .bottomTrailing)
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
}
