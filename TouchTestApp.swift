import SwiftUI
import WebKit

@main
struct TouchTestApp: App {
    var body: some Scene {
        WindowGroup {
            TouchTestView()
                .preferredColorScheme(.dark)
        }
    }
}

// Bundled scenarios stay in sync with Pages and never require a network connection.
struct OfflineSuiteView: UIViewControllerRepresentable {
    let onClose: () -> Void
    func makeUIViewController(context: Context) -> SuiteWebController {
        let controller = SuiteWebController()
        controller.onClose = onClose
        return controller
    }
    func updateUIViewController(_ controller: SuiteWebController, context: Context) { controller.onClose = onClose }
    static func dismantleUIViewController(_ controller: SuiteWebController, coordinator: ()) { controller.stop() }
}

final class SuiteWebController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate {
    var onClose: (() -> Void)?
    private var webView: WKWebView!
    private var lastInsets: UIEdgeInsets?
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(self, name: "touchTestNative")
        let bridge = """
        window.touchTestNative = true;
        document.addEventListener('DOMContentLoaded', () => {
          const button = document.createElement('button');
          button.id = 'nativeBack'; button.textContent = '返回';
          button.style.cssText = 'background:#111;color:#fff;border:1px solid #666;border-radius:7px;padding:4px 7px;font-size:11px';
          button.onclick = () => window.webkit.messageHandlers.touchTestNative.postMessage({action:'close'});
          document.querySelector('.title').append(button);
        });
        """
        configuration.userContentController.addUserScript(WKUserScript(source: bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        if let folder = Bundle.main.url(forResource: "Web", withExtension: nil),
           FileManager.default.fileExists(atPath: folder.appendingPathComponent("index.html").path) {
            webView.loadFileURL(folder.appendingPathComponent("index.html"), allowingReadAccessTo: folder)
        } else {
            webView.loadHTMLString("<meta name='viewport' content='width=device-width'><body style='background:black;color:white;font:18px -apple-system;padding:40px'>离线测试资源缺失，请重新下载最新版 IPA。</body>", baseURL: nil)
            let button = UIButton(type: .system)
            button.setTitle("返回", for: .normal)
            button.addTarget(self, action: #selector(closeSuite), for: .touchUpInside)
            button.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(button)
            NSLayoutConstraint.activate([button.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8)])
        }
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if ProcessInfo.processInfo.arguments.contains("--landscape"), let scene = view.window?.windowScene {
            setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
        }
    }
    override func viewSafeAreaInsetsDidChange() { super.viewSafeAreaInsetsDidChange(); syncSafeInsets() }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); syncSafeInsets() }
    private func syncSafeInsets() {
        guard isViewLoaded, webView != nil else { return }
        let windowInsets = view.window?.safeAreaInsets ?? .zero
        let local = view.safeAreaInsets
        let inset = UIEdgeInsets(top: max(local.top, windowInsets.top), left: max(local.left, windowInsets.left), bottom: max(local.bottom, windowInsets.bottom), right: max(local.right, windowInsets.right))
        guard lastInsets != inset else { return }; lastInsets = inset
        let script = """
        if(document.documentElement){
          const root=document.documentElement.style;
          root.setProperty('--native-safe-top','\(inset.top)px');
          root.setProperty('--native-safe-right','\(inset.right)px');
          root.setProperty('--native-safe-bottom','\(inset.bottom)px');
          root.setProperty('--native-safe-left','\(inset.left)px');
          window.dispatchEvent(new Event('resize'));
        }
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { lastInsets = nil; syncSafeInsets() }
    @objc private func closeSuite() { onClose?() }
    func stop() {
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "touchTestNative")
        webView?.navigationDelegate = nil
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.isFileURL == true,
              let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        if action == "close" { onClose?(); return }
        guard action == "export", let content = body["content"] as? String,
              let filename = body["filename"] as? String,
              content.utf8.count <= 12_000_000, filename.hasSuffix(".json") || filename.hasSuffix(".csv") else { return }
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TouchTestExports", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent((filename as NSString).lastPathComponent)
            try content.write(to: url, atomically: true, encoding: .utf8)
            guard presentedViewController == nil else { return }
            let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            share.popoverPresentationController?.sourceView = view
            share.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            present(share, animated: true)
        } catch {
            let alert = UIAlertController(title: "导出失败", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            if presentedViewController == nil { present(alert, animated: true) }
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let allowed = navigationAction.request.url?.isFileURL == true || navigationAction.request.url?.absoluteString == "about:blank"
        decisionHandler(allowed ? .allow : .cancel)
    }
}
