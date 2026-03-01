import SwiftUI
import WebKit

// MARK: - PressReaderWebView

struct PressReaderWebView: UIViewRepresentable {

    let initialURL: URL
    let pressReaderPath: String  // ex: "switzerland/le-temps"

    private static let injectedJS = """
    (function() {

        // 1. Masquer la navbar PressReader
        var style = document.getElementById('__bavl_style');
        if (!style) {
            style = document.createElement('style');
            style.id = '__bavl_style';
            style.textContent = `
                .header, .site-header, nav.navbar, [class*="header"],
                [class*="Header"], [class*="nav-bar"], [class*="NavBar"],
                [class*="top-bar"], [class*="TopBar"] {
                    display: none !important;
                }
                body, #root, .app-container {
                    padding-top: 0 !important;
                    margin-top: 0 !important;
                }
            `;
            (document.head || document.documentElement).appendChild(style);
        }

        // 2. Fermer le popup "Bienvenue"
        function dismissPopup() {
            var selectors = [
                'button[aria-label="Close"]', 'button[aria-label="Fermer"]',
                'button.welcome-dialog__close', '.modal-close',
                '[data-testid="welcome-dismiss"]'
            ];
            for (var i = 0; i < selectors.length; i++) {
                var btn = document.querySelector(selectors[i]);
                if (btn) { btn.click(); return true; }
            }
            var buttons = document.querySelectorAll('button');
            for (var j = 0; j < buttons.length; j++) {
                var t = (buttons[j].innerText || '').toLowerCase().trim();
                if (t === 'close' || t === 'fermer' || t === 'x' || t === 'x') {
                    buttons[j].click(); return true;
                }
            }
            return false;
        }
        if (!dismissPopup()) {
            var popupObs = new MutationObserver(function(_, obs) {
                if (dismissPopup()) obs.disconnect();
            });
            popupObs.observe(document.documentElement, { childList: true, subtree: true });
            setTimeout(function() { popupObs.disconnect(); }, 10000);
        }

        var path = window.location.pathname;

        // 3. Sur /archive : extraire la derniere date disponible
        if (path.endsWith('/archive')) {
            function extractLatestDate() {
                var links = document.querySelectorAll('a[href]');
                var dates = [];
                var re = /\\/([0-9]{8})(?:\\/|$)/;
                for (var i = 0; i < links.length; i++) {
                    var m = links[i].getAttribute('href').match(re);
                    if (m) dates.push(m[1]);
                }
                if (dates.length === 0) return false;
                dates.sort();
                var latest = dates[dates.length - 1];
                window.webkit.messageHandlers.lastEdition.postMessage(latest);
                return true;
            }
            if (!extractLatestDate()) {
                var archObs = new MutationObserver(function(_, obs) {
                    if (extractLatestDate()) obs.disconnect();
                });
                archObs.observe(document.documentElement, { childList: true, subtree: true });
                setTimeout(function() { archObs.disconnect(); }, 8000);
            }
        }

        // 4. Sur /textview : detecter page blanche
        if (path.indexOf('/textview') !== -1) {
            setTimeout(function() {
                var article = document.querySelector('article, .article-content, .text-content');
                var isEmpty = !article || article.innerText.trim().length < 50;
                var title = document.title || '';
                var notFound = title.toLowerCase().indexOf('not found') !== -1
                            || title.toLowerCase().indexOf('404') !== -1;
                if (isEmpty || notFound) {
                    window.webkit.messageHandlers.pageBlank.postMessage(window.location.href);
                }
            }, 3000);
        }

    })();
    """

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.userContentController.add(context.coordinator, name: "lastEdition")
        config.userContentController.add(context.coordinator, name: "pageBlank")
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = wv
        context.coordinator.pressReaderPath = pressReaderPath
        wv.load(URLRequest(url: initialURL))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var pressReaderPath: String = ""

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let url = webView.url?.absoluteString ?? "nil"
            print("BAVL didFinish:", url)
            webView.evaluateJavaScript(PressReaderWebView.injectedJS) { _, err in
                if let err = err { print("BAVL JS error:", err) }
            }
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            switch message.name {
            case "lastEdition":
                guard let date = message.body as? String,
                      let url = URL(string: "https://www.pressreader.com/\(pressReaderPath)/\(date)/textview")
                else { return }
                DispatchQueue.main.async { self.webView?.load(URLRequest(url: url)) }

            case "pageBlank":
                guard let url = URL(string: "https://www.pressreader.com/\(pressReaderPath)/archive")
                else { return }
                DispatchQueue.main.async { self.webView?.load(URLRequest(url: url)) }

            default: break
            }
        }
    }
}

// MARK: - PressReaderSheet

struct PressReaderSheet: View {
    let newspaper: Newspaper
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let url = newspaper.resolvedURL {
                PressReaderWebView(
                    initialURL: url,
                    pressReaderPath: newspaper.pressReaderPath
                )
                .ignoresSafeArea()
            } else {
                ContentUnavailableView("URL invalide", systemImage: "xmark.circle")
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .padding(.top, 56)
            .padding(.leading, 16)
        }
    }
}
