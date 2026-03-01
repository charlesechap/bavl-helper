import SwiftUI
import WebKit

// MARK: - Palette (miroir ContentView)
private extension Color {
    static let bg      = Color(red: 0.13, green: 0.13, blue: 0.13)
    static let fg      = Color(red: 0.80, green: 0.80, blue: 0.80)
    static let fgDim   = Color(red: 0.50, green: 0.50, blue: 0.50)
    static let fgFaint = Color(red: 0.30, green: 0.30, blue: 0.30)
}

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

        // 3. Sur /archive : extraire le bearer token et l'envoyer a Swift
        if (path.indexOf('/archive') !== -1) {
            var token = (window.preset && window.preset.bearerToken) ? window.preset.bearerToken : null;
            if (token) {
                window.webkit.messageHandlers.bearerToken.postMessage(token);
            } else {
                setTimeout(function() {
                    var t2 = (window.preset && window.preset.bearerToken) ? window.preset.bearerToken : null;
                    if (t2) {
                        window.webkit.messageHandlers.bearerToken.postMessage(t2);
                    } else {
                        window.webkit.messageHandlers.bearerToken.postMessage('');
                    }
                }, 500);
            }
        }

        // 4. Sur /textview : envoyer le titre et detecter page blanche
        if (path.indexOf('/textview') !== -1) {
            function sendTitle() {
                var title = document.title || '';
                if (title !== '') {
                    window.webkit.messageHandlers.pageTitle.postMessage(title);
                }
            }
            sendTitle();
            var titleObs = new MutationObserver(function() { sendTitle(); });
            var titleEl = document.querySelector('title');
            if (titleEl) titleObs.observe(titleEl, {childList:true, subtree:true, characterData:true});
            setTimeout(function() { titleObs.disconnect(); }, 5000);

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
        config.userContentController.add(context.coordinator, name: "bearerToken")
        config.userContentController.add(context.coordinator, name: "pageBlank")
        config.userContentController.add(context.coordinator, name: "pageTitle")
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
        var onTitleChange: ((String) -> Void)?
        var onURLChange: ((URL?) -> Void)?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let url = webView.url?.absoluteString ?? "nil"
            print("BAVL didFinish:", url)
            DispatchQueue.main.async { self.onURLChange?(webView.url) }
            webView.evaluateJavaScript(PressReaderWebView.injectedJS) { _, err in
                if let err = err { print("BAVL JS error:", err) }
            }
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            switch message.name {

            case "bearerToken":
                let token = message.body as? String ?? ""
                print("BAVL bearerToken received, length:", token.count)
                if token.isEmpty {
                    loadFallbackDate()
                } else {
                    fetchLastEditionViaAPI(bearerToken: token)
                }

            case "pageBlank":
                guard let url = URL(string: "https://www.pressreader.com/\(pressReaderPath)/archive")
                else { return }
                print("BAVL pageBlank -> retour archive")
                DispatchQueue.main.async { self.webView?.load(URLRequest(url: url)) }

            case "pageTitle":
                let title = message.body as? String ?? ""
                print("BAVL pageTitle:", title)
                DispatchQueue.main.async { self.onTitleChange?(title) }

            default:
                break
            }
        }

        // MARK: - API

        private func fetchLastEditionViaAPI(bearerToken: String) {
            let cid = pressReaderPath
            guard let encoded = cid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://ingress.pressreader.com/services/catalog/issues?cid=\(encoded)&count=3")
            else { loadFallbackDate(); return }

            var request = URLRequest(url: url, timeoutInterval: 10)
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            print("BAVL API call ->", url.absoluteString)

            URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
                guard let self = self else { return }
                guard let data = data, error == nil else { self.loadFallbackDate(); return }
                let raw = String(data: data, encoding: .utf8) ?? ""
                print("BAVL API response (first 300):", String(raw.prefix(300)))
                if let date = self.extractLatestDate(from: raw) {
                    print("BAVL API date trouvee:", date)
                    self.navigateToTextView(date: date)
                } else {
                    self.loadFallbackDate()
                }
            }.resume()
        }

        private func extractLatestDate(from json: String) -> String? {
            let pattern = "[^0-9]([0-9]{8})[^0-9]"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let padded = " \(json) "
            let range = NSRange(padded.startIndex..., in: padded)
            var dates: [String] = []
            regex.enumerateMatches(in: padded, range: range) { match, _, _ in
                guard let match = match, let r = Range(match.range(at: 1), in: padded) else { return }
                let d = String(padded[r])
                if d >= "20200101" && d <= "20301231" { dates.append(d) }
            }
            return dates.sorted().last
        }

        private func loadFallbackDate() {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
            let yesterday = cal.date(byAdding: .day, value: -1, to: Date())!
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyyMMdd"
            fmt.timeZone = TimeZone(identifier: "Europe/Zurich")
            let date = fmt.string(from: yesterday)
            print("BAVL fallback date:", date)
            navigateToTextView(date: date)
        }

        private func navigateToTextView(date: String) {
            guard let url = URL(string: "https://www.pressreader.com/\(pressReaderPath)/\(date)/textview")
            else { return }
            DispatchQueue.main.async { self.webView?.load(URLRequest(url: url)) }
        }

        // MARK: - Actions toolbar

        func goToPreviousArticle() {
            webView?.go(back: true)
        }

        func goToNextArticle() {
            webView?.go(forward: true)
        }

        func goToArchive() {
            guard let url = URL(string: "https://www.pressreader.com/\(pressReaderPath)/archive")
            else { return }
            webView?.load(URLRequest(url: url))
        }
    }
}

