import SwiftUI

extension View {
    func presenceCard(capsule: Bool = false, elevated: Bool = false) -> some View {
        modifier(PresenceCardModifier(capsule: capsule, elevated: elevated))
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
        modifier(PresenceHeroGlowModifier(active: active))
    }
}

private struct PresenceHeroGlowModifier: ViewModifier {
    let active: Bool
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content.shadow(
            color: active ? theme.primaryColor.opacity(0.28) : .black.opacity(0.18),
            radius: active ? 28 : 14,
            y: active ? 12 : 8
        )
    }
}

private struct PresenceCardModifier: ViewModifier {
    let capsule: Bool
    let elevated: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            if capsule {
                content
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(theme.surface(for: colorScheme)))
                    .glassEffect(.regular.tint(theme.primaryColor.opacity(0.07)), in: .capsule)
            } else {
                content
                    .background(
                        RoundedRectangle(cornerRadius: elevated ? BrandRadius.lg : BrandRadius.md, style: .continuous)
                            .fill(theme.surface(for: colorScheme, elevated: elevated))
                    )
                    .glassEffect(
                        .regular.tint(theme.primaryColor.opacity(elevated ? 0.07 : 0.04)),
                        in: .rect(cornerRadius: elevated ? BrandRadius.lg : BrandRadius.md)
                    )
                    .shadow(color: elevated ? .black.opacity(colorScheme == .dark ? 0.24 : 0.08) : .clear, radius: elevated ? 16 : 0, y: elevated ? 7 : 0)
            }
        } else {
            content
                .padding(.horizontal, capsule ? 12 : 0)
                .padding(.vertical, capsule ? 8 : 0)
                .background {
                    if capsule {
                        Capsule().fill(fill).overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
                    } else {
                        RoundedRectangle(cornerRadius: elevated ? BrandRadius.lg : BrandRadius.md, style: .continuous)
                            .fill(fill)
                            .overlay(
                                RoundedRectangle(cornerRadius: elevated ? BrandRadius.lg : BrandRadius.md, style: .continuous)
                                    .strokeBorder(stroke, lineWidth: 1)
                            )
                            .shadow(color: elevated ? .black.opacity(colorScheme == .dark ? 0.24 : 0.08) : .clear, radius: elevated ? 16 : 0, y: elevated ? 7 : 0)
                    }
                }
        }
    }

    private var fill: some ShapeStyle {
        AnyShapeStyle(theme.surface(for: colorScheme, elevated: elevated))
    }

    private var stroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }
}

private struct PresencePanelBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                if colorScheme == .dark {
                    LinearGradient(colors: [theme.darkBackground, theme.darkBackground.opacity(0.92), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                    LinearGradient(
                        colors: [theme.primaryColor.opacity(0.14), .clear, theme.secondaryColor.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    LinearGradient(colors: [theme.lightBackground, .white.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    LinearGradient(
                        colors: [theme.secondaryColor.opacity(0.10), .clear, theme.primaryColor.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                Circle()
                    .fill(theme.secondaryColor.opacity(colorScheme == .dark ? 0.10 : 0.07))
                    .frame(width: 260, height: 260)
                    .blur(radius: 50)
                    .offset(x: -130, y: -180)
                Circle()
                    .fill(theme.primaryColor.opacity(colorScheme == .dark ? 0.10 : 0.06))
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
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    if colorScheme == .dark {
                        theme.darkBackground
                    } else {
                        theme.lightBackground
                    }
                    LinearGradient(
                        colors: [theme.secondaryColor.opacity(0.10), .clear, theme.primaryColor.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .ignoresSafeArea()
            }
    }
}
