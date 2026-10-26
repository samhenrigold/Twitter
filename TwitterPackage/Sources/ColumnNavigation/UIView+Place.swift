import UIKit

extension UIView {
    /// Sets geometry through bounds and center and assigns the transform once (inside an animation block, one
    /// animation per property; resetting the transform to identity first would queue competing transform
    /// animations, which Core Animation flags on Liquid Glass layers underneath).
    func place(in frame: CGRect, transform: CGAffineTransform) {
        bounds.size = frame.size
        center = CGPoint(x: frame.midX, y: frame.midY)
        if self.transform != transform { self.transform = transform }
    }
}
