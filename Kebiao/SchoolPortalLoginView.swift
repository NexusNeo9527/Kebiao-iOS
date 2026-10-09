import SwiftUI
import WebKit

struct SchoolPortalLoginView: View {
    let url: URL
    let sourceName: String
    @Binding var preview: ScheduleImportPreview?

    @Environment(\.dismiss) private var dismiss
    @State private var webView = WKWebView()
    @State private var isLoading = true
    @State private var isExtracting = false
    @State private var errorMessage: String?
    @State private var frameURLs: [URL] = []

    var body: some View {
        NavigationStack {
            ZStack {
                PortalWebView(webView: webView, url: url, isLoading: $isLoading)
                    .ignoresSafeArea(edges: .bottom)
                if isLoading {
                    ProgressView("正在打开教务系统…")
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .navigationTitle(sourceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { webView.goBack() } label: { Image(systemName: "chevron.backward") }
                        .disabled(!webView.canGoBack)
                        .accessibilityLabel("后退")
                    Button { webView.goForward() } label: { Image(systemName: "chevron.forward") }
                        .disabled(!webView.canGoForward)
                        .accessibilityLabel("前进")
                    Spacer()
                    Button {
                        extractCurrentTimetable()
                    } label: {
                        if isExtracting {
                            ProgressView()
                        } else {
                            Label("读取当前课表", systemImage: "tablecells")
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(isLoading || isExtracting)
                }
            }
            .confirmationDialog("课表位于独立页面，请选择入口", isPresented: Binding(
                get: { !frameURLs.isEmpty }, set: { if !$0 { frameURLs = [] } }
            ), titleVisibility: .visible) {
                ForEach(frameURLs, id: \.absoluteString) { url in
                    Button(url.host ?? "打开课表页面") {
                        webView.load(URLRequest(url: url))
                        frameURLs = []
                    }
                }
                Button("取消", role: .cancel) { frameURLs = [] }
            }
            .alert("无法读取课表", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private func extractCurrentTimetable() {
        isExtracting = true
        webView.evaluateJavaScript(Self.tableExtractionScript) { result, error in
            isExtracting = false
            if let error {
                errorMessage = "网页内容读取失败：\(error.localizedDescription)"
                return
            }
            guard let payload = result as? String,
                  !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "当前页面没有可读取的课表。请先登录并打开“学生课表”或“我的课表”页面。"
                return
            }
            if payload.hasPrefix("__KEBIAO_FRAMES__") {
                let json = String(payload.dropFirst("__KEBIAO_FRAMES__".count))
                let addresses = (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
                frameURLs = addresses.compactMap(URL.init(string:)).filter { $0.scheme == "https" }
                if frameURLs.isEmpty { errorMessage = "课表位于无法直接访问的框架，请使用学校的独立课表入口或文件导入。" }
                return
            }
            do {
                preview = try ScheduleImportService.parseSchoolPortalPayload(payload, sourceName: sourceName)
                dismiss()
            } catch {
                errorMessage = "\(error.localizedDescription) 请确认当前显示的是完整课表，并尽量切换到列表或表格视图。"
            }
        }
    }

    static let tableExtractionScript = #"""
    (() => {
      const clean = value => (value || '').replace(/\s+/g, ' ').trim();
      const tables = [];
      const texts = [];
      const frames = new Set();
      const visit = (doc, depth) => {
        if (!doc || depth > 5) return;
        const visible = element => {
          const style = doc.defaultView.getComputedStyle(element);
          return style.display !== 'none' && style.visibility !== 'hidden';
        };
        for (const table of Array.from(doc.querySelectorAll('table')).filter(visible)) {
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
      if (tables.length) return tables.join('\n\n');
      if (frames.size) return '__KEBIAO_FRAMES__' + JSON.stringify(Array.from(frames));
      return texts.join('\n\n');
    })();
    """#
}

private struct PortalWebView: UIViewRepresentable {
    let webView: WKWebView
    let url: URL
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading)
    }

    func makeUIView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        @Binding private var isLoading: Bool

        init(isLoading: Binding<Bool>) {
            _isLoading = isLoading
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
            return nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }
    }
}
