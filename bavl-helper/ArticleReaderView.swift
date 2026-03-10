import SwiftUI

// MARK: - Modèles

struct ArticleParagraph: Identifiable {
    let id = UUID()
    let text: String
    let style: ParagraphStyle
    let imageURL: URL?
    let nativeSize: CGSize

    init(text: String, style: ParagraphStyle, imageURL: URL? = nil, nativeSize: CGSize = .zero) {
        self.text = text
        self.style = style
        self.imageURL = imageURL
        self.nativeSize = nativeSize
    }

    enum ParagraphStyle {
        case body
        case heading
        case subheading
        case caption
        case image
    }
}

struct ArticleContent: Identifiable {
    let id: Int64
    let title: String
    let subtitle: String?
    let author: String?
    let sectionName: String?
    let date: String
    let paragraphs: [ArticleParagraph]

    static func parse(from json: [String: Any]) -> ArticleContent? {
        guard let id = json["id"] as? Int64 ?? (json["id"] as? Int).map(Int64.init),
              let titleRaw = json["title"] as? String
        else { return nil }
        let title = titleRaw.fixedEncoding
        let subtitle    = (json["subtitle"] as? String)?.fixedEncoding
        let author      = (json["author"]   as? String)?.fixedEncoding
        let sectionName = ((json["issue"] as? [String: Any])?["sectionName"] as? String)?.fixedEncoding
        let dateStr     = (json["issue"] as? [String: Any])?["date"] as? String ?? ""

        var paragraphs: [ArticleParagraph] = []
        if let rawParagraphs = json["paragraphs"] as? [[String: Any]] {
            for p in rawParagraphs {
                let pType = p["type"] as? String ?? "text"
                if pType == "photo" {
                    let rawKey = (p["regionKey"] as? String) ?? (p["id"] as? String) ?? ""
                    if !rawKey.isEmpty,
                       let encoded = rawKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                       let imgURL = URL(string: "https://i.prcdn.co/img?regionKey=\(encoded)&width=1170") {
                        let caption = (p["text"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? ""
                        paragraphs.append(ArticleParagraph(text: caption, style: .image, imageURL: imgURL))
                    }
                    continue
                }
                guard let raw = p["text"] as? String else { continue }
                let clean = raw.fixedEncoding
                    .replacingOccurrences(of: "\u{00AD}", with: "")
                    .replacingOccurrences(of: "\u{200B}", with: "")
                let style: ArticleParagraph.ParagraphStyle
                switch p["style"] as? Int {
                case 2: style = .heading
                case 3: style = .subheading
                case 4: style = .caption
                default: style = .body
                }
                paragraphs.append(ArticleParagraph(text: clean, style: style))
            }
        }

        if let imgs = json["images"] as? [[String: Any]] {
            var imageParagraphs: [ArticleParagraph] = []
            for img in imgs {
                let rawKey = (img["regionKey"] as? String) ?? (img["id"] as? String) ?? ""
                guard !rawKey.isEmpty,
                      let encoded = rawKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                else { continue }
                let sizeDict = img["size"] as? [String: Any]
                let nativeW = (sizeDict?["width"] as? Int) ?? (sizeDict?["width"] as? Double).map { Int($0) } ?? 0
                let nativeH = (sizeDict?["height"] as? Int) ?? (sizeDict?["height"] as? Double).map { Int($0) } ?? 0
                guard nativeW >= 100 && nativeH >= 100 else { continue }
                let targetW = nativeW > 0 ? min(nativeW, 1170) : 1170
                guard let imgURL = URL(string: "https://i.prcdn.co/img?regionKey=\(encoded)&width=\(targetW)")
                else { continue }
                let caption = (img["caption"] as? String)?.fixedEncoding ?? ""
                let sz = CGSize(width: CGFloat(nativeW), height: CGFloat(nativeH))
                imageParagraphs.append(ArticleParagraph(text: caption, style: .image, imageURL: imgURL, nativeSize: sz))
            }
            if !imageParagraphs.isEmpty && !paragraphs.isEmpty {
                paragraphs.insert(contentsOf: imageParagraphs, at: min(1, paragraphs.count))
            }
        }

        return ArticleContent(
            id: id, title: title, subtitle: subtitle,
            author: author, sectionName: sectionName,
            date: dateStr, paragraphs: paragraphs
        )
    }
}

// MARK: - Cache articles

final class ArticleCache {
    nonisolated(unsafe) private var cache: [Int64: ArticleContent] = [:]
    nonisolated(unsafe) private var inFlight: Set<Int64> = []

    func get(_ id: Int64) -> ArticleContent? { cache[id] }

    func prefetch(ids: [Int64], bearer: String) {
        for id in ids where cache[id] == nil && !inFlight.contains(id) {
            inFlight.insert(id)
            fetch(id: id, bearer: bearer)
        }
    }

    func fetch(id: Int64, bearer: String, completion: ((ArticleContent?) -> Void)? = nil) {
        if let cached = cache[id] { completion?(cached); return }
        guard let url = URL(string: "https://ingress.pressreader.com/services/v1/articles/\(id)/?articleFields=8191&isHyphenated=true&fullBody=true") else {
            DispatchQueue.main.async { completion?(nil) }; return
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let art = ArticleContent.parse(from: json)
            else {
                DispatchQueue.main.async { self?.inFlight.remove(id); completion?(nil) }
                return
            }
            DispatchQueue.main.async {
                self?.cache[id] = art
                self?.inFlight.remove(id)
                completion?(art)
            }
        }.resume()
    }
}

// MARK: - ArticleReaderView

struct ArticleReaderView: View {
    let allArticles: [ArticleMeta]
    let initialIndex: Int
    let newspaperName: String
    let editionDate: String
    let pressReaderPath: String
    let bearer: String
    let onJournal: () -> Void

    @AppStorage("readingTheme") private var themeKey: String = "night"

    @State private var currentIndex: Int
    @State private var showShare = false
    @State private var shareText: String = ""
    @State private var cache = ArticleCache()
    @State private var barVisible = true
    @State private var lastScrollY: CGFloat = 0

    private var theme: ReadingTheme { themeKey == "day" ? .day : .night }
    private var colorScheme: ColorScheme { themeKey == "day" ? .light : .dark }

    init(allArticles: [ArticleMeta], initialIndex: Int, newspaperName: String,
         editionDate: String, pressReaderPath: String, bearer: String, onJournal: @escaping () -> Void) {
        self.allArticles = allArticles
        self.initialIndex = initialIndex
        self.newspaperName = newspaperName
        self.editionDate = editionDate
        self.pressReaderPath = pressReaderPath
        self.bearer = bearer
        self.onJournal = onJournal
        self._currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            articleTabView
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            NavBar(
                title: newspaperName,
                subtitle: barDateLabel,
                visible: barVisible
            )
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [shareText])
        }
        .preferredColorScheme(colorScheme)
    }

