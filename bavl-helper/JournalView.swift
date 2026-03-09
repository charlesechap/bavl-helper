import SwiftUI
import Combine

// MARK: - Modèles article léger (metadata)

struct ArticleMeta: Identifiable {
    let id: Int64
    let title: String
    let subtitle: String?
    let author: String?
    let shortContent: String?
    let sectionName: String?
    let pageNumber: Int?
    let thumbnailURL: URL?

    static func parse(from json: [String: Any]) -> ArticleMeta? {
        guard let rawId = json["id"],
              let titleRaw = json["title"] as? String
        else { return nil }
        let id: Int64
        if let i = rawId as? Int64 { id = i }
        else if let i = rawId as? Int { id = Int64(i) }
        else if let d = rawId as? Double { id = Int64(d) }
        else { return nil }
        let title = titleRaw.fixedEncoding

        let subtitle = (json["subtitle"] as? String)?.fixedEncoding
        let author = (json["author"] as? String)?.fixedEncoding
        let shortContent = (json["shortContent"] as? String)?.fixedEncoding
        let sectionName = ((json["issue"] as? [String: Any])?["sectionName"] as? String)?.fixedEncoding
        let pageNumber = ((json["issue"] as? [String: Any])?["page"] as? [String: Any])?["number"] as? Int

        let thumbURL: URL?
        if let imgs = json["images"] as? [[String: Any]],
           let first = imgs.first,
           let rk = first["id"] as? String, !rk.isEmpty,
           let encoded = rk.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            thumbURL = URL(string: "https://i.prcdn.co/img?regionKey=\(encoded)&width=432")
        } else {
            thumbURL = nil
        }

        return ArticleMeta(
            id: id, title: title, subtitle: subtitle,
            author: author, shortContent: shortContent,
            sectionName: sectionName, pageNumber: pageNumber,
            thumbnailURL: thumbURL
        )
    }
}

struct JournalSection: Identifiable {
    let id: String   // sectionName ou "—"
    var articles: [ArticleMeta]
}

// MARK: - JournalViewModel

@MainActor
class JournalViewModel: ObservableObject {
    @Published var sections: [JournalSection] = []
    @Published var state: LoadState = .idle
    @Published var currentIssueId: String = ""
    @Published var currentDate: String = ""

    enum LoadState: Equatable { case idle, loading, ready, error(String) }

    private(set) var bearerToken: String = ""
    private var pressReaderPath: String = ""

    func onBearerReady(token: String, path: String) {
        print("JOURNAL onBearerReady token.count=\(token.count)")
        bearerToken = token
        pressReaderPath = path
    }

    func resetForEditionChange() {
        currentIssueId = ""
        sections = []
        state = .loading
    }

    func onTOCLoaded(ids: [Int64], issueId: String) {
        print("JOURNAL onTOCLoaded ids=\(ids.count) token.count=\(bearerToken.count)")
        guard !ids.isEmpty else { return }
        // Ignorer si même édition déjà chargée (double didFinish du WebView)
        guard issueId != currentIssueId || state == LoadState.idle else {
            print("JOURNAL onTOCLoaded skipped: same issueId=\(issueId)")
            return
        }
        currentIssueId = issueId
        sections = []
        state = .loading
        fetchMetadata(ids: ids)
    }

