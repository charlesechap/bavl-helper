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

    var todayURL: URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let dateStr = formatter.string(from: Date())
        switch viewMode {
        case .text:
            return URL(string: "https://www.pressreader.com/\(pressReaderPath)/\(dateStr)/textview")
        case .layout:
            return URL(string: "https://www.pressreader.com/\(pressReaderPath)/\(dateStr)")
        }
    }
}

extension Newspaper {
    static let leTemps = Newspaper(name: "Le Temps", pressReaderPath: "switzerland/le-temps")
    static let defaults: [Newspaper] = [leTemps]
}
