import SwiftUI

// MARK: - Modèles

struct ArticleParagraph: Identifiable {
    let id = UUID()
    let text: String
    let style: ParagraphStyle
    let imageURL: URL?    // non-nil quand style == .image
    let nativeSize: CGSize // taille native en pixels (pour éviter upscale)

    init(text: String, style: ParagraphStyle, imageURL: URL? = nil, nativeSize: CGSize = .zero) {
        self.text = text
        self.style = style
        self.imageURL = imageURL
        self.nativeSize = nativeSize
    }

    enum ParagraphStyle {
        case body
        case heading    // style = 2
        case subheading // style = 3 (si existe)
        case caption    // style = 4 (si existe)
        case image      // type = "photo" avec regionKey
    }
}

struct ArticleContent: Identifiable {
    let id: Int64
    let title: String
    let subtitle: String?
    let author: String?
    let sectionName: String?
    let date: String          // "20260307"
    let paragraphs: [ArticleParagraph]

    static func parse(from json: [String: Any]) -> ArticleContent? {
        guard let id = json["id"] as? Int64 ?? (json["id"] as? Int).map(Int64.init),
              let titleRaw = json["title"] as? String
        else { return nil }
        let title = titleRaw.fixedEncoding

        let subtitle = (json["subtitle"] as? String)?.fixedEncoding
        let author = (json["author"] as? String)?.fixedEncoding
        let sectionName = ((json["issue"] as? [String: Any])?["sectionName"] as? String)?.fixedEncoding

        // Date depuis issue.date
        let dateStr = (json["issue"] as? [String: Any])?["date"] as? String ?? ""

        // Parser paragraphs
        var paragraphs: [ArticleParagraph] = []
        if let rawParagraphs = json["paragraphs"] as? [[String: Any]] {
            for p in rawParagraphs {
                let pType = p["type"] as? String ?? "text"
                // Image (type = "photo")
                if pType == "photo" {
                    // regionKey peut être sous "regionKey" ou "id" selon l'endpoint
                    let rawKey = (p["regionKey"] as? String) ?? (p["id"] as? String) ?? ""
                    print("ARTICLE photo keys=\(Array(p.keys).sorted()) rawKey=\(rawKey.prefix(20))")
                    if !rawKey.isEmpty,
                       let encoded = rawKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                       let imgURL = URL(string: "https://i.prcdn.co/img?regionKey=\(encoded)&width=1170") {
                        let caption = (p["text"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? ""
                        paragraphs.append(ArticleParagraph(text: caption, style: .image, imageURL: imgURL))
                    }
                    continue
                }
                guard let raw = p["text"] as? String else { continue }
                // Nettoyer soft-hyphens et tirets conditionnels
                let clean = raw.fixedEncoding
                    .replacingOccurrences(of: "\u{00AD}", with: "") // soft hyphen
                    .replacingOccurrences(of: "\u{200B}", with: "") // zero-width space
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

        // Injecter images depuis json["images"] (absent des paragraphs)
        if let imgs = json["images"] as? [[String: Any]] {
            var imageParagraphs: [ArticleParagraph] = []
            for img in imgs {
                let rawKey = (img["regionKey"] as? String) ?? (img["id"] as? String) ?? ""
                guard !rawKey.isEmpty,
                      let encoded = rawKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                else { continue }
                // Filtrer icônes/filets, ne pas upscaler au-delà du natif
                let sizeDict = img["size"] as? [String: Any]
                let nativeW = (sizeDict?["width"] as? Int) ?? (sizeDict?["width"] as? Double).map { Int($0) } ?? 0
                let nativeH = (sizeDict?["height"] as? Int) ?? (sizeDict?["height"] as? Double).map { Int($0) } ?? 0
                // Ignorer images trop petites (icônes, filets graphiques)
                guard nativeW >= 100 && nativeH >= 100 else { continue }
                let targetW = nativeW > 0 ? min(nativeW, 1170) : 1170
                guard let imgURL = URL(string: "https://i.prcdn.co/img?regionKey=\(encoded)&width=\(targetW)")
                else { continue }
                let caption = (img["caption"] as? String)?.fixedEncoding ?? ""
                let sz = CGSize(width: CGFloat(nativeW), height: CGFloat(nativeH))
                imageParagraphs.append(ArticleParagraph(text: caption, style: .image, imageURL: imgURL, nativeSize: sz))
            }
            // Insérer la première image après le 1er paragraphe body (chapeau)
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
@MainActor
final class ArticleCache: ObservableObject {
    private var cache: [Int64: ArticleContent] = [:]
    private var inFlight: Set<Int64> = []

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
            completion?(nil); return
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

// MARK: - Vue principale

struct ArticleReaderView: View {
    let allArticles: [ArticleMeta]
    let initialIndex: Int
    let newspaperName: String
    let bearer: String
    let onJournal: () -> Void

    @State private var currentIndex: Int
    @State private var showShare = false
    @State private var shareText: String = ""
    @StateObject private var cache = ArticleCache()

    init(allArticles: [ArticleMeta], initialIndex: Int, newspaperName: String, bearer: String, onJournal: @escaping () -> Void) {
        self.allArticles = allArticles
        self.initialIndex = initialIndex
        self.newspaperName = newspaperName
        self.bearer = bearer
        self.onJournal = onJournal
        self._currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        GeometryReader { geo in
            let safeTop = geo.safeAreaInsets.top
            ZStack(alignment: .top) {
                Color(red: 0.13, green: 0.13, blue: 0.13).ignoresSafeArea()

                TabView(selection: $currentIndex) {
                    ForEach(Array(allArticles.enumerated()), id: \.offset) { idx, meta in
                        ArticlePageView(
                            meta: meta,
                            cache: cache,
                            bearer: bearer,
                            safeTop: safeTop,
                            isActive: idx == currentIndex,
                            onShareReady: { text in
                                shareText = text
                                showShare = true
                            }
                        )
                        .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
                .onChange(of: currentIndex) { _, newIdx in
                    // Prefetch article courant + voisins
                    let ids = [newIdx - 1, newIdx, newIdx + 1]
                        .filter { $0 >= 0 && $0 < allArticles.count }
                        .map { allArticles[$0].id }
                    cache.prefetch(ids: ids, bearer: bearer)
                }
                .onAppear {
                    // Prefetch initial
                    let ids = [initialIndex - 1, initialIndex, initialIndex + 1]
                        .filter { $0 >= 0 && $0 < allArticles.count }
                        .map { allArticles[$0].id }
                    cache.prefetch(ids: ids, bearer: bearer)
                }
                .gesture(
                    DragGesture(minimumDistance: 40)
                        .onEnded { v in
                            // Swipe down → retour journal
                            if v.translation.height > 80 && abs(v.translation.width) < 60 {
                                onJournal()
                            }
                        }
                )

                readerBar(safeTop: safeTop)
            }
            .ignoresSafeArea(edges: .top)
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [shareText])
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - TerminalBar

    private func readerBar(safeTop: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                Button(action: onJournal) {
                    Text("←")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color(white: 0.82))
                }
                .frame(width: 44, height: 44)
                .padding(.leading, 8)

                Spacer()

                Button(action: onJournal) {
                    Text(barLabel)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color(white: 0.35))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)

                Spacer()

                Button { showShare = true } label: {
                    Text("↑")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color(white: 0.82))
                }
                .frame(width: 44, height: 44)
                .padding(.trailing, 8)
            }
            .frame(height: 44)
            .background(Color(red: 0.13, green: 0.13, blue: 0.13))
            Divider().overlay(Color(white: 0.20))
        }
        .padding(.top, safeTop)
    }

    private var barLabel: String {
        guard currentIndex < allArticles.count else { return newspaperName }
        let dateStr = "" // date sera dans ArticlePageView
        _ = dateStr
        return newspaperName
    }
}

// MARK: - ArticlePageView (une page du TabView)

private struct ArticlePageView: View {
    let meta: ArticleMeta
    let cache: ArticleCache
    let bearer: String
    let safeTop: CGFloat
    let isActive: Bool
    let onShareReady: (String) -> Void

    @State private var article: ArticleContent? = nil
    @State private var loading = true
    // scrollID forcé à changer à chaque fois qu'on revient sur cet article
    @State private var scrollResetID = UUID()

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.13, green: 0.13, blue: 0.13).ignoresSafeArea()

            if let art = article {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        articleHeader(art)
                            .padding(.top, safeTop + 44 + 20)
                            .padding(.horizontal, 20)

                        Divider()
                            .overlay(Color(white: 0.25))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)

                        ForEach(art.paragraphs) { para in
                            paragraphView(para)
                                .padding(.horizontal, 20)
                                .padding(.bottom, paragraphSpacing(para))
                        }

                        Color.clear.frame(height: 60)
                    }
                }
                // Forcer le retour en haut à chaque activation de cette page
                .id(scrollResetID)
            } else if loading {
                VStack {
                    Spacer()
                    ProgressView()
                        .tint(Color(white: 0.45))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.top, safeTop + 44)
            }
        }
        .onAppear { loadFromCacheOrFetch() }
        .onChange(of: isActive) { _, active in
            if active {
                // Revenir en haut à chaque fois qu'on arrive sur cette page
                scrollResetID = UUID()
                loadFromCacheOrFetch()
            }
        }
    }

