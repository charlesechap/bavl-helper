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

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f
    }()

    /// Dernière édition disponible (pas de date → PressReader choisit)
    var latestURL: URL? {
        switch viewMode {
        case .text:
            return URL(string: "https://www.pressreader.com/\(pressReaderPath)/textview")
        case .layout:
            return URL(string: "https://www.pressreader.com/\(pressReaderPath)")
        }
    }
}

extension Newspaper {
    static let leTemps = Newspaper(name: "Le Temps", pressReaderPath: "switzerland/le-temps")
    static let defaults: [Newspaper] = [leTemps]
}
