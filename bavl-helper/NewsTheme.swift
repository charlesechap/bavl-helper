import SwiftUI

// MARK: - NewsTheme
// Palette typographique et couleurs pour les vues journal/article.
// Deux modes : .day (fond papier journal chaud) et .night (fond off-black, repose les yeux).

struct NewsTheme {

    enum Mode { case day, night }

    // MARK: Couleurs fond
    let background:    Color   // fond principal
    let surface:       Color   // fond cards / sections headers
    let divider:       Color   // séparateurs

    // MARK: Couleurs texte
    let textPrimary:   Color   // titres, corps
    let textSecondary: Color   // chapeau, sous-titres
    let textTertiary:  Color   // auteurs, dates, légendes
    let textDim:       Color   // labels rubriques, meta

    // MARK: Accent
    let accent:        Color   // rouge journal — rubriques, traits
    let accentMuted:   Color   // version adoucie pour dark mode

    // MARK: Images placeholder
    let imagePlaceholder: Color

    // MARK: Presets
    static let day = NewsTheme(
        background:       Color(red: 0.975, green: 0.968, blue: 0.952),
        surface:          Color(red: 0.955, green: 0.948, blue: 0.930),
        divider:          Color(red: 0.780, green: 0.768, blue: 0.748),
        textPrimary:      Color(red: 0.100, green: 0.095, blue: 0.090),
        textSecondary:    Color(red: 0.280, green: 0.268, blue: 0.255),
        textTertiary:     Color(red: 0.460, green: 0.448, blue: 0.432),
        textDim:          Color(red: 0.560, green: 0.548, blue: 0.530),
        accent:           Color(red: 0.720, green: 0.080, blue: 0.080),
        accentMuted:      Color(red: 0.820, green: 0.160, blue: 0.120),
        imagePlaceholder: Color(red: 0.880, green: 0.872, blue: 0.856)
    )

    static let night = NewsTheme(
        background:       Color(red: 0.100, green: 0.100, blue: 0.108),
        surface:          Color(red: 0.138, green: 0.138, blue: 0.148),
        divider:          Color(red: 0.218, green: 0.218, blue: 0.228),
        textPrimary:      Color(red: 0.900, green: 0.892, blue: 0.878),
        textSecondary:    Color(red: 0.668, green: 0.660, blue: 0.645),
        textTertiary:     Color(red: 0.468, green: 0.460, blue: 0.448),
        textDim:          Color(red: 0.368, green: 0.362, blue: 0.350),
        accent:           Color(red: 0.920, green: 0.340, blue: 0.280),
        accentMuted:      Color(red: 0.820, green: 0.260, blue: 0.200),
        imagePlaceholder: Color(red: 0.180, green: 0.180, blue: 0.188)
    )
}

// MARK: - Environment key
private struct NewsThemeKey: EnvironmentKey {
    static let defaultValue = NewsTheme.night
}

extension EnvironmentValues {
    var newsTheme: NewsTheme {
        get { self[NewsThemeKey.self] }
        set { self[NewsThemeKey.self] = newValue }
    }
}

// MARK: - Section accent colors (par rubrique)
extension NewsTheme {
    /// Couleur d'accent pour une rubrique donnée (fallback sur `accent`).
    func sectionAccent(for name: String) -> Color {
        switch name.lowercased() {
        case let s where s.contains("monde") || s.contains("international"):
            return Color(red: 0.15, green: 0.38, blue: 0.65)
        case let s where s.contains("éco") || s.contains("finance") || s.contains("business"):
            return Color(red: 0.12, green: 0.52, blue: 0.35)
        case let s where s.contains("culture") || s.contains("art") || s.contains("cinéma"):
            return Color(red: 0.52, green: 0.18, blue: 0.62)
        case let s where s.contains("sport"):
            return Color(red: 0.88, green: 0.42, blue: 0.08)
        case let s where s.contains("science") || s.contains("santé"):
            return Color(red: 0.08, green: 0.52, blue: 0.62)
        default:
            return accent
        }
    }
}
