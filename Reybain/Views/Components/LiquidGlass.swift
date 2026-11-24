// Reybain - LiquidGlass.swift
// Reusable iOS 26 Liquid Glass & Apple Intelligence components with iOS 17–25 fallbacks.

import SwiftUI

// MARK: - 1. LiquidGlassCard (Modifier + Container)

enum LiquidGlassStyle {
    /// Floating functional chrome (composer, playback bar, floating header pills).
    case chrome
    /// Editorial content surface on OLED obsidian (cards, checklists, activity cards).
    case surface
    /// Highlighted surface with subtle brand tint.
    case tinted(Color)
}

struct LiquidGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = Theme.Radius.card
    var style: LiquidGlassStyle = .chrome
    var interactive: Bool = false
    var showSpecularRim: Bool = true

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if reduceTransparency {
            content
                .background(solidFallbackFill, in: shape)
                .overlay(shape.strokeBorder(Theme.bgElevatedStroke, lineWidth: 1))
        } else {
            glassSurface(content: content, shape: shape)
        }
    }

    @ViewBuilder
    private func glassSurface(content: Content, shape: RoundedRectangle) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), case .chrome = style {
            content
                .glassEffect(makeChromeGlass(), in: shape)
                .overlay(specularOverlay(shape: shape))
        } else if #available(iOS 26.0, *), case .tinted(let tint) = style {
            content
                .glassEffect(makeTintedGlass(tint), in: shape)
                .overlay(specularOverlay(shape: shape))
        } else {
            fallbackMaterialSurface(content: content, shape: shape)
        }
        #else
        fallbackMaterialSurface(content: content, shape: shape)
        #endif
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private func makeChromeGlass() -> Glass {
        interactive ? Glass.regular.interactive() : Glass.regular
    }

    @available(iOS 26.0, *)
    private func makeTintedGlass(_ tint: Color) -> Glass {
        let base = Glass.regular.tint(tint.opacity(0.28))
        return interactive ? base.interactive() : base
    }
    #endif

    @ViewBuilder
    private func fallbackMaterialSurface(content: Content, shape: RoundedRectangle) -> some View {
        content
            .background {
                ZStack {
                    switch style {
                    case .chrome:
                        shape.fill(.ultraThinMaterial)
                        shape.fill(Theme.glass)
                    case .surface:
                        shape.fill(Theme.bgCard.opacity(0.94))
                    case .tinted(let tint):
                        shape.fill(.ultraThinMaterial)
                        shape.fill(Theme.bgElevated.opacity(0.72))
                        shape.fill(tint.opacity(0.14))
                    }

                    // Soft top inner sheen simulating curved glass refraction
                    shape.fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                }
            }
            .overlay(specularOverlay(shape: shape))
            .shadow(color: Color.black.opacity(0.42), radius: 16, x: 0, y: 8)
    }

    @ViewBuilder
    private func specularOverlay(shape: RoundedRectangle) -> some View {
        if showSpecularRim {
            shape.strokeBorder(rimStrokeStyle, lineWidth: 0.85)
                .allowsHitTesting(false)
        }
    }

    private var rimStrokeStyle: AnyShapeStyle {
        switch style {
        case .tinted(let tint):
            return AnyShapeStyle(
                LinearGradient(
                    colors: [tint.opacity(0.55), Theme.specularTop, tint.opacity(0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .chrome:
            return AnyShapeStyle(Theme.specularRimGradient)
        case .surface:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.white.opacity(0.16), Color.white.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    private var solidFallbackFill: Color {
        switch style {
        case .chrome: return Theme.bgElevated
        case .surface: return Theme.bgCard
        case .tinted: return Theme.bgCardHighlight
        }
    }
}

struct LiquidGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = Theme.Radius.card
    var style: LiquidGlassStyle = .chrome
    var interactive: Bool = false
    let content: Content

    init(
        cornerRadius: CGFloat = Theme.Radius.card,
        style: LiquidGlassStyle = .chrome,
        interactive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.style = style
        self.interactive = interactive
        self.content = content()
    }

    var body: some View {
        content.modifier(
            LiquidGlassCardModifier(
                cornerRadius: cornerRadius,
                style: style,
                interactive: interactive
            )
        )
    }
}

extension View {
    func liquidGlassCard(
        cornerRadius: CGFloat = Theme.Radius.card,
        style: LiquidGlassStyle = .chrome,
        interactive: Bool = false
    ) -> some View {
        modifier(
            LiquidGlassCardModifier(
                cornerRadius: cornerRadius,
                style: style,
                interactive: interactive
            )
        )
    }
}

// MARK: - 2. LiquidGlassPill (Capsule Chrome for Chips, Toolbars & Composer)

struct LiquidGlassPillModifier: ViewModifier {
    var tint: Color? = nil
    var interactive: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(
                    Capsule().fill(tint.map { $0.opacity(0.24) } ?? Theme.bgElevated)
                )
                .overlay(
                    Capsule().strokeBorder(tint?.opacity(0.55) ?? Theme.bgElevatedStroke, lineWidth: 1)
                )
        } else {
            pillSurface(content: content)
        }
    }

    @ViewBuilder
    private func pillSurface(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(makePillGlass(), in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(pillStrokeStyle, lineWidth: 0.8)
                        .allowsHitTesting(false)
                )
        } else {
            fallbackPill(content: content)
        }
        #else
        fallbackPill(content: content)
        #endif
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private func makePillGlass() -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint.opacity(0.26)) }
        if interactive { glass = glass.interactive() }
        return glass
    }
    #endif

    private var pillStrokeStyle: AnyShapeStyle {
        if let tint {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [tint.opacity(0.58), Theme.specularTop, tint.opacity(0.16)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(Theme.specularRimGradient)
    }

    private func fallbackPill(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(tint.map { $0.opacity(0.16) } ?? Theme.glass)
                    Capsule().fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.10), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .overlay(
                Capsule()
                    .strokeBorder(pillStrokeStyle, lineWidth: 0.85)
                    .allowsHitTesting(false)
            )
            .shadow(color: Color.black.opacity(0.32), radius: 10, x: 0, y: 4)
    }
}

