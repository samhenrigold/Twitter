import UIKit
import WebKit

/// A web link's page, loading as the preview opens, as Safari previews a link. Not interactive: a tap on it opens
/// the link where links open.
final class WebPreviewController: UIViewController {
    private let url: URL

    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let webView = WKWebView()
        webView.isUserInteractionEnabled = false
        webView.load(URLRequest(url: url))
        view = webView
    }
}
