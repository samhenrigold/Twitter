// Private UINavigationController overrides, installed on ColumnNavigationController only.
// Each hook calls UIKit's original implementation first, so compact width (and anything
// we don't special-case) stays stock behavior.
//
// - _frameForWrapperViewForViewController:  where the top VC's wrapper sits (nav view coords)
// - _frameForViewController:                the top VC's view inside its wrapper (wrapper coords)
// - _positionNavigationBarHidden:edge:initialOffset:  re-centers the system bar over the top column
//

import ObjectiveC
import UIKit

@MainActor
enum NavigationControllerHooks {
    static func installIfNeeded() {
        _ = installed
    }

    private static let installed: Bool = {
        hookRect("_frameForWrapperViewForViewController:") { nav, viewController, base in
            nav.columnFrameForTopWrapper(of: viewController) ?? base
        }
        hookRect("_frameForViewController:") { nav, viewController, base in
            nav.columnFrameForTopView(of: viewController) ?? base
        }
        hookPositionNavigationBar()
        return true
    }()

    /// Makes one view instance transparent to touches that land on it directly (touches on its subviews still hit).
    /// The navigation transition view spans the whole container but only hosts the top column; without this it
    /// swallows taps meant for leading columns underneath it. Done by isa-swizzling to a runtime subclass.
    static func makeTouchTransparent(_ view: UIView) {
        guard let base = object_getClass(view) else { return }
        let name = "ColumnNavPassthrough_\(NSStringFromClass(base))"
        guard !NSStringFromClass(base).hasPrefix("ColumnNavPassthrough_") else { return }
        let subclass: AnyClass
        if let existing = NSClassFromString(name) {
            subclass = existing
        } else {
            guard let created = objc_allocateClassPair(base, name, 0),
                let method = class_getInstanceMethod(base, #selector(UIView.hitTest(_:with:)))
            else { return }
            let selector = #selector(UIView.hitTest(_:with:))
            typealias Original = @convention(c) (AnyObject, Selector, CGPoint, UIEvent?) -> UIView?
            let original = unsafeBitCast(method_getImplementation(method), to: Original.self)
            let block: @convention(block) (AnyObject, CGPoint, UIEvent?) -> UIView? = { object, point, event in
                let hit = original(object, selector, point, event)
                return hit === object ? nil : hit
            }
            class_addMethod(created, selector, imp_implementationWithBlock(block), method_getTypeEncoding(method))
            objc_registerClassPair(created)
            subclass = created
        }
        object_setClass(view, subclass)
    }

    private static func hookRect(
        _ name: String, _ body: @escaping (ColumnNavigationController, UIViewController, CGRect) -> CGRect
    ) {
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(UINavigationController.self, selector) else {
            print("ColumnNav: missing private selector \(name)")
            return
        }
        typealias Original = @convention(c) (AnyObject, Selector, AnyObject) -> CGRect
        let original = unsafeBitCast(method_getImplementation(method), to: Original.self)
        let block: @convention(block) (AnyObject, AnyObject) -> CGRect = { object, argument in
            let base = original(object, selector, argument)
            guard let nav = object as? ColumnNavigationController, let viewController = argument as? UIViewController
            else { return base }
            return body(nav, viewController, base)
        }
        class_addMethod(
            ColumnNavigationController.self, selector, imp_implementationWithBlock(block),
            method_getTypeEncoding(method))
    }

    private static func hookPositionNavigationBar() {
        let selector = NSSelectorFromString("_positionNavigationBarHidden:edge:initialOffset:")
        guard let method = class_getInstanceMethod(UINavigationController.self, selector) else {
            print("ColumnNav: missing private selector _positionNavigationBarHidden:edge:initialOffset:")
            return
        }
        typealias Original = @convention(c) (AnyObject, Selector, Bool, UInt, CGFloat) -> Void
        let original = unsafeBitCast(method_getImplementation(method), to: Original.self)
        let block: @convention(block) (AnyObject, Bool, UInt, CGFloat) -> Void = { object, hidden, edge, offset in
            original(object, selector, hidden, edge, offset)
            (object as? ColumnNavigationController)?.positionNavigationBarOverTopColumn()
        }
        class_addMethod(
            ColumnNavigationController.self, selector, imp_implementationWithBlock(block),
            method_getTypeEncoding(method))
    }
}
