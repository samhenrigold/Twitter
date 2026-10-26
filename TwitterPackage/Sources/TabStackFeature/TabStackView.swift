import ColumnNavigation
import ComposableArchitecture
import SwiftUI

/// A tab's navigation in a window of its own (one opened from "Open in New Window"); see ``TabStackController``.
package struct TabStackView: UIViewControllerRepresentable {
    let store: StoreOf<TabStack>
    let title: LocalizedStringKey

    package init(store: StoreOf<TabStack>, title: LocalizedStringKey) {
        self.store = store
        self.title = title
    }

    package func makeCoordinator() -> TabStackController {
        TabStackController(store: store, title: title)
    }

    package func makeUIViewController(context: Context) -> ColumnNavigationController {
        context.coordinator.navigationController
    }

    package func updateUIViewController(_ controller: ColumnNavigationController, context: Context) {}
}
