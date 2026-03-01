import SwiftUI
import WebKit

// MARK: - Palette (miroir ContentView)
private extension Color {
    static let bg      = Color(red: 0.13, green: 0.13, blue: 0.13)
    static let fg      = Color(red: 0.80, green: 0.80, blue: 0.80)
    static let fgDim   = Color(red: 0.50, green: 0.50, blue: 0.50)
    static let fgFaint = Color(red: 0.30, green: 0.30, blue: 0.30)
}

// MARK: - Modèle édition

struct PressReaderEdition: Identifiable {
    let id: String        // issueId ex: "f1652026022800000051001001"
    let date: String      // "20260301"
    let formattedDate: String
    let thumbnailURL: URL?

    init(issueId: String, date: String) {
        self.id = issueId
        self.date = date

        // Formater la date pour l'affichage
        let inp = DateFormatter()
        inp.dateFormat = "yyyyMMdd"
        inp.locale = Locale(identifier: "fr_CH")
        let out = DateFormatter()
        out.dateStyle = .full
        out.timeStyle = .none
        out.locale = Locale(identifier: "fr_CH")
        if let d = inp.date(from: date) {
            self.formattedDate = out.string(from: d).capitalized
        } else {
            self.formattedDate = date
        }

        // URL miniature PressReader
        self.thumbnailURL = URL(string: "https://i.prcdn.co/img?file=\(issueId)&page=1&width=150")
    }
}

// MARK: - PressReaderSheet (racine)

struct PressReaderSheet: View {
    let newspaper: Newspaper
    @Environment(\.dismiss) private var dismiss

    // Navigation interne
    @State private var showArchive = true          // commence par la liste archives
    @State private var selectedEdition: PressReaderEdition? = nil

    // État webview
    @State private var currentURL: URL? = nil
    @State private var coordinator: PressReaderWebView.Coordinator? = nil

    // Archives
    @State private var editions: [PressReaderEdition] = []
    @State private var archiveLoading = true
    @State private var archiveError: String? = nil
    @State private var bearerToken: String? = nil

    // Mode d'affichage courant détecté depuis l'URL
    private var viewMode: ViewMode {
        let s = currentURL?.absoluteString ?? ""
        return s.contains("/textview") ? .text : .layout
    }