    // MARK: - Fetch metadata légère (articleFields=3927)
    private func fetchMetadata(ids: [Int64]) {
        // PressReader limite à ~20 ids par requête — on batch
        let batchSize = 20
        let batches = stride(from: 0, to: ids.count, by: batchSize).map {
            Array(ids[$0..<min($0 + batchSize, ids.count)])
        }
        var allMeta: [ArticleMeta] = []
        let group = DispatchGroup()

        print("JOURNAL fetchMetadata batches=\(batches.count) token.isEmpty=\(bearerToken.isEmpty)")
        for batch in batches {
            group.enter()
            let idsStr = batch.map { String($0) }.joined(separator: "%2C")
            guard let url = URL(string: "https://ingress.pressreader.com/services/v1/articles/?ids=\(idsStr)&articleFields=3927&isHyphenated=false") else {
                group.leave(); continue
            }
            var req = URLRequest(url: url, timeoutInterval: 15)
            req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")

            URLSession.shared.dataTask(with: req) { data, resp, _ in
                defer { group.leave() }
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard let data else { print("JOURNAL meta no data"); return }
                // Logger les 200 premiers chars pour voir la structure
                print("JOURNAL meta status=\(status) len=\(data.count)")
                // Essayer dict {Items:[]} ou array directement []
                var items: [[String: Any]] = []
                if let obj = try? JSONSerialization.jsonObject(with: data) {
                    if let dict = obj as? [String: Any] {
                        items = (dict["Items"] as? [[String: Any]])
                            ?? (dict["items"] as? [[String: Any]]) ?? []
                    } else if let arr = obj as? [[String: Any]] {
                        items = arr
                    }
                }
                let parsed = items.compactMap { ArticleMeta.parse(from: $0) }
                print("JOURNAL meta items=\(items.count) parsed=\(parsed.count) thumbs=\(parsed.filter{$0.thumbnailURL != nil}.count)")
                DispatchQueue.main.async { allMeta.append(contentsOf: parsed) }
            }.resume()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            var seen = Set<Int64>()
            let unique = allMeta.filter { seen.insert($0.id).inserted }
            print("JOURNAL ready: \(unique.count) articles")
            let sorted = unique.sorted { ($0.pageNumber ?? 999) < ($1.pageNumber ?? 999) }
            self.sections = self.groupBySections(sorted)
            self.state = .ready
        }
    }

    private func groupBySections(_ articles: [ArticleMeta]) -> [JournalSection] {
        var result: [JournalSection] = []
        var seen: [String: Int] = [:]
        for article in articles {
            let key = article.sectionName ?? "—"
            if let idx = seen[key] {
                result[idx].articles.append(article)
            } else {
                seen[key] = result.count
                result.append(JournalSection(id: key, articles: [article]))
            }
        }
        return result
    }

    func fetchArticle(id: Int64, completion: @escaping (ArticleContent?) -> Void) {
        guard let url = URL(string: "https://ingress.pressreader.com/services/v1/articles/\(id)/?articleFields=8191&isHyphenated=true&fullBody=true") else {
            completion(nil); return
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let article = ArticleContent.parse(from: json)
            else { DispatchQueue.main.async { completion(nil) }; return }
            DispatchQueue.main.async { completion(article) }
        }.resume()
    }
}

// MARK: - JournalView

struct JournalView: View {
    @ObservedObject var vm: JournalViewModel
    let newspaper: Newspaper
    let editions: [PressReaderEdition]
    let onDismiss: () -> Void
    let onEditionSelect: (PressReaderEdition) -> Void

    @State private var selectedArticle: ArticleContent? = nil
    @State private var selectedArticleIndex: Int = 0
    @State private var loadingArticleId: Int64? = nil
    @State private var barVisible = true
    @State private var lastScrollY: CGFloat = 0
    @State private var previewMeta: ArticleMeta? = nil
    @State private var previewArticle: ArticleContent? = nil
    @State private var loadingPreviewId: Int64? = nil

    private let bgColor = Color(red: 0.13, green: 0.13, blue: 0.13)
    private let activeColor = Color(white: 0.82)
    private let dimColor = Color(white: 0.35)
    private let faintColor = Color(white: 0.20)

