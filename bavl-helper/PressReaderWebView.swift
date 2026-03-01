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

        // 3. Sur /archive : extraire le bearer token et l'envoyer à Swift
        if (path.indexOf('/archive') !== -1) {
            var token = (window.preset && window.preset.bearerToken) ? window.preset.bearerToken : null;
            if (token) {
                window.webkit.messageHandlers.bearerToken.postMessage(token);
            } else {
                // Le preset n'est pas encore disponible, on attend un peu
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
        config.userContentController.add(context.coordinator, name: "bearerToken")
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

            case "bearerToken":
                let token = message.body as? String ?? ""
                print("BAVL bearerToken received, length:", token.count)
                if token.isEmpty {
                    print("BAVL bearer token vide, fallback DOM")
                    loadFallbackDate()
                } else {
                    fetchLastEditionViaAPI(bearerToken: token)
                }

            case "pageBlank":
                guard let url = URL(string: "https://www.pressreader.com/\(pressReaderPath)/archive")
                else { return }
                print("BAVL pageBlank → retour archive")
                DispatchQueue.main.async { self.webView?.load(URLRequest(url: url)) }

            default:
                break
            }
        }

        // MARK: - Appel API direct avec le bearer token

        private func fetchLastEditionViaAPI(bearerToken: String) {
            // L'URL de service est https://ingress.pressreader.com/services/
            // On reconstruit le cid depuis pressReaderPath (ex: "switzerland/le-temps")
            let cid = pressReaderPath
            guard let encoded = cid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://ingress.pressreader.com/services/catalog/issues?cid=\(encoded)&count=3")
            else {
                print("BAVL URL API invalide")
                loadFallbackDate()
                return
            }

            var request = URLRequest(url: url, timeoutInterval: 10)
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            print("BAVL API call →", url.absoluteString)

            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }

                if let error = error {
                    print("BAVL API error:", error.localizedDescription)
                    self.loadFallbackDate()
                    return
                }

                guard let data = data else {
                    print("BAVL API no data")
                    self.loadFallbackDate()
                    return
                }

                // Log la réponse brute pour debug
                let raw = String(data: data, encoding: .utf8) ?? "(non-utf8)"
                print("BAVL API response (first 300):", String(raw.prefix(300)))

                // Extraire la première date YYYYMMDD valide
                if let date = self.extractLatestDate(from: raw) {
                    print("BAVL API date trouvée:", date)
                    self.navigateToTextView(date: date)
                } else {
                    print("BAVL API aucune date extraite")
                    self.loadFallbackDate()
                }
            }.resume()
        }

        // MARK: - Extraction de date depuis JSON brut

        private func extractLatestDate(from json: String) -> String? {
            let pattern = "[^0-9]([0-9]{8})[^0-9]"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let padded = " \(json) "
            let range = NSRange(padded.startIndex..., in: padded)
            var dates: [String] = []
            regex.enumerateMatches(in: padded, range: range) { match, _, _ in
                guard let match = match,
                      let r = Range(match.range(at: 1), in: padded) else { return }
                let d = String(padded[r])
                if d >= "20200101" && d <= "20301231" {
                    dates.append(d)
                }
            }
            return dates.sorted().last
        }

        // MARK: - Fallback : hier

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

        // MARK: - Navigation vers textview

        private func navigateToTextView(date: String) {
            guard let url = URL(string: "https://www.pressreader.com/\(pressReaderPath)/\(date)/textview")
            else { return }
            DispatchQueue.main.async { self.webView?.load(URLRequest(url: url)) }
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
