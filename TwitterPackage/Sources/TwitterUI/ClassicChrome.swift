import SwiftUI
import UIKit

// Twitter 4.x's chrome, dressed onto the system's own bars so they keep their behavior (back swipe, the folded
// display's side bar, accessibility): Twitter for iPad's silver column bars over the content, and the dark tab bar
// beside it. On iOS 27 the navigation bar is see-through with its items floating over the content, and
// `toolbarBackground` flattens any style to one color, so the bar is drawn as the content's own top bar instead: a
// safe-area bar whose backdrop reaches up behind the navigation bar.

extension View {
    /// Twitter for iPad's column bar behind the navigation bar, with `bar` (a feed switcher, say) on it beneath the
    /// title.
    package func classicTitleBar(@ViewBuilder bar: () -> some View) -> some View {
        modifier(ClassicTitleBar(bar: bar()))
    }

    /// Twitter for iPad's column bar behind the navigation bar.
    package func classicTitleBar() -> some View {
        classicTitleBar { EmptyBarContent() }
    }

    /// Twitter 4.x's tab bar turned on its side, filling the leading and trailing safe areas: where iPhone Duo's side
    /// bar keeps the status bar and the window's own vertical bar. Draws nothing where there are no side insets. Apply
    /// it below the navigation stack's bars (inside its content), so the system's bar items sit on top of it.
    package func classicSideBar() -> some View {
        modifier(ClassicSideBarModifier())
    }

    /// Twitter 4.x's dark tab bar, whatever the app's appearance. Apply inside a tab.
    package func classicTabBar() -> some View {
        background { DarkTabBarChrome().frame(width: 0, height: 0) }
    }
}

private struct ClassicTitleBar<Bar: View>: ViewModifier {
    let bar: Bar
    @Environment(\.classicBarContentTop) private var contentTop

    @Environment(\.classicTitleBarIsBare) private var isBare

    func body(content: Content) -> some View {
        content
            .safeAreaBar(edge: .top) {
                bar
                    .frame(maxWidth: .infinity)
                    // Bare, a bar with nothing in it isn't drawn at all; a switcher keeps a strip of bar of its own.
                    .padding(.top, isBare ? 8 : 0)
                    .background { ClassicColumnBarBackdrop() }
                    .opacity(isBare && Bar.self == EmptyBarContent.self ? 0 : 1)
            }
            // The bar is opaque: content stops at it instead of fading beneath.
            .scrollEdgeEffectHidden(true, for: .top)
            // Where the column says where its bar ends, content starts there rather than below the system's taller
            // navigation bar.
            .safeAreaPadding(.top, contentTop ?? 0)
            .ignoresSafeArea(.container, edges: contentTop != nil ? .top : [])
    }
}

/// A column bar with nothing in it, beneath the navigation bar.
package struct EmptyBarContent: View {
    package var body: some View {
        Color.clear.frame(height: 0)
    }
}

extension EnvironmentValues {
    /// Whether column bars stand alone, with no navigation bar above them (a screen pushed on one stack): an empty
    /// one isn't drawn, and one with content draws just a strip around it.
    @Entry package var classicTitleBarIsBare = false

    /// Whether the window's sidebar carries the screen's "…" menu, so the screen leaves it out of its own bar.
    @Entry package var sidebarCarriesColumnMenu = false

    /// How far below a column's top its content starts, when the column sizes its own bar rather than leaving it to
    /// the system's navigation bar.
    @Entry package var classicBarContentTop: CGFloat? = nil
}

package enum ClassicChrome {

    /// How far past the navigation bar's trailing margin a column's buttons sit, to line up with the content below.
    static let barButtonOutset: CGFloat = 22

    /// The bottom of `bg_tab_bar`'s charcoal gradient.
    package static let tabBarColor = Color(.tabBar)
    /// A tab icon's grey, top to bottom (`ic_tab_home_default`).
    static let embossedGlyph = [Color(.glyphEmbossedTop), Color(.glyphEmbossedBottom)]
    /// A selected tab icon's blue, top to bottom (`ic_tab_home_selected`).
    static let litGlyph = [Color(.glyphLitTop), Color(.glyphLitBottom)]
}

private struct ClassicSideBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    ClassicSideBarFill(hairlineEdge: .trailing)
                        .frame(width: max(proxy.safeAreaInsets.leading, 0))
                        .allowsHitTesting(false)

                    Spacer(minLength: 0)
                        .allowsHitTesting(false)

                    ClassicSideBarFill(hairlineEdge: .leading)
                        .allowsHitTesting(false)
                        .frame(width: max(proxy.safeAreaInsets.trailing, 0))
                }
                .ignoresSafeArea()
            }
        }
    }
}

