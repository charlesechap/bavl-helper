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
                /* masquer header */
                .header, .site-header, nav.navbar, [class*="header"],
                [class*="Header"], [class*="nav-bar"], [class*="NavBar"],
                [class*="top-bar"], [class*="TopBar"] { display: none !important; }
                body, #root, .app-container { padding-top: 0 !important; margin-top: 0 !important; }
                /* masquer footer PressReader */
                .footer, .site-footer, footer, [class*="footer"],
                [class*="Footer"], [class*="bottom-bar"], [class*="BottomBar"],
                [class*="article-footer"], [class*="ArticleFooter"],
                .reader-footer, .text-footer, .content-footer { display: none !important; }
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
            // Charger le TOC dès qu'on est sur une page PressReader
            if url.contains("pressreader.com") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.fetchTOCIfNeeded()
                }
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
            let date = fallbackDate()
            print("BAVL fallback date:", date)
            navigateToTextView(date: date)
        }

        private func navigateToTextView(date: String) {
            guard let url = URL(string: "https://www.pressreader.com/\(pressReaderPath)/\(date)/textview")
            else { return }
            DispatchQueue.main.async { self.webView?.load(URLRequest(url: url)) }
        }

        // MARK: - TOC Navigation

        private var tocArticleIds: [Int64] = []
        private var currentIssueId: String = ""   // ex: f1652026022800000051001001
        private var currentDate: String = ""       // ex: 20260228

        /// Appel TOC depuis l'URL courante (appelé après chaque navigation)
        func fetchTOCIfNeeded() {
            guard let url = webView?.url?.absoluteString else { return }
            // Extraire la date (8 chiffres) depuis l'URL directement
            let dateRegex = try? NSRegularExpression(pattern: "/(\\d{8})/")
            if let match = dateRegex?.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
               let range = Range(match.range(at: 1), in: url) {
                self.currentDate = String(url[range])
            }
            // L'issue id est dans window.preset.cid (ex: f1652026022800000051001001)
            // On utilise l'issueId construit depuis la date et le cid de la publication
            // Chercher dans window.preset
            webView?.evaluateJavaScript("""
                (function() {
                    var p = window.preset || {};
                    var issueId = p.issueId || p.issue || (p.cid ? p.cid : '');
                    return issueId;
                })();
            """) { [weak self] result, _ in
                guard let self = self,
                      let issueId = result as? String, !issueId.isEmpty
                else { return }
                if issueId == self.currentIssueId { return }  // TOC déjà chargé
                self.currentIssueId = issueId
                self.loadTOC(issueId: issueId)
            }
        }

        private func loadTOC(issueId: String) {
            guard let url = URL(string: "https://s.prcdn.co/services/toc/?issue=\(issueId)&version=2&expungeVersion=")
            else { return }
            print("BAVL TOC fetch ->", url.absoluteString)
            URLSession.shared.dataTask(with: URLRequest(url: url)) { [weak self] data, _, error in
                guard let self = self, let data = data, error == nil else { return }
                guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let pages = root["Pages"] as? [[String: Any]]
                else { return }
                var ids: [Int64] = []
                for page in pages {
                    if let articles = page["Articles"] as? [[String: Any]] {
                        for art in articles {
                            if let idNum = art["Id"] as? Int64 {
                                ids.append(idNum)
                            } else if let idDouble = art["Id"] as? Double {
                                ids.append(Int64(idDouble))
                            }
                        }
                    }
                }
                print("BAVL TOC loaded: \(ids.count) articles")
                DispatchQueue.main.async { self.tocArticleIds = ids }
            }.resume()
        }

        private func currentArticleId() -> Int64? {
            guard let path = webView?.url?.path else { return nil }
            // path: /switzerland/le-temps/20260228/281530822504009  ou /textview
            let components = path.split(separator: "/")
            if let last = components.last, let id = Int64(last), id > 1_000_000_000_000 {
                return id
            }
            return nil
        }

        private func navigate(to articleId: Int64) {
            guard !pressReaderPath.isEmpty, !currentDate.isEmpty else { return }
            let urlStr = "https://www.pressreader.com/\(pressReaderPath)/\(currentDate)/\(articleId)/textview"
            guard let url = URL(string: urlStr) else { return }
            print("BAVL navigate ->", urlStr)
            DispatchQueue.main.async { self.webView?.load(URLRequest(url: url)) }
        }

        // MARK: - Actions toolbar

        func goToPreviousArticle() {
            guard let current = currentArticleId(),
                  let idx = tocArticleIds.firstIndex(of: current),
                  idx > 0
            else { return }
            navigate(to: tocArticleIds[idx - 1])
        }

        func goToNextArticle() {
            guard let current = currentArticleId(),
                  let idx = tocArticleIds.firstIndex(of: current),
                  idx < tocArticleIds.count - 1
            else { return }
            navigate(to: tocArticleIds[idx + 1])
        }

        func goToArchive() {
            guard let url = URL(string: "https://www.pressreader.com/\(pressReaderPath)/archive")
            else { return }
            webView?.load(URLRequest(url: url))
        }

        func goToTextView() {
            // Si on est sur un article: {path}/{date}/{articleId}/textview
            // Sinon: {path}/{date}/textview
            let date = currentDate.isEmpty ? fallbackDate() : currentDate
            if let articleId = currentArticleId() {
                let urlStr = "https://www.pressreader.com/\(pressReaderPath)/\(date)/\(articleId)/textview"
                guard let url = URL(string: urlStr) else { return }
                DispatchQueue.main.async { self.webView?.load(URLRequest(url: url)) }
            } else {
                navigateToTextView(date: date)
            }
        }

        func goToPDF() {
            // Si on est sur un article: {path}/{date}/{articleId}  (layout sans /textview)
            // Sinon: {path}/{date}
            let date = currentDate.isEmpty ? fallbackDate() : currentDate
            if let articleId = currentArticleId() {
                let urlStr = "https://www.pressreader.com/\(pressReaderPath)/\(date)/\(articleId)"
                guard let url = URL(string: urlStr) else { return }
                DispatchQueue.main.async { self.webView?.load(URLRequest(url: url)) }
            } else {
                guard let url = URL(string: "https://www.pressreader.com/\(pressReaderPath)/\(date)")
                else { return }
                DispatchQueue.main.async { self.webView?.load(URLRequest(url: url)) }
            }
        }

        private func fallbackDate() -> String {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
            let yesterday = cal.date(byAdding: .day, value: -1, to: Date())!
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyyMMdd"
            fmt.timeZone = TimeZone(identifier: "Europe/Zurich")
            return fmt.string(from: yesterday)
        }
    }
}