struct LiquidGlassPill<Content: View>: View {
    var tint: Color? = nil
    var interactive: Bool = false
    let content: Content

    init(
        tint: Color? = nil,
        interactive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.interactive = interactive
        self.content = content()
    }

    var body: some View {
        content.modifier(LiquidGlassPillModifier(tint: tint, interactive: interactive))
    }
}

extension View {
    func liquidGlassPill(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(LiquidGlassPillModifier(tint: tint, interactive: interactive))
    }
}

// MARK: - 3. AppleIntelligenceGlow (Iridescent Active-State Halo)

struct AppleIntelligenceGlowModifier: ViewModifier {
    var isActive: Bool
    var cornerRadius: CGFloat = Theme.Radius.composer
    var lineWidth: CGFloat = 1.6
    var glowRadius: CGFloat = 8
    var colors: [Color] = Theme.intelligenceColors

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .overlay {
                if isActive {
                    TimelineView(.animation(paused: !isActive || reduceMotion)) { timeline in
                        let degrees = reduceMotion
                            ? 35.0
                            : (timeline.date.timeIntervalSinceReferenceDate * 72.0)
                                .truncatingRemainder(dividingBy: 360.0)
                        let gradient = AngularGradient(
                            colors: colors,
                            center: .center,
                            angle: .degrees(degrees)
                        )

                        ZStack {
                            // Soft diffused outer aura
                            shape
                                .strokeBorder(gradient, lineWidth: lineWidth + 2.5)
                                .blur(radius: glowRadius)
                                .opacity(0.62)

                            // Crisp iridescent hairline border
                            shape
                                .strokeBorder(gradient, lineWidth: lineWidth)
                                .opacity(0.95)
                        }
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
    }
}

extension View {
    /// Wraps a floating control or active card in an Apple Intelligence iridescent shimmer.
    func appleIntelligenceGlow(
        isActive: Bool,
        cornerRadius: CGFloat = Theme.Radius.composer,
        lineWidth: CGFloat = 1.6,
        glowRadius: CGFloat = 8,
        colors: [Color] = Theme.intelligenceColors
    ) -> some View {
        modifier(
            AppleIntelligenceGlowModifier(
                isActive: isActive,
                cornerRadius: cornerRadius,
                lineWidth: lineWidth,
                glowRadius: glowRadius,
                colors: colors
            )
        )
    }
}

// MARK: - 4. LiquidGlassFloatingTabBar (Custom Floating Dock for MainTabView)

struct LiquidGlassFloatingTabBar: View {
    @Binding var selectedTab: MainTabView.Tab
    var isLiveActive: Bool = false

    @Namespace private var selectionNamespace
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        dockContainer {
            HStack(spacing: 4) {
                ForEach(MainTabView.Tab.allCases, id: \.self) { tab in
                    tabButton(for: tab)
                }
            }
            .padding(5)
        }
        .padding(.horizontal, 28)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func dockContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), !reduceTransparency {
            GlassEffectContainer(spacing: 6) {
                content()
                    .glassEffect(Glass.regular.interactive(), in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Theme.specularRimGradient, lineWidth: 0.85)
                            .allowsHitTesting(false)
                    )
                    .shadow(color: Color.black.opacity(0.45), radius: 18, x: 0, y: 10)
            }
        } else {
            fallbackDock(content: content)
        }
        #else
        fallbackDock(content: content)
        #endif
    }

    private func fallbackDock<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .liquidGlassPill(interactive: true)
            .shadow(color: Color.black.opacity(0.50), radius: 20, x: 0, y: 10)
    }

    private func tabButton(for tab: MainTabView.Tab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            guard selectedTab != tab else { return }
            HapticFeedback.selection()
            withAnimation(Theme.Motion.snappy) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 16, weight: isSelected ? .semibold : .medium))
                        .symbolRenderingMode(.hierarchical)

                    // Subtle live pulse dot on the Live tab when a session is running in background
                    if tab == .live && isLiveActive && !isSelected {
                        Circle()
                            .fill(Theme.iridescentCyan)
                            .frame(width: 6, height: 6)
                            .offset(x: 4, y: -2)
                    }
                }

                Text(tab.rawValue)
                    .font(.caption.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .contentShape(Capsule())
            .background {
                if isSelected {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Theme.iridescentIndigo.opacity(0.42),
                                    Theme.iridescentCyan.opacity(0.24)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Theme.specularTop, Theme.iridescentCyan.opacity(0.30)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.75
                                )
                        )
                        .matchedGeometryEffect(id: "activeTabPill", in: selectionNamespace)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - 5. SettingsIconBadge & Obsidian Settings Chrome

struct SettingsIconBadge: View {
    let icon: String
    let tint: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous)
                            .strokeBorder(tint.opacity(0.32), lineWidth: 0.75)
                    )
            )
    }
}

extension View {
    /// Applies unified obsidian card row styling inside Settings `Form` and `List` sections.
    func reybainSettingsRow() -> some View {
        self
            .listRowBackground(Theme.bgCard)
            .listRowSeparatorTint(Color.white.opacity(0.08))
    }

    /// Wraps a Settings `Form` or `List` in the calibrated OLED obsidian backdrop with hidden scroll chrome.
    func reybainSettingsCanvas() -> some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            self
                .scrollContentBackground(.hidden)
        }
        .tint(Theme.accent)
    }
}