/// `bg_tab_bar` turned on its side: a black hairline against the content, then charcoal darkening away from it.
private struct ClassicSideBarFill: View {
    let hairlineEdge: HorizontalEdge

    var body: some View {
        let towardContent: UnitPoint = hairlineEdge == .leading ? .leading : .trailing
        let away: UnitPoint = hairlineEdge == .leading ? .trailing : .leading
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: Color(.sideBarEdge), location: 0.02),
                .init(color: ClassicChrome.tabBarColor, location: 1)
            ],
            startPoint: towardContent,
            endPoint: away
        )
        .accessibilityHidden(true)
    }
}

/// `iPad-columnbar-background`, stretched over everything above the content (status bar, navigation bar, and the
/// safe-area bar it backs), keeping its slate bottom edge a point thick, with `iPad-top-shadow` falling onto the content.
/// In dark mode, the same bar in slate.
private struct ClassicColumnBarBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(.columnBarDarkTop),
                        Color(.columnBarDarkBottom)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .overlay(alignment: .bottom) { Color.black.frame(height: 1) }
            } else {
                Image("ColumnBar", bundle: .module)
                    .resizable(capInsets: EdgeInsets(top: 0, leading: 0, bottom: 1, trailing: 0))
            }
        }
        .overlay(alignment: .bottom) {
            Image("ColumnBarShadow", bundle: .module)
                .resizable()
                .frame(height: 16)
                .offset(y: 16)
        }
        // Up behind the navigation bar, and sideways to wherever its items reach (across the fold, say).
        .ignoresSafeArea(edges: [.top, .horizontal])
        .accessibilityHidden(true)
    }
}

/// Twitter for iPad's `iPad-sidebar-shadow`: the long, soft shadow a column casts sideways onto whatever it lies on,
/// from `edge`. A bitmap rather than a blurred shadow, so it costs nothing to move. Overlay it on the column.
package struct ClassicColumnShadow: View {
    let edge: HorizontalEdge

    package init(edge: HorizontalEdge) {
        self.edge = edge
    }

    package var body: some View {
        // 41 pt wide, of which the 5 pt nearest the column sit under it.
        Image("ColumnShadow", bundle: .module)
            .resizable()
            .frame(width: 41)
            .scaleEffect(x: edge == .leading ? 1 : -1)
            .offset(x: edge == .leading ? -36 : 36)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .ignoresSafeArea(edges: .vertical)
    }
}

/// Twitter 4.x's action bar under a post's details (`t1-tweet-details-action-bar`): a shelf across the full width,
/// shading the post above it, with its actions spread evenly along it at 4.x's full size. In dark mode, the same shelf
/// in slate.
package struct ClassicDetailActionBar<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    package init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    package var body: some View {
        HStack(spacing: 0) {
            ForEach(subviews: content) { action in
                action.frame(maxWidth: .infinity)
            }
        }
        .environment(\.engagementIconSize, 24)
        .frame(minHeight: 45)
        // The bitmap's top 3 pt are the shadow it casts upward.
        .padding(.top, 3)
        .background {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [Color(.detailBarDarkTop), Color(.detailBarDarkBottom)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .padding(.top, 3)
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 3)
                }
            } else {
                Image("DetailActionBar", bundle: .module)
                    .resizable(capInsets: EdgeInsets(top: 4, leading: 0, bottom: 1, trailing: 0))
            }
        }
    }
}

/// Twitter 4.x's tab icons: embossed grey, and blue with a glow when selected.
package enum ClassicTabIcon: String {
    case home
    /// Connect: mentions and interactions.
    case at
    /// 4.x had no bookmarks: Twitter's bookmark, drawn the way 4.x drew its tab icons.
    case bookmark
    /// Discover.
    case hash
    case profile

    package func image(isSelected: Bool) -> Image {
        Image("TabIcon-\(rawValue)\(isSelected ? "-selected" : "")", bundle: .module)
            .renderingMode(.original)
    }
}