    var body: some View {
        GeometryReader { geo in
            let safeTop = geo.safeAreaInsets.top
            ZStack(alignment: .top) {
                bgColor.ignoresSafeArea()

                // Contenu principal
                Group {
                    switch vm.state {
                    case .idle:
                        centeredMessage("Connexion en cours…")
                    case .loading:
                        centeredMessage("Chargement du journal…")
                    case .error(let msg):
                        centeredMessage("Erreur : \(msg)")
                    case .ready:
                        articleList(safeTop: safeTop)
                    }
                }
                .padding(.top, safeTop + 89)  // hauteur barre fermée = 89
                .onScrollGeometryChange(for: CGFloat.self,
                    of: { $0.contentOffset.y },
                    action: { old, new in
                        let delta = new - lastScrollY
                        lastScrollY = new
                        if new <= 0 {
                            barVisible = true
                        } else if delta > 6 {
                            barVisible = false   // scroll vers le bas → cache
                        } else if delta < -6 {
                            barVisible = true    // scroll vers le haut → montre
                        }
                    }
                )

                // TerminalBar
                journalBar(safeTop: safeTop)

        
            }
            .ignoresSafeArea(edges: .top)
        }
        // Sheet article (TabView multi-articles)
        .sheet(item: $selectedArticle) { _ in
            ArticleReaderView(
                allArticles: flatArticles,
                initialIndex: selectedArticleIndex,
                newspaperName: newspaper.name,
                editionDate: vm.currentDate,
                pressReaderPath: newspaper.pressReaderPath,
                bearer: bearerToken,
                onJournal: { selectedArticle = nil }
            )
            .presentationCornerRadius(0)
        }
        // Sheet aperçu long press
        .sheet(item: $previewMeta) { meta in
            ArticlePreviewSheet(
                meta: meta,
                article: previewArticle,
                onRead: {
                    if let art = previewArticle {
                        let idx = flatArticles.firstIndex(where: { $0.id == meta.id }) ?? 0
                        previewMeta = nil
                        previewArticle = nil
                        selectedArticleIndex = idx
                        selectedArticle = art
                    }
                },
                onDismiss: {
                    previewMeta = nil
                    previewArticle = nil
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }

        .preferredColorScheme(.dark)
    }

    // MARK: - Liste articles

    private func articleList(safeTop: CGFloat) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(vm.sections) { section in
                    Section {
                        ForEach(section.articles) { article in
                            articleRow(article)
                            Divider().overlay(faintColor).padding(.horizontal, 16)
                        }
                    } header: {
                        sectionHeader(section.id)
                    }
                }
                Color.clear.frame(height: 32)
            }
        }
    }

    private func articleRow(_ article: ArticleMeta) -> some View {
        Button {
            guard loadingArticleId == nil else { return }
            loadingArticleId = article.id
            vm.fetchArticle(id: article.id) { content in
                loadingArticleId = nil
                if let content {
                    selectedArticleIndex = flatArticles.firstIndex(where: { $0.id == article.id }) ?? 0
                    selectedArticle = content
                }
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(article.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(activeColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)

                    if let sub = article.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(white: 0.55))
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }

                    if let auth = article.author, !auth.isEmpty {
                        Text(auth)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(dimColor)
                    }
                }
                Spacer(minLength: 8)
                // Zone droite fixe — évite le relayout au tap
                ZStack {
                    if loadingArticleId == article.id {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(dimColor)
                            .frame(width: 72, height: 72)
                    } else if let thumbURL = article.thumbnailURL {
                        AsyncImage(url: thumbURL) { img in
                            img.resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color(white: 0.18)
                        }
                        .frame(width: 72, height: 72)
                        .cornerRadius(4)
                        .clipped()
                    } else if let p = article.pageNumber {
                        Text("p.\(p)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(dimColor)
                            .frame(width: 72, alignment: .trailing)
                    } else {
                        Color.clear.frame(width: 0)
                    }
                }
                .frame(width: 72)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0.4) {
            guard loadingPreviewId == nil else { return }
            loadingPreviewId = article.id
            previewMeta = article
            vm.fetchArticle(id: article.id) { content in
                loadingPreviewId = nil
                previewArticle = content
            }
        }
    }

    private func sectionHeader(_ name: String) -> some View {
        HStack {
            Text(name.uppercased())
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(dimColor)
                .tracking(1.5)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(bgColor)
        .overlay(alignment: .bottom) {
            Rectangle().fill(faintColor).frame(height: 0.5)
        }
    }

    // MARK: - TerminalBar

    private func journalBar(safeTop: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Nom du journal
            Text(newspaper.name)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(Color(white: 0.82))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(bgColor)

            Divider().overlay(faintColor)

            // Date de l'édition — swipe gauche = édition précédente, droite = suivante
            Text(dateLabel)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(Color(white: 0.82))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(bgColor)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 30)
                        .onEnded { v in
                            guard abs(v.translation.width) > abs(v.translation.height) else { return }
                            guard let idx = editions.firstIndex(where: { $0.date == vm.currentDate }) else { return }
                            if v.translation.width < 0 {
                                // swipe gauche = édition plus ancienne (index +1)
                                if idx + 1 < editions.count {
                                    onEditionSelect(editions[idx + 1])
                                }
                            } else {
                                // swipe droite = édition plus récente (index -1)
                                if idx > 0 {
                                    onEditionSelect(editions[idx - 1])
                                }
                            }
                        }
                )

            Divider().overlay(faintColor)
        }
        .offset(y: barVisible ? 0 : -(safeTop + barHeight))
        .opacity(barVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.22), value: barVisible)
        .padding(.top, safeTop)
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { v in
                    if v.translation.height > 60 && abs(v.translation.width) < 80 {
                        onDismiss()
                    }
                }
        )
    }

    private var barHeight: CGFloat { 89 }
    // MARK: - Helpers

    private func editionDateLabel(_ dateStr: String) -> String {
        guard dateStr.count == 8 else { return "—" }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd"
        fmt.locale = Locale(identifier: "fr_CH")
        guard let d = fmt.date(from: dateStr) else { return dateStr }
        let out = DateFormatter()
        out.dateFormat = "EEEE d MMMM yyyy"
        out.locale = Locale(identifier: "fr_CH")
        let s = out.string(from: d)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    private var dateLabel: String {
        let dateStr = vm.currentDate
        guard dateStr.count == 8 else { return "—" }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd"
        fmt.locale = Locale(identifier: "fr_CH")
        guard let d = fmt.date(from: dateStr) else { return "—" }
        let disp = DateFormatter()
        disp.dateFormat = "EEEE d MMMM yyyy"   // "lundi 9 mars 2026"
        disp.locale = Locale(identifier: "fr_CH")
        let s = disp.string(from: d)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    // Liste plate de tous les articles (pour TabView navigation)
    private var flatArticles: [ArticleMeta] {
        vm.sections.flatMap { $0.articles }
    }

    // Expose le token pour passer à ArticleReaderView
    private var bearerToken: String { vm.bearerToken }

    private func centeredMessage(_ msg: String) -> some View {
        VStack {
            Spacer()
            Text(msg)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(dimColor)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - ArticlePreviewSheet
private struct ArticlePreviewSheet: View {
    let meta: ArticleMeta
    let article: ArticleContent?
    let onRead: () -> Void
    let onDismiss: () -> Void

    private let bg = Color(red: 0.10, green: 0.10, blue: 0.10)
    private let active = Color(white: 0.88)
    private let dim = Color(white: 0.45)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Handle bar
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(white: 0.30))
                    .frame(width: 36, height: 4)
                Spacer()
            }
            .padding(.top, 12)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let sec = meta.sectionName {
                        Text(sec.uppercased())
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(dim)
                            .tracking(1.5)
                    }
                    Text(meta.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(active)
                    if let sub = meta.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.system(size: 14))
                            .foregroundStyle(Color(white: 0.60))
                    }
                    if let auth = meta.author, !auth.isEmpty {
                        Text(auth)
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(dim)
                    }

                    Divider().overlay(Color(white: 0.20)).padding(.vertical, 4)

                    if let art = article {
                        // Premiers paragraphes body
                        let preview = art.paragraphs
                            .filter { if case .body = $0.style { return true }; return false }
                            .prefix(3)
                        ForEach(Array(preview)) { para in
                            Text(para.text)
                                .font(.system(size: 15))
                                .foregroundStyle(Color(white: 0.75))
                                .lineSpacing(4)
                        }
                    } else {
                        ProgressView()
                            .tint(dim)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    }

                    Color.clear.frame(height: 20)
                }
                .padding(.horizontal, 20)
            }

            // Bouton Lire
            Button(action: onRead) {
                Text("Lire l'article")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(active)
            }
            .buttonStyle(.plain)
            .disabled(article == nil)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

// MARK: - Encoding fix
private extension String {
    /// Corrige le double-encoding UTF-8/Latin-1 fréquent dans l'API PressReader.
    /// Ex: "Â«" (U+00C2 + U+00AB) → "«"
    var fixedEncoding: String {
        guard let latin1 = self.data(using: .isoLatin1),
              let utf8 = String(data: latin1, encoding: .utf8)
        else { return self }
        return utf8
    }
}
