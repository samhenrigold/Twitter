import UIKit

/// The prototype's live tuning for the column stack.
package final class ColumnDebugPanelViewController: UIViewController {
    private var settings: ColumnSettings { .shared }

    package init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    package override func viewDidLoad() {
        super.viewDidLoad()
        title = "Columns"
        view.backgroundColor = UIColor(resource: .debugPanelBackground)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            })

        let overlay = UISwitch()
        overlay.isOn = settings.showsOverlay
        overlay.addAction(
            UIAction { [weak self] action in
                self?.settings.showsOverlay = (action.sender as? UISwitch)?.isOn ?? false
            }, for: .valueChanged)

        let pinsRoot = UISwitch()
        pinsRoot.isOn = settings.pinsRoot
        pinsRoot.addAction(
            UIAction { [weak self] action in
                self?.settings.pinsRoot = (action.sender as? UISwitch)?.isOn ?? false
            }, for: .valueChanged)

        let overview = UISwitch()
        overview.isOn = settings.overviewEnabled
        overview.addAction(
            UIAction { [weak self] action in
                self?.settings.overviewEnabled = (action.sender as? UISwitch)?.isOn ?? false
            }, for: .valueChanged)

        let backSwipe = UISwitch()
        backSwipe.isOn = settings.cardBackSwipeEnabled
        backSwipe.addAction(
            UIAction { [weak self] action in
                self?.settings.cardBackSwipeEnabled = (action.sender as? UISwitch)?.isOn ?? false
            }, for: .valueChanged)

        let verticalBarItems = UISwitch()
        verticalBarItems.isOn = settings.verticalBarItems
        verticalBarItems.addAction(
            UIAction { [weak self] action in
                self?.settings.verticalBarItems = (action.sender as? UISwitch)?.isOn ?? false
            }, for: .valueChanged)

        let stack = UIStackView(arrangedSubviews: [
            row("Overview (release a root pull partway)", overview),
            row("Focused column's buttons in the Duo's vertical bar", verticalBarItems),
            row("Back swipe on cards (seam / edge pops)", backSwipe),
            row("Pin root (Tweetie sidebar peek)", pinsRoot),
            row("Overlay", overlay),
            slider("Root peek", value: settings.stackInset, range: 0...200) { self.settings.stackInset = $0 },
            slider("Throw friction", value: settings.throwFriction, range: 0.5...0.95) {
                self.settings.throwFriction = $0
            },
            slider("Pop distance", value: settings.popDistance, range: 40...300) { self.settings.popDistance = $0 },
            slider("Throwaway distance", value: settings.throwawayDistance, range: 60...300) {
                self.settings.throwawayDistance = $0
            }
        ])
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -20)
        ])
    }

    private func row(_ title: String, _ control: UIView) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)
        let row = UIStackView(arrangedSubviews: [label, control])
        row.spacing = 12
        return row
    }

    private func slider(
        _ title: String, value: CGFloat, range: ClosedRange<CGFloat>, onChange: @escaping (CGFloat) -> Void
    ) -> UIView {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        let format = { (v: CGFloat) in "\(title): \(String(format: range.upperBound > 10 ? "%.0f" : "%.2f", v))" }
        label.text = format(value)
        let slider = UISlider()
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.value = Float(value)
        slider.addAction(
            UIAction { action in
                guard let slider = action.sender as? UISlider else { return }
                let v = CGFloat(slider.value)
                label.text = format(v)
                onChange(v)
            }, for: .valueChanged)
        let stack = UIStackView(arrangedSubviews: [label, slider])
        stack.axis = .vertical
        stack.spacing = 4
        return stack
    }
}