// MARK: - PressReaderSheet

struct PressReaderSheet: View {
    let newspaper: Newspaper
    @Environment(\.dismiss) private var dismiss

    @State private var currentURL: URL? = nil
    @State private var coordinator: PressReaderWebView.Coordinator? = nil

    // Mode d'affichage courant détecté depuis l'URL
    private var viewMode: ViewMode {
        let s = currentURL?.absoluteString ?? ""
        return s.contains("/textview") ? .text : .layout
    }

    private var isOnArticle: Bool {
        let s = currentURL?.absoluteString ?? ""
        // article avec ID 15 chiffres, avec ou sans /textview
        return s.range(of: #"/[0-9]{15}"#, options: .regularExpression) != nil
    }

    private var isOnJournal: Bool {
        // page du journal (date sans article), avec ou sans /textview
        let s = currentURL?.absoluteString ?? ""
        let hasDate = s.range(of: #"/[0-9]{8}"#, options: .regularExpression) != nil
        let hasArticle = s.range(of: #"/[0-9]{15}"#, options: .regularExpression) != nil
        return hasDate && !hasArticle
    }

    private var isOnArchive: Bool {
        currentURL?.absoluteString.contains("/archive") == true
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            // WebView plein écran, commence sous la barre custom
            if let url = newspaper.archiveURL {
                _PressReaderWebViewBridge(
                    initialURL: url,
                    pressReaderPath: newspaper.pressReaderPath,
                    onCoordinatorReady: { coordinator = $0 },
                    onURLChange: { currentURL = $0 }
                )
                .ignoresSafeArea()
                .padding(.top, 28) // hauteur de la barre custom
            } else {
                ContentUnavailableView("URL invalide", systemImage: "xmark.circle")
            }

            // Barre custom ultra-fine
            TerminalBar(
                isOnArchive: isOnArchive,
                isOnJournal: isOnJournal,
                isOnArticle: isOnArticle,
                viewMode: viewMode,
                currentURL: currentURL,
                onDismiss: { dismiss() },
                onTxt: { coordinator?.goToTextView() },
                onPdf: { coordinator?.goToPDF() },
                onPrev: { coordinator?.goToPreviousArticle() },
                onNext: { coordinator?.goToNextArticle() },
                onArchive: { coordinator?.goToArchive() }
            )
        }
        .ignoresSafeArea(edges: .top)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Barre terminal custom

private struct TerminalBar: View {
    let isOnArchive: Bool
    let isOnJournal: Bool
    let isOnArticle: Bool
    let viewMode: ViewMode
    let currentURL: URL?
    let onDismiss: () -> Void
    let onTxt: () -> Void
    let onPdf: () -> Void
    let onPrev: () -> Void
    let onNext: () -> Void
    let onArchive: () -> Void

    // Police terminal, taille légèrement augmentée
    private let termFont = Font.system(size: 14, weight: .regular, design: .monospaced)
    private let dimColor = Color(white: 0.35)
    private let activeColor = Color(white: 0.82)
    private let inactiveColor = Color(white: 0.45)

    var body: some View {
        HStack(spacing: 0) {
            // Fermer
            BarBtn("×", color: dimColor, action: onDismiss)

            Spacer()

            // Boutons contextuels
            if isOnArchive {
                BarBtn("txt", color: activeColor, action: onTxt)
                separator
                BarBtn("pdf", color: activeColor, action: onPdf)
            }

            if isOnJournal {
                // Sur la page journal: montrer mode actif et permettre de switcher
                BarBtn("txt", color: viewMode == .text ? activeColor : inactiveColor, action: onTxt)
                separator
                BarBtn("pdf", color: viewMode == .layout ? activeColor : inactiveColor, action: onPdf)
                separator
                BarBtn("≡", color: dimColor, action: onArchive)
            }

            if isOnArticle {
                BarBtn("◂◂", color: activeColor, action: onPrev)
                separator
                BarBtn("▸▸", color: activeColor, action: onNext)
                separator
                // switch txt/pdf pour l'article courant
                BarBtn("txt", color: viewMode == .text ? activeColor : inactiveColor, action: onTxt)
                separator
                BarBtn("pdf", color: viewMode == .layout ? activeColor : inactiveColor, action: onPdf)
                separator
                BarBtn("≡", color: dimColor, action: onArchive)
                if let url = currentURL {
                    separator
                    ShareLink(item: url) {
                        Text("↑")
                            .font(Font.system(size: 14, weight: .regular, design: .monospaced))
                            .foregroundStyle(activeColor)
                            .frame(height: 28)
                            .padding(.horizontal, 10)
                    }
                }
            }
        }
        .frame(height: 28)
        .background(Color.black)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(white: 0.18))
                .frame(height: 0.5)
        }
        .padding(.top, UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 44)
    }

    private var separator: some View {
        Text("|")
            .font(Font.system(size: 12, weight: .ultraLight, design: .monospaced))
            .foregroundStyle(Color(white: 0.22))
            .frame(height: 28)
    }
}

private struct BarBtn: View {
    let label: String
    let color: Color
    let action: () -> Void

    init(_ label: String, color: Color, action: @escaping () -> Void) {
        self.label = label
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Font.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundStyle(color)
                .frame(height: 28)
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

// Extension pour navigation avant/arrière
private extension WKWebView {
    func goBackward() { goBack() }
    func goForward_() { goForward() }
}
