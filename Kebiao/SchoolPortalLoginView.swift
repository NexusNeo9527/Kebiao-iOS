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
            do {
                preview = try ScheduleImportService.parseSchoolPortalPayload(payload, sourceName: sourceName)
                dismiss()
            } catch {
                errorMessage = "\(error.localizedDescription) 请确认当前显示的是完整课表，并尽量切换到列表或表格视图。"
            }
        }
    }

    private static let tableExtractionScript = #"""
    (() => {
      const clean = value => (value || '').replace(/\s+/g, ' ').trim();
      const visible = element => {
        const style = window.getComputedStyle(element);
        return style.display !== 'none' && style.visibility !== 'hidden';
      };
      const tables = Array.from(document.querySelectorAll('table')).filter(visible);
      if (tables.length > 0) {
        return tables.map(table => Array.from(table.rows).map(row =>
          Array.from(row.cells).map(cell => clean(cell.innerText)).join('\t')
        ).filter(Boolean).join('\n')).filter(Boolean).join('\n\n');
      }
      return document.body ? document.body.innerText : '';
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
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding private var isLoading: Bool

        init(isLoading: Binding<Bool>) {
            _isLoading = isLoading
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
