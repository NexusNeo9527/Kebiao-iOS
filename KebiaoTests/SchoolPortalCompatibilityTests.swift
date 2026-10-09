import WebKit
import XCTest
@testable import Kebiao

@MainActor
final class SchoolPortalCompatibilityTests: XCTestCase {
    func testFirstPortalPageReceivesRecognizableBrowserIdentity() async throws {
        let webView = WKWebView()
        let originalValue = try await webView.evaluateJavaScript("navigator.userAgent")
        let original = try XCTUnwrap(originalValue as? String)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            SchoolPortalBrowser.prepare(webView) { continuation.resume(with: $0) }
        }
        let compatible = try XCTUnwrap(webView.customUserAgent)
        XCTAssertTrue(compatible.hasPrefix(original))
        XCTAssertTrue(compatible.contains("Safari/"))

        let loaded = expectation(description: "First portal document loaded")
        let observer = PortalNavigationObserver { loaded.fulfill() }
        webView.navigationDelegate = observer
        // Model the official portal's browser classifier and ticket request
        // metadata in the first script run by the first loaded document.
        webView.loadHTMLString("""
        <html><head><script>
        const equipmentName = navigator.userAgent.indexOf('Safari') > -1 ? 'Safari' : undefined;
        const parameters = new URLSearchParams();
        if (equipmentName !== undefined) parameters.set('equipmentName', equipmentName);
        window.portalParameters = parameters.toString();
        </script></head><body>Portal fixture</body></html>
        """, baseURL: URL(string: "https://portal.example/"))
        await fulfillment(of: [loaded], timeout: 10)
        let parameters = try await webView.evaluateJavaScript("window.portalParameters") as? String
        XCTAssertEqual(parameters, "equipmentName=Safari")
    }
}

private final class PortalNavigationObserver: NSObject, WKNavigationDelegate {
    let finished: () -> Void

    init(finished: @escaping () -> Void) { self.finished = finished }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished() }
}
