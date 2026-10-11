import Combine
import WebKit
import XCTest
@testable import Kebiao

@MainActor
final class SchoolPortalCompatibilityTests: XCTestCase {
    func testFirstPortalPageReceivesRecognizableBrowserIdentity() async throws {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
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

    func testNewLoginWindowReceivesIdentityBeforeItsFirstScriptAndPreservesOpener() async throws {
        let fixture = PortalSessionFixture()
        let session = fixture.session
        defer { fixture.close() }
        let parentReady = fixture.messages.expect("parent-ready", in: self)
        let childReady = fixture.messages.expect("child-ready", in: self)
        let openerMessage = fixture.messages.expect("opener-message", in: self)
        let parentURL = fixture.url("/parent?semester=1")
        let childURL = fixture.url("/child?ticket=test-ticket&state=accepted")
        fixture.pages["/parent"] = Self.parentDocument
        fixture.pages["/child"] = Self.childDocument

        session.start(at: parentURL)
        await fulfillment(of: [parentReady], timeout: 10)
        // SSO sites often open their destination after an asynchronous ticket
        // exchange, outside the original tap's user gesture.
        _ = try await session.rootWebView.evaluateJavaScript(
            "setTimeout(() => { window.portalChild = window.open('\(childURL.absoluteString)', 'school-login'); }, 0); true")
        await fulfillment(of: [childReady, openerMessage], timeout: 10)
        let opened = try await session.rootWebView.evaluateJavaScript("Boolean(window.portalChild)")
        XCTAssertEqual(opened as? Bool, true)

        let parent = try XCTUnwrap(fixture.messages.values["parent-ready"])
        let child = try XCTUnwrap(fixture.messages.values["child-ready"])
        XCTAssertEqual(session.windows.count, 2)
        XCTAssertFalse(session.activeWebView === session.rootWebView)
        XCTAssertEqual(child["userAgent"] as? String, parent["userAgent"] as? String)
        XCTAssertTrue((child["userAgent"] as? String)?.contains("Safari/") == true)
        XCTAssertEqual(child["equipmentName"] as? String, "Safari")
        XCTAssertEqual(child["hasOpener"] as? Bool, true)
        XCTAssertEqual(child["url"] as? String, childURL.absoluteString)
        XCTAssertEqual(fixture.messages.values["opener-message"]?["matchedSource"] as? Bool, true)
        XCTAssertTrue(session.activeWebView.configuration.websiteDataStore === session.rootWebView.configuration.websiteDataStore)
        XCTAssertEqual(session.rootWebView.url, parentURL, "A child navigation must not replace its opener document.")

        let closed = expectation(description: "window.close restores parent window")
        let observation = session.$windows.filter { $0.count == 1 }.sink { _ in closed.fulfill() }
        _ = try await session.activeWebView.evaluateJavaScript("window.close(); true")
        await fulfillment(of: [closed], timeout: 10)
        observation.cancel()
        XCTAssertTrue(session.activeWebView === session.rootWebView)
        XCTAssertEqual(session.rootWebView.url, parentURL)
        let received = try await session.rootWebView.evaluateJavaScript("window.parentMessages[0].equipmentName")
        XCTAssertEqual(received as? String, "Safari")
    }

    func testBlankTargetPostIsLoadedOnceWithOriginalTicketAndQuery() async throws {
        let fixture = PortalSessionFixture()
        defer { fixture.close() }
        let parentReady = fixture.messages.expect("parent-ready", in: self)
        let childReady = fixture.messages.expect("child-ready", in: self)
        let target = fixture.url("/child?ticket=test-ticket&redirect=%2Fstudent%2Ftimetable&semester=2026-1")
        fixture.pages["/parent"] = Self.parentDocument + """
        <form id="ticket-exchange" method="POST" target="_blank" action="\(target.absoluteString)">
          <input type="hidden" name="equipmentName" value="Safari">
          <input type="hidden" name="ticket" value="fixture-ticket">
        </form>
        """
        fixture.pages["/child"] = Self.childDocument

        fixture.session.start(at: fixture.url("/parent"))
        await fulfillment(of: [parentReady], timeout: 10)
        _ = try await fixture.session.rootWebView.evaluateJavaScript("document.getElementById('ticket-exchange').submit(); true")
        await fulfillment(of: [childReady], timeout: 10)
        let child = fixture.session.activeWebView
        // A JavaScript round trip runs after this document's first script, without
        // adding a timed sleep or a second navigation to an SSO ticket endpoint.
        _ = try await child.evaluateJavaScript("document.readyState")

        let exchanges = fixture.requests.filter { $0.url?.path == "/child" }
        XCTAssertEqual(exchanges.count, 1, "WebKit must load the supplied navigation itself; replaying it can consume the SSO ticket twice.")
        XCTAssertEqual(exchanges.first?.httpMethod, "POST")
        XCTAssertEqual(exchanges.first?.url, target)
        XCTAssertEqual(child.url, target)
        XCTAssertEqual(fixture.session.rootWebView.url?.path, "/parent")
        XCTAssertEqual(fixture.session.windows.count, 2)
    }

    func testLoginCookiesAreSharedWithChildrenAndResetOnlyClearsSchoolDomains() async throws {
        var preparationCount = 0
        let fixture = PortalSessionFixture { webView, completion in
            preparationCount += 1
            // Reset starts a new identity preparation at the school's real
            // entry. Keep that navigation suspended; this fixture is offline.
            if preparationCount == 1 { SchoolPortalBrowser.prepare(webView, completion: completion) }
        }
        defer { fixture.close() }
        let parentReady = fixture.messages.expect("parent-ready", in: self)
        let childReady = fixture.messages.expect("child-ready", in: self)
        fixture.pages["/parent"] = Self.parentDocument
        fixture.pages["/child"] = Self.childDocument
        let store = fixture.session.rootWebView.configuration.websiteDataStore.httpCookieStore
        for (name, domain) in [("school-sso", ".cqut.edu.cn"), ("school-auth", "auth.cqut.edu.cn"),
                               ("other-account", ".unrelated.example"), ("lookalike-account", "cqut.edu.cn.unrelated.example")] {
            let cookie = try XCTUnwrap(HTTPCookie(properties: [.name: name, .value: "fixture-value", .domain: domain,
                .path: "/", .secure: "TRUE", .expires: Date(timeIntervalSinceNow: 3_600)]))
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                store.setCookie(cookie) { continuation.resume() }
            }
        }
        fixture.session.start(at: fixture.url("/parent"))
        await fulfillment(of: [parentReady], timeout: 10)
        _ = try await fixture.session.rootWebView.evaluateJavaScript("window.portalChild = window.open('\(fixture.url("/child").absoluteString)', 'school-login'); true")
        await fulfillment(of: [childReady], timeout: 10)
        let childStore = fixture.session.activeWebView.configuration.websiteDataStore.httpCookieStore
        let childCookies = await cookies(in: childStore)
        XCTAssertEqual(Set(childCookies.map(\.name)), ["school-sso", "school-auth", "other-account", "lookalike-account"])
        XCTAssertTrue(fixture.session.isWebsiteDataRecordRelevant("cqut.edu.cn"))
        XCTAssertTrue(fixture.session.isWebsiteDataRecordRelevant("auth.cqut.edu.cn"))
        XCTAssertFalse(fixture.session.isWebsiteDataRecordRelevant("unrelated.example"))
        XCTAssertFalse(fixture.session.isWebsiteDataRecordRelevant("cqut.edu.cn.unrelated.example"))

        await fixture.session.resetLogin()
        let remaining = await cookies(in: store)
        XCTAssertEqual(Set(remaining.map(\.name)), ["other-account", "lookalike-account"])
        XCTAssertEqual(fixture.session.windows.count, 1)
        XCTAssertEqual(preparationCount, 2)
    }

