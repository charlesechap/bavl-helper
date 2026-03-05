import Foundation

enum ViewMode: String, Codable, CaseIterable {
    case text = "text"
    case layout = "layout"

    var label: String {
        switch self {
        case .text: return "Texte"
        case .layout: return "Mise en page"
        }
    }
}

struct Newspaper: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var pressReaderPath: String
    var viewMode: ViewMode = .text
    var lastEditionDate: String? = nil  // format "yyyyMMdd", chargé dynamiquement

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f
    }()

    var resolvedURL: URL? {
        let date = lastEditionDate ?? Newspaper.dateFormatter.string(from: Date())
        switch viewMode {
        case .text:
            return URL(string: "https://www.pressreader.com/\(pressReaderPath)/\(date)/textview")
        case .layout:
            return URL(string: "https://www.pressreader.com/\(pressReaderPath)/\(date)")
        }
    }

    var archiveURL: URL? {
        URL(string: "https://www.pressreader.com/\(pressReaderPath)/archive")
    }
}

extension Newspaper {
    static let leTemps = Newspaper(name: "Le Temps", pressReaderPath: "switzerland/le-temps")
    static let defaults: [Newspaper] = [leTemps]
}
