import SwiftUI
import Combine

// MARK: - Theme

struct ReadingTheme {
    // Backgrounds
    let background:   Color
    let surface:      Color
    let surfaceAlt:   Color
    // Text
    let textPrimary:   Color
    let textSecondary: Color
    let textTertiary:  Color
    // Accent & UI
    let accent:        Color
    let divider:       Color
    let sectionBg:     Color

    static let day = ReadingTheme(
        background:    Color(red: 0.97, green: 0.96, blue: 0.93),
        surface:       Color(red: 0.93, green: 0.92, blue: 0.89),
        surfaceAlt:    Color(red: 0.90, green: 0.89, blue: 0.86),
        textPrimary:   Color(red: 0.11, green: 0.10, blue: 0.09),
        textSecondary: Color(red: 0.35, green: 0.33, blue: 0.30),
        textTertiary:  Color(red: 0.55, green: 0.52, blue: 0.48),
        accent:        Color(red: 0.72, green: 0.08, blue: 0.08),
        divider:       Color(red: 0.78, green: 0.76, blue: 0.72),
        sectionBg:     Color(red: 0.95, green: 0.94, blue: 0.91)
    )

    static let night = ReadingTheme(
        background:    Color(red: 0.10, green: 0.10, blue: 0.11),
        surface:       Color(red: 0.14, green: 0.14, blue: 0.15),
        surfaceAlt:    Color(red: 0.18, green: 0.18, blue: 0.19),
        textPrimary:   Color(red: 0.90, green: 0.89, blue: 0.87),
        textSecondary: Color(red: 0.60, green: 0.59, blue: 0.57),
        textTertiary:  Color(red: 0.38, green: 0.37, blue: 0.36),
        accent:        Color(red: 0.92, green: 0.36, blue: 0.36),
        divider:       Color(red: 0.22, green: 0.22, blue: 0.23),
        sectionBg:     Color(red: 0.12, green: 0.12, blue: 0.13)
    )
}

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

        let subtitle    = (json["subtitle"]    as? String)?.fixedEncoding
        let author      = (json["author"]      as? String)?.fixedEncoding
        let shortContent = (json["shortContent"] as? String)?.fixedEncoding
        let sectionName = ((json["issue"] as? [String: Any])?["sectionName"] as? String)?.fixedEncoding
        let pageNumber  = ((json["issue"] as? [String: Any])?["page"] as? [String: Any])?["number"] as? Int

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
    let id: String
    var articles: [ArticleMeta]
}

// MARK: - Couleur par rubrique

