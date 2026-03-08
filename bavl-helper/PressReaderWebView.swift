import SwiftUI
import WebKit

// MARK: - Palette

private extension Color {
    static let bg      = Color(red: 0.13, green: 0.13, blue: 0.13)
    static let fg      = Color(red: 0.80, green: 0.80, blue: 0.80)
    static let fgDim   = Color(red: 0.50, green: 0.50, blue: 0.50)
    static let fgFaint = Color(red: 0.30, green: 0.30, blue: 0.30)
}

// MARK: - Helpers date

private let editionDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd"
    f.locale = Locale(identifier: "fr_CH")
    f.timeZone = TimeZone(identifier: "Europe/Zurich")
    return f
}()

private let editionDisplayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEE dd.MM.yyyy"   // "Ven. 06.03.2026"
    f.locale = Locale(identifier: "fr_CH")
    f.timeZone = TimeZone(identifier: "Europe/Zurich")
    return f
}()

// MARK: - Modèle édition

struct PressReaderEdition: Identifiable, Hashable {
    let date: String      // "yyyyMMdd"
    let issueId: Int      // Id numérique (pour futures fonctionnalités)
    var id: String { date }

    var displayLabel: String {
        guard let d = editionDateFormatter.date(from: date) else { return date }
        return editionDisplayFormatter.string(from: d)
    }
}

// MARK: - PressReaderWebView

struct PressReaderWebView: UIViewRepresentable {

    let initialURL: URL
    let pressReaderPath: String

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
                .art-vote, .art-tools-tiny { display: none !important; }
                .pop.pop-default { display: none !important; }
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

