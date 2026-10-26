import UIKit

final class ColumnTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private weak var controller: ColumnNavigationController?

    init(controller: ColumnNavigationController) {
        self.controller = controller
    }

    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        0.4
    }

    func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {
        guard let controller else {
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            return
        }
        controller.runColumnTransition(transitionContext)
    }
}
