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

        // 3. Sur /archive : extraire la dernière date (SPA — attendre le rendu)
        if (path.indexOf('/archive') !== -1) {
            var __sent = false;

            function extractDatesFromDOM() {
                if (__sent) return false;
                var dates = [];
                // Chercher dans les liens <a href="/switzerland/le-temps/20260228">
                var links = document.querySelectorAll('a[href]');
                var reLink = /\\/([0-9]{8})(?:\\/|$)/;
                for (var i = 0; i < links.length; i++) {
                    var href = links[i].getAttribute('href') || '';
                    var m = reLink.exec(href);
                    if (m) {
                        var d = m[1];
                        if (d >= '20200101' && d <= '20301231') dates.push(d);
                    }
                }
                // Chercher dans les attributs data-* (ex: data-date="20260228")
                var all = document.querySelectorAll('[data-date],[data-issue-date],[data-edition]');
                for (var k = 0; k < all.length; k++) {
                    var attrs = ['data-date','data-issue-date','data-edition'];
                    for (var a = 0; a < attrs.length; a++) {
                        var val = all[k].getAttribute(attrs[a]) || '';
                        var clean = val.replace(/-/g,'');
                        if (/^[0-9]{8}$/.test(clean) && clean >= '20200101' && clean <= '20301231') {
                            dates.push(clean);
                        }
                    }
                }
                if (dates.length === 0) return false;
                dates.sort();
                var latest = dates[dates.length - 1];
                __sent = true;
                console.log('BAVL latest (dom):', latest);
                window.webkit.messageHandlers.lastEdition.postMessage(latest);
                return true;
            }

            // Tentative via l'API interne que la SPA utilise
            function tryAPIFetch() {
                if (__sent) return;
                var parts = window.location.pathname.replace(/^\\//, '').split('/');
                if (parts.length < 2) return;
                var cid = parts.slice(0, parts.length - 1).join('/');

                // Essayer plusieurs endpoints possibles
                var endpoints = [
                    'https://services.pressreader.com/api/catalog/issues?cid=' + encodeURIComponent(cid) + '&count=5',
                    'https://cdn1.pressreader.com/api/issues?cid=' + encodeURIComponent(cid) + '&count=5'
                ];

                endpoints.forEach(function(url) {
                    if (__sent) return;
                    fetch(url, {credentials: 'include'})
                        .then(function(r) { return r.json(); })
                        .then(function(data) {
                            if (__sent) return;
                            var str = JSON.stringify(data);
                            var re = /[^0-9]([0-9]{8})[^0-9]/g;
                            var dates = [];
                            var m;
                            while ((m = re.exec(str)) !== null) {
                                var d = m[1];
                                if (d >= '20200101' && d <= '20301231') dates.push(d);
                            }
                            if (dates.length > 0) {
                                dates.sort();
                                var latest = dates[dates.length - 1];
                                __sent = true;
                                console.log('BAVL latest (api):', latest);
                                window.webkit.messageHandlers.lastEdition.postMessage(latest);
                            }
                        })
                        .catch(function(e) { console.log('BAVL api error:', e.message || e); });
                });
            }

            tryAPIFetch();

            // MutationObserver : déclenche dès que la SPA injecte du contenu
            var domObserver = new MutationObserver(function() { extractDatesFromDOM(); });
            domObserver.observe(document.documentElement, {childList: true, subtree: true, attributes: true, attributeFilter: ['href','data-date','data-issue-date','data-edition']});

            // Polling de secours toutes les secondes pendant 20s
            var tries = 0;
            var iv = setInterval(function() {
                tries++;
                if (extractDatesFromDOM() || tries >= 20) {
                    clearInterval(iv);
                    domObserver.disconnect();
                    if (!__sent) {
                        // Fallback : essayer avec hier
                        var d = new Date();
                        d.setDate(d.getDate() - 1);
                        var fallback = '' + d.getFullYear()
                            + String(d.getMonth()+1).padStart(2,'0')
                            + String(d.getDate()).padStart(2,'0');
                        console.log('BAVL fallback date:', fallback);
                        __sent = true;
                        window.webkit.messageHandlers.lastEdition.postMessage(fallback);
                    }
                }
            }, 1000);
        }

        // 4. Sur /textview : détecter page blanche après 3s
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
            if let url = newspaper.archiveURL {
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