        // 3. Toutes les pages : bearer token + publication CID
        // cid priorité: window.preset.cid court (ex: "switzerland/le-temps")
        //               sinon: 2 premiers segments du path (/country/paper/...)
        function extractCid() {
            var p = window.preset;
            if (p && p.cid && p.cid.indexOf('/') !== -1 && p.cid.length < 60) {
                return p.cid;  // ex: "switzerland/le-temps"
            }
            // Fallback: extraire depuis le path URL
            var parts = window.location.pathname.replace(/^\\//, '').split('/');
            if (parts.length >= 2) return parts[0] + '/' + parts[1];
            return null;
        }
        function sendAuthInfo() {
            var p = window.preset;
            var token = p && p.bearerToken ? p.bearerToken : null;
            var cid   = extractCid();
            if (token && cid) {
                window.webkit.messageHandlers.authInfo.postMessage(
                    JSON.stringify({token: token, cid: cid})
                );
                return true;
            }
            return false;
        }
        if (!sendAuthInfo()) {
            setTimeout(function() { sendAuthInfo(); }, 800);
        }

        // 4. Intercepter fetch() pour capturer la réponse calendar/get
        //    PressReader appelle cet endpoint avec ses propres cookies de session
        //    → on capte la réponse et on l'envoie à Swift
        if (!window.__bavl_fetch_patched) {
            window.__bavl_fetch_patched = true;
            var _origFetch = window.fetch.bind(window);
            window.fetch = function(input, init) {
                var url = (typeof input === 'string') ? input : (input && input.url ? input.url : '');
                var isCalendar = url && url.indexOf('calendar/get') !== -1;
                return _origFetch(input, init).then(function(response) {
                    if (isCalendar) {
                        var cloned = response.clone();
                        cloned.text().then(function(body) {
                            window.webkit.messageHandlers.calendarRaw.postMessage(body);
                        });
                    }
                    return response;
                });
            };
        }

        // 5. Sur /textview : titre
        if (path.indexOf('/textview') !== -1) {
            function sendTitle() {
                var title = document.title || '';
                if (title !== '') window.webkit.messageHandlers.pageTitle.postMessage(title);
            }
            sendTitle();
            var titleObs = new MutationObserver(function() { sendTitle(); });
            var titleEl = document.querySelector('title');
            if (titleEl) titleObs.observe(titleEl, {childList:true, subtree:true, characterData:true});
            setTimeout(function() { titleObs.disconnect(); }, 5000);
        }

    })();
    """

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        for name in ["authInfo", "bearerToken", "pageBlank", "pageTitle", "calendarRaw"] {
            config.userContentController.add(context.coordinator, name: name)
        }
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
        /// Callback déclenché quand la liste des éditions est disponible
        var onEditionsLoaded: (([PressReaderEdition]) -> Void)?
        private var urlObservation: NSKeyValueObservation?
        private var calendarLoaded = false
        private var lastEditionLoaded = false

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

            case "authInfo":
                guard let jsonStr = message.body as? String,
                      let data = jsonStr.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String]
                else { loadFallbackDate(); return }
                let token = dict["token"] ?? ""
                let cid   = dict["cid"]   ?? ""
                print("BAVL authInfo: token.count=\(token.count) cid=\(cid)")
                if token.isEmpty { loadFallbackDate(); return }
                // Navigation vers dernière édition (une seule fois)
                if !lastEditionLoaded {
                    lastEditionLoaded = true
                    fetchLastEditionViaAPI(bearerToken: token, cid: cid)
                }


            case "calendarRaw":
                guard !calendarLoaded else { return }
                let body = message.body as? String ?? ""
                print("BAVL calendarRaw intercepté, body(300):", String(body.prefix(300)))
                parseCalendarAndEmit(body: body)

            // Rétro-compatibilité si bearerToken est encore émis
            case "bearerToken":
                let token = message.body as? String ?? ""
                if token.isEmpty { loadFallbackDate() }
                // Note: sans cid, on ne peut pas appeler le calendar — attend authInfo

            case "pageTitle":
                let title = message.body as? String ?? ""
                DispatchQueue.main.async { self.onTitleChange?(title) }

            default:
                break
            }
        }


        // MARK: - Calendar API (liste des éditions disponibles)

        /// Parse un body JSON calendar/get et émet les éditions si non vides.
        /// Retourne true si des éditions ont été trouvées.
        @discardableResult
        private func parseCalendarAndEmit(body: String) -> Bool {
            guard let data = body.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let years = root["Years"] as? [String: Any], !years.isEmpty
            else {
                print("BAVL calendar: Years vide ou parse échoué")
                return false
            }
            var editions: [PressReaderEdition] = []
            for (yearStr, monthsAny) in years {
                guard let months = monthsAny as? [String: Any], let year = Int(yearStr) else { continue }
                for (monthStr, daysAny) in months {
                    guard let days = daysAny as? [String: Any], let month = Int(monthStr) else { continue }
                    for (dayStr, infoAny) in days {
                        guard let info = infoAny as? [String: Any], let day = Int(dayStr) else { continue }
                        let available: Bool
                        if let b = info["P"] as? Bool          { available = b }
                        else if let n = info["P"] as? Int      { available = n != 0 }
                        else if let n = info["P"] as? NSNumber { available = n.boolValue }
                        else { continue }
                        guard available else { continue }
                        let issueId: Int
                        if let n = info["Id"] as? Int         { issueId = n }
                        else if let d = info["Id"] as? Double { issueId = Int(d) }
                        else { issueId = 0 }
                        editions.append(PressReaderEdition(date: String(format: "%04d%02d%02d", year, month, day), issueId: issueId))
                    }
                }
            }
            let sorted = editions.sorted { $0.date > $1.date }
            print("BAVL calendar: \(sorted.count) éditions parsées depuis interceptor")
            guard !sorted.isEmpty else { return false }
            calendarLoaded = true
            DispatchQueue.main.async { self.onEditionsLoaded?(sorted) }
            return true
        }

        // MARK: - API (dernière édition)

        private func fetchLastEditionViaAPI(bearerToken: String, cid: String) {
            guard let encoded = cid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)?
                          .replacingOccurrences(of: "/", with: "%2F"),
                  let url = URL(string: "https://ingress.pressreader.com/services/catalog/issues?cid=\(encoded)&count=90")
            else { loadFallbackDate(); return }
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            print("BAVL catalog/issues fetch count=90")

            URLSession.shared.dataTask(with: request) { [weak self] data, resp, error in
                guard let self = self else { return }
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard let data = data, error == nil else { self.loadFallbackDate(); return }
                let raw = String(data: data, encoding: .utf8) ?? ""
                print("BAVL catalog/issues status=\(status) body(300):", String(raw.prefix(300)))

                // Extraire toutes les éditions pour le dropdown
                if !self.calendarLoaded,
                   let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let issues = parsed["Issues"] as? [[String: Any]], !issues.isEmpty {
                    var editions: [PressReaderEdition] = []
                    let datePattern = try? NSRegularExpression(pattern: "[^0-9]([0-9]{8})[^0-9]")
                    for issue in issues {
                        // Extraire issueId
                        let issueId = issue["Issue"] as? String ?? ""
                        // Extraire date depuis les champs de l'issue
                        let issueJson = (try? JSONSerialization.data(withJSONObject: issue))
                            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
                        let padded = " \(issueJson) "
                        var dates: [String] = []
                        datePattern?.enumerateMatches(in: padded, range: NSRange(padded.startIndex..., in: padded)) { m, _, _ in
                            guard let m = m, let r = Range(m.range(at: 1), in: padded) else { return }
                            let d = String(padded[r])
                            if d >= "20200101" && d <= "20301231" { dates.append(d) }
                        }
                        if let dateStr = dates.sorted().last {
                            editions.append(PressReaderEdition(date: dateStr, issueId: 0))
                        }
                    }
                    let sorted = editions.sorted { $0.date > $1.date }
                    print("BAVL catalog/issues: \(sorted.count) éditions parsées")
                    if !sorted.isEmpty {
                        self.calendarLoaded = true
                        DispatchQueue.main.async { self.onEditionsLoaded?(sorted) }
                    }
                }

                // Naviguer vers le dernier issue + charger TOC
                if let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let issues = parsed["Issues"] as? [[String: Any]],
                   let first = issues.first,
                   let issueId = first["Issue"] as? String, !issueId.isEmpty {
                    self.currentIssueId = issueId
                    self.loadTOC(issueId: issueId)
                }
                if let date = self.extractLatestDate(from: raw) {
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
            var dates: [String] = []
            regex.enumerateMatches(in: padded, range: NSRange(padded.startIndex..., in: padded)) { match, _, _ in
                guard let match = match, let r = Range(match.range(at: 1), in: padded) else { return }
                let d = String(padded[r])
                if d >= "20200101" && d <= "20301231" { dates.append(d) }
            }
            return dates.sorted().last
        }

        private func loadFallbackDate() { navigateToTextView(date: fallbackDate()) }

        private func navigateToTextView(date: String) {
            guard let url = URL(string: "https://www.pressreader.com/\(pressReaderPath)/\(date)/textview") else { return }
            DispatchQueue.main.async { self.webView?.load(URLRequest(url: url)) }
        }

        func navigateToEdition(_ edition: PressReaderEdition) {
            navigateToTextView(date: edition.date)
        }

        // MARK: - TOC

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
                    return p.issueId || p.issue || (p.cid ? p.cid : '');
                })();
            """) { [weak self] result, _ in
                guard let self = self,
                      let issueId = result as? String, !issueId.isEmpty,
                      issueId != self.currentIssueId
                else { return }
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
                            if let n = art["Id"] as? Int64        { ids.append(n) }
                            else if let d = art["Id"] as? Double  { ids.append(Int64(d)) }
                        }
                    }
                }
                print("BAVL TOC: \(ids.count) articles")
                DispatchQueue.main.async { self.tocArticleIds = ids }
            }.resume()
        }

        private func currentArticleId() -> Int64? {
            guard let path = webView?.url?.path else { return nil }
            for comp in path.split(separator: "/").map(String.init).reversed() {
                if let id = Int64(comp), id > 100_000_000_000 { return id }
            }
            return nil
        }

        private func navigate(to articleId: Int64) {
            let urlStr = "https://www.pressreader.com/\(pressReaderPath)/\(currentDate)/\(articleId)/textview"
            guard let url = URL(string: urlStr) else { return }
            DispatchQueue.main.async { self.webView?.load(URLRequest(url: url)) }
        }

        // MARK: - Actions toolbar

        func goToPreviousArticle() {
            guard let c = currentArticleId(), let i = tocArticleIds.firstIndex(of: c), i > 0 else { return }
            navigate(to: tocArticleIds[i - 1])
        }

        func goToNextArticle() {
            guard let c = currentArticleId(), let i = tocArticleIds.firstIndex(of: c), i < tocArticleIds.count - 1 else { return }
            navigate(to: tocArticleIds[i + 1])
        }

        func goToArchive() {
            guard let url = URL(string: "https://www.pressreader.com/\(pressReaderPath)/archive") else { return }
            webView?.load(URLRequest(url: url))
        }

        func goToJournal() {
            let date = currentDate.isEmpty ? fallbackDate() : currentDate
            guard let url = URL(string: "https://www.pressreader.com/\(pressReaderPath)/\(date)/textview") else { return }
            DispatchQueue.main.async { self.webView?.load(URLRequest(url: url)) }
        }

        func sharePDF(presenter: UIViewController) {
            guard let wv = webView else { return }
            wv.createPDF(configuration: WKPDFConfiguration()) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let data):
                        let title = wv.title?.replacingOccurrences(of: "/", with: "-") ?? "article"
                        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(title).pdf")
                        try? data.write(to: tmp)
                        let av = UIActivityViewController(activityItems: [tmp], applicationActivities: nil)
                        av.popoverPresentationController?.sourceView = presenter.view
                        av.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: 44, width: 0, height: 0)
                        av.popoverPresentationController?.permittedArrowDirections = .up
                        presenter.present(av, animated: true)
                    case .failure(let err):
                        print("BAVL PDF error:", err)
                    }
                }
            }
        }

        func goToTextView() {
            let date = currentDate.isEmpty ? fallbackDate() : currentDate
            if let id = currentArticleId() {
                guard let url = URL(string: "https://www.pressreader.com/\(pressReaderPath)/\(date)/\(id)/textview") else { return }
                DispatchQueue.main.async { self.webView?.load(URLRequest(url: url)) }
            } else {
                navigateToTextView(date: date)
            }
        }

        func goToPDF() {
            let date = currentDate.isEmpty ? fallbackDate() : currentDate
            if let id = currentArticleId() {
                guard let url = URL(string: "https://www.pressreader.com/\(pressReaderPath)/\(date)/\(id)") else { return }
                DispatchQueue.main.async { self.webView?.load(URLRequest(url: url)) }
            } else {
                guard let url = URL(string: "https://www.pressreader.com/\(pressReaderPath)/\(date)") else { return }
                DispatchQueue.main.async { self.webView?.load(URLRequest(url: url)) }
            }
        }

        private func fallbackDate() -> String {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyyMMdd"
            fmt.timeZone = TimeZone(identifier: "Europe/Zurich")
            return fmt.string(from: cal.date(byAdding: .day, value: -1, to: Date())!)
        }
    }
}