// MARK: - PressReaderSheet

struct PressReaderSheet: View {
    let newspaper: Newspaper
    @Environment(\.dismiss) private var dismiss

    @State private var currentURL: URL? = nil
    @State private var coordinator: PressReaderWebView.Coordinator? = nil

    private var isOnArticle: Bool {
        currentURL?.absoluteString.contains("/textview") == true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if let url = newspaper.archiveURL {
                    _PressReaderWebViewBridge(
                        initialURL: url,
                        pressReaderPath: newspaper.pressReaderPath,
                        onCoordinatorReady: { coordinator = $0 },
                        onURLChange: { currentURL = $0 }
                    )
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView("URL invalide", systemImage: "xmark.circle")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("X") { dismiss() }
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color.fgDim)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isOnArticle {
                        Button("[◁◁]") { coordinator?.goToPreviousArticle() }
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Color.fg)
                        Button("[▷▷]") { coordinator?.goToNextArticle() }
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Color.fg)
                        Button("[≡]") { coordinator?.goToArchive() }
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Color.fg)
                        if let url = currentURL {
                            ShareLink(item: url) {
                                Text("[↑]")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(Color.fg)
                            }
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Bridge UIViewRepresentable pour exposer le coordinator

private struct _PressReaderWebViewBridge: UIViewRepresentable {
    let initialURL: URL
    let pressReaderPath: String
    var onCoordinatorReady: (PressReaderWebView.Coordinator) -> Void
    var onURLChange: ((URL?) -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.userContentController.add(context.coordinator, name: "bearerToken")
        config.userContentController.add(context.coordinator, name: "pageBlank")
        config.userContentController.add(context.coordinator, name: "pageTitle")
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = wv
        context.coordinator.pressReaderPath = pressReaderPath
        context.coordinator.onURLChange = onURLChange
        wv.load(URLRequest(url: initialURL))
        DispatchQueue.main.async { self.onCoordinatorReady(context.coordinator) }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> PressReaderWebView.Coordinator {
        PressReaderWebView.Coordinator()
    }
}

// Extension pour go(back:) / go(forward:)
private extension WKWebView {
    func go(back: Bool) {
        if back { goBack() } else { goForward() }
    }
}
