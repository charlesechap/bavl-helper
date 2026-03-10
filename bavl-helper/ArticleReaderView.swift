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
        case quote   // ← blockquote mise en avant
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
        let title      = titleRaw.fixedEncoding
        let subtitle   = (json["subtitle"] as? String)?.fixedEncoding
        let author     = (json["author"] as? String)?.fixedEncoding
        let sectionName = ((json["issue"] as? [String: Any])?["sectionName"] as? String)?.fixedEncoding
        let dateStr    = (json["issue"] as? [String: Any])?["date"] as? String ?? ""

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
                guard let imgURL = URL(string: "https://i.prcdn.co/img?regionKey=\(encoded)&width=\(targetW)") else { continue }
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

// MARK: - Cache articles partagé

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
    let newspaper: Newspaper
    let editionDate: String
    let bearer: String
    let onJournal: () -> Void

    @State private var currentIndex: Int
    @State private var showShare = false
    @State private var shareText: String = ""
    @State private var cache = ArticleCache()
    @State private var barVisible = true
    @State private var lastScrollY: CGFloat = 0

    // Thème : same as JournalView (night par défaut)
    private let theme = NewsTheme.night

    init(allArticles: [ArticleMeta], initialIndex: Int, newspaper: Newspaper,
         editionDate: String, bearer: String, onJournal: @escaping () -> Void) {
        self.allArticles = allArticles
        self.initialIndex = initialIndex
        self.newspaper = newspaper
        self.editionDate = editionDate
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
                title: newspaper.name,
                subtitle: barDateLabel,
                visible: barVisible
            )
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [shareText])
        }
    }

    // MARK: - TabView articles

    private var articleTabView: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(allArticles.enumerated()), id: \.offset) { idx, meta in
                ArticlePageView(
                    meta: meta,
                    prevMeta: idx > 0 ? allArticles[idx - 1] : nil,
                    nextMeta: idx + 1 < allArticles.count ? allArticles[idx + 1] : nil,
                    cache: cache,
                    bearer: bearer,
                    newspaper: newspaper,
                    isActive: idx == currentIndex,
                    theme: theme,
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
    let newspaper: Newspaper
    let isActive: Bool
    let theme: NewsTheme
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
                        articleBody(art)
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
                    ProgressView().tint(theme.textDim).scaleEffect(0.9)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { loadFromCacheOrFetch() }
        .onChange(of: isActive) { _, active in
            if active { scrollResetID = UUID(); loadFromCacheOrFetch() }
        }
    }

    // MARK: - Header article

    private func articleHeader(_ art: ArticleContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image hero — pleine largeur, pas de marges
            if let heroImage = art.paragraphs.first(where: { $0.style == .image }),
               let url = heroImage.imageURL {
                heroImageView(url: url, nativeSize: heroImage.nativeSize)
                    .padding(.bottom, 20)
            }

            VStack(alignment: .leading, spacing: 0) {
                // Rubrique avec trait coloré
                if let sec = art.sectionName, !sec.isEmpty {
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(theme.sectionAccent(for: sec))
                            .frame(width: 3, height: 14)
                        Text(sec.uppercased())
                            .font(.system(size: 11, weight: .semibold, design: .default))
                            .tracking(1.2)
                            .foregroundStyle(theme.sectionAccent(for: sec))
                    }
                    .padding(.bottom, 12)
                }

                // Titre — New York Bold, grand
                Text(art.title)
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
                    .padding(.bottom, art.subtitle != nil ? 12 : 16)

                // Chapeau — New York Italic
                if let sub = art.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 17, weight: .regular, design: .serif).italic())
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(4)
                        .padding(.bottom, 14)
                }

                // Auteur + date
                HStack(spacing: 6) {
                    if let auth = art.author, !auth.isEmpty {
                        Text(auth.uppercased())
                            .font(.system(size: 10, weight: .regular, design: .default))
                            .tracking(0.6)
                            .foregroundStyle(theme.textTertiary)
                    }
                    if !art.date.isEmpty, let d = displayDate(art.date) {
                        Text("·").foregroundStyle(theme.textDim)
                        Text(d)
                            .font(.system(size: 10, weight: .regular, design: .default))
                            .foregroundStyle(theme.textDim)
                    }
                }
                .padding(.bottom, 20)

                // Trait de séparation
                Rectangle()
                    .fill(theme.divider)
                    .frame(height: 0.5)
                    .padding(.bottom, 22)
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Image hero pleine largeur

    private func heroImageView(url: URL, nativeSize: CGSize) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let ratio: CGFloat = nativeSize.width > 0 ? nativeSize.height / nativeSize.width : (9.0/16.0)
            let h = min(w * ratio, w * 0.75) // max 75% de la largeur
            AsyncImage(url: url) { img in
                img.resizable().aspectRatio(contentMode: .fill)
                    .frame(width: w, height: h).clipped()
            } placeholder: {
                theme.imagePlaceholder.frame(width: w, height: h)
            }
        }
        .frame(height: {
            let w = UIScreen.main.bounds.width
            let ratio: CGFloat = nativeSize.width > 0 ? nativeSize.height / nativeSize.width : (9.0/16.0)
            return min(w * ratio, w * 0.75)
        }())
    }

    // MARK: - Corps de l'article

    private func articleBody(_ art: ArticleContent) -> some View {
        let bodyParagraphs = art.paragraphs.filter { para in
            // Exclure la première image (déjà affichée en hero)
            if para.style == .image {
                return para.id != art.paragraphs.first(where: { $0.style == .image })?.id
            }
            return true
        }

        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(bodyParagraphs) { para in
                paragraphView(para)
                    .padding(.bottom, paragraphSpacing(para))
            }
        }
    }

    // MARK: - Paragraphes

    @ViewBuilder
    private func paragraphView(_ para: ArticleParagraph) -> some View {
        switch para.style {

        // ── Inter-titre (h2)
        case .heading:
            Text(para.text)
                .font(.system(size: 19, weight: .bold, design: .serif))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
                .textSelection(.enabled)
                .padding(.horizontal, 20)
                .padding(.top, 10)

        // ── Sous-titre (h3)
        case .subheading:
            Text(para.text)
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
                .padding(.horizontal, 20)
                .padding(.top, 4)

        // ── Corps — New York, interligne 1.5
        case .body:
            Text(para.text)
                .font(.system(size: 17, weight: .regular, design: .serif))
                .foregroundStyle(theme.textPrimary)
                .lineSpacing(6)   // ≈ 1.47 avec 17pt (17 * 1.47 ≈ 25, linespacing additionnel = 8)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.horizontal, 20)

        // ── Blockquote / citation mise en avant
        case .quote:
            HStack(spacing: 0) {
                Rectangle()
                    .fill(theme.accent)
                    .frame(width: 3)
                Text(para.text)
                    .font(.system(size: 19, weight: .bold, design: .serif).italic())
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(4)
                    .padding(.leading, 16)
                    .padding(.trailing, 20)
            }
            .padding(.leading, 20)
            .padding(.vertical, 6)

        // ── Légende image
        case .caption:
            Text(para.text)
                .font(.system(size: 12, weight: .regular, design: .default).italic())
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
                .padding(.horizontal, 20)

        // ── Image inline (pas la hero)
        case .image:
            VStack(alignment: .leading, spacing: 0) {
                if let url = para.imageURL {
                    GeometryReader { geo in
                        let w = geo.size.width
                        let r: CGFloat = para.nativeSize.width > 0
                            ? para.nativeSize.height / para.nativeSize.width : 0.67
                        let h = min(w * r, w * 0.80)
                        AsyncImage(url: url) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                                .frame(width: w, height: h).clipped()
                        } placeholder: {
                            theme.imagePlaceholder.frame(width: w, height: h)
                        }
                    }
                    .frame(height: {
                        let w = UIScreen.main.bounds.width
                        let r: CGFloat = para.nativeSize.width > 0
                            ? para.nativeSize.height / para.nativeSize.width : 0.67
                        return min(w * r, w * 0.80)
                    }())
                }
                if !para.text.isEmpty {
                    Text(para.text)
                        .font(.system(size: 11, weight: .regular, design: .default).italic())
                        .foregroundStyle(theme.textTertiary)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
            }
            .padding(.bottom, 4)
        }
    }

    private func paragraphSpacing(_ para: ArticleParagraph) -> CGFloat {
        switch para.style {
        case .heading:   return 4
        case .subheading: return 6
        case .body:      return 18
        case .quote:     return 20
        case .caption:   return 14
        case .image:     return 20
        }
    }

    private func displayDate(_ s: String) -> String? {
        guard s.count == 8 else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"
        guard let d = f.date(from: s) else { return nil }
        f.dateStyle = .medium; f.timeStyle = .none
        f.locale = Locale(identifier: "fr_CH")
        return f.string(from: d)
    }

    // MARK: - Footer

    private func articleFooter(_ art: ArticleContent) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(theme.divider).frame(height: 0.5)
                .padding(.top, 10)

            // Article suivant
            if let next = nextMeta {
                adjacentArticleRow(meta: next, label: "article suivant", action: onNextArticle)
                Rectangle().fill(theme.divider).frame(height: 0.5)
            }

            // Barre d'actions
            HStack(spacing: 0) {
                footerButton(icon: "square.and.arrow.up", label: "partager") {
                    onShare(buildShareText(art))
                }
                footerButton(icon: "arrow.clockwise", label: "recharger") {
                    article = nil; loading = true
                    cache.fetch(id: meta.id, bearer: bearer) { fetched in
                        article = fetched; loading = false; scrollResetID = UUID()
                    }
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

            Color.clear.frame(height: 32)
        }
        .background(theme.surface)
    }

    @ViewBuilder
    private func footerButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(theme.textSecondary)
                Text(label)
                    .font(.system(size: 9, design: .default))
                    .foregroundStyle(theme.textDim)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func adjacentArticleRow(meta: ArticleMeta, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(label.uppercased())
                        .font(.system(size: 10, weight: .regular, design: .default))
                        .tracking(0.8)
                        .foregroundStyle(theme.textDim)
                    Text(meta.title)
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                    if let sub = meta.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.system(size: 13, weight: .regular, design: .serif).italic())
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(2)
                    }
                    if let auth = meta.author, !auth.isEmpty {
                        Text(auth.uppercased())
                            .font(.system(size: 10, weight: .regular))
                            .tracking(0.5)
                            .foregroundStyle(theme.textTertiary)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textDim)
                    .padding(.top, 3)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
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
            case .body:    parts.append(para.text)
            case .heading: parts.append("\n" + para.text)
            default: break
            }
        }
        return parts.joined(separator: "\n")
    }

    private func articleURL(_ art: ArticleContent) -> URL? {
        let path = newspaper.pressReaderPath.isEmpty ? "publication" : newspaper.pressReaderPath
        return URL(string: "https://www.pressreader.com/\(path)/\(art.date)/\(art.id)/textview")
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
