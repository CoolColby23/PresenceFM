import SwiftUI

extension View {
    @ViewBuilder
    func presenceCard(capsule: Bool = false, elevated: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if capsule {
                glassEffect(.regular, in: .capsule)
            } else {
                glassEffect(.regular, in: .rect(cornerRadius: elevated ? BrandRadius.lg : BrandRadius.md))
                    .shadow(color: elevated ? .black.opacity(0.14) : .clear, radius: elevated ? 18 : 0, y: elevated ? 8 : 0)
            }
        } else {
            modifier(PresenceCardModifier(capsule: capsule, elevated: elevated))
        }
    }

    @ViewBuilder
    func presenceButton(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }

    func presencePanelBackground() -> some View {
        modifier(PresencePanelBackground())
    }

    func presenceSidebarChrome() -> some View {
        modifier(PresenceSidebarChrome())
    }

    func presenceHeroGlow(active: Bool = true) -> some View {
        shadow(
            color: active ? BrandColors.electricBlue.opacity(0.28) : .black.opacity(0.18),
            radius: active ? 28 : 14,
            y: active ? 12 : 8
        )
    }
}

private struct PresenceCardModifier: ViewModifier {
    let capsule: Bool
    let elevated: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, capsule ? 12 : 0)
            .padding(.vertical, capsule ? 8 : 0)
            .background {
                if capsule {
                    Capsule().fill(fill).overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
                } else {
                    RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous)
                        .fill(fill)
                        .overlay(
                            RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous)
                                .strokeBorder(stroke, lineWidth: 1)
                        )
                        .shadow(color: elevated ? .black.opacity(colorScheme == .dark ? 0.35 : 0.08) : .clear, radius: elevated ? 16 : 0, y: elevated ? 6 : 0)
                }
            }
    }

    private var fill: some ShapeStyle {
        if colorScheme == .dark {
            return AnyShapeStyle(Color.white.opacity(elevated ? 0.10 : 0.065))
        }
        return AnyShapeStyle(Color.white.opacity(elevated ? 0.90 : 0.76))
    }

    private var stroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }
}

private struct PresencePanelBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                if colorScheme == .dark {
                    BrandColors.heroBackdropDark
                    LinearGradient(
                        colors: [BrandColors.electricBlue.opacity(0.14), .clear, BrandColors.cyan.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    BrandColors.heroBackdropLight
                    LinearGradient(
                        colors: [BrandColors.cyan.opacity(0.10), .clear, BrandColors.electricBlue.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                Circle()
                    .fill(BrandColors.cyan.opacity(colorScheme == .dark ? 0.10 : 0.07))
                    .frame(width: 260, height: 260)
                    .blur(radius: 50)
                    .offset(x: -130, y: -180)
                Circle()
                    .fill(BrandColors.electricBlue.opacity(colorScheme == .dark ? 0.10 : 0.06))
                    .frame(width: 320, height: 320)
                    .blur(radius: 70)
                    .offset(x: 180, y: 180)
            }
            .ignoresSafeArea()
        }
    }
}

private struct PresenceSidebarChrome: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    if colorScheme == .dark {
                        BrandColors.ink
                    } else {
                        BrandColors.cloud
                    }
                    LinearGradient(
                        colors: [BrandColors.cyan.opacity(0.10), .clear, BrandColors.electricBlue.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .ignoresSafeArea()
            }
    }
}