    private func loadFromCacheOrFetch() {
        if let cached = cache.get(meta.id) {
            article = cached
            loading = false
        } else {
            loading = true
            cache.fetch(id: meta.id, bearer: bearer) { art in
                article = art
                loading = art == nil ? false : false
            }
        }
    }

    // MARK: - Header

    private func articleHeader(_ art: ArticleContent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let section = art.sectionName, !section.isEmpty {
                Text(section.uppercased())
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color(white: 0.45))
                    .tracking(1.5)
            }
            Text(art.title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color(white: 0.92))
                .fixedSize(horizontal: false, vertical: true)
            if let sub = art.subtitle, !sub.isEmpty {
                Text(sub)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(white: 0.65))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            HStack(spacing: 8) {
                if let auth = art.author, !auth.isEmpty {
                    Text(auth)
                        .font(.system(.caption))
                        .foregroundStyle(Color(white: 0.50))
                }
                if !art.date.isEmpty, let d = displayDate(art.date) {
                    Text("·").foregroundStyle(Color(white: 0.30))
                    Text(d).font(.system(.caption)).foregroundStyle(Color(white: 0.40))
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Paragraphes

    @ViewBuilder
    private func paragraphView(_ para: ArticleParagraph) -> some View {
        switch para.style {
        case .heading:
            Text(para.text)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(white: 0.88))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8).padding(.bottom, 4)
        case .subheading:
            Text(para.text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(white: 0.75))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        case .caption:
            Text(para.text)
                .font(.system(size: 12))
                .foregroundStyle(Color(white: 0.40))
                .italic()
                .fixedSize(horizontal: false, vertical: true)
        case .image:
            VStack(alignment: .leading, spacing: 0) {
                if let url = para.imageURL {
                    GeometryReader { geo in
                        let w = geo.size.width
                        let r = para.nativeSize.width > 0
                            ? para.nativeSize.height / para.nativeSize.width : 0.75
                        let h = w * r
                        AsyncImage(url: url) { img in
                            img.resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: w, height: h)
                                .clipped()
                        } placeholder: {
                            Color(white: 0.18).frame(width: w, height: h)
                        }
                    }
                    .frame(height: {
                        let w = UIScreen.main.bounds.width
                        let r = para.nativeSize.width > 0
                            ? para.nativeSize.height / para.nativeSize.width : 0.75
                        return w * r
                    }())
                }
                if !para.text.isEmpty {
                    Text(para.text)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.38))
                        .italic()
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, -20)
            .padding(.bottom, 12)
        case .body:
            Text(para.text)
                .font(.system(size: 16))
                .foregroundStyle(Color(white: 0.82))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func paragraphSpacing(_ para: ArticleParagraph) -> CGFloat {
        switch para.style {
        case .heading: return 2
        case .body: return 16
        default: return 10
        }
    }

    private func displayDate(_ s: String) -> String? {
        guard s.count == 8 else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"
        guard let d = f.date(from: s) else { return nil }
        f.dateStyle = .medium; f.timeStyle = .none; f.locale = Locale(identifier: "fr_CH")
        return f.string(from: d)
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
    /// Corrige le double-encoding UTF-8/Latin-1 fréquent dans l'API PressReader.
    var fixedEncoding: String {
        guard let latin1 = self.data(using: .isoLatin1),
              let utf8 = String(data: latin1, encoding: .utf8)
        else { return self }
        return utf8
    }
}
