import SwiftUI
import WebKit

struct TopologySnapshot: Encodable {
    let node: ManagedNode
    let overview: Overview
    let sites: [Site]
    let projects: [ProjectHealth]
    let jobs: [JobState]
}

struct TopologyWebView: UIViewRepresentable {
    let snapshot: TopologySnapshot

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "hostwatchTopology")

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = UIColor(red: 6 / 255, green: 10 / 255, blue: 16 / 255, alpha: 1)
        view.scrollView.backgroundColor = view.backgroundColor
        view.scrollView.isScrollEnabled = false
        view.scrollView.bounces = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.allowsBackForwardNavigationGestures = false
        #if DEBUG
        view.isInspectable = true
        #endif

        context.coordinator.load(snapshot, in: view)
        guard let url = Bundle.main.url(forResource: "ios-topology", withExtension: "html") else {
            assertionFailure("The bundled Repo Lens topology renderer is missing")
            return view
        }
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.load(snapshot, in: view)
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "hostwatchTopology")
        view.navigationDelegate = nil
        view.stopLoading()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private var ready = false
        private var pendingPayload: String?
        private var deliveredPayload: String?
        private var deliveringPayload: String?

        func load(_ snapshot: TopologySnapshot, in view: WKWebView) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            let payload = data.base64EncodedString()
            guard payload != pendingPayload, payload != deliveredPayload else { return }
            pendingPayload = payload
            deliverIfReady(in: view)
        }

        private func deliverIfReady(in view: WKWebView) {
            guard ready, let payload = pendingPayload else { return }
            guard deliveringPayload != payload else { return }
            deliveringPayload = payload
            let script = "window.HostwatchTopology.mount(JSON.parse(atob('\(payload)')))"
            view.evaluateJavaScript(script) { [weak self] _, error in
                guard let self else { return }
                self.deliveringPayload = nil
                guard error == nil else { return }
                self.deliveredPayload = payload
                if self.pendingPayload == payload { self.pendingPayload = nil }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            deliverIfReady(in: webView)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "hostwatchTopology" else { return }
            ready = true
            if let view = message.webView { deliverIfReady(in: view) }
        }
    }
}
