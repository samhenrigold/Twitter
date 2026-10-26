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

    /// A color per column, cycling.
    private static let columnColors: [ColorResource] = [
        .debugColumn0, .debugColumn1, .debugColumn2, .debugColumn3, .debugColumn4, .debugColumn5
    ]

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        for region in reservedRegions(kind: .division, options: .includeInactive) {
            UIColor(resource: .debugDivision).setFill()
            context.fill(region.frame)
        }
        for region in reservedRegions(kind: .occlusion, options: .includeInactive) {
            UIColor(resource: region.isActive ? .debugOcclusionActive : .debugOcclusionInactive).setFill()
            context.fill(region.frame)
        }

        for (index, frame) in columnFrames.enumerated() {
            let color = UIColor(resource: Self.columnColors[index % Self.columnColors.count])
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
        UIColor(resource: .debugStopMarker).setFill()
        for x in stopMarkers {
            context.fill(CGRect(x: x - 1, y: bounds.maxY - 30, width: 2, height: 22))
        }
    }
}
