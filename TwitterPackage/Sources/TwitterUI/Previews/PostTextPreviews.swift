import PostText
import Routing
import SwiftUI

extension Text {
    /// The typeset text, with each entity's run (a mention, hashtag, cashtag or link) tagged by an ``EntityRun``
    /// attribute so its glyphs can be found in the text's layout. Text without entities is a single attributed `Text`.
    init(entitiesTaggedIn typeset: TypesetPostText) {
        guard typeset.hasEntities else {
            self.init(typeset.attributedString)
            return
        }
        // A custom attribute belongs to a whole `Text`, so the string is joined from one `Text` per segment. The
        // format is nothing but placeholders ("%@%@…"), so the lookup finds no translation and adds no characters.
        var interpolation = LocalizedStringKey.StringInterpolation(
            literalCapacity: 0, interpolationCount: typeset.segments.count)
        for (index, segment) in typeset.segments.enumerated() {
            let text = Text(segment.text)
            interpolation.appendInterpolation(
                segment.entity == nil ? text : text.customAttribute(EntityRun(index: index)))
        }
        self.init(LocalizedStringKey(stringInterpolation: interpolation))
    }
}

/// Marks the glyph runs of one entity in a laid-out `Text`; `index` is its segment in ``TypesetPostText/segments``.
struct EntityRun: TextAttribute {
    let index: Int
}

extension EnvironmentValues {
    /// Off where text isn't interactive, such as inside a preview or a card that is one big button.
    @Entry package var postTextPreviewsEnabled = true
}

/// Long-pressing a mention, hashtag, cashtag or link in post text lifts it with a preview and menu, as Twitter's
/// status body does for its active ranges (`bodyTextView:previewConfigurationForActiveTextRange:`).
///
/// SwiftUI can't attach a context menu to part of a `Text`, so the entities' glyph rects are read from the text's
/// layout (`Text.LayoutKey`, matched through ``EntityRun``) and a transparent UIKit layer over the text claims
/// touches only inside them. Elsewhere touches fall through to the row underneath, including the row's own context
/// menu. Text without entities adds nothing.
struct PostTextPreviews: ViewModifier {
    let typeset: TypesetPostText
    @Environment(\.postTextPreviewsEnabled) private var isEnabled

    func body(content: Content) -> some View {
        if typeset.hasEntities, isEnabled {
            content.overlayPreferenceValue(Text.LayoutKey.self) { layouts in
                GeometryReader { proxy in
                    EntityInteractionLayer(targets: Self.targets(in: typeset, layouts: layouts, proxy: proxy))
                }
            }
        } else {
            content
        }
    }

    /// Each entity's rects, one per line it lands on, in the overlay's coordinates.
    @MainActor static func targets(
        in typeset: TypesetPostText, layouts: Text.LayoutKey.Value, proxy: GeometryProxy
    ) -> [EntityTarget] {
        var rects: [Int: [CGRect]] = [:]
        for anchored in layouts {
            let origin = proxy[anchored.origin]
            for line in anchored.layout {
                var lineRects: [Int: CGRect] = [:]
                for run in line {
                    guard let index = run[EntityRun.self]?.index else { continue }
                    let rect = run.typographicBounds.rect.offsetBy(dx: origin.x, dy: origin.y)
                    lineRects[index] = lineRects[index]?.union(rect) ?? rect
                }
                for (index, rect) in lineRects {
                    rects[index, default: []].append(rect)
                }
            }
        }
        return rects.sorted { $0.key < $1.key }.compactMap { index, rects in
            typeset.segments[index].entity.map { EntityTarget(index: index, entity: $0, rects: rects) }
        }
    }
}

private struct EntityInteractionLayer: UIViewRepresentable {
    let targets: [EntityTarget]
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    func makeUIView(context: Context) -> EntityInteractionView {
        EntityInteractionView()
    }

    func updateUIView(_ view: EntityInteractionView, context: Context) {
        view.targets = targets
        let openURL = openURL
        view.open = { openURL($0) }
        let openWindow = openWindow
        view.openWindow = supportsMultipleWindows ? { openWindow(value: $0.window) } : nil
    }
}
