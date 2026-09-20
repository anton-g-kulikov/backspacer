import Testing
import WebKit
@testable import Backspacer

// V-tests: the navigation delegate must actually be the one WebKit calls. Under Swift 6 a method
// whose completion-handler type differs from the protocol's "nearly matches" — compiles, is never
// called — and every https: link then opens inside the window (regression shipped in 0.8.0–0.9.1).
@Suite @MainActor struct NavigationDelegateTests {
    @Test("V1 AppDelegate implements WebKit's decidePolicyForNavigationAction selector")
    func respondsToPolicySelector() {
        let d = AppDelegate()
        #expect(d.responds(to: NSSelectorFromString("webView:decidePolicyForNavigationAction:decisionHandler:")))
    }

    @Test("V2 the other WebKit callbacks are real too: content-process crash, script messages")
    func respondsToOtherSelectors() {
        let d = AppDelegate()
        #expect(d.responds(to: NSSelectorFromString("webViewWebContentProcessDidTerminate:")))
        let b = Bridge(catalog: try! Fixture.catalog(), diagnostics: Fixture.quiet)
        #expect(b.responds(to: NSSelectorFromString("userContentController:didReceiveScriptMessage:")))
    }
}
