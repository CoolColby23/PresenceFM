import SwiftUI

extension View {
    @ViewBuilder
    func presenceCard(capsule: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if capsule { glassEffect(.regular, in: .capsule) }
            else { glassEffect(.regular, in: .rect(cornerRadius: 12)) }
        } else {
            padding(.horizontal, capsule ? 12 : 0)
                .padding(.vertical, capsule ? 8 : 0)
                .background(.regularMaterial, in: capsule ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: 12)))
        }
    }

    @ViewBuilder
    func presenceButton(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}
