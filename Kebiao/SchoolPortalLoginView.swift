import SwiftUI
import UIKit
import WebKit

struct SchoolPortalLoginView: View {
    let url: URL
    let sourceName: String
    @Binding var preview: ScheduleImportPreview?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = SchoolPortalSession()
    @State private var frameURLs: [URL] = []
    @State private var address = ""
    @State private var confirmsReset = false
    @State private var dialogInput = ""

    var body: some View {
        let presentedDialogID = session.javaScriptDialog?.id
        return NavigationStack {
            VStack(spacing: 8) {
                HStack {
                    TextField("学校网页地址", text: $address)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .onSubmit { openAddress() }
                    Button("前往") { openAddress() }.disabled(session.isLoading || session.isResetting)
                    Button { session.activeWebView.reload() } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(session.isLoading || session.isResetting)
                        .accessibilityLabel("刷新网页")
                }
                .padding(.horizontal)
                Text(session.loginIssue ?? "登录后进入教务系统，选择学期并打开完整课表，再点下方读取。")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                if session.windows.count > 1 {
                    HStack {
                        Text("学校新窗口 · \(session.windows.count - 1)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("关闭新窗口，返回上一页") { session.closeActiveWindow() }
                            .font(.caption)
                            .accessibilityIdentifier("portal-close-window")
                    }.padding(.horizontal)
                }
                ZStack {
                    PortalWebView(webView: session.activeWebView)
                        .ignoresSafeArea(edges: .bottom)
                    if session.isLoading || session.isResetting {
                        ProgressView(session.isResetting ? "正在清除此学校的登录状态…" : "正在打开教务系统…")
                            .padding(18)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .onAppear {
                address = SchoolPortalSession.safeDisplayAddress(for: url)
                session.start(at: url)
            }
            .onDisappear { session.close() }
            .onChange(of: session.displayAddress) { _, value in address = value }
            .onChange(of: session.activeWebView) { _, _ in frameURLs = [] }
            .onChange(of: session.javaScriptDialog?.id) { _, _ in
                dialogInput = session.javaScriptDialog?.defaultText ?? ""
            }
            .navigationTitle(sourceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("重新登录") { confirmsReset = true }
                        .disabled(session.isResetting)
                        .accessibilityIdentifier("portal-reset-login")
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { session.activeWebView.goBack() } label: { Image(systemName: "chevron.backward") }
                        .disabled(!session.canGoBack || session.isResetting)
                        .accessibilityLabel("后退")
                    Button { session.activeWebView.goForward() } label: { Image(systemName: "chevron.forward") }
                        .disabled(!session.canGoForward || session.isResetting)
                        .accessibilityLabel("前进")
                    Spacer()
                    Button {
                        extractCurrentTimetable()
                    } label: {
                        if session.isExtracting {
                            ProgressView()
                        } else {
                            Label("读取当前课表", systemImage: "tablecells")
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(session.isLoading || session.isExtracting || session.isResetting || session.javaScriptDialog != nil || session.hasBlockingAuthenticationError)
                    .accessibilityIdentifier("read-current-timetable")
                }
            }
            .confirmationDialog("课表位于独立页面，请选择入口", isPresented: Binding(
                get: { !frameURLs.isEmpty }, set: { if !$0 { frameURLs = [] } }
            ), titleVisibility: .visible) {
                ForEach(frameURLs, id: \.absoluteString) { url in
                    Button(url.host ?? "打开课表页面") {
                        session.open(url)
                        frameURLs = []
                    }
                }
                Button("取消", role: .cancel) { frameURLs = [] }
            }
            .confirmationDialog("清除此学校登录状态后重新登录？", isPresented: $confirmsReset, titleVisibility: .visible) {
                Button("清除此学校状态并重新登录", role: .destructive) {
                    Task { await session.resetLogin() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("只清除本次学校入口域及子域的登录数据；可识别的教育域包含该校子域。其他学校登录状态和已有课程会保留。")
            }
            .alert(session.javaScriptDialog?.title ?? "学校网页提示", isPresented: Binding(
                get: { session.javaScriptDialog != nil },
                set: {
                    if !$0, let presentedDialogID { session.completeJavaScriptDialog(id: presentedDialogID, accepted: false, input: nil) }
                }
            ), presenting: session.javaScriptDialog) { dialog in
                if dialog.kind == .prompt { TextField("网页要求的内容", text: $dialogInput) }
                if dialog.kind != .alert {
                    Button("取消", role: .cancel) { session.completeJavaScriptDialog(id: dialog.id, accepted: false, input: nil) }
                }
                Button("确定") { session.completeJavaScriptDialog(id: dialog.id, accepted: true, input: dialogInput) }
            } message: { dialog in
                Text(dialog.message)
            }
            .background {
                Color.clear.alert("学校网页打开或读取失败", isPresented: Binding(
                get: { session.errorMessage != nil },
                set: { if !$0 { session.errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { session.errorMessage = nil }
            } message: {
                Text(session.errorMessage ?? "请刷新网页或重新登录后重试。")
            }
            }
        }
    }

    private func openAddress() {
        guard !session.isLoading, !session.isResetting else { return }
        guard let destination = ImportScheduleView.portalNavigationURL(from: address) else {
            session.errorMessage = "请输入学校提供的 HTTPS 网址。"
            return
        }
        session.open(destination)
        address = SchoolPortalSession.safeDisplayAddress(for: destination)
    }

    private func extractCurrentTimetable() {
        session.readCurrentTimetable { result in
            guard case .success(let payload) = result else { return }
            guard !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                session.errorMessage = "当前页面没有可读取的课表。请先登录并打开“学生课表”或“我的课表”页面。"
                return
            }
            if payload.hasPrefix("__KEBIAO_FRAMES__") {
                let json = String(payload.dropFirst("__KEBIAO_FRAMES__".count))
                let addresses = (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
                frameURLs = addresses.compactMap(URL.init(string:)).filter { $0.scheme == "https" }
                if frameURLs.isEmpty { session.errorMessage = "课表位于无法直接访问的框架，请使用学校的独立课表入口或文件导入。" }
                return
            }
            do {
                preview = try ScheduleImportService.parseSchoolPortalPayload(payload, sourceName: sourceName)
                dismiss()
            } catch {
                session.errorMessage = "\(error.localizedDescription) 请确认当前显示的是完整课表，并尽量切换到列表或表格视图。"
            }
        }
    }

    static let tableExtractionScript = #"""
    (() => {
      const clean = value => (value || '').replace(/\s+/g, ' ').trim();
      const tables = [];
      const gridCells = [];
      let hasGrid = false;
      const texts = [];
      const frames = new Set();
      const visit = (doc, depth) => {
        if (!doc || depth > 5) return;
        const visible = element => {
          const style = doc.defaultView.getComputedStyle(element);
          return style.display !== 'none' && style.visibility !== 'hidden';
        };
        for (const table of Array.from(doc.querySelectorAll('table')).filter(visible)) {
          // Expand row/column spans before mapping a weekday column. Empty cells
          // and merged morning/afternoon labels must not shift course positions.
          const matrix = [];
          Array.from(table.rows).forEach((row, r) => {
            matrix[r] ||= [];
            let c = 0;
            for (const cell of Array.from(row.cells)) {
              while (matrix[r][c]) c++;
              const entry = { cell, row: r, col: c };
              const height = Math.max(1, Math.min(100, Number(cell.rowSpan) || 1));
              const width = Math.max(1, Math.min(100, Number(cell.colSpan) || 1));
              for (let dy = 0; dy < height; dy++) {
                matrix[r + dy] ||= [];
                for (let dx = 0; dx < width; dx++) matrix[r + dy][c + dx] = entry;
              }
              c += width;
            }
          });
          const isDay = value => /^(?:星期|周)[一二三四五六日天]$/.test(clean(value));
          const header = matrix.findIndex(row => row.filter(entry => entry && isDay(entry.cell.innerText)).length >= 2);
          if (header >= 0) {
            hasGrid = true;
            const columns = matrix[header].map(entry => entry && isDay(entry.cell.innerText) ? clean(entry.cell.innerText) : null);
            const firstDay = columns.findIndex(Boolean);
            const sectionAt = r => (matrix[r] || []).slice(0, firstDay)
              .map(entry => clean(entry?.cell.innerText)).find(value => /^(?:第)?\s*\d{1,2}(?:\s*[-–—~至,、]\s*\d{1,2})*\s*(?:节)?$/.test(value)) || '';
            for (let r = header + 1; r < matrix.length; r++) {
              for (let c = firstDay; c < columns.length; c++) {
                const entry = matrix[r]?.[c];
                if (!columns[c] || !entry || entry.row !== r) continue;
                const text = (entry.cell.innerText || '').trim();
                if (!text || isDay(text)) continue;
                const lastRow = Math.min(matrix.length - 1, r + (Number(entry.cell.rowSpan) || 1) - 1);
                const firstSection = sectionAt(r), lastSection = sectionAt(lastRow);
                const numbers = (firstSection + '-' + lastSection).match(/\d+/g)?.map(Number) || [];
                const section = numbers.length ? Math.min(...numbers) + '-' + Math.max(...numbers) : '';
                gridCells.push({ weekday: columns[c], section, text });
              }
            }
            continue;
          }
          const rows = Array.from(table.rows).map(row =>
            Array.from(row.cells).map(cell => clean(cell.innerText)).join('\t')
          ).filter(Boolean);
          if (rows.some(row => /课程名称|课程名|科目|course\s*name/i.test(row))) tables.push(rows.join('\n'));
        }
        if (doc.body) texts.push(doc.body.innerText || '');
        for (const frame of doc.querySelectorAll('iframe, frame')) {
          try {
            if (frame.contentDocument && frame.contentDocument.body) visit(frame.contentDocument, depth + 1);
            else if (frame.src) frames.add(frame.src);
          } catch (_) { if (frame.src) frames.add(frame.src); }
        }
      };
      visit(document, 0);
      if (hasGrid) return '__KEBIAO_GRID__' + JSON.stringify(gridCells);
      if (tables.length) return tables.join('\n\n');
      if (frames.size) return '__KEBIAO_FRAMES__' + JSON.stringify(Array.from(frames));
      return texts.join('\n\n');
    })();
    """#
}

// The CQUT portal derives equipmentName from its browser classifier and sends
// it when exchanging the SSO ticket. A bare WKWebView UA has no browser token,
// so that required field is omitted. Keep WebKit's device/OS identity and add
// the Safari-compatible tokens before the first page can run its classifier.
enum SchoolPortalBrowser {
    @MainActor
    static func prepare(_ webView: WKWebView, completion: @escaping (Result<Void, Error>) -> Void) {
        webView.evaluateJavaScript(browserIdentityScript) { value, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let userAgent = value as? String, !userAgent.isEmpty else {
                completion(.failure(BrowserIdentityError.unavailable))
                return
            }
            webView.customUserAgent = userAgent
            completion(.success(()))
        }
    }

    static let browserIdentityScript = #"""
    (() => {
      const ua = navigator.userAgent || '';
      if (!ua || /\b(?:Safari|Chrome|CriOS|Firefox|FxiOS|Edge|Opera|OPR)\//.test(ua)) return ua;
      const ios = ua.match(/(?:CPU(?: iPhone)? OS|iPhone OS) (\d+)(?:_(\d+))?/);
      const version = ios ? ' Version/' + ios[1] + '.' + (ios[2] || '0') : '';
      return ua + version + ' Safari/604.1';
    })();
    """#

    private enum BrowserIdentityError: LocalizedError {
        case unavailable

        var errorDescription: String? { "浏览器信息初始化失败，请关闭导入页面后重新打开。" }
    }
}

private struct PortalWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView { UIView() }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard uiView.subviews.first !== webView else { return }
        uiView.subviews.forEach { $0.removeFromSuperview() }
        webView.frame = uiView.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        uiView.addSubview(webView)
    }
}

@MainActor
final class SchoolPortalSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    typealias BrowserPreparation = (WKWebView, @escaping (Result<Void, Error>) -> Void) -> Void

    struct JavaScriptDialog: Identifiable {
        enum Kind: Equatable { case alert, confirm, prompt }
        let id: UUID
        let title: String
        let message: String
        let kind: Kind
        let defaultText: String?
    }

    @Published private(set) var activeWebView: WKWebView
    @Published private(set) var windows: [WKWebView]
    @Published private(set) var isLoading = false
    @Published private(set) var isExtracting = false
    @Published private(set) var isResetting = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var displayAddress = ""
    @Published private(set) var loginIssue: String?
    @Published private(set) var hasBlockingAuthenticationError = false
    @Published private(set) var javaScriptDialog: JavaScriptDialog?
    @Published var errorMessage: String?

    private(set) var visitedHosts = Set<String>()
    private(set) var rootWebView: WKWebView
    private let initialConfiguration: WKWebViewConfiguration
    private let websiteDataStore: WKWebsiteDataStore
    private let maximumWindowCount: Int
    private let prepareBrowser: BrowserPreparation
    private var entryURL: URL?
    private var originalEntryURL: URL?
    private var schoolDomain: String?
    private var generation = 0
    private var isClosed = false
    private var preparingWindow: ObjectIdentifier?
    private var documentGenerations: [ObjectIdentifier: Int] = [:]
    private var scriptedLoginIssues: [ObjectIdentifier: String] = [:]
    private var observations: [ObjectIdentifier: [NSKeyValueObservation]] = [:]
    private var pendingDialogs: [(JavaScriptDialog, ObjectIdentifier, (Bool, String?) -> Void)] = []
    private var activeDialogCompletion: ((Bool, String?) -> Void)?
    private var activeDialogWindow: ObjectIdentifier?
    private var isDismissingDialog = false

    convenience init(websiteDataStore: WKWebsiteDataStore = .default(), maximumWindowCount: Int = 4) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        self.init(configuration: configuration, maximumWindowCount: maximumWindowCount)
    }

    init(configuration: WKWebViewConfiguration, maximumWindowCount: Int = 4,
         prepareBrowser: @escaping BrowserPreparation = SchoolPortalBrowser.prepare) {
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        rootWebView = webView
        activeWebView = webView
        windows = [webView]
        initialConfiguration = configuration
        websiteDataStore = configuration.websiteDataStore
        self.maximumWindowCount = max(1, min(4, maximumWindowCount))
        self.prepareBrowser = prepareBrowser
        super.init()
        configure(webView)
    }

    func start(at url: URL) {
        guard !isClosed, !isResetting else { return }
        generation += 1
        let currentGeneration = generation
        if entryURL?.host != url.host { visitedHosts.removeAll() }
        entryURL = url
        originalEntryURL = url
        schoolDomain = url.host.map(Self.schoolDomain(for:))
        dismissAllDialogs()
        for window in windows where window !== rootWebView { detach(window) }
        windows = [rootWebView]
        rootWebView.stopLoading()
        activeWebView = rootWebView
        loginIssue = nil
        hasBlockingAuthenticationError = false
        scriptedLoginIssues[ObjectIdentifier(rootWebView)] = nil
        errorMessage = nil
        isExtracting = false
        remember(url)
        displayAddress = Self.safeDisplayAddress(for: url)
        let root = rootWebView
        preparingWindow = ObjectIdentifier(root)
        refreshActiveState()
        prepareBrowser(root) { [weak self, weak root] result in
            guard let self, let root, !self.isClosed,
                  self.generation == currentGeneration, self.rootWebView === root,
                  self.activeWebView === root else { return }
            self.preparingWindow = nil
            switch result {
            case .success:
                #if targetEnvironment(simulator)
                if url.host == "portal.fixture", ProcessInfo.processInfo.arguments.contains("--ui-test-import-login") {
                    root.loadHTMLString(Self.simulatorLoginFixture, baseURL: url)
                } else {
                    root.load(URLRequest(url: url))
                }
                #else
                root.load(URLRequest(url: url))
                #endif
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
            self.refreshActiveState()
        }
    }

    func open(_ url: URL) {
        guard !isClosed, !isResetting else { return }
        guard entryURL != nil, preparingWindow == nil else { start(at: url); return }
        generation += 1
        isExtracting = false
        loginIssue = nil
        hasBlockingAuthenticationError = false
        errorMessage = nil
        displayAddress = Self.safeDisplayAddress(for: url)
        remember(url)
        // Temporary authentication parameters belong to this navigation. Only
        // the address shown to the user is redacted; this request is unchanged.
        activeWebView.load(URLRequest(url: url))
        refreshActiveState()
    }

    func closeActiveWindow() {
        guard activeWebView !== rootWebView else { return }
        closeWindow(activeWebView)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        generation += 1
        preparingWindow = nil
        dismissAllDialogs()
        windows.forEach(detach)
        windows = []
        isLoading = false
        isExtracting = false
        isResetting = false
    }

    func resetLogin() async {
        guard !isClosed, !isResetting, let entryURL = originalEntryURL ?? entryURL else { return }
        generation += 1
        let resetGeneration = generation
        isResetting = true
        isExtracting = false
        preparingWindow = nil
        dismissAllDialogs()
        windows.forEach { $0.stopLoading() }
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records: [WKWebsiteDataRecord] = await withCheckedContinuation { continuation in
            websiteDataStore.fetchDataRecords(ofTypes: types) { continuation.resume(returning: $0) }
        }
        guard !isClosed, generation == resetGeneration else { return }
        let relevant = records.filter { isWebsiteDataRecordRelevant($0.displayName) }
        if !relevant.isEmpty {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                websiteDataStore.removeData(ofTypes: types, for: relevant) { continuation.resume() }
            }
        }
        // Explicitly await cookie removal too: website records can be incomplete
        // while a recent login is still writing its cookie data.
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        for cookie in cookies where isWebsiteDataRecordRelevant(cookie.domain) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                websiteDataStore.httpCookieStore.delete(cookie) { continuation.resume() }
            }
        }
        guard !isClosed, generation == resetGeneration else { return }
        windows.forEach(detach)
        let root = WKWebView(frame: .zero, configuration: initialConfiguration)
        rootWebView = root
        activeWebView = root
        windows = [root]
        configure(root)
        visitedHosts.removeAll()
        isResetting = false
        // Begin again at the stable entry, never replay an SSO callback ticket.
        let stableEntry: URL
        if schoolDomain == "cqut.edu.cn" {
            stableEntry = URL(string: "https://ehall.cqut.edu.cn/new_office_hall/")!
        } else if let components = URLComponents(url: entryURL, resolvingAgainstBaseURL: false) {
            stableEntry = ImportScheduleView.stablePortalEntry(from: components) ?? entryURL
        } else {
            stableEntry = entryURL
        }
        start(at: stableEntry)
    }

    func isWebsiteDataRecordRelevant(_ displayName: String) -> Bool {
        let candidate = displayName.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        guard !candidate.isEmpty, let schoolDomain else { return false }
        return candidate == schoolDomain || candidate.hasSuffix("." + schoolDomain)
    }

    static func safeDisplayAddress(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.host ?? "学校网页" }
        components.user = nil
        components.password = nil
        if let fragment = components.fragment, !fragment.contains("?"),
           let items = URLComponents(string: "https://portal.invalid/?\(fragment)")?.queryItems {
            let tokenNames: Set<String> = ["ticket", "code", "access_token", "id_token", "oauth_token"]
            if items.contains(where: { tokenNames.contains($0.name.lowercased()) }) { components.fragment = nil }
        }
        return ImportScheduleView.stablePortalEntry(from: components)?.absoluteString ?? (url.host ?? "学校网页")
    }

    func inspectActivePage(completion: @escaping (Bool) -> Void) {
        let webView = activeWebView
        let token = snapshot(for: webView)
        webView.evaluateJavaScript(Self.loginStateInspectionScript) { [weak self, weak webView] value, error in
            guard let self, let webView, self.isCurrent(token, webView: webView) else { completion(false); return }
            if error != nil {
                self.loginIssue = "学校网页状态暂时无法读取，请等待加载完成或刷新后重试。"
                completion(false)
                return
            }
            let reason = self.scriptedLoginIssues[ObjectIdentifier(webView)] ?? ((value as? [String: Any])?["reason"] as? String)
            self.loginIssue = Self.loginMessage(for: reason)
            self.hasBlockingAuthenticationError = reason == "unknownDevice" || reason == "expiredSession"
            completion(self.loginIssue == nil)
        }
    }

    func readCurrentTimetable(completion: @escaping (Result<String, Error>) -> Void) {
        guard !isClosed, !isResetting, !isLoading, !isExtracting else {
            completion(.failure(PortalReadError.pageChanged))
            return
        }
        let webView = activeWebView
        let token = snapshot(for: webView)
        isExtracting = true
        inspectActivePage { [weak self, weak webView] readable in
            guard let self, let webView, self.isCurrent(token, webView: webView) else {
                completion(.failure(PortalReadError.pageChanged)); return
            }
            guard readable else {
                self.isExtracting = false
                let message = (self.loginIssue ?? "请先完成学校登录。") + " 登录后打开完整课表再读取；也可以使用文件导入。"
                self.errorMessage = message
                completion(.failure(PortalReadError.blocked(message)))
                return
            }
            webView.evaluateJavaScript(SchoolPortalLoginView.tableExtractionScript) { [weak self, weak webView] value, error in
                guard let self, let webView, self.isCurrent(token, webView: webView) else {
                    completion(.failure(PortalReadError.pageChanged)); return
                }
                self.isExtracting = false
                if let error {
                    self.errorMessage = "网页内容读取失败：\(error.localizedDescription)"
                    completion(.failure(error))
                } else {
                    completion(.success(value as? String ?? ""))
                }
            }
        }
    }

    static let loginStateInspectionScript = #"""
    (() => {
      let unknownDevice = false, expiredSession = false, loginForm = false;
      const visit = (doc, depth) => {
        if (!doc || depth > 5) return;
        const text = doc.body?.innerText || '';
        unknownDevice ||= /未知(?:的)?设备|设备(?:未识别|无法识别)|unknown\s+device|unrecognized\s+device/i.test(text);
        expiredSession ||= /登录(?:已)?(?:失效|过期|超时)|会话(?:已)?(?:失效|过期)|请重新登录|session\s+(?:has\s+)?expired|login\s+(?:has\s+)?expired/i.test(text);
        for (const input of doc.querySelectorAll('input[type="password"]')) {
          const style = doc.defaultView.getComputedStyle(input);
          let transparent = false;
          for (let parent = input; parent; parent = parent.parentElement) {
            if (Number(doc.defaultView.getComputedStyle(parent).opacity) === 0) transparent = true;
          }
          if (!transparent && style.display !== 'none' && style.visibility !== 'hidden' && style.visibility !== 'collapse' &&
              input.getClientRects().length && input.getBoundingClientRect().width > 0 && input.getBoundingClientRect().height > 0) loginForm = true;
        }
        for (const frame of doc.querySelectorAll('iframe, frame')) {
          try { if (frame.contentDocument?.body) visit(frame.contentDocument, depth + 1); } catch (_) {}
        }
      };
      visit(document, 0);
      return { reason: unknownDevice ? 'unknownDevice' : expiredSession ? 'expiredSession' : loginForm ? 'loginForm' : null };
    })();
    """#

    func completeJavaScriptDialog(id: UUID? = nil, accepted: Bool, input: String?) {
        guard let shown = javaScriptDialog, id == nil || id == shown.id else { return }
        let completion = activeDialogCompletion
        activeDialogCompletion = nil
        activeDialogWindow = nil
        javaScriptDialog = nil
        isDismissingDialog = true
        completion?(accepted, input)
        // Allow SwiftUI to dismiss the old panel before presenting the next one.
        // A delayed dismissal from the old UUID cannot cancel a newer dialog.
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.isDismissingDialog = false
            self?.presentNextDialog()
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard !isClosed, !isResetting, manages(webView), windows.count < maximumWindowCount,
              let identity = webView.customUserAgent, !identity.isEmpty else {
            if !isClosed { errorMessage = "学校新窗口无法打开。请关闭多余窗口后重试，或使用课表文件导入。" }
            return nil
        }
        // The provided configuration preserves opener and the exact navigation
        // request. WebKit loads it after this delegate returns, including POST.
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        let child = WKWebView(frame: .zero, configuration: configuration)
        child.customUserAgent = identity
        configure(child)
        windows.append(child)
        if let url = navigationAction.request.url { remember(url) }
        activate(child)
        return child
    }

    func webViewDidClose(_ webView: WKWebView) { closeWindow(webView) }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard manages(webView), !isClosed, !isResetting else { return }
        let identifier = ObjectIdentifier(webView)
        documentGenerations[identifier, default: 0] += 1
        scriptedLoginIssues[identifier] = nil
        dismissDialogs(for: identifier)
        if webView === activeWebView {
            generation += 1
            isExtracting = false
            loginIssue = nil
            hasBlockingAuthenticationError = false
            refreshActiveState()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard manages(webView), !isClosed, !isResetting else { return }
        if let url = webView.url { remember(url) }
        guard webView === activeWebView else { return }
        refreshActiveState()
        inspectActivePage { _ in }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error, in: webView) }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error, in: webView) }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard !isClosed, !isResetting, manages(webView) else { decisionHandler(.cancel); return }
        if navigationAction.targetFrame?.isMainFrame == true, let url = navigationAction.request.url { remember(url) }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        enqueueDialog(in: webView, frame: frame, message: message, kind: .alert, defaultText: nil) { _, _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        enqueueDialog(in: webView, frame: frame, message: message, kind: .confirm, defaultText: nil) { accepted, _ in completionHandler(accepted) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        enqueueDialog(in: webView, frame: frame, message: prompt, kind: .prompt, defaultText: defaultText) { accepted, input in completionHandler(accepted ? input : nil) }
    }

    private struct PageSnapshot {
        let generation: Int
        let documentGeneration: Int
    }

    private func snapshot(for webView: WKWebView) -> PageSnapshot {
        PageSnapshot(generation: generation, documentGeneration: documentGenerations[ObjectIdentifier(webView), default: 0])
    }

    private func isCurrent(_ snapshot: PageSnapshot, webView: WKWebView) -> Bool {
        !isClosed && !isResetting && manages(webView) && activeWebView === webView && generation == snapshot.generation &&
        documentGenerations[ObjectIdentifier(webView), default: 0] == snapshot.documentGeneration
    }

    private func configure(_ webView: WKWebView) {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        let identifier = ObjectIdentifier(webView)
        documentGenerations[identifier] = 0
        observations[identifier] = [
            webView.observe(\.url, options: [.new]) { [weak self, weak webView] _, _ in
                Task { @MainActor in
                    guard let self, let webView, self.manages(webView), !self.isClosed, self.activeWebView === webView else { return }
                    self.refreshActiveState()
                }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self, weak webView] _, _ in
                Task { @MainActor in
                    guard let self, let webView, self.manages(webView), !self.isClosed, self.activeWebView === webView else { return }
                    self.refreshActiveState()
                }
            }
        ]
    }

    private func detach(_ webView: WKWebView) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        let identifier = ObjectIdentifier(webView)
        observations[identifier] = nil
        documentGenerations[identifier] = nil
        scriptedLoginIssues[identifier] = nil
    }

    private func manages(_ webView: WKWebView) -> Bool { windows.contains { $0 === webView } }

    private func activate(_ webView: WKWebView) {
        generation += 1
        activeWebView = webView
        isExtracting = false
        loginIssue = nil
        hasBlockingAuthenticationError = false
        refreshActiveState()
    }

    private func closeWindow(_ webView: WKWebView) {
        guard webView !== rootWebView, let index = windows.firstIndex(where: { $0 === webView }) else { return }
        let wasActive = webView === activeWebView
        windows.remove(at: index)
        dismissDialogs(for: ObjectIdentifier(webView))
        detach(webView)
        if wasActive, let parent = windows.last {
            activate(parent)
            inspectActivePage { _ in }
        }
    }

    private func refreshActiveState() {
        guard !isClosed else { return }
        isLoading = preparingWindow == ObjectIdentifier(activeWebView) || activeWebView.isLoading
        canGoBack = activeWebView.canGoBack
        canGoForward = activeWebView.canGoForward
        if let url = activeWebView.url { displayAddress = Self.safeDisplayAddress(for: url) }
    }

    private func remember(_ url: URL) {
        if let host = url.host?.lowercased(), url.scheme?.lowercased() == "https" || url.scheme?.lowercased() == "http" { visitedHosts.insert(host) }
    }

    private static func schoolDomain(for host: String) -> String {
        let value = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let labels = value.split(separator: ".")
        guard labels.count > 2, !value.contains(":"), !value.allSatisfy({ $0.isNumber || $0 == "." }) else { return value }
        // School domains are fixed when this session starts. Visiting another
        // school or a cross-domain SSO page never grants permission to clear it.
        let compoundSuffixes: Set<String> = ["edu.cn", "ac.cn", "ac.uk"]
        let suffix = labels.suffix(2).joined(separator: ".")
        if compoundSuffixes.contains(suffix) { return labels.suffix(3).joined(separator: ".") }
        if labels.last == "edu" { return labels.suffix(2).joined(separator: ".") }
        // Without a public-suffix database, unknown suffixes and hosted tenants
        // use the exact entry host rather than risk deleting another tenant.
        return value
    }

    private func failed(_ error: Error, in webView: WKWebView) {
        guard (error as NSError).code != NSURLErrorCancelled, manages(webView), !isClosed, !isResetting, activeWebView === webView else { return }
        refreshActiveState()
        errorMessage = "学校网页打开失败：\(error.localizedDescription) 请检查网络、校园网要求或入口网址，刷新或重新登录后重试。"
    }

    private static func loginMessage(for reason: String?) -> String? {
        switch reason {
        case "unknownDevice": "学校提示“未知设备”。请使用“重新登录”清除此学校旧会话后重试；若仍被学校限制，请使用课表文件导入。"
        case "expiredSession": "学校登录已过期，请重新登录后再打开课表。"
        case "loginForm": "请先在学校网页完成登录，再进入教务系统打开完整课表。"
        default: nil
        }
    }

    private func enqueueDialog(in webView: WKWebView, frame: WKFrameInfo, message: String,
                               kind: JavaScriptDialog.Kind, defaultText: String?, completion: @escaping (Bool, String?) -> Void) {
        guard manages(webView), !isClosed, !isResetting else { completion(false, nil); return }
        let host = frame.request.url?.host ?? webView.url?.host ?? "学校网页"
        let reason: String?
        if message.range(of: "未知(?:的)?设备|设备(?:未识别|无法识别)|unknown\\s+device|unrecognized\\s+device", options: [.regularExpression, .caseInsensitive]) != nil {
            reason = "unknownDevice"
        } else if message.range(of: "登录(?:已)?(?:失效|过期|超时)|会话(?:已)?(?:失效|过期)|请重新登录|session\\s+(?:has\\s+)?expired", options: [.regularExpression, .caseInsensitive]) != nil {
            reason = "expiredSession"
        } else { reason = nil }
        if let reason {
            scriptedLoginIssues[ObjectIdentifier(webView)] = reason
            if webView === activeWebView {
                loginIssue = Self.loginMessage(for: reason)
                hasBlockingAuthenticationError = true
            }
        }
        let dialog = JavaScriptDialog(id: UUID(), title: "\(host) 的网页提示", message: message, kind: kind, defaultText: defaultText)
        pendingDialogs.append((dialog, ObjectIdentifier(webView), completion))
        presentNextDialog()
    }

    private func presentNextDialog() {
        guard activeDialogCompletion == nil, !isDismissingDialog, !pendingDialogs.isEmpty, !isClosed, !isResetting else { return }
        let next = pendingDialogs.removeFirst()
        javaScriptDialog = next.0
        activeDialogWindow = next.1
        activeDialogCompletion = next.2
    }

    private func dismissDialogs(for identifier: ObjectIdentifier) {
        let removed = pendingDialogs.filter { $0.1 == identifier }
        pendingDialogs.removeAll { $0.1 == identifier }
        for dialog in removed { dialog.2(false, nil) }
        if activeDialogWindow == identifier { completeJavaScriptDialog(accepted: false, input: nil) }
    }

    private func dismissAllDialogs() {
        let queued = pendingDialogs
        pendingDialogs.removeAll()
        let completion = activeDialogCompletion
        activeDialogCompletion = nil
        activeDialogWindow = nil
        javaScriptDialog = nil
        isDismissingDialog = false
        completion?(false, nil)
        for dialog in queued { dialog.2(false, nil) }
    }

    private enum PortalReadError: LocalizedError {
        case pageChanged
        case blocked(String)

        var errorDescription: String? {
            switch self {
            case .pageChanged: "网页已改变，请等待当前页面加载完成后重新读取。"
            case .blocked(let message): message
            }
        }
    }

    #if targetEnvironment(simulator)
    private static let simulatorLoginFixture = #"""
    <!doctype html><html lang="zh"><head><meta name="viewport" content="width=device-width,initial-scale=1">
    <style>body{font:17px -apple-system;padding:18px;color:#172136;background:#f7f9fc}button{display:block;font:inherit;margin:18px 0;padding:14px;border:1px solid #b9c9e0;border-radius:12px;background:white}table{font-size:14px;border-collapse:collapse}td,th{border:1px solid #bbc9d9;padding:8px}h1{font-size:24px}</style></head>
    <body><h1>门户首页</h1><p id="identity"></p><button onclick="openTeaching()">打开教务系统</button>
    <button onclick="testDialogs()">测试连续网页确认</button><p id="confirmation-result"></p>
    <button onclick="alert('未知设备')">模拟设备识别异常</button><p>登录与新窗口使用同一个学校会话。</p>
    <table><tr><th>课程名称</th><th>教师</th><th>教室</th><th>星期</th><th>节次</th><th>周次</th></tr>
    <tr><td>网页登录示例课</td><td>李老师</td><td>A101</td><td>星期一</td><td>第1-2节</td><td>1-20周</td></tr></table>
    <script>
    document.getElementById('identity').textContent = '浏览器：' + (navigator.userAgent.includes('Safari/') ? 'Safari' : '未识别');
    function testDialogs() {
      alert('网页提示一');
      const accepted = confirm('是否继续进入教务系统？');
      document.getElementById('confirmation-result').textContent = accepted ? '网页确认已完成' : '网页确认已取消';
    }
    function openTeaching() {
      const child = window.open('about:blank', 'teaching');
      if (!child) return;
      child.document.open();
      child.document.write('<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{font:17px -apple-system;padding:20px;background:#f7f9fc}button{font:inherit;padding:16px;border:1px solid #b9c9e0;border-radius:12px;background:white}h1{font-size:24px}</style></head><body><h1>教务子页面</h1><p id="child-identity"></p><p>课程网页已在新窗口打开。</p><button onclick="window.close()">关闭教务窗口</button><scr' + 'ipt>document.getElementById("child-identity").textContent="浏览器："+(navigator.userAgent.includes("Safari/")?"Safari":"未识别")+" · 父窗口："+(window.opener?"已连接":"未连接");if(window.opener)window.opener.postMessage("teaching-ready","*");</scr' + 'ipt></body></html>');
      child.document.close();
    }
    </script></body></html>
    """#
    #endif
}
