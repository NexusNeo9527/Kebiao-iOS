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
    @State private var address = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                HStack {
                    TextField("学校网页地址", text: $address)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .onSubmit { openAddress() }
                    Button("前往") { openAddress() }
                    Button { webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("刷新网页")
                }
                .padding(.horizontal)
                Text("登录后进入教务系统，选择学期并打开完整课表，再点下方读取。")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                ZStack {
                    PortalWebView(webView: webView, url: url, isLoading: $isLoading, errorMessage: $errorMessage)
                        .ignoresSafeArea(edges: .bottom)
                    if isLoading {
                        ProgressView("正在打开教务系统…")
                            .padding(18)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .onAppear { address = url.absoluteString }
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

    private func openAddress() {
        guard let components = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https", components.host != nil,
              let entry = ImportScheduleView.stablePortalEntry(from: components) else {
            errorMessage = "请输入学校提供的 HTTPS 网址。"
            return
        }
        address = entry.absoluteString
        webView.load(URLRequest(url: entry))
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

private struct PortalWebView: UIViewRepresentable {
    let webView: WKWebView
    let url: URL
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, errorMessage: $errorMessage)
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
        @Binding private var errorMessage: String?

        init(isLoading: Binding<Bool>, errorMessage: Binding<String?>) {
            _isLoading = isLoading
            _errorMessage = errorMessage
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
            failed(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            failed(error)
        }

        private func failed(_ error: Error) {
            isLoading = false
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            errorMessage = "学校网页打开失败：\(error.localizedDescription) 请检查网络、校园网要求或入口网址，然后刷新重试。"
        }
    }
}
