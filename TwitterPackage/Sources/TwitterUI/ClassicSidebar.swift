import SwiftUI

/// A tab in ``ClassicSidebar``.
package struct ClassicSidebarTab<ID: Hashable>: Identifiable {
    package let icon: ClassicTabIcon
    package let id: ID
    package let title: LocalizedStringKey

    package init(_ title: LocalizedStringKey, icon: ClassicTabIcon, id: ID) {
        self.icon = icon
        self.id = id
        self.title = title
    }
}

/// Twitter for iPad's sidebar, standing in for the system tab bar: charcoal (`iPad-sidebarbg`) down the trailing edge,
/// with compose and the frontmost column's actions at the top and the tabs at the bottom, each in 4.x's own icons on a
/// dark tile when selected. Collapsed it's a strip of icons; expanded, where there's room beside a lone column, each tab
/// has its name beside it.
package struct ClassicSidebar<ID: Hashable, Actions: View>: View {
    /// The window edge it runs down; the content is on the other side.
    let edge: HorizontalEdge
    let isExpanded: Bool
    let tabs: [ClassicSidebarTab<ID>]
    /// Room left at the top for the status bar, where the system keeps it in the side bar.
    let topInset: CGFloat
    /// How far the content's centre line sits from the sidebar's own: in iPhone Duo's side bar, the status bar is
    /// centred a little in from the display's rounded corner, and the sidebar lines up under it.
    let centerOffset: CGFloat
    @Binding var selection: ID
    /// Compose, unless the window's own vertical bar carries it (see ``View/classicSideBar()``).
    let compose: (() -> Void)?
    let reselect: (ID) -> Void
    @ViewBuilder let actions: Actions

    package init(
        tabs: [ClassicSidebarTab<ID>],
        selection: Binding<ID>,
        edge: HorizontalEdge = .trailing,
        isExpanded: Bool,
        topInset: CGFloat = 0,
        centerOffset: CGFloat = 0,
        compose: (() -> Void)?,
        reselect: @escaping (ID) -> Void,
        @ViewBuilder actions: () -> Actions
    ) {
        self.actions = actions()
        self.compose = compose
        self.edge = edge
        self.isExpanded = isExpanded
        self.reselect = reselect
        _selection = selection
        self.tabs = tabs
        self.topInset = topInset
        self.centerOffset = centerOffset
    }

    /// What the system reserves along the sidebar (``ReservedRegion/Kind/occlusion``): the camera, and the status bar
    /// beside it.
    @State private var occlusion = SidebarOcclusion()

    package var body: some View {
        VStack(spacing: 0) {
            if let compose {
                // Below what the system reserves at the top (the camera and status bar), or the status bar's usual height
                // where nothing is reserved.
                Color.clear.frame(height: max(occlusion.top, topInset))

                // Compose across the top; the screen's own buttons beneath it, side by side when expanded, stacked in
                // the strip.
                VStack(spacing: 12) {
                    Button(action: compose) {
                        ClassicGlyphLabel("New Tweet", glyph: .compose)
                    }
                    .buttonStyle(ClassicComposeButtonStyle(isExpanded: isExpanded))

                    let layout =
                        isExpanded ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 12))
                    layout {
                        actions
                    }
                    .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
                }
                .padding(.top, 12)
            }

            Spacer(minLength: 16)

            VStack(spacing: 6) {
                ForEach(tabs) { tab in
                    ClassicSidebarTabButton(
                        tab: tab,
                        isExpanded: isExpanded,
                        isSelected: tab.id == selection
                    ) {
                        if tab.id == selection {
                            reselect(tab.id)
                        } else {
                            selection = tab.id
                        }
                    }
                }
            }
            .padding(.bottom, 12 + occlusion.bottom)
        }
        // A negative offset moves the content toward the leading edge.
        .padding(.leading, (isExpanded ? 12 : 6) + max(centerOffset, 0) * 2)
        .padding(.trailing, (isExpanded ? 12 : 6) + max(-centerOffset, 0) * 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: SidebarOcclusion.self) { proxy in
            SidebarOcclusion(proxy: proxy)
        } action: {
            occlusion = $0
        }
        .background {
            ClassicSidebarBackground(contentEdge: edge == .trailing ? .leading : .trailing, castsShadow: isExpanded)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Compose, the one action that matters most: the app's blue button (`btn_following`, as Follow is) with the glyph in
/// white, the size of a tab; expanded, it says "New Tweet" beside the glyph and fills the row.
package struct ClassicComposeButtonStyle: ButtonStyle {
    let isExpanded: Bool

    package func makeBody(configuration: Configuration) -> some View {
        Group {
            if isExpanded {
                configuration.label.labelStyle(.titleAndIcon)
            } else {
                configuration.label.labelStyle(.iconOnly)
            }
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.45), radius: 0, y: -1)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(maxWidth: isExpanded ? .infinity : 56, minHeight: 44)
        .background {
            // 11 × 31 pt with rounded ends; the point-wide middle stretches.
            Image("ButtonFollowing", bundle: .module)
                .resizable(capInsets: EdgeInsets(top: 15, leading: 5, bottom: 15, trailing: 5))
        }
        .brightness(configuration.isPressed ? -0.12 : 0)
        .contentShape(.rect)
    }
}