    private var articleTabView: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(allArticles.enumerated()), id: \.offset) { idx, meta in
                ArticlePageView(
                    meta: meta,
                    prevMeta: idx > 0 ? allArticles[idx - 1] : nil,
                    nextMeta: idx + 1 < allArticles.count ? allArticles[idx + 1] : nil,
                    cache: cache,
                    bearer: bearer,
                    pressReaderPath: pressReaderPath,
                    theme: theme,
                    isActive: idx == currentIndex,
                    onPrevArticle: { currentIndex = max(0, idx - 1) },
                    onNextArticle: { currentIndex = idx + 1 },
                    onJournal: onJournal,
                    onShare: { text in shareText = text; showShare = true },
                    barVisible: $barVisible,
                    lastScrollY: $lastScrollY
                )
                .tag(idx)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .onChange(of: currentIndex) { _, newIdx in
            let ids = [newIdx - 1, newIdx, newIdx + 1]
                .filter { $0 >= 0 && $0 < allArticles.count }
                .map { allArticles[$0].id }
            cache.prefetch(ids: ids, bearer: bearer)
        }
        .onAppear {
            let ids = [initialIndex - 1, initialIndex, initialIndex + 1]
                .filter { $0 >= 0 && $0 < allArticles.count }
                .map { allArticles[$0].id }
            cache.prefetch(ids: ids, bearer: bearer)
        }
    }

    private var barDateLabel: String {
        guard editionDate.count == 8 else { return "—" }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyyMMdd"
        fmt.locale = Locale(identifier: "fr_CH")
        guard let d = fmt.date(from: editionDate) else { return "—" }
        let disp = DateFormatter()
        disp.dateFormat = "EEEE d MMMM yyyy"
        disp.locale = Locale(identifier: "fr_CH")
        let s = disp.string(from: d)
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}