    func testPageInspectionDetectsLoginFailuresWithoutReadingCredentialValues() async throws {
        let cases: [(body: String, reason: String?)] = [
            ("<p>未知设备</p><input type='password' value='fixture-secret'>", "unknownDevice"),
            ("<p>登录已失效，请重新登录</p><input type='password' value='fixture-secret'>", "expiredSession"),
            ("<input name='account' value='fixture-account'><input type='password' value='fixture-secret'>", "loginForm"),
            ("<input type='password' style='display:none' value='fixture-secret'><table><tr><td>我的课表</td></tr></table>", nil),
            ("<input type='password' style='visibility:hidden' value='fixture-secret'><p>课表页面</p>", nil),
            ("<iframe srcdoc=\"<p>未知设备</p>\"></iframe>", "unknownDevice"),
            ("<iframe srcdoc=\"<input type='password' value='fixture-secret'>\"></iframe>", "loginForm"),
            ("<p>课表页面</p>", nil)
        ]
        for (index, value) in cases.enumerated() {
            let fixture = PortalSessionFixture()
            let ready = fixture.messages.expect("state-ready", in: self)
            fixture.pages["/state"] = """
            <!doctype html><html><body>\(value.body)<script>
            window.addEventListener('load', () => window.webkit.messageHandlers.portalFixture.postMessage({event: 'state-ready'}));
            </script></body></html>
            """
            fixture.session.start(at: fixture.url("/state?case=\(index)"))
            await fulfillment(of: [ready], timeout: 10)
            let raw = try await fixture.session.rootWebView.evaluateJavaScript(SchoolPortalSession.loginStateInspectionScript)
            let result = try XCTUnwrap(raw as? [String: Any])
            XCTAssertEqual(Set(result.keys), ["reason"], "The state probe must not return account fields, password fields, or page text.")
            XCTAssertEqual(result["reason"] as? String, value.reason, "State fixture \(index)")
            let readable = await withCheckedContinuation { continuation in
                fixture.session.inspectActivePage { continuation.resume(returning: $0) }
            }
            XCTAssertEqual(readable, value.reason == nil, "State fixture \(index)")
            if value.reason == nil {
                XCTAssertNil(fixture.session.loginIssue)
            } else {
                let issue = try XCTUnwrap(fixture.session.loginIssue)
                if fixture.session.isLoading {
                    let finished = expectation(description: "State fixture finished navigation")
                    let observation = fixture.session.$isLoading.filter { !$0 }.first().sink { _ in finished.fulfill() }
                    await fulfillment(of: [finished], timeout: 10)
                    observation.cancel()
                }
                let extraction = await withCheckedContinuation { continuation in
                    fixture.session.readCurrentTimetable { continuation.resume(returning: $0) }
                }
                switch extraction {
                case .success:
                    XCTFail("A login error or visible password form must be blocked before timetable extraction.")
                case .failure(let error):
                    XCTAssertTrue(error.localizedDescription.contains(issue))
                    XCTAssertFalse(error.localizedDescription.contains("fixture-secret"))
                    XCTAssertFalse(error.localizedDescription.contains("fixture-account"))
                }
                XCTAssertFalse(fixture.session.isExtracting)
            }
            fixture.close()
        }
    }