extension ButtonStyle where Self == ClassicComposeButtonStyle {
    /// Compose in the app's blue, with its name beside the glyph when there's room for it.
    package static func classicCompose(isExpanded: Bool) -> ClassicComposeButtonStyle {
        ClassicComposeButtonStyle(isExpanded: isExpanded)
    }
}

private struct ClassicSidebarTabButton<ID: Hashable>: View {
    let tab: ClassicSidebarTab<ID>
    let isExpanded: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                tab.icon.image(isSelected: isSelected)
                    // 4.x's blue glow pooling under the selected icon.
                    .background(alignment: .bottom) {
                        if isSelected {
                            Image("TabGlow", bundle: .module)
                                .offset(y: 8)
                                .accessibilityHidden(true)
                        }
                    }

                if isExpanded {
                    Text(tab.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isSelected ? Color.white : Color(.glyphEmbossedTop))
                        .shadow(color: .black.opacity(0.8), radius: 0, y: -1)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, isExpanded ? 12 : 0)
            .frame(maxWidth: isExpanded ? .infinity : 56, minHeight: 50)
            .background {
                if isSelected {
                    // `bg_tab_bar_selected`: a dark tile pressed into the bar.
                    Image("TabSelected", bundle: .module)
                        .resizable()
                        .clipShape(.rect(cornerRadius: 6))
                        .shadow(color: .white.opacity(0.08), radius: 0, y: 1)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// `iPad-sidebarbg` with a black edge against the content, casting Twitter for iPad's column shadow onto it when expanded.
private struct ClassicSidebarBackground: View {
    let contentEdge: HorizontalEdge
    /// Expanded, it's a panel lying over the backdrop; collapsed it's the side bar's own strip, casting nothing.
    let castsShadow: Bool

    var body: some View {
        let alignment: Alignment = contentEdge == .leading ? .leading : .trailing
        // A texture, so tiled at its own size rather than stretched to the sidebar's.
        Image("SidebarBackground", bundle: .module)
            .resizable(resizingMode: .tile)
            .overlay(alignment: alignment) {
                Color.black.frame(width: 1)
            }
            .overlay(alignment: alignment) {
                if castsShadow {
                    ClassicColumnShadow(edge: contentEdge)
                }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

extension EnvironmentValues {
    /// Whether the window has a ``ClassicSidebar``, which carries compose; columns keep their own menus in their bars.
    @Entry package var hasClassicSidebar = false
}

/// A column's "…" menu, in 4.x's bar button: on the side bar for the frontmost column, on its own bar otherwise.
package struct ClassicColumnMenu<Items: View>: View {
    let glyph: ClassicGlyph
    let isOnSideBar: Bool
    let title: LocalizedStringKey
    @ViewBuilder let items: Items

    package init(
        _ title: LocalizedStringKey,
        glyph: ClassicGlyph = .more,
        isOnSideBar: Bool,
        @ViewBuilder items: () -> Items
    ) {
        self.glyph = glyph
        self.isOnSideBar = isOnSideBar
        self.items = items()
        self.title = title
    }

    package var body: some View {
        Menu {
            items
        } label: {
            ClassicGlyphLabel(title, glyph: glyph)
        }
        .menuStyle(.button)
        .buttonStyle(.classicBar(isOnSideBar: isOnSideBar))
    }
}

/// A column's "…" menu, in its own bar.
package struct ClassicColumnMenuToolbarItem<Items: View>: ToolbarContent {
    let glyph: ClassicGlyph
    let hasClassicSidebar: Bool
    let isFrontmostColumn: Bool
    let title: LocalizedStringKey
    let items: Items

    package init(
        _ title: LocalizedStringKey,
        glyph: ClassicGlyph = .more,
        isFrontmostColumn: Bool,
        hasClassicSidebar: Bool,
        @ViewBuilder items: () -> Items
    ) {
        self.glyph = glyph
        self.hasClassicSidebar = hasClassicSidebar
        self.isFrontmostColumn = isFrontmostColumn
        self.items = items()
        self.title = title
    }

    package var body: some ToolbarContent {
        // Always in its own bar: every column carries its own, wherever it is in the stack.
        ToolbarItem(placement: .topBarTrailing) {
            ClassicColumnButtons {
                ClassicColumnMenu(title, glyph: glyph, isOnSideBar: false) {
                    items
                }
            }
        }
        .sharedBackgroundVisibility(.hidden)
        // The button carries its own padding; the bar's would space the column's buttons apart.
        .contentMarginsRemoved()
    }
}

/// A column's bar buttons, out to the content's edge (the switcher's below), past the margin the bar keeps for its own
/// glass items.
package struct ClassicColumnButtons<Content: View>: View {
    @ViewBuilder let content: Content

    package init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    package var body: some View {
        HStack(spacing: 6) {
            content
        }
        .padding(.trailing, -ClassicChrome.barButtonOutset)
    }
}

/// How far the display's occlusions (the camera) reach into the sidebar from its top and bottom.
private struct SidebarOcclusion: Equatable {
    var bottom: CGFloat = 0
    var top: CGFloat = 0

    init() {}

    init(proxy: GeometryProxy) {
        let height = proxy.size.height
        // Anywhere along the sidebar's edge of the window: the region may sit past a collapsed sidebar's narrow frame.
        for region in proxy.reservedRegions(kind: .occlusion) {
            if region.frame.midY < height / 2 {
                top = max(top, region.frame.maxY + region.margins.bottom)
            } else {
                bottom = max(bottom, height - region.frame.minY + region.margins.top)
            }
        }
    }
}
