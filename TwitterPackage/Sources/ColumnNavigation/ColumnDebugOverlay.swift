// Draws column frames, scroll stop points, and iPhone Duo reserved regions.
//

import UIKit

final class ColumnDebugOverlay: UIView {
    private var columnFrames: [CGRect] = []
    private var stopMarkers: [CGFloat] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// - Parameter stopMarkers: x of the top column's leading edge at each scroll stop.
    func update(frames: [CGRect], stopMarkers: [CGFloat], in host: UIView) {
        columnFrames = frames
        self.stopMarkers = stopMarkers
        host.bringSubviewToFront(self)
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        for region in reservedRegions(kind: .division, options: .includeInactive) {
            (region.isActive ? UIColor.systemRed : UIColor.systemRed.withAlphaComponent(0.3)).withAlphaComponent(0.25)
                .setFill()
            context.fill(region.frame)
        }
        for region in reservedRegions(kind: .occlusion, options: .includeInactive) {
            UIColor.systemOrange.withAlphaComponent(region.isActive ? 0.35 : 0.12).setFill()
            context.fill(region.frame)
        }

        for (index, frame) in columnFrames.enumerated() {
            let color = UIColor(hue: CGFloat(index) * 0.17, saturation: 0.8, brightness: 0.85, alpha: 1)
            color.setStroke()
            let path = UIBezierPath(rect: frame.insetBy(dx: 1.5, dy: 1.5))
            path.lineWidth = 3
            path.stroke()
            let label = "\(index)  \(Int(frame.width))pt" as NSString
            label.draw(
                at: CGPoint(x: frame.minX + 8, y: bounds.maxY - 54),
                withAttributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: color
                ])
        }

        // Stop points: where the top column's leading edge rests at each stop.
        UIColor.systemPink.setFill()
        for x in stopMarkers {
            context.fill(CGRect(x: x - 1, y: bounds.maxY - 30, width: 2, height: 22))
        }
    }
}