    func testPreparationCompletionAfterClosingDoesNotLoadOrReopenSession() async throws {
        var preparations: [(Result<Void, Error>) -> Void] = []
        let fixture = PortalSessionFixture { _, completion in preparations.append(completion) }
        defer { fixture.close() }
        fixture.pages["/cancelled"] = Self.parentDocument
        let unexpected = expectation(description: "A cancelled session must not request a school page")
        unexpected.isInverted = true
        fixture.handler.onRequest = { _ in unexpected.fulfill() }
        fixture.session.start(at: fixture.url("/cancelled"))
        XCTAssertEqual(preparations.count, 1)
        fixture.session.close()
        preparations[0](.success(()))
        await fulfillment(of: [unexpected], timeout: 1)
        XCTAssertTrue(fixture.requests.isEmpty)
        XCTAssertNil(fixture.session.rootWebView.url)
        XCTAssertTrue(fixture.session.windows.isEmpty)
        XCTAssertFalse(fixture.session.isLoading)
    }

    func testOlderPreparationCannotReplaceNewerSchoolEntry() async throws {
        var preparations: [(Result<Void, Error>) -> Void] = []
        let fixture = PortalSessionFixture { _, completion in preparations.append(completion) }
        defer { fixture.close() }
        fixture.pages["/old-entry"] = Self.parentDocument
        fixture.pages["/new-entry"] = Self.parentDocument
        let loaded = fixture.messages.expect("parent-ready", in: self)
        let oldRequest = expectation(description: "An old preparation cannot issue its navigation")
        oldRequest.isInverted = true
        fixture.handler.onRequest = { request in
            if request.url?.path == "/old-entry" { oldRequest.fulfill() }
        }
        fixture.session.start(at: fixture.url("/old-entry?ticket=old"))
        let latest = fixture.url("/new-entry?ticket=current&state=accepted")
        fixture.session.start(at: latest)
        XCTAssertEqual(preparations.count, 2)
        preparations[1](.success(()))
        await fulfillment(of: [loaded], timeout: 10)
        preparations[0](.failure(URLError(.cancelled)))
        preparations[0](.success(()))
        await fulfillment(of: [oldRequest], timeout: 1)
        XCTAssertEqual(fixture.session.rootWebView.url, latest)
        XCTAssertEqual(fixture.requests.map(\.url), [latest])
        XCTAssertFalse(fixture.session.isLoading)
    }