/// Twitter 4.x's bar glyphs, for bar buttons.
package enum ClassicGlyph: String {
    /// `ic_title_compose`.
    case compose = "GlyphCompose"
    /// `ic_title_action`: a page with an arrow leaving it, for sharing.
    case action = "GlyphAction"
    /// Three dots: the system's, which sit inside a bar button where 4.x's `more` spilled out of it.
    case more

    /// One color, given by the foreground style (see ``ClassicGlyphLabel``).
    package var image: Image {
        switch self {
        case .more: Image(systemName: "ellipsis")
        default: Image(rawValue, bundle: .module).renderingMode(.template)
        }
    }
}

/// A bar button's label: the glyph, with its title for accessibility and the overflow menu. Give its button a
/// ``ClassicBarButtonStyle``.
package struct ClassicGlyphLabel: View {
    let glyph: ClassicGlyph
    let title: LocalizedStringKey

    package init(_ title: LocalizedStringKey, glyph: ClassicGlyph) {
        self.glyph = glyph
        self.title = title
    }

    package var body: some View {
        Label {
            Text(title)
        } icon: {
            glyph.image
        }
    }
}

/// Twitter 4.x's bar buttons, glyphs alone. On a column's silver bar, pressed into it: dark grey with the bar's light on
/// the lip below. On the side bar, embossed the way 4.x's tab icons are: grey darkening downward under a black edge, lit
/// blue while pressed.
package struct ClassicBarButtonStyle: ButtonStyle {
    let isOnSideBar: Bool

    package func makeBody(configuration: Configuration) -> some View {
        ClassicBarButton(configuration: configuration, isOnSideBar: isOnSideBar)
    }
}

extension ButtonStyle where Self == ClassicBarButtonStyle {
    /// A bar button for a column's own bar, or for the side bar beside it.
    package static func classicBar(isOnSideBar: Bool) -> ClassicBarButtonStyle {
        ClassicBarButtonStyle(isOnSideBar: isOnSideBar)
    }
}

private struct ClassicBarButton: View {
    let configuration: ButtonStyle.Configuration
    let isOnSideBar: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let label = configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 15, weight: .bold))
        Group {
            if isOnSideBar {
                label
                    .foregroundStyle(
                        LinearGradient(
                            colors: configuration.isPressed ? ClassicChrome.litGlyph : ClassicChrome.embossedGlyph,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .black.opacity(0.85), radius: 0.5, y: -1)
                    .frame(minWidth: 44, minHeight: 44)
            } else {
                // Pressed into the silver bar: dark grey under a highlight along its lower edge, darker while pressed.
                label
                    .foregroundStyle(Color(.barGlyph).opacity(configuration.isPressed ? 0.6 : 1))
                    // Light catching the lip below in light mode; a shadow pressed under it on the dark bar.
                    .shadow(color: Color(.barGlyphHighlight), radius: 0, y: colorScheme == .dark ? -1 : 1)
                    .frame(width: 30, height: 30)
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
        .contentShape(.rect)
    }
}

/// Darkens the tab bar's chrome and nothing else. Neither SwiftUI's `toolbarColorScheme` nor the tab bar's own
/// interface style reach the glass platter iPhone Duo's side bar draws the tabs on; the platter belongs to the tab bar
/// controller's chrome, which is a sibling of the tabs' content, so its style can be set without touching the content.
private struct DarkTabBarChrome: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Anchor { Anchor() }
    func updateUIViewController(_ controller: Anchor, context: Context) {}

    final class Anchor: UIViewController {
        override func viewIsAppearing(_ animated: Bool) {
            super.viewIsAppearing(animated)
            darkenTabBarChrome()
        }

        // The tab bar controller rebuilds its chrome as the bars change (pushing, folding); keep it dark.
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            darkenTabBarChrome()
        }

        private func darkenTabBarChrome() {
            guard let tabBarController, var chrome = tabBarController.tabBar.superview else { return }
            while let parent = chrome.superview, parent !== tabBarController.view {
                chrome = parent
            }
            if chrome.overrideUserInterfaceStyle != .dark { chrome.overrideUserInterfaceStyle = .dark }
        }
    }
}

extension EnvironmentValues {
    /// Whether this screen is the newest column (or the only screen). iPhone Duo has one side bar for the window, so
    /// only the frontmost column puts its buttons there; the columns behind it keep theirs in their own bars.
    @Entry package var isFrontmostColumn = true
}

extension ToolbarItemPlacement {
    /// The side bar for the frontmost column, which bar buttons favor where there is one; a column behind it keeps its
    /// buttons at the trailing end of its own bar.
    package static func classicSideBar(isFrontmostColumn: Bool) -> ToolbarItemPlacement {
        isFrontmostColumn ? .bottomBar : .topBarTrailing
    }
}
