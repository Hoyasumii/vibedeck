import Foundation
import Testing
import WebKit
@testable import VibeDeckApp

struct LinkViewerTests {
    private let original = URL(string: "http://example.com/start")!
    private let destination = URL(string: "https://example.com/final")!

    @Test func initialRequestAndRedirectStayEmbedded() {
        #expect(LinkViewerNavigation.decision(url: original, currentURL: nil, type: .other, isMainFrame: true) == .allow)
        #expect(LinkViewerNavigation.decision(url: destination, currentURL: original, type: .other, isMainFrame: true) == .allow)
        #expect(LinkViewerNavigation.decision(url: destination, currentURL: destination, type: .linkActivated, isMainFrame: true) == .allow)
    }

    @Test(arguments: ["file:///tmp/private", "javascript:alert(1)", "data:text/html,hello", "vibedeck-source://node/a"])
    func unsupportedSchemesNeverLoadInMainFrameOrPopup(_ value: String) throws {
        let url = try #require(URL(string: value))
        #expect(!LinkViewerNavigation.permits(url))
        for type in [WKNavigationType.other, .linkActivated, .formSubmitted] {
            #expect(LinkViewerNavigation.decision(url: url, currentURL: original, type: type, isMainFrame: true) == .cancel)
            #expect(LinkViewerNavigation.decision(url: url, currentURL: original, type: type, isMainFrame: nil) == .cancel)
        }
    }

    @Test func otherPagesAndFormsOpenExternally() {
        #expect(LinkViewerNavigation.decision(url: destination, currentURL: original, type: .linkActivated, isMainFrame: true) == .external)
        #expect(LinkViewerNavigation.decision(url: destination, currentURL: original, type: .formSubmitted, isMainFrame: true) == .external)
        #expect(LinkViewerNavigation.decision(url: destination, currentURL: original, type: .linkActivated, isMainFrame: nil) == .external)
        #expect(LinkViewerNavigation.decision(url: destination, currentURL: original, type: .other, isMainFrame: nil, opensWindow: true) == .external)
    }

    @Test func subframesRemainAvailableAndMissingURLIsRejected() {
        #expect(LinkViewerNavigation.decision(url: destination, currentURL: original, type: .other, isMainFrame: false) == .allow)
        #expect(LinkViewerNavigation.decision(url: destination, currentURL: original, type: .linkActivated, isMainFrame: false) == .allow)
        #expect(LinkViewerNavigation.decision(url: URL(string: "about:blank"), currentURL: original, type: .other, isMainFrame: false) == .allow)
        #expect(LinkViewerNavigation.decision(url: nil, currentURL: original, type: .other, isMainFrame: true) == .cancel)
    }
}
