// Columns that offer their bar buttons to the Duo's vertical bar. The navigation controller hosts the focused
// column's buttons there (through its toolbar, whose items the vertical bar takes when it's present), and the
// column drops them from its own bar meanwhile.
//

import UIKit

@MainActor
package protocol ColumnBarItemProviding: UIViewController {
    /// A fresh set of the column's bar buttons (a bar button item can only be in one bar at a time). Give them
    /// identifiers: the vertical bar matches buttons by identifier and routes taps through `performColumnBarAction`.
    func makeColumnBarItems() -> [UIBarButtonItem]
    /// The button with `identifier` was tapped in the vertical bar while this column was focused.
    func performColumnBarAction(_ identifier: String)
    /// Whether the column's own bar shows its buttons (false while they're in the vertical bar).
    func setColumnBarItemsShown(_ shown: Bool)
}
