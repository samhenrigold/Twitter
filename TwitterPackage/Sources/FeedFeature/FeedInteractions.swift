import ComposableArchitecture
import SwiftUI
import Translation
import TwitterUI

private struct FeedInteractions: ViewModifier {
    /// About how far the system's refresh control is pulled before it triggers.
    private static let refreshTriggerDistance: CGFloat = 80

    @Bindable var store: StoreOf<FeedFeature>
    /// The pull catching, releasing, then the timeline landing: Twitter for iPad's "psst", "psst" and "pop". The
    /// refresh control plays its own haptics.
    @State private var isPastRefreshTrigger = false

    func body(content: Content) -> some View {
        content
            .refreshable {
                ClassicSound.psst2.play()
                await store.send(.refreshPulled).finish()
                ClassicSound.pop.play()
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y < -(geometry.contentInsets.top + Self.refreshTriggerDistance)
            } action: { _, isPast in
                if isPast, !isPastRefreshTrigger { ClassicSound.psst1.play() }
                isPastRefreshTrigger = isPast
            }
            .task { store.send(.task) }
            .alert($store.scope(state: \.alert, action: \.alert))
            .translationPresentation(
                isPresented: Binding {
                    store.translating != nil
                } set: { isPresented in
                    if !isPresented { store.send(.translationDismissed) }
                },
                text: store.translating?.text ?? ""
            )
            .environment(
                \.openURL,
                OpenURLAction { url in
                    store.send(.linkTapped(url))
                    return .handled
                })
    }
}

extension View {
    func feedInteractions(store: StoreOf<FeedFeature>) -> some View {
        modifier(FeedInteractions(store: store))
    }
}
