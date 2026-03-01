import SwiftUI
import WebKit

// MARK: - PressReaderWebView

struct PressReaderWebView: UIViewRepresentable {

    let initialURL: URL
    let pressReaderPath: String  // ex: "switzerland/le-temps"

    private static let injectedJS = """
    (function() {

        // 1. Masquer la navbar PressReader
        if (!document.getElementById('__bavl_style')) {
            var s = document.createElement('style');
            s.id = '__bavl_style';
            s.textContent = `
                .header, .site-header, nav.navbar, [class*="header"],
                [class*="Header"], [class*="nav-bar"], [class*="NavBar"],
                [class*="top-bar"], [class*="TopBar"] { display: none !important; }
                body, #root, .app-container { padding-top: 0 !important; margin-top: 0 !important; }
            `;
            (document.head || document.documentElement).appendChild(s);
        }

        // 2. Fermer le popup "Bienvenue"
        function dismissPopup() {
            var sel = ['button[aria-label="Close"]','button[aria-label="Fermer"]',
                       'button.welcome-dialog__close','.modal-close','[data-testid="welcome-dismiss"]'];
            for (var i = 0; i < sel.length; i++) {
                var b = document.querySelector(sel[i]);
                if (b) { b.click(); return true; }
            }
            var btns = document.querySelectorAll('button');
            for (var j = 0; j < btns.length; j++) {
                var t = (btns[j].innerText || '').toLowerCase().trim();
                if (t === 'close' || t === 'fermer' || t === 'x') { btns[j].click(); return true; }
            }
            return false;
        }
        if (!dismissPopup()) {
            var pObs = new MutationObserver(function(_, o) { if (dismissPopup()) o.disconnect(); });
            pObs.observe(document.documentElement, {childList:true, subtree:true});
            setTimeout(function() { pObs.disconnect(); }, 10000);
        }

        var path = window.location.pathname;

        // 3. Sur /archive : scanner le HTML brut toutes les secondes pour trouver la derniere date
        if (path.indexOf('/archive') !== -1) {
            var __sent = false;
            var __tries = 0;
            function findLatest() {
                if (__sent) return;
                var html = document.documentElement.innerHTML;
                var re = /\\/([0-9]{8})(?:\\/|")/g;
                var dates = [], m;
                while ((m = re.exec(html)) !== null) {
                    var d = m[1];
                    if (d >= '20200101' && d <= '20301231') dates.push(d);
                }
                if (dates.length === 0) return;
                dates.sort();
                var latest = dates[dates.length - 1];
                __sent = true;
                console.log('BAVL latest:', latest);
                window.webkit.messageHandlers.lastEdition.postMessage(latest);
            }
            findLatest();
            if (!__sent) {
                var iv = setInterval(function() {
                    __tries++;
                    findLatest();
                    if (__sent || __tries >= 15) clearInterval(iv);
                }, 1000);
            }
        }

        // 4. Sur /textview : detecter page blanche apres 3s
        if (path.indexOf('/textview') !== -1) {
            setTimeout(function() {
                var article = document.querySelector('article, .article-content, .text-content');
                var isEmpty = !article || article.innerText.trim().length < 50;
                var title = document.title || '';
                var notFound = title.toLowerCase().indexOf('not found') !== -1 || title === '';
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
            print("BAVL message:", message.name, message.body)
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