    private var isOnArticle: Bool {
        let s = currentURL?.absoluteString ?? ""
        return s.range(of: #"/[0-9]{8}/[0-9]{10,}"#, options: .regularExpression) != nil
    }

    private var isOnJournal: Bool {
        let s = currentURL?.absoluteString ?? ""
        let hasDate    = s.range(of: #"/[0-9]{8}"#, options: .regularExpression) != nil
        let hasArticle = s.range(of: #"/[0-9]{8}/[0-9]{10,}"#, options: .regularExpression) != nil
        return hasDate && !hasArticle
    }

    var body: some View {
        GeometryReader { geo in
            let safeTop = geo.safeAreaInsets.top
            ZStack(alignment: .top) {
                Color.bg.ignoresSafeArea()

                if showArchive {
                    // Vue archives native
                    ArchiveListView(
                        newspaper: newspaper,
                        editions: editions,
                        loading: archiveLoading,
                        error: archiveError,
                        safeTop: safeTop,
                        onSelect: { edition in
                            selectedEdition = edition
                            showArchive = false
                            // Charger l'URL selon le mode
                            let urlStr: String
                            switch newspaper.viewMode {
                            case .text:
                                urlStr = "https://www.pressreader.com/\(newspaper.pressReaderPath)/\(edition.date)/textview"
                            case .layout:
                                urlStr = "https://www.pressreader.com/\(newspaper.pressReaderPath)/\(edition.date)"
                            }
                            currentURL = URL(string: urlStr)
                        },
                        onDismiss: { dismiss() }
                    )
                } else {
                    // Vue WebView
                    if let url = currentURL {
                        _PressReaderWebViewBridge(
                            initialURL: url,
                            pressReaderPath: newspaper.pressReaderPath,
                            onCoordinatorReady: { coordinator = $0 },
                            onURLChange: { currentURL = $0 }
                        )
                        .ignoresSafeArea()
                        .padding(.top, safeTop + 44)
                    }

                    // Barre terminal
                    TerminalBar(
                        isOnJournal: isOnJournal,
                        isOnArticle: isOnArticle,
                        viewMode: viewMode,
                        currentURL: currentURL,
                        onBack: {
                            if isOnArticle {
                                coordinator?.goToJournal()
                            } else {
                                // retour aux archives
                                showArchive = true
                            }
                        },
                        onTxt: { coordinator?.goToTextView() },
                        onPdf: { coordinator?.goToPDF() },
                        onShare: {
                            guard let coord = coordinator else { return }
                            guard let scene = UIApplication.shared.connectedScenes
                                .compactMap({ $0 as? UIWindowScene })
                                .first(where: { $0.activationState == .foregroundActive }),
                                  let window = scene.windows.first(where: { $0.isKeyWindow }),
                                  let root = window.rootViewController
                            else { return }
                            var presenter = root
                            while let p = presenter.presentedViewController { presenter = p }
                            coord.sharePDF(presenter: presenter)
                        },
                        safeAreaTop: safeTop
                    )
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .preferredColorScheme(.dark)
        .task { await loadArchives() }
    }

    // MARK: - Chargement archives

    private func loadArchives() async {
        archiveLoading = true
        archiveError = nil

        // 1. Obtenir le bearer token via une page archive PressReader
        guard let archiveURL = URL(string: "https://www.pressreader.com/\(newspaper.pressReaderPath)/archive") else {
            archiveError = "URL invalide"
            archiveLoading = false
            return
        }

        // On passe par le TokenLoader (WKWebView caché) pour obtenir le bearer token
        let token = await TokenLoader.shared.fetchToken(for: archiveURL)
        guard let token = token, !token.isEmpty else {
            archiveError = "Impossible d'obtenir le token d'authentification"
            archiveLoading = false
            return
        }
        bearerToken = token

        // 2. Appel API catalog
        let cid = newspaper.pressReaderPath
        guard let encoded = cid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let apiURL = URL(string: "https://ingress.pressreader.com/services/catalog/issues?cid=\(encoded)&count=30")
        else {
            archiveError = "Erreur URL API"
            archiveLoading = false
            return
        }

        var req = URLRequest(url: apiURL, timeoutInterval: 10)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let issues = parsed?["Issues"] as? [[String: Any]] ?? []

            var result: [PressReaderEdition] = []
            for issue in issues {
                guard let issueId = issue["Issue"] as? String, !issueId.isEmpty else { continue }
                // Extraire la date depuis l'issueId ou le champ IssueDate
                if let dateStr = extractDate(from: issue, issueId: issueId) {
                    result.append(PressReaderEdition(issueId: issueId, date: dateStr))
                }
            }
            editions = result
            archiveLoading = false
        } catch {
            archiveError = error.localizedDescription
            archiveLoading = false
        }
    }

    private func extractDate(from issue: [String: Any], issueId: String) -> String? {
        // Essayer le champ IssueDate ou IssueDateTime
        for key in ["IssueDate", "IssueDateTime", "Date", "DateTime", "PublicationDate"] {
            if let val = issue[key] as? String {
                // Format attendu: peut être ISO ou yyyyMMdd
                let cleaned = val.replacingOccurrences(of: "-", with: "").prefix(8)
                if cleaned.count == 8, Int(cleaned) != nil { return String(cleaned) }
                // Essayer ISO 8601
                let iso = DateFormatter()
                iso.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                if let d = iso.date(from: val) {
                    let out = DateFormatter()
                    out.dateFormat = "yyyyMMdd"
                    return out.string(from: d)
                }
            }
        }
        // Extraire depuis l'issueId (pattern: les 8 chiffres de date dans l'ID)
        let pattern = #"(\d{8})"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: issueId, range: NSRange(issueId.startIndex..., in: issueId)),
           let range = Range(match.range(at: 1), in: issueId) {
            let candidate = String(issueId[range])
            if candidate >= "20200101" && candidate <= "20301231" { return candidate }
        }
        return nil
    }
}

// MARK: - TokenLoader (WKWebView caché pour obtenir le bearer token)

@MainActor
class TokenLoader: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    static let shared = TokenLoader()

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String?, Never>?

    func fetchToken(for url: URL) async -> String? {
        return await withCheckedContinuation { cont in
            self.continuation = cont

            let config = WKWebViewConfiguration()
            config.websiteDataStore = .default()
            config.userContentController.add(self, name: "bearerToken")

            let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
            wv.navigationDelegate = self
            self.webView = wv

            // Attacher au UIWindow pour l'exécution JS
            if let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first?.windows.first {
                window.addSubview(wv)
                wv.isHidden = true
            }

            wv.load(URLRequest(url: url))

            // Timeout de sécurité
            Task {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                self.resolveToken(nil)
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let js = """
        (function() {
            var token = (window.preset && window.preset.bearerToken) ? window.preset.bearerToken : null;
            if (token) {
                window.webkit.messageHandlers.bearerToken.postMessage(token);
            } else {
                setTimeout(function() {
                    var t2 = (window.preset && window.preset.bearerToken) ? window.preset.bearerToken : null;
                    window.webkit.messageHandlers.bearerToken.postMessage(t2 || '');
                }, 800);
            }
        })();
        """
        webView.evaluateJavaScript(js) { _, _ in }
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "bearerToken" else { return }
        let token = message.body as? String
        resolveToken(token?.isEmpty == false ? token : nil)
    }

    private func resolveToken(_ token: String?) {
        guard let cont = continuation else { return }
        continuation = nil
        webView?.removeFromSuperview()
        webView = nil
        cont.resume(returning: token)
    }
}

// MARK: - ArchiveListView

private struct ArchiveListView: View {
    let newspaper: Newspaper
    let editions: [PressReaderEdition]
    let loading: Bool
    let error: String?
    let safeTop: CGFloat
    let onSelect: (PressReaderEdition) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Barre terminal archive
            HStack(spacing: 0) {
                BarBtn("X", color: Color(white: 0.35), action: onDismiss)
                    .padding(.leading, 8)
                Spacer()
                Text(newspaper.name.uppercased())
                    .font(Font.system(.footnote, design: .monospaced))
                    .foregroundStyle(Color(white: 0.45))
                Spacer()
                // Espace symétrique au X
                Color.clear.frame(width: 44, height: 44)
            }
            .frame(height: 44)
            .background(Color.bg)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(white: 0.18)).frame(height: 0.5)
            }
            .padding(.top, safeTop)

            if loading {
                Spacer()
                ProgressView()
                    .tint(Color(white: 0.5))
                Spacer()
            } else if let error = error {
                Spacer()
                Text("Erreur : \(error)")
                    .font(Font.system(.caption, design: .monospaced))
                    .foregroundStyle(Color(white: 0.45))
                    .padding()
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(editions) { edition in
                            EditionRow(edition: edition)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(edition) }
                            Divider()
                                .background(Color(white: 0.20))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - EditionRow

private struct EditionRow: View {
    let edition: PressReaderEdition

    var body: some View {
        HStack(spacing: 12) {
            // Miniature
            AsyncImage(url: edition.thumbnailURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 80)
                        .clipped()
                case .failure(_):
                    Rectangle()
                        .fill(Color(white: 0.20))
                        .frame(width: 60, height: 80)
                default:
                    Rectangle()
                        .fill(Color(white: 0.15))
                        .frame(width: 60, height: 80)
                        .overlay(ProgressView().tint(Color(white: 0.4)).scaleEffect(0.6))
                }
            }

            // Date
            Text(edition.formattedDate)
                .font(Font.system(.body, design: .monospaced))
                .foregroundStyle(Color(white: 0.80))
                .frame(maxWidth: .infinity, alignment: .leading)

            // Chevron
            Text("›")
                .font(Font.system(.title3, design: .monospaced))
                .foregroundStyle(Color(white: 0.30))
                .padding(.trailing, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.bg)
    }
}

// MARK: - PressReaderWebView (conservé pour UIViewRepresentable)

struct PressReaderWebView: UIViewRepresentable {

    let initialURL: URL
    let pressReaderPath: String

    private static let injectedJS = """
    (function() {

        // 1. Masquer la navbar PressReader + popups contextuels
        if (!document.getElementById('__bavl_style')) {
            var s = document.createElement('style');
            s.id = '__bavl_style';
            s.textContent = `
                /* masquer header */
                .header, .site-header, nav.navbar, [class*="header"],
                [class*="Header"], [class*="nav-bar"], [class*="NavBar"],
                [class*="top-bar"], [class*="TopBar"] { display: none !important; }
                body, #root, .app-container { padding-top: 0 !important; margin-top: 0 !important; }
                /* masquer footer PressReader (art-vote + art-tools-tiny) */
                .art-vote, .art-tools-tiny { display: none !important; }
                /* masquer popup contextuel article (.pop, .pop-default) */
                .pop, .pop-default, [role="dialog"].pop { display: none !important; }
            `;
            (document.head || document.documentElement).appendChild(s);
        }

        // 2. Fermer le popup "Bienvenue" + observer pour popups dynamiques
        function dismissPopup() {
            var dismissed = false;
            // Popup bienvenue
            var sel = ['button[aria-label="Close"]','button[aria-label="Fermer"]',
                       'button.welcome-dialog__close','.modal-close','[data-testid="welcome-dismiss"]'];
            for (var i = 0; i < sel.length; i++) {
                var b = document.querySelector(sel[i]);
                if (b) { b.click(); dismissed = true; }
            }
            // Popup contextuel article (menu options)
            var popups = document.querySelectorAll('.pop, .pop-default, [role="dialog"]');
            popups.forEach(function(p) {
                var closeBtn = p.querySelector('button.toolbar-btn, button[class*="close"], button[class*="Close"]');
                if (closeBtn) { closeBtn.click(); dismissed = true; }
                else { p.style.display = 'none'; dismissed = true; }
            });
            return dismissed;
        }
        dismissPopup();
        var pObs = new MutationObserver(function() { dismissPopup(); });
        pObs.observe(document.documentElement, {childList:true, subtree:true});

        var path = window.location.pathname;

        // 3. Sur /textview : envoyer le titre et detecter page blanche
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
        private var urlObservation: NSKeyValueObservation?

        func startObservingURL(_ wv: WKWebView) {
            urlObservation = wv.observe(\.url, options: [.new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.onURLChange?(webView.url)
                    if let urlStr = webView.url?.absoluteString {
                        let dateRegex = try? NSRegularExpression(pattern: #"/(\d{8})/"#)
                        if let match = dateRegex?.firstMatch(in: urlStr, range: NSRange(urlStr.startIndex..., in: urlStr)),
                           let range = Range(match.range(at: 1), in: urlStr) {
                            self.currentDate = String(urlStr[range])
                        }
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let url = webView.url?.absoluteString ?? "nil"
            print("BAVL didFinish:", url)
            DispatchQueue.main.async { self.onURLChange?(webView.url) }
            webView.evaluateJavaScript(PressReaderWebView.injectedJS) { _, err in
                if let err = err { print("BAVL JS error:", err) }
            }
            if url.contains("pressreader.com") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.fetchTOCIfNeeded()
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            switch message.name {
            case "pageBlank":
                print("BAVL pageBlank: page vide détectée")

            case "pageTitle":
                let title = message.body as? String ?? ""
                print("BAVL pageTitle:", title)
                DispatchQueue.main.async { self.onTitleChange?(title) }

            default:
                break
            }
        }

        // MARK: - TOC Navigation

        private var tocArticleIds: [Int64] = []
        private var currentIssueId: String = ""
        var currentDate: String = ""

        func fetchTOCIfNeeded() {
            guard let url = webView?.url?.absoluteString else { return }
            let dateRegex = try? NSRegularExpression(pattern: "/(\\d{8})/")
            if let match = dateRegex?.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
               let range = Range(match.range(at: 1), in: url) {
                self.currentDate = String(url[range])
            }
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
                if issueId == self.currentIssueId { return }
                self.currentIssueId = issueId
                self.loadTOC(issueId: issueId)
            }
        }

        private func loadTOC(issueId: String) {
            guard let url = URL(string: "https://s.prcdn.co/services/toc/?issue=\(issueId)&version=2&expungeVersion=")
            else { return }
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
            let components = path.split(separator: "/").map(String.init)
            for comp in components.reversed() {
                if let id = Int64(comp), id > 100_000_000_000 { return id }
            }
            return nil
        }

        private func navigate(to articleId: Int64) {
            guard !pressReaderPath.isEmpty, !currentDate.isEmpty else { return }
            let urlStr = "https://www.pressreader.com/\(pressReaderPath)/\(currentDate)/\(articleId)/textview"
            guard let url = URL(string: urlStr) else { return }
            DispatchQueue.main.async { self.webView?.load(URLRequest(url: url)) }
        }

        // MARK: - Actions toolbar

        func goToJournal() {
            let date = currentDate.isEmpty ? fallbackDate() : currentDate
            guard let url = URL(string: "https://www.pressreader.com/\(pressReaderPath)/\(date)/textview")
            else { return }
            print("BAVL goToJournal ->", url.absoluteString)
            DispatchQueue.main.async { self.webView?.load(URLRequest(url: url)) }
        }

        func sharePDF(presenter: UIViewController) {
            guard let wv = webView else { return }
            let config = WKPDFConfiguration()
            wv.createPDF(configuration: config) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let data):
                        let title = wv.title?.replacingOccurrences(of: "/", with: "-") ?? "article"
                        let filename = "\(title).pdf"
                        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                        try? data.write(to: tmp)
                        let av = UIActivityViewController(activityItems: [tmp], applicationActivities: nil)
                        av.popoverPresentationController?.sourceView = presenter.view
                        av.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: 44, width: 0, height: 0)
                        av.popoverPresentationController?.permittedArrowDirections = .up
                        presenter.present(av, animated: true)
                    case .failure(let err):
                        print("BAVL createPDF error:", err)
                    }
                }
            }
        }

        func goToTextView() {
            let date = currentDate.isEmpty ? fallbackDate() : currentDate
            if let articleId = currentArticleId() {
                let urlStr = "https://www.pressreader.com/\(pressReaderPath)/\(date)/\(articleId)/textview"
                guard let url = URL(string: urlStr) else { return }
                DispatchQueue.main.async { self.webView?.load(URLRequest(url: url)) }
            } else {
                guard let url = URL(string: "https://www.pressreader.com/\(pressReaderPath)/\(date)/textview")
                else { return }
                DispatchQueue.main.async { self.webView?.load(URLRequest(url: url)) }
            }
        }

        func goToPDF() {
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

// MARK: - Barre terminal custom

private struct TerminalBar: View {
    let isOnJournal: Bool
    let isOnArticle: Bool
    let viewMode: ViewMode
    let currentURL: URL?
    let onBack: () -> Void
    let onTxt: () -> Void
    let onPdf: () -> Void
    let onShare: () -> Void

    var safeAreaTop: CGFloat = 0

    private let dimColor      = Color(white: 0.35)
    private let activeColor   = Color(white: 0.82)
    private let inactiveColor = Color(white: 0.45)

    var body: some View {
        HStack(spacing: 0) {
            // X / ‹ à gauche (contextuel)
            BarBtn(isOnArticle ? "‹" : "X", color: dimColor, action: onBack)
                .padding(.leading, 8)

            Spacer()

            // Boutons contextuels à droite
            if isOnJournal {
                BarBtn("txt", color: viewMode == .text ? activeColor : inactiveColor, action: onTxt)
                separator
                BarBtn("pdf", color: viewMode == .layout ? activeColor : inactiveColor, action: onPdf)
            }

            if isOnArticle {
                BarBtn("↑", color: activeColor, action: onShare)
                    .padding(.trailing, 4)
            }
        }
        .padding(.trailing, 8)
        .frame(height: 44)
        .background(Color.bg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(white: 0.18))
                .frame(height: 0.5)
        }
        .padding(.top, safeAreaTop)
    }

    private var separator: some View {
        Text("|")
            .font(Font.system(size: 12, weight: .ultraLight, design: .monospaced))
            .foregroundStyle(Color(white: 0.22))
            .frame(height: 44)
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
                .font(Font.system(.body, design: .monospaced))
                .foregroundStyle(color)
                .frame(height: 44)
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bridge UIViewRepresentable

private struct _PressReaderWebViewBridge: UIViewRepresentable {
    let initialURL: URL
    let pressReaderPath: String
    var onCoordinatorReady: (PressReaderWebView.Coordinator) -> Void
    var onURLChange: ((URL?) -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.userContentController.add(context.coordinator, name: "pageBlank")
        config.userContentController.add(context.coordinator, name: "pageTitle")
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = wv
        context.coordinator.pressReaderPath = pressReaderPath
        context.coordinator.onURLChange = onURLChange
        wv.load(URLRequest(url: initialURL))
        context.coordinator.startObservingURL(wv)
        DispatchQueue.main.async { self.onCoordinatorReady(context.coordinator) }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> PressReaderWebView.Coordinator {
        PressReaderWebView.Coordinator()
    }
}
