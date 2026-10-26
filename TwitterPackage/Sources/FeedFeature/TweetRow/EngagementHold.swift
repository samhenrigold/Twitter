import SwiftUI

extension View {
    /// Held rather than tapped, an action button does something else, as Twitter's do: who liked or retweeted the
    /// Tweet, or opening it in the Twitter app. The hold wins over the button's tap, so letting go doesn't also tap it.
    /// Nothing happens on hold when `action` is nil.
    func onHold(_ name: LocalizedStringKey, perform action: (() -> Void)?) -> some View {
        modifier(EngagementHold(name: name, action: action))
    }
}

private struct EngagementHold: ViewModifier {
    let name: LocalizedStringKey
    let action: (() -> Void)?
    @State private var holds = 0

    func body(content: Content) -> some View {
        if let action {
            content
                // Quicker than the row's context menu, which otherwise takes the press (on iPad at 0.35 s already).
                .highPriorityGesture(
                    LongPressGesture(minimumDuration: 0.25).onEnded { _ in
                        holds += 1
                        action()
                    }
                )
                .sensoryFeedback(.impact(weight: .medium), trigger: holds)
                .accessibilityAction(named: Text(name), action)
        } else {
            content
        }
    }
}
