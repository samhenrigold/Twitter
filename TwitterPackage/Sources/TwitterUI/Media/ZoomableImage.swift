import AVFoundation
import SwiftUI
import UIKit

/// A photo that pinches and double-taps to zoom like Photos: decelerating pans, rubber-banding, and a zoomed photo
/// that pans to its edge before the pager around it takes over. SwiftUI has no zooming scroll view, so this wraps
/// `UIScrollView`.
struct ZoomableImage: UIViewRepresentable {
    let image: CGImage
    /// Whether this is the page in view; one scrolled away goes back to 1x.
    let isSelected: Bool
    @Binding var isZoomed: Bool
    let onSingleTap: () -> Void

    func makeUIView(context: Context) -> ZoomingScrollView {
        let view = ZoomingScrollView()
        view.setImage(UIImage(cgImage: image))
        return view
    }

    func updateUIView(_ view: ZoomingScrollView, context: Context) {
        // The larger decode has the same aspect ratio, so swapping it keeps the zoom scale and offset.
        view.setImage(UIImage(cgImage: image))
        view.onSingleTap = onSingleTap
        view.onZoomChange = { zoomed in
            if isZoomed != zoomed { isZoomed = zoomed }
        }
        if !isSelected, view.zoomScale > view.minimumZoomScale {
            // The pager resets `isZoomed` itself; reporting this reset would write the binding mid-update.
            let reportZoomChange = view.onZoomChange
            view.onZoomChange = { _ in }
            view.setZoomScale(view.minimumZoomScale, animated: false)
            view.onZoomChange = reportZoomChange
        }
    }
}

final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate {
    var onSingleTap: () -> Void = {}
    var onZoomChange: (Bool) -> Void = { _ in }
    private let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
        // Waits out a double tap, so zooming in doesn't also flash the controls.
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(doubleTap)
        addGestureRecognizer(singleTap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setImage(_ image: UIImage) {
        guard imageView.image?.cgImage !== image.cgImage else { return }
        let sizeChanged = imageView.image?.size != image.size
        imageView.image = image
        if sizeChanged { setNeedsLayout() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Fit at 1x, again whenever the bounds change while unzoomed (rotation, folding, the caption moving aside).
        if zoomScale == minimumZoomScale, let size = imageView.image?.size, size.width > 0, size.height > 0 {
            let fitted = AVMakeRect(aspectRatio: size, insideRect: CGRect(origin: .zero, size: bounds.size))
            imageView.frame = CGRect(origin: .zero, size: fitted.size)
            contentSize = fitted.size
        }
        centerContent()
    }

    /// Keeps a photo smaller than the viewport centered in it.
    private func centerContent() {
        let horizontal = max((bounds.width - contentSize.width) / 2, 0)
        let vertical = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
        onZoomChange(zoomScale > minimumZoomScale + 0.01)
    }

    @objc private func singleTapped() {
        onSingleTap()
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        guard zoomScale == minimumZoomScale else {
            setZoomScale(minimumZoomScale, animated: true)
            return
        }
        let point = gesture.location(in: imageView)
        let scale = min(maximumZoomScale, 2.5)
        let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
        zoom(
            to: CGRect(origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), size: size),
            animated: true
        )
    }

    override func accessibilityIncrement() {
        setZoomScale(min(zoomScale + 1, maximumZoomScale), animated: true)
    }

    override func accessibilityDecrement() {
        setZoomScale(max(zoomScale - 1, minimumZoomScale), animated: true)
    }
}