private func sectionAccentColor(for name: String, theme: ReadingTheme) -> Color {
    let lower = name.lowercased()
    if lower.contains("une") || lower.contains("actu") || lower.contains("nation") {
        return theme.accent
    } else if lower.contains("intern") || lower.contains("monde") {
        return Color(red: 0.15, green: 0.35, blue: 0.65)
    } else if lower.contains("éco") || lower.contains("eco") || lower.contains("finan") {
        return Color(red: 0.12, green: 0.48, blue: 0.28)
    } else if lower.contains("cult") || lower.contains("art") || lower.contains("livr") {
        return Color(red: 0.45, green: 0.20, blue: 0.60)
    } else if lower.contains("sport") {
        return Color(red: 0.82, green: 0.38, blue: 0.08)
    } else if lower.contains("sci") || lower.contains("tech") {
        return Color(red: 0.08, green: 0.42, blue: 0.60)
    }
    return theme.textTertiary
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
        bearerToken = token
        pressReaderPath = path
    }

    func injectPreload(_ data: JournalPreloadData) {
        bearerToken = data.bearerToken
        pressReaderPath = data.pressReaderPath
        if !data.currentDate.isEmpty { currentDate = data.currentDate }
        if !data.tocIds.isEmpty {
            onTOCLoaded(ids: data.tocIds, issueId: data.tocIssueId)
        }
    }

    func resetForEditionChange() {
        currentIssueId = ""
        sections = []
        state = .loading
    }

    func onTOCLoaded(ids: [Int64], issueId: String) {
        guard !ids.isEmpty else { return }
        guard issueId != currentIssueId || state == LoadState.idle else { return }
        currentIssueId = issueId
        sections = []
        state = .loading
        fetchMetadata(ids: ids)
    }

    private func fetchMetadata(ids: [Int64]) {
        let batchSize = 20
        let batches = stride(from: 0, to: ids.count, by: batchSize).map {
            Array(ids[$0..<min($0 + batchSize, ids.count)])
        }
        var allMeta: [ArticleMeta] = []
        let group = DispatchGroup()

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
                guard let data else { return }
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
                DispatchQueue.main.async { allMeta.append(contentsOf: parsed) }
            }.resume()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            var seen = Set<Int64>()
            let unique = allMeta.filter { seen.insert($0.id).inserted }
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

    @AppStorage("readingTheme") private var themeKey: String = "night"

    @State private var currentEditionIndex: Int = 0
    @State private var selectedArticle: ArticleContent? = nil
    @State private var selectedArticleIndex: Int = 0
    @State private var loadingArticleId: Int64? = nil
    @State private var barVisible = true
    @State private var lastScrollY: CGFloat = 0
    @State private var previewMeta: ArticleMeta? = nil
    @State private var previewArticle: ArticleContent? = nil
    @State private var loadingPreviewId: Int64? = nil

    private var theme: ReadingTheme { themeKey == "day" ? .day : .night }
    private var colorScheme: ColorScheme { themeKey == "day" ? .light : .dark }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            editionTabView
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            NavBar(
                title: newspaper.name,
                subtitle: currentDateLabel,
                visible: barVisible
            )
        }
        .sheet(item: $selectedArticle) { _ in
            ArticleReaderView(
                allArticles: flatArticles,
                initialIndex: selectedArticleIndex,
                newspaper: newspaper,
                editionDate: vm.currentDate,
                bearer: bearerToken,
                onJournal: { selectedArticle = nil }
            )
            .presentationCornerRadius(0)
        }
        .sheet(item: $previewMeta) { meta in
            ArticlePreviewSheet(
                meta: meta,
                article: previewArticle,
                theme: theme,
                onRead: {
                    if let art = previewArticle {
                        let idx = flatArticles.firstIndex(where: { $0.id == meta.id }) ?? 0
                        previewMeta = nil; previewArticle = nil
                        selectedArticleIndex = idx; selectedArticle = art
                    }
                },
                onDismiss: { previewMeta = nil; previewArticle = nil }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(colorScheme)
        }
        .preferredColorScheme(colorScheme)
        .onChange(of: editions) { _, newEditions in
            if let idx = newEditions.firstIndex(where: { $0.date == vm.currentDate }) {
                currentEditionIndex = idx
            } else if !newEditions.isEmpty {
                currentEditionIndex = 0
            }
        }
    }

    // MARK: - TabView éditions

    private var editionTabView: some View {
        TabView(selection: $currentEditionIndex) {
            if editions.isEmpty {
                editionPage(for: nil).tag(0)
            } else {
                ForEach(Array(editions.enumerated()), id: \.offset) { idx, edition in
                    editionPage(for: edition).tag(idx)
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .onChange(of: currentEditionIndex) { _, newIdx in
            guard !editions.isEmpty, newIdx < editions.count else { return }
            let edition = editions[newIdx]
            guard edition.date != vm.currentDate else { return }
            lastScrollY = 0
            withAnimation(.easeInOut(duration: 0.22)) { barVisible = true }
            onEditionSelect(edition)
        }
    }

    @ViewBuilder
    private func editionPage(for edition: PressReaderEdition?) -> some View {
        switch vm.state {
        case .idle, .loading:
            loadingView
        case .error(let msg):
            centeredMessage("Erreur : \(msg)")
        case .ready:
            articleList
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .tint(theme.textTertiary)
                .scaleEffect(0.9)
            Text("Chargement du journal…")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(theme.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Liste articles

    private var articleList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(vm.sections) { section in
                    Section {
                        ForEach(Array(section.articles.enumerated()), id: \.element.id) { idx, article in
                            articleRow(article, isLast: idx == section.articles.count - 1)
                        }
                    } header: {
                        sectionHeader(section.id)
                    }
                }
                // Breathing room en bas
                Color.clear.frame(height: 48)
            }
        }
        .onScrollGeometryChange(for: CGFloat.self,
            of: { $0.contentOffset.y + $0.contentInsets.top },
            action: { _, new in
                let delta = new - lastScrollY
                lastScrollY = new
                if new <= 0 {
                    withAnimation(.easeInOut(duration: 0.22)) { barVisible = true }
                } else if delta > 6 {
                    withAnimation(.easeInOut(duration: 0.22)) { barVisible = false }
                } else if delta < -6 {
                    withAnimation(.easeInOut(duration: 0.22)) { barVisible = true }
                }
            }
        )
    }

    // MARK: - Article row

    private func articleRow(_ article: ArticleMeta, isLast: Bool) -> some View {
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
            HStack(alignment: .top, spacing: 14) {
                // Contenu textuel
                VStack(alignment: .leading, spacing: 5) {
                    Text(article.title)
                        .font(.system(.callout, design: .serif).weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)

                    if let sub = article.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.system(.footnote, design: .serif))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(2)
                    }
                    if let auth = article.author, !auth.isEmpty {
                        Text(auth)
                            .font(.system(size: 11, weight: .regular, design: .default))
                            .foregroundStyle(theme.textTertiary)
                            .padding(.top, 1)
                    }
                }

                Spacer(minLength: 8)

                // Thumbnail ou numéro de page
                ZStack {
                    if loadingArticleId == article.id {
                        ProgressView()
                            .scaleEffect(0.75)
                            .tint(theme.textTertiary)
                            .frame(width: 76, height: 76)
                    } else if let thumbURL = article.thumbnailURL {
                        AsyncImage(url: thumbURL) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            theme.surfaceAlt
                        }
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    } else if let p = article.pageNumber {
                        VStack(spacing: 1) {
                            Text("p.")
                                .font(.system(size: 9))
                            Text("\(p)")
                                .font(.system(size: 16, weight: .light, design: .serif))
                        }
                        .foregroundStyle(theme.textTertiary)
                        .frame(width: 40, alignment: .center)
                    }
                }
                .frame(width: 76)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(theme.background)
        }
        .buttonStyle(.plain)
        // Séparateur entre articles (pas après le dernier de la section)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(theme.divider)
                    .frame(height: 0.5)
                    .padding(.leading, 18)
            }
        }
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

    // MARK: - Section header

    private func sectionHeader(_ name: String) -> some View {
        let accentColor = sectionAccentColor(for: name, theme: theme)
        return HStack(spacing: 8) {
            Rectangle()
                .fill(accentColor)
                .frame(width: 3, height: 14)
                .cornerRadius(1.5)
            Text(name.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(accentColor)
                .tracking(1.4)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(theme.sectionBg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.divider)
                .frame(height: 0.5)
        }
    }

    // MARK: - Helpers

    private var currentDateLabel: String {
        let dateStr = editions.isEmpty ? vm.currentDate
            : (currentEditionIndex < editions.count ? editions[currentEditionIndex].date : vm.currentDate)
        return dateLabel(dateStr)
    }

    private func dateLabel(_ dateStr: String) -> String {
        guard dateStr.count == 8 else { return "—" }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd"
        fmt.locale = Locale(identifier: "fr_CH")
        guard let d = fmt.date(from: dateStr) else { return "—" }
        let disp = DateFormatter()
        disp.dateFormat = "EEEE d MMMM yyyy"
        disp.locale = Locale(identifier: "fr_CH")
        let s = disp.string(from: d)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    private var flatArticles: [ArticleMeta] { vm.sections.flatMap { $0.articles } }
    private var bearerToken: String { vm.bearerToken }

    private func centeredMessage(_ msg: String) -> some View {
        VStack {
            Spacer()
            Text(msg)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(theme.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - ArticlePreviewSheet

private struct ArticlePreviewSheet: View {
    let meta: ArticleMeta
    let article: ArticleContent?
    let theme: ReadingTheme
    let onRead: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Drag handle
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.divider)
                    .frame(width: 36, height: 4)
                Spacer()
            }
            .padding(.top, 12)
            .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Rubrique
                    if let sec = meta.sectionName {
                        let accentColor = sectionAccentColor(for: sec, theme: theme)
                        HStack(spacing: 6) {
                            Rectangle()
                                .fill(accentColor)
                                .frame(width: 3, height: 12)
                                .cornerRadius(1.5)
                            Text(sec.uppercased())
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(accentColor)
                                .tracking(1.4)
                        }
                        .padding(.bottom, 10)
                    }

                    // Titre
                    Text(meta.title)
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 8)

                    // Sous-titre
                    if let sub = meta.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.system(size: 15, design: .serif).italic())
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 8)
                    }

                    // Auteur
                    if let auth = meta.author, !auth.isEmpty {
                        Text(auth)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textTertiary)
                            .padding(.bottom, 16)
                    }

                    // Séparateur
                    Rectangle()
                        .fill(theme.divider)
                        .frame(height: 1)
                        .padding(.bottom, 16)

                    // Extrait
                    if let art = article {
                        let preview = art.paragraphs
                            .filter { if case .body = $0.style { return true }; return false }
                            .prefix(3)
                        ForEach(Array(preview)) { para in
                            Text(para.text)
                                .font(.system(size: 15, design: .serif))
                                .foregroundStyle(theme.textSecondary)
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, 12)
                        }
                    } else {
                        HStack {
                            Spacer()
                            ProgressView().tint(theme.textTertiary).padding(.vertical, 24)
                            Spacer()
                        }
                    }

                    Color.clear.frame(height: 20)
                }
                .padding(.horizontal, 22)
            }

            // Bouton Lire
            Button(action: onRead) {
                Text("Lire l'article")
                    .font(.system(.body, design: .serif).weight(.medium))
                    .foregroundStyle(theme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(theme.textPrimary)
            }
            .buttonStyle(.plain)
            .disabled(article == nil)
            .opacity(article == nil ? 0.4 : 1)
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(theme.background.ignoresSafeArea())
    }
}

// MARK: - Encoding fix

private extension String {
    var fixedEncoding: String {
        guard let latin1 = self.data(using: .isoLatin1),
              let utf8 = String(data: latin1, encoding: .utf8)
        else { return self }
        return utf8
    }
}