    func testAddressNavigationPreservesSsoParametersWhileDisplayHidesThem() throws {
        let address = "https://ehall.cqut.edu.cn/new_office_hall/?ticket=fixture-ticket&code=fixture-code&state=accepted&semester=2026-1#/personalInfo?ticket=hash-ticket&tab=timetable"
        let url = try XCTUnwrap(ImportScheduleView.portalNavigationURL(from: address))
        XCTAssertEqual(url.absoluteString, address)
        let display = SchoolPortalSession.safeDisplayAddress(for: url)
        XCTAssertFalse(display.contains("fixture-ticket"))
        XCTAssertFalse(display.contains("fixture-code"))
        XCTAssertFalse(display.contains("hash-ticket"))
        XCTAssertTrue(display.contains("ehall.cqut.edu.cn"))
        let fragmentAddress = "https://ehall.cqut.edu.cn/login#access_token=fixture-fragment-token&state=accepted&token_type=bearer"
        let fragmentURL = try XCTUnwrap(ImportScheduleView.portalNavigationURL(from: fragmentAddress))
        XCTAssertEqual(fragmentURL.absoluteString, fragmentAddress)
        XCTAssertFalse(SchoolPortalSession.safeDisplayAddress(for: fragmentURL).contains("fixture-fragment-token"))
    }

    func testAddressNavigationRejectsInsecureOrCredentialContainingUrls() {
        for address in ["http://ehall.cqut.edu.cn/", "javascript:alert(1)", "https:///timetable", "https://user:password@ehall.cqut.edu.cn/"] {
            XCTAssertNil(ImportScheduleView.portalNavigationURL(from: address), address)
        }
    }

    func testStartingDifferentSchoolUpdatesCleanupScopeWithoutKeepingPreviousSchool() {
        let fixture = PortalSessionFixture { _, _ in }
        defer { fixture.close() }
        fixture.session.start(at: URL(string: "https://portal.school-a.edu.cn/")!)
        XCTAssertTrue(fixture.session.isWebsiteDataRecordRelevant("school-a.edu.cn"))
        fixture.session.start(at: URL(string: "https://portal.school-b.edu.cn/")!)
        XCTAssertTrue(fixture.session.isWebsiteDataRecordRelevant("auth.school-b.edu.cn"))
        XCTAssertFalse(fixture.session.isWebsiteDataRecordRelevant("school-a.edu.cn"))
        XCTAssertFalse(fixture.session.isWebsiteDataRecordRelevant("edu.cn"))
    }