// MARK: - PressReaderSheet

struct PressReaderSheet: View {
    let newspaper: Newspaper
    let preloadedWebView: WKWebView?
    @ObservedObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var currentURL: URL? = nil
    @State private var coordinator: PressReaderWebView.Coordinator? = nil
    @State private var editions: [PressReaderEdition] = []
    @State private var showEditionPicker = false

    private var viewMode: ViewMode {
        (currentURL?.absoluteString ?? "").contains("/textview") ? .text : .layout
    }

    private var isOnArticle: Bool {
        (currentURL?.absoluteString ?? "").range(of: #"/[0-9]{8}/[0-9]{10,}"#, options: .regularExpression) != nil
    }

    private var isOnJournal: Bool {
        let s = currentURL?.absoluteString ?? ""
        return s.range(of: #"/[0-9]{8}"#, options: .regularExpression) != nil
            && s.range(of: #"/[0-9]{8}/[0-9]{10,}"#, options: .regularExpression) == nil
    }

    private var isOnArchive: Bool {
        currentURL?.absoluteString.contains("/archive") == true
    }

    private var currentDateFromURL: String {
        let s = currentURL?.absoluteString ?? ""
        guard let r = s.range(of: #"[0-9]{8}"#, options: .regularExpression) else { return "" }
        return String(s[r])
    }

    /// "Le Temps  —  Ven. 06.03.2026"
    private var editionLabel: String {
        let dateStr = currentDateFromURL
        guard dateStr.count == 8, let d = editionDateFormatter.date(from: dateStr) else {
            return newspaper.name
        }
        return "\(newspaper.name)  —  \(editionDisplayFormatter.string(from: d))"
    }

    var body: some View {
        GeometryReader { geo in
            let safeTop = geo.safeAreaInsets.top
            ZStack(alignment: .top) {
                Color.bg.ignoresSafeArea()

                if let url = newspaper.resolvedURL ?? newspaper.archiveURL {
                    _PressReaderWebViewBridge(
                        initialURL: url,
                        pressReaderPath: newspaper.pressReaderPath,
                        onCoordinatorReady: { coord in
                            coordinator = coord
                            coord.onEditionsLoaded = { loaded in
                                editions = loaded
                            }
                        },
                        onURLChange: { currentURL = $0 }
                    )
                    .ignoresSafeArea()
                    .padding(.top, safeTop + 44)
                } else {
                    ContentUnavailableView("URL invalide", systemImage: "xmark.circle")
                }

                TerminalBar(
                    isOnArchive: isOnArchive,
                    isOnJournal: isOnJournal,
                    isOnArticle: isOnArticle,
                    viewMode: viewMode,
                    editionLabel: editionLabel,
                    showEditionPicker: $showEditionPicker,
                    onDismiss: { dismiss() },
                    onTxt: { coordinator?.goToTextView() },
                    onPdf: { coordinator?.goToPDF() },
                    onJournal: { coordinator?.goToJournal() },
                    onShare: {
                        guard let coord = coordinator else { return }
                        guard let scene = UIApplication.shared.connectedScenes
                            .compactMap({ $0 as? UIWindowScene })
                            .first(where: { $0.activationState == .foregroundActive }),
                              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                        else { return }
                        var presenter = root
                        while let p = presenter.presentedViewController { presenter = p }
                        coord.sharePDF(presenter: presenter)
                    },
                    safeAreaTop: safeTop
                )

                // Dropdown éditions
                if showEditionPicker {
                    EditionPickerOverlay(
                        editions: editions,
                        currentDate: currentDateFromURL,
                        safeTop: safeTop,
                        onSelect: { edition in
                            showEditionPicker = false
                            coordinator?.navigateToEdition(edition)
                        },
                        onDismiss: { showEditionPicker = false }
                    )
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - EditionPickerOverlay

private struct EditionPickerOverlay: View {
    let editions: [PressReaderEdition]
    let currentDate: String
    let safeTop: CGFloat
    let onSelect: (PressReaderEdition) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.50)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            Group {
                if editions.isEmpty {
                    // Avant que l'API réponde: spinner + message
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(Color(white: 0.6))
                        Text("chargement des éditions…")
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Color(white: 0.55))
                    }
                    .padding(20)
                    .background(Color(red: 0.10, green: 0.10, blue: 0.10))
                    .overlay(Rectangle().stroke(Color(white: 0.22), lineWidth: 0.5))
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(editions) { edition in
                                    let isCurrent = edition.date == currentDate
                                    Button { onSelect(edition) } label: {
                                        HStack(spacing: 0) {
                                            Spacer()
                                            Text(isCurrent ? "›  " : "   ")
                                                .font(.system(.body, design: .monospaced))
                                                .foregroundStyle(Color(white: 0.95))
                                            Text(edition.displayLabel)
                                                .font(.system(.body, design: .monospaced))
                                                .foregroundStyle(isCurrent ? Color(white: 0.95) : Color(white: 0.78))
                                            Spacer()
                                        }
                                        .padding(.vertical, 11)
                                        .background(isCurrent ? Color(white: 0.18) : Color.clear)
                                    }
                                    .buttonStyle(.plain)
                                    .id(edition.date)
                                    Divider().background(Color(white: 0.18))
                                }
                            }
                        }
                        .frame(width: 240)
                        .frame(maxHeight: 360)
                        .onAppear {
                            guard !currentDate.isEmpty else { return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                proxy.scrollTo(currentDate, anchor: .center)
                            }
                        }
                    }
                    .background(Color(red: 0.10, green: 0.10, blue: 0.10))
                    .overlay(Rectangle().stroke(Color(white: 0.22), lineWidth: 0.5))
                }
            }
            .padding(.top, safeTop + 44)
        }
    }
}

// MARK: - TerminalBar

private struct TerminalBar: View {
    let isOnArchive: Bool
    let isOnJournal: Bool
    let isOnArticle: Bool
    let viewMode: ViewMode
    let editionLabel: String
    @Binding var showEditionPicker: Bool
    let onDismiss: () -> Void
    let onTxt: () -> Void
    let onPdf: () -> Void
    let onJournal: () -> Void
    let onShare: () -> Void
    var safeAreaTop: CGFloat = 0

