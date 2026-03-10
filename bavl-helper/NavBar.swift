import SwiftUI

/// Barre de navigation partagée — JournalView et ArticleReaderView.
/// Placée via `.safeAreaInset(edge: .top, spacing: 0)` sur le ZStack parent.
/// SwiftUI gère automatiquement le notch/Dynamic Island — aucun calcul manuel.
/// L'animation hide/show est obtenue via `frame(height:)` + `clipped()`.
struct NavBar: View {
    let title: String
    let subtitle: String
    let visible: Bool

    private let bgColor   = Color(red: 0.13, green: 0.13, blue: 0.13)
    private let faint     = Color(white: 0.20)
    private let titleColor    = Color(white: 0.82)
    private let subtitleColor = Color(white: 0.55)
    private let barHeight: CGFloat = 89   // 2 × 44 + 1 divider (≈1pt)

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
        // Animation hide : la hauteur passe à 0, le contenu est clippé
        .frame(height: visible ? barHeight : 0)
        .clipped()
        .animation(.easeInOut(duration: 0.22), value: visible)
    }
}