    func testOpeningExternalSchoolDoesNotExpandOriginalSchoolCleanupScope() async {
        let fixture = PortalSessionFixture { _, _ in }
        defer { fixture.close() }
        fixture.session.start(at: URL(string: "https://portal.school-a.edu.cn/")!)
        let cancelled = expectation(description: "Cross-school navigation cancelled before network")
        let blocker = PortalNavigationBlocker { cancelled.fulfill() }
        // This scope test does not contact a real school. Only the navigation
        // delegate is replaced; real popup tests keep the session's UI delegate.
        fixture.session.rootWebView.navigationDelegate = blocker
        fixture.session.open(URL(string: "https://portal.school-b.edu.cn/")!)
        await fulfillment(of: [cancelled], timeout: 10)
        XCTAssertTrue(fixture.session.isWebsiteDataRecordRelevant("school-a.edu.cn"))
        XCTAssertFalse(fixture.session.isWebsiteDataRecordRelevant("school-b.edu.cn"))
        XCTAssertFalse(fixture.session.isWebsiteDataRecordRelevant("school-a.edu.cn.unrelated.example"))
    }

    func testResetAfterExternalNavigationKeepsOtherSchoolCookies() async throws {
        var preparationCount = 0
        let fixture = PortalSessionFixture { webView, completion in
            preparationCount += 1
            if preparationCount == 1 { SchoolPortalBrowser.prepare(webView, completion: completion) }
        }
        defer { fixture.close() }
        let initialReady = fixture.messages.expect("parent-ready", in: self)
        let externalReady = fixture.messages.expect("external-ready", in: self)
        fixture.pages["/parent"] = Self.parentDocument
        fixture.pages["/external"] = Self.parentDocument.replacingOccurrences(of: "'parent-ready'", with: "'external-ready'")
        let store = fixture.session.rootWebView.configuration.websiteDataStore.httpCookieStore
        for (name, domain) in [("school-a", ".school-a.edu.cn"), ("school-a-auth", "auth.school-a.edu.cn"),
                               ("school-b", ".school-b.edu.cn"), ("lookalike", "school-a.edu.cn.unrelated.example")] {
            let cookie = try XCTUnwrap(HTTPCookie(properties: [.name: name, .value: "fixture-value", .domain: domain,
                .path: "/", .secure: "TRUE", .expires: Date(timeIntervalSinceNow: 3_600)]))
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                store.setCookie(cookie) { continuation.resume() }
            }
        }
        fixture.session.start(at: fixture.url("/parent", host: "portal.school-a.edu.cn"))
        await fulfillment(of: [initialReady], timeout: 10)
        fixture.session.open(fixture.url("/external", host: "portal.school-b.edu.cn"))
        await fulfillment(of: [externalReady], timeout: 10)

