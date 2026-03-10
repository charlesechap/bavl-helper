import SwiftUI

/// Barre de navigation partagée — JournalView et ArticleReaderView.
///
/// Utilisée en .overlay(alignment: .top) { NavBar().ignoresSafeArea(edges: .top) }
/// Le contenu scrollable doit réserver NavBar.height via contentMargins.
struct NavBar: View {
    let title: String
    let subtitle: String
    let visible: Bool

    /// Hauteur de la barre (2 lignes × 44pt + séparateur) — hors safe area top
    static let height: CGFloat = 89

    private let bgColor       = Color(red: 0.13, green: 0.13, blue: 0.13)
    private let faint         = Color(white: 0.20)
    private let titleColor    = Color(white: 0.82)
    private let subtitleColor = Color(white: 0.55)

    var body: some View {
        VStack(spacing: 0) {
            // Zone safe area — fond seulement, pas de contenu
            Color.clear
                .frame(maxWidth: .infinity)

            // Ligne 1 : titre
            Text(title)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 44)

            Divider().overlay(faint)

            // Ligne 2 : sous-titre / date
            Text(subtitle)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(subtitleColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 44)

            Divider().overlay(faint)
        }
        .background(bgColor.ignoresSafeArea(edges: .top))
        // Animation : glisse vers le haut et disparaît
        .offset(y: visible ? 0 : -NavBar.height)
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.22), value: visible)
    }
}
