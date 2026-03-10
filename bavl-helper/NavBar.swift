import SwiftUI

/// Barre de navigation partagée — JournalView et ArticleReaderView.
///
/// Usage :
///   ZStack { … }
///   .overlay(alignment: .top) { NavBar(title:, subtitle:, visible:) }
///
/// La barre est une overlay flottante par-dessus le contenu.
/// Elle ne perturbe pas le layout du contenu en dessous.
/// Animation : offset vers le haut + opacity.
/// Le contenu scrollable doit réserver de l'espace via contentMargins ou padding.
struct NavBar: View {
    let title: String
    let subtitle: String
    let visible: Bool

    // Hauteur de la barre sans la safeArea (2 lignes × 44pt + 1 divider)
    static let height: CGFloat = 89

    private let bgColor       = Color(red: 0.13, green: 0.13, blue: 0.13)
    private let faint         = Color(white: 0.20)
    private let titleColor    = Color(white: 0.82)
    private let subtitleColor = Color(white: 0.55)

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 44)

            Divider().overlay(faint)

            Text(subtitle)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(subtitleColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 44)

            Divider().overlay(faint)
        }
        .background(bgColor)
        // Animation : glisse vers le haut et disparaît
        .offset(y: visible ? 0 : -NavBar.height)
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.22), value: visible)
    }
}