    private let activeColor = Color(white: 0.82)

    var body: some View {
        ZStack {
            // Gauche
            HStack {
                BarBtn(isOnArticle ? "←" : "←", color: activeColor,
                       action: isOnArticle ? onJournal : onDismiss)
                    .padding(.leading, 16)
                Spacer()
                // Droite (article)
                if isOnArticle {
                    BarBtn("↩", color: activeColor, action: onJournal)
                    barSep
                    BarBtn("↑", color: activeColor, action: onShare)
                        .padding(.trailing, 16)
                } else {
                    Spacer().frame(width: 16)
                }
            }

            // Centre absolu
            if isOnJournal {
                Button { showEditionPicker.toggle() } label: {
                    Text(editionLabel)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(activeColor)
                        .lineLimit(1)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
            }

            if isOnArchive {
                HStack(spacing: 0) {
                    BarBtn("txt", color: activeColor, action: onTxt)
                    barSep
                    BarBtn("pdf", color: activeColor, action: onPdf)
                }
            }
        }
        .frame(height: 44)
        .background(Color.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(white: 0.18)).frame(height: 0.5)
        }
        .padding(.top, safeAreaTop)
    }

    private var barSep: some View {
        Text("|").font(.system(size: 12, weight: .ultraLight, design: .monospaced))
            .foregroundStyle(Color(white: 0.22)).frame(height: 44)
    }
}

private struct BarBtn: View {
    let label: String; let color: Color; let action: () -> Void
    init(_ l: String, color: Color, action: @escaping () -> Void) { label=l; self.color=color; self.action=action }
    var body: some View {
        Button(action: action) {
            Text(label).font(.system(.body, design: .monospaced))
                .foregroundStyle(color).frame(height: 44).padding(.horizontal, 10).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

// MARK: - Bridge

private struct _PressReaderWebViewBridge: UIViewRepresentable {
    let initialURL: URL
    let pressReaderPath: String
    var onCoordinatorReady: (PressReaderWebView.Coordinator) -> Void
    var onURLChange: ((URL?) -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        for name in ["authInfo", "bearerToken", "pageBlank", "pageTitle", "calendarRaw"] {
            config.userContentController.add(context.coordinator, name: name)
        }
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = wv
        context.coordinator.pressReaderPath = pressReaderPath
        context.coordinator.onURLChange = onURLChange
        context.coordinator.startObservingURL(wv)
        wv.load(URLRequest(url: initialURL))
        DispatchQueue.main.async { self.onCoordinatorReady(context.coordinator) }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
    func makeCoordinator() -> PressReaderWebView.Coordinator { PressReaderWebView.Coordinator() }
}

private extension WKWebView {
    func goBackward() { goBack() }
    func goForward_() { goForward() }
}


