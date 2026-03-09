import SwiftUI

// MARK: - Modèles

struct ArticleParagraph: Identifiable {
    let id = UUID()
    let text: String
    let style: ParagraphStyle
    let imageURL: URL?    // non-nil quand style == .image

    init(text: String, style: ParagraphStyle, imageURL: URL? = nil) {
        self.text = text
        self.style = style
        self.imageURL = imageURL
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
                      let encoded = rawKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let imgURL = URL(string: "https://i.prcdn.co/img?regionKey=\(encoded)&width=1170")
                else { continue }
                let caption = (img["caption"] as? String)?.fixedEncoding ?? ""
                imageParagraphs.append(ArticleParagraph(text: caption, style: .image, imageURL: imgURL))
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

// MARK: - Vue principale

struct ArticleReaderView: View {
    let article: ArticleContent
    let onDismiss: () -> Void
    let onJournal: () -> Void

    var body: some View {
        GeometryReader { geo in
            let safeTop = geo.safeAreaInsets.top
            ZStack(alignment: .top) {
                Color(red: 0.13, green: 0.13, blue: 0.13).ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Header article
                        articleHeader
                            .padding(.top, safeTop + 44 + 20)
                            .padding(.horizontal, 20)

                        Divider()
                            .overlay(Color(white: 0.25))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)

                        // Corps
                        ForEach(article.paragraphs) { para in
                            paragraphView(para)
                                .padding(.horizontal, 20)
                                .padding(.bottom, paragraphSpacing(para))
                        }

                        // Marge basse
                        Color.clear.frame(height: 60)
                    }
                }

                // TerminalBar article reader
                readerBar(safeTop: safeTop)
            }
            .ignoresSafeArea(edges: .top)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var articleHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Rubrique + date
            if let section = article.sectionName, !section.isEmpty {
                Text(section.uppercased())
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color(white: 0.45))
                    .tracking(1.5)
            }

            // Titre
            Text(article.title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color(white: 0.92))
                .fixedSize(horizontal: false, vertical: true)

            // Sous-titre
            if let sub = article.subtitle, !sub.isEmpty {
                Text(sub)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color(white: 0.65))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            // Auteur + date
            HStack(spacing: 8) {
                if let auth = article.author, !auth.isEmpty {
                    Text(auth)
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(Color(white: 0.50))
                }
                if !article.date.isEmpty, let d = displayDate(article.date) {
                    Text("·")
                        .foregroundStyle(Color(white: 0.30))
                    Text(d)
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(Color(white: 0.40))
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
                .padding(.top, 8)
                .padding(.bottom, 4)
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
            VStack(alignment: .leading, spacing: 6) {
                if let url = para.imageURL {
                    PressImage(url: url, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 160)
                }
                if !para.text.isEmpty {
                    Text(para.text)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.38))
                        .italic()
                        .padding(.horizontal, 20)
                }
            }
            .padding(.horizontal, -20)  // annuler le padding parent pour aller pleine largeur
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

    // MARK: - TerminalBar lecture

    private func readerBar(safeTop: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                // ← retour journal
                Button(action: onJournal) {
                    Text("←")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color(white: 0.82))
                }
                .frame(width: 44, height: 44)
                .padding(.leading, 8)

                Spacer()

                // Titre court centré
                Text(article.title)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color(white: 0.35))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 200)

                Spacer()

                // X fermer
                Button(action: onDismiss) {
                    Text("X")
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

    // MARK: - Helpers

    private func displayDate(_ dateStr: String) -> String? {
        guard dateStr.count == 8 else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd"
        guard let d = fmt.date(from: dateStr) else { return nil }
        fmt.dateStyle = .medium; fmt.timeStyle = .none; fmt.locale = Locale(identifier: "fr_CH")
        return fmt.string(from: d)
    }
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