// MARK: - ArticlePageView

private struct ArticlePageView: View {
    let meta: ArticleMeta
    let prevMeta: ArticleMeta?
    let nextMeta: ArticleMeta?
    let cache: ArticleCache
    let bearer: String
    let pressReaderPath: String
    let theme: ReadingTheme
    let isActive: Bool
    let onPrevArticle: () -> Void
    let onNextArticle: () -> Void
    let onJournal: () -> Void
    let onShare: (String) -> Void

    @State private var article: ArticleContent? = nil
    @State private var loading = true
    @State private var scrollResetID = UUID()
    @Binding var barVisible: Bool
    @Binding var lastScrollY: CGFloat

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            if let art = article {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        articleHeader(art)
                        bodyContent(art)
                        articleFooter(art)
                    }
                }
                .id(scrollResetID)
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
            } else if loading {
                VStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(theme.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { loadFromCacheOrFetch() }
        .onChange(of: isActive) { _, active in
            if active {
                scrollResetID = UUID()
                loadFromCacheOrFetch()
            }
        }
    }

    private func loadFromCacheOrFetch() {
        if let cached = cache.get(meta.id) {
            article = cached; loading = false
        } else {
            loading = true
            cache.fetch(id: meta.id, bearer: bearer) { art in
                article = art; loading = false
            }
        }
    }

    // MARK: - Header article

    private func articleHeader(_ art: ArticleContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Rubrique colorée
            if let section = art.sectionName, !section.isEmpty {
                let accentColor = sectionAccentColor(for: section, theme: theme)
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(accentColor)
                        .frame(width: 3, height: 13)
                        .cornerRadius(1.5)
                    Text(section.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(accentColor)
                        .tracking(1.4)
                }
                .padding(.bottom, 14)
            }

            // Titre principal — SF Pro bold, grande taille
            Text(art.title)
                .font(.system(size: 26, weight: .bold, design: .default))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(nil)
                .padding(.bottom, 10)

            // Chapeau — New York italic
            if let sub = art.subtitle, !sub.isEmpty {
                Text(sub)
                    .font(.system(size: 17, design: .serif).italic())
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
                    .padding(.bottom, 14)
            }

            // Meta ligne (auteur + date)
            HStack(spacing: 6) {
                if let auth = art.author, !auth.isEmpty {
                    Text(auth)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                }
                if let auth = art.author, !auth.isEmpty,
                   !art.date.isEmpty, displayDate(art.date) != nil {
                    Text("·")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                }
                if !art.date.isEmpty, let d = displayDate(art.date) {
                    Text(d)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .padding(.bottom, 20)

            // Ligne de séparation
            Rectangle()
                .fill(theme.divider)
                .frame(height: 1)
                .padding(.bottom, 20)
        }
        .padding(.top, 24)
        .padding(.horizontal, 20)
    }

    // MARK: - Corps de l'article

    @ViewBuilder
    private func bodyContent(_ art: ArticleContent) -> some View {
        ForEach(art.paragraphs) { para in
            paragraphView(para)
        }
    }

    @ViewBuilder
    private func paragraphView(_ para: ArticleParagraph) -> some View {
        switch para.style {

        case .heading:
            Text(para.text)
                .font(.system(size: 18, weight: .bold, design: .default))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 6)

        case .subheading:
            Text(para.text)
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 4)

        case .caption:
            Text(para.text)
                .font(.system(size: 12, design: .serif).italic())
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.vertical, 4)

        case .image:
            VStack(alignment: .leading, spacing: 0) {
                if let url = para.imageURL {
                    GeometryReader { geo in
                        let w = geo.size.width
                        let r: CGFloat = para.nativeSize.width > 0
                            ? para.nativeSize.height / para.nativeSize.width : 0.65
                        AsyncImage(url: url) { img in
                            img.resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: w, height: w * r)
                                .clipped()
                        } placeholder: {
                            theme.surfaceAlt
                                .frame(width: w, height: w * r)
                                .overlay(
                                    ProgressView()
                                        .tint(theme.textTertiary)
                                        .scaleEffect(0.7)
                                )
                        }
                    }
                    .frame(height: {
                        let w = UIScreen.main.bounds.width
                        let r: CGFloat = para.nativeSize.width > 0
                            ? para.nativeSize.height / para.nativeSize.width : 0.65
                        return w * r
                    }())
                }
                if !para.text.isEmpty {
                    Text(para.text)
                        .font(.system(size: 11, design: .serif).italic())
                        .foregroundStyle(theme.textTertiary)
                        .padding(.horizontal, 20)
                        .padding(.top, 7)
                        .padding(.bottom, 4)
                }
            }
            .padding(.vertical, 16)

        case .body:
            Text(para.text)
                // New York serif — police de lecture longue par excellence
                .font(.system(size: 17, design: .serif))
                .foregroundStyle(theme.textPrimary)
                .lineSpacing(6)          // interligne ~1.5 à 17pt
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.horizontal, 20)
                .padding(.bottom, 18)    // espacement entre paragraphes
        }
    }

    private func displayDate(_ s: String) -> String? {
        guard s.count == 8 else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"
        guard let d = f.date(from: s) else { return nil }
        f.dateStyle = .medium; f.timeStyle = .none; f.locale = Locale(identifier: "fr_CH")
        return f.string(from: d)
    }

    // MARK: - Footer article

    @ViewBuilder
    private func articleFooter(_ art: ArticleContent) -> some View {
        VStack(spacing: 0) {

            // Article suivant
            if let next = nextMeta {
                Rectangle().fill(theme.divider).frame(height: 1)
                adjacentArticleRow(meta: next, label: "article suivant", action: onNextArticle)
            }

            // Barre d'actions
            Rectangle().fill(theme.divider).frame(height: 1)
            HStack(spacing: 0) {
                footerButton(icon: "list.bullet", label: "journal", action: onJournal)
                footerButton(icon: "square.and.arrow.up", label: "partager") {
                    onShare(buildShareText(art))
                }
                if let url = articleURL(art) {
                    footerButton(icon: "safari", label: "safari") {
                        UIApplication.shared.open(url)
                    }
                }
            }
            .frame(height: 60)
            .padding(.horizontal, 8)
            .background(theme.surface)

            // Espace safe area bas
            Color.clear.frame(height: 20)
        }
        .padding(.top, 8)
    }

    private func footerButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(theme.textSecondary)
                Text(label)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func adjacentArticleRow(meta: ArticleMeta, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(label.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.textTertiary)
                        .tracking(1.2)
                    Text(meta.title)
                        .font(.system(.callout, design: .serif).weight(.medium))
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                    if let sub = meta.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.system(.footnote, design: .serif))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(2)
                    }
                    if let auth = meta.author, !auth.isEmpty {
                        Text(auth)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textTertiary)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.top, 3)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(theme.surface)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func buildShareText(_ art: ArticleContent) -> String {
        var parts: [String] = []
        if let s = art.sectionName { parts.append(s.uppercased()) }
        parts.append(art.title)
        if let sub = art.subtitle, !sub.isEmpty { parts.append(sub) }
        if let auth = art.author, !auth.isEmpty { parts.append("par " + auth) }
        parts.append("")
        for para in art.paragraphs {
            switch para.style {
            case .body: parts.append(para.text)
            case .heading: parts.append("\n" + para.text)
            default: break
            }
        }
        return parts.joined(separator: "\n")
    }

    private func articleURL(_ art: ArticleContent) -> URL? {
        let path = pressReaderPath.isEmpty ? "publication" : pressReaderPath
        return URL(string: "https://www.pressreader.com/\(path)/\(art.date)/\(art.id)/textview")
    }
}

// MARK: - ShareSheet

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
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
