import UIKit

#if DEBUG
    /// Logs on-screen (presentation) frames of the transitioning views every frame, when COLUMNNAV_TRACE=1.
    @MainActor
    final class TransitionTrace: NSObject {
        private static var current: TransitionTrace?
        private let views: [String: UIView]
        private weak var space: UIView?
        private var link: CADisplayLink?
        private var frameCount = 0

        private init(views: [String: UIView], space: UIView) {
            self.views = views
            self.space = space
        }

        static func start(_ views: [String: UIView], in space: UIView) {
            guard ProcessInfo.processInfo.environment["COLUMNNAV_TRACE"] == "1" else { return }
            current?.link?.invalidate()
            let trace = TransitionTrace(views: views, space: space)
            trace.log()
            trace.link = CADisplayLink(target: trace, selector: #selector(tick))
            trace.link?.add(to: .main, forMode: .common)
            current = trace
        }

        @objc private func tick() {
            frameCount += 1
            log()
            if frameCount > 40 {
                link?.invalidate()
                link = nil
            }
        }

        private func log() {
            guard let space, let spaceLayer = space.layer.presentation() ?? Optional(space.layer) else { return }
            let parts = views.sorted { $0.key < $1.key }.map { name, view -> String in
                let layer = view.layer.presentation() ?? view.layer
                guard view.window != nil else { return "\(name)=offscreen" }
                let r = layer.convert(layer.bounds, to: spaceLayer)
                return "\(name)=(\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height)))"
            }
            print("TRACE \(frameCount) " + parts.joined(separator: " "))
        }
    }
#endif