        await fixture.session.resetLogin()
        let remaining = await cookies(in: store)
        XCTAssertEqual(Set(remaining.map(\.name)), ["school-b", "lookalike"])
        XCTAssertEqual(preparationCount, 2)
    }

    func testStaleDialogDismissalDoesNotCancelFollowingConfirm() async throws {
        let fixture = PortalSessionFixture()
        defer { fixture.close() }
        fixture.pages["/parent"] = Self.parentDocument
        let ready = fixture.messages.expect("parent-ready", in: self)
        fixture.session.start(at: fixture.url("/parent"))
        await fulfillment(of: [ready], timeout: 10)
        let alertPresented = expectation(description: "JavaScript alert presented")
        let confirmPresented = expectation(description: "JavaScript confirm presented")
        let completed = fixture.messages.expect("dialogs-completed", in: self)
        var alertID: UUID?
        var confirmID: UUID?
        let observation = fixture.session.$javaScriptDialog.compactMap { $0 }.sink { dialog in
            if dialog.message == "fixture-alert", alertID == nil {
                alertID = dialog.id
                alertPresented.fulfill()
            } else if dialog.message == "fixture-confirm", confirmID == nil {
                confirmID = dialog.id
                confirmPresented.fulfill()
            }
        }
        defer { observation.cancel() }
        let evaluation = Task { @MainActor in
            try await fixture.session.rootWebView.evaluateJavaScript("""
            alert('fixture-alert');
            const accepted = confirm('fixture-confirm');
            window.webkit.messageHandlers.portalFixture.postMessage({event: 'dialogs-completed', accepted});
            true;
            """)
        }
        await fulfillment(of: [alertPresented], timeout: 10)
        let firstID = try XCTUnwrap(alertID)
        fixture.session.completeJavaScriptDialog(id: firstID, accepted: true, input: nil)
        await fulfillment(of: [confirmPresented], timeout: 10)
        let secondID = try XCTUnwrap(confirmID)
        XCTAssertNotEqual(firstID, secondID)
        fixture.session.completeJavaScriptDialog(id: firstID, accepted: false, input: nil)
        XCTAssertEqual(fixture.session.javaScriptDialog?.id, secondID, "Dismissal from an old SwiftUI alert must leave the new confirm pending.")
        fixture.session.completeJavaScriptDialog(id: secondID, accepted: true, input: nil)
        await fulfillment(of: [completed], timeout: 10)
        _ = try await evaluation.value
        XCTAssertEqual(fixture.messages.values["dialogs-completed"]?["accepted"] as? Bool, true)
        XCTAssertNil(fixture.session.javaScriptDialog)
    }

    func testUnknownDeviceAlertRemainsBlockedUntilNextNavigation() async throws {
        let fixture = PortalSessionFixture()
        defer { fixture.close() }
        fixture.pages["/parent"] = Self.parentDocument
        fixture.pages["/recovered"] = Self.parentDocument.replacingOccurrences(of: "'parent-ready'", with: "'recovered-ready'")
        let ready = fixture.messages.expect("parent-ready", in: self)
        fixture.session.start(at: fixture.url("/parent"))
        await fulfillment(of: [ready], timeout: 10)
        let presented = expectation(description: "Unknown device alert presented")
        let completed = fixture.messages.expect("unknown-alert-completed", in: self)
        let observation = fixture.session.$javaScriptDialog.compactMap { $0 }.first().sink { _ in presented.fulfill() }
        let evaluation = Task { @MainActor in
            try await fixture.session.rootWebView.evaluateJavaScript("""
            alert('未知设备');
            window.webkit.messageHandlers.portalFixture.postMessage({event: 'unknown-alert-completed'});
            true;
            """)
        }
        await fulfillment(of: [presented], timeout: 10)
        observation.cancel()
        let dialog = try XCTUnwrap(fixture.session.javaScriptDialog)
        fixture.session.completeJavaScriptDialog(id: dialog.id, accepted: true, input: nil)
        await fulfillment(of: [completed], timeout: 10)
        _ = try await evaluation.value
        let readable = await withCheckedContinuation { continuation in
            fixture.session.inspectActivePage { continuation.resume(returning: $0) }
        }
        XCTAssertFalse(readable, "An SSO error reported by alert must not disappear merely because body text is normal.")
        XCTAssertTrue(fixture.session.loginIssue?.contains("未知设备") == true)

        let recovered = fixture.messages.expect("recovered-ready", in: self)
        fixture.session.open(fixture.url("/recovered"))
        await fulfillment(of: [recovered], timeout: 10)
        let newPageReadable = await withCheckedContinuation { continuation in
            fixture.session.inspectActivePage { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(newPageReadable)
        XCTAssertNil(fixture.session.loginIssue)
    }

    func testClosingInactiveSiblingWindowKeepsCurrentWindowAlive() async throws {
        let fixture = PortalSessionFixture()
        defer { fixture.close() }
        fixture.pages["/parent"] = Self.parentDocument
        fixture.pages["/child-a"] = Self.childDocument
        fixture.pages["/child-b"] = Self.childDocument
        let parentReady = fixture.messages.expect("parent-ready", in: self)
        fixture.session.start(at: fixture.url("/parent"))
        await fulfillment(of: [parentReady], timeout: 10)
        let firstReady = fixture.messages.expect("child-ready", in: self)
        _ = try await fixture.session.rootWebView.evaluateJavaScript("window.childA = window.open('\(fixture.url("/child-a").absoluteString)', 'child-a'); true")
        await fulfillment(of: [firstReady], timeout: 10)
        let first = fixture.session.activeWebView
        let secondReady = fixture.messages.expect("child-ready", in: self)
        _ = try await fixture.session.rootWebView.evaluateJavaScript("window.childB = window.open('\(fixture.url("/child-b").absoluteString)', 'child-b'); true")
        await fulfillment(of: [secondReady], timeout: 10)
        let second = fixture.session.activeWebView
        XCTAssertFalse(first === second)
        XCTAssertEqual(fixture.session.windows.count, 3)
        let closed = expectation(description: "Inactive sibling closed")
        let observation = fixture.session.$windows.filter { $0.count == 2 }.first().sink { _ in closed.fulfill() }
        _ = try await first.evaluateJavaScript("window.close(); true")
        await fulfillment(of: [closed], timeout: 10)
        observation.cancel()
        XCTAssertTrue(fixture.session.activeWebView === second)
        XCTAssertTrue(fixture.session.windows.contains { $0 === second })
        XCTAssertFalse(fixture.session.windows.contains { $0 === first })
        XCTAssertEqual(fixture.session.rootWebView.url?.path, "/parent")
        let location = try await second.evaluateJavaScript("window.location.href")
        XCTAssertEqual(location as? String, fixture.url("/child-b").absoluteString)
    }

    func testUnknownPublicSuffixesAndSharedHostingNeverIncludeAnotherSchool() {
        let hosts: [(entry: String, other: String, publicSuffix: String)] = [
            ("portal.school-a.ac.jp", "portal.school-b.ac.jp", "ac.jp"),
            ("portal.school-a.edu.au", "portal.school-b.edu.au", "edu.au"),
            ("school-a.github.io", "school-b.github.io", "github.io"),
            ("school-a.appspot.com", "school-b.appspot.com", "appspot.com"),
            ("portal.a.azurewebsites.net", "portal.b.azurewebsites.net", "azurewebsites.net")
        ]
        for value in hosts {
            let fixture = PortalSessionFixture { _, _ in }
            fixture.session.start(at: URL(string: "https://\(value.entry)/")!)
            XCTAssertTrue(fixture.session.isWebsiteDataRecordRelevant(value.entry))
            XCTAssertFalse(fixture.session.isWebsiteDataRecordRelevant(value.other))
            XCTAssertFalse(fixture.session.isWebsiteDataRecordRelevant(value.publicSuffix))
            fixture.close()
        }
    }

    func testSpaLoginFormCanClearWithoutASecondNavigationAndThenReadTimetable() async throws {
        let fixture = PortalSessionFixture()
        defer { fixture.close() }
        let ready = fixture.messages.expect("state-ready", in: self)
        fixture.pages["/spa"] = """
        <!doctype html><html><body>
        <input id="login-password" type="password" value="fixture-secret">
        <script>window.addEventListener('load', () => window.webkit.messageHandlers.portalFixture.postMessage({event: 'state-ready'}));</script>
        </body></html>
        """
        let url = fixture.url("/spa")
        fixture.session.start(at: url)
        await fulfillment(of: [ready], timeout: 10)
        let initiallyReadable = await withCheckedContinuation { continuation in
            fixture.session.inspectActivePage { continuation.resume(returning: $0) }
        }
        XCTAssertFalse(initiallyReadable)
        XCTAssertNotNil(fixture.session.loginIssue)
        _ = try await fixture.session.rootWebView.evaluateJavaScript("""
        document.getElementById('login-password').remove();
        document.body.insertAdjacentHTML('beforeend', '<table><tr><th>课程名称</th><th>教师</th></tr><tr><td>fixture-course</td><td>fixture-teacher</td></tr></table>');
        true;
        """)
        let nowReadable = await withCheckedContinuation { continuation in
            fixture.session.inspectActivePage { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(nowReadable, "A completed SPA login must clear a transient login-form hint without didFinish navigation.")
        XCTAssertNil(fixture.session.loginIssue)
        if fixture.session.isLoading {
            let finished = expectation(description: "SPA root finished loading")
            let observation = fixture.session.$isLoading.filter { !$0 }.first().sink { _ in finished.fulfill() }
            await fulfillment(of: [finished], timeout: 10)
            observation.cancel()
        }
        let result = await withCheckedContinuation { continuation in
            fixture.session.readCurrentTimetable { continuation.resume(returning: $0) }
        }
        let payload = try result.get()
        XCTAssertTrue(payload.contains("fixture-course"))
        XCTAssertFalse(payload.contains("fixture-secret"))
        XCTAssertEqual(fixture.session.rootWebView.url, url)
        XCTAssertEqual(fixture.requests.count, 1)
    }

    private func cookies(in store: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
    }

    private static let parentDocument = """
    <!doctype html><html><head><script>
    window.parentMessages = [];
    window.addEventListener('message', event => {
      window.parentMessages.push(event.data);
      window.webkit.messageHandlers.portalFixture.postMessage({
        event: 'opener-message', matchedSource: event.source === window.portalChild
      });
    });
    window.webkit.messageHandlers.portalFixture.postMessage({event: 'parent-ready', userAgent: navigator.userAgent});
    </script></head><body>School portal fixture</body></html>
    """

    private static let childDocument = """
    <!doctype html><html><head><script>
    const equipmentName = navigator.userAgent.indexOf('Safari') > -1 ? 'Safari' : undefined;
    window.webkit.messageHandlers.portalFixture.postMessage({
      event: 'child-ready', userAgent: navigator.userAgent, equipmentName,
      hasOpener: window.opener !== null, url: window.location.href
    });
    if (window.opener) window.opener.postMessage({equipmentName, ticket: 'fixture-ticket'}, '*');
    </script></head><body>SSO callback fixture</body></html>
    """
}

@MainActor
private final class PortalSessionFixture {
    let messages: PortalFixtureMessages
    let handler: PortalFixtureSchemeHandler
    let session: SchoolPortalSession

    var pages: [String: String] {
        get { handler.pages }
        set { handler.pages = newValue }
    }
    var requests: [URLRequest] { handler.requests }

    init(prepareBrowser: @escaping SchoolPortalSession.BrowserPreparation = SchoolPortalBrowser.prepare) {
        let messages = PortalFixtureMessages()
        let handler = PortalFixtureSchemeHandler()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(messages, name: "portalFixture")
        configuration.setURLSchemeHandler(handler, forURLScheme: "kebiao-portal-test")
        self.messages = messages
        self.handler = handler
        session = SchoolPortalSession(configuration: configuration, prepareBrowser: prepareBrowser)
        session.rootWebView.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    }

    func url(_ path: String, host: String = "ehall.cqut.edu.cn") -> URL { URL(string: "kebiao-portal-test://\(host)\(path)")! }

    func close() {
        session.close()
        session.rootWebView.configuration.userContentController.removeScriptMessageHandler(forName: "portalFixture")
    }
}

@MainActor
private final class PortalFixtureMessages: NSObject, WKScriptMessageHandler {
    private var expectations: [String: XCTestExpectation] = [:]
    private(set) var values: [String: [String: Any]] = [:]

    func expect(_ event: String, in test: XCTestCase) -> XCTestExpectation {
        let expectation = test.expectation(description: "Portal script message: \(event)")
        expectations[event] = expectation
        return expectation
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let value = message.body as? [String: Any], let event = value["event"] as? String else { return }
        values[event] = value
        expectations.removeValue(forKey: event)?.fulfill()
    }
}

@MainActor
private final class PortalFixtureSchemeHandler: NSObject, WKURLSchemeHandler {
    var pages: [String: String] = [:]
    private(set) var requests: [URLRequest] = []
    var onRequest: ((URLRequest) -> Void)?

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let request = urlSchemeTask.request
        requests.append(request)
        onRequest?(request)
        guard let url = request.url, let html = pages[url.path] else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let data = Data(html.utf8)
        urlSchemeTask.didReceive(URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8"))
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

private final class PortalNavigationObserver: NSObject, WKNavigationDelegate {
    let finished: () -> Void

    init(finished: @escaping () -> Void) { self.finished = finished }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished() }
}

private final class PortalNavigationBlocker: NSObject, WKNavigationDelegate {
    private let didAttempt: () -> Void

    init(didAttempt: @escaping () -> Void) { self.didAttempt = didAttempt }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.cancel)
        didAttempt()
    }
}
