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

        return ArticleMeta(
            id: id, title: title, subtitle: subtitle,
            author: author, shortContent: shortContent,
            sectionName: sectionName, pageNumber: pageNumber
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

    enum LoadState { case idle, loading, ready, error(String) }

    private var bearerToken: String = ""
    private var pressReaderPath: String = ""

    func onBearerReady(token: String, path: String) {
        print("JOURNAL onBearerReady token.count=\(token.count)")
        bearerToken = token
        pressReaderPath = path
    }

    func onTOCLoaded(ids: [Int64], issueId: String) {
        print("JOURNAL onTOCLoaded ids=\(ids.count) token.count=\(bearerToken.count)")
        guard !ids.isEmpty else { return }
        currentIssueId = issueId
        state = .loading
        fetchMetadata(ids: ids)
    }

    // MARK: - Fetch metadata légère (articleFields=3911)
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
            guard let url = URL(string: "https://ingress.pressreader.com/services/v1/articles/?ids=\(idsStr)&articleFields=3911&isHyphenated=false") else {
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
                print("JOURNAL meta items=\(items.count) parsed=\(parsed.count)")
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
    @State private var loadingArticleId: Int64? = nil
    @State private var showEditionPicker = false

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
                .padding(.top, safeTop + 44)

                // TerminalBar
                journalBar(safeTop: safeTop)

                // Edition picker
                if showEditionPicker {
                    editionPickerOverlay(safeTop: safeTop)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .sheet(item: $selectedArticle) { article in
            ArticleReaderView(
                article: article,
                onDismiss: { selectedArticle = nil },
                onJournal: { selectedArticle = nil }
            )
            .presentationCornerRadius(0)
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
                if let content { selectedArticle = content }
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
                Spacer()
                if loadingArticleId == article.id {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(dimColor)
                } else if let p = article.pageNumber {
                    Text("p.\(p)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(dimColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
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
            HStack(alignment: .center, spacing: 0) {
                // ← fermer
                Button(action: onDismiss) {
                    Text("←")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(activeColor)
                }
                .frame(width: 44, height: 44)
                .padding(.leading, 8)

                Spacer()

                // Edition label (cliquable)
                Button { showEditionPicker.toggle() } label: {
                    Text(editionLabel)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(showEditionPicker ? activeColor : dimColor)
                        .lineLimit(1)
                }

                Spacer()

                // Espace droite symétrique
                Color.clear.frame(width: 44, height: 44)
                    .padding(.trailing, 8)
            }
            .frame(height: 44)
            .background(bgColor)
            Divider().overlay(faintColor)
        }
        .padding(.top, safeTop)
    }

    // MARK: - Edition picker

    private func editionPickerOverlay(safeTop: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { showEditionPicker = false }

            VStack(spacing: 0) {
                Color.clear.frame(height: safeTop + 44)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(editions) { edition in
                            Button {
                                showEditionPicker = false
                                onEditionSelect(edition)
                            } label: {
                                HStack {
                                    Text(edition.displayLabel)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(edition.date == vm.currentDate ? activeColor : Color(white: 0.60))
                                    Spacer()
                                    if edition.date == vm.currentDate {
                                        Text("●")
                                            .font(.system(size: 8))
                                            .foregroundStyle(activeColor)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(faintColor).padding(.horizontal, 16)
                        }
                    }
                    .background(bgColor)
                }
                .frame(maxHeight: 400)
                .background(bgColor)
            }
        }
    }

    // MARK: - Helpers

    private var editionLabel: String {
        let dateStr = vm.currentDate
        guard dateStr.count == 8 else { return newspaper.name }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd"
        guard let d = fmt.date(from: dateStr) else { return newspaper.name }
        let disp = DateFormatter()
        disp.dateStyle = .medium; disp.timeStyle = .none
        disp.locale = Locale(identifier: "fr_CH")
        return "\(newspaper.name)  —  \(disp.string(from: d))"
    }

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
