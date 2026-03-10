import SwiftUI

/// Barre de navigation partagée — JournalView et ArticleReaderView.
/// Placée en .overlay(alignment: .top) sur le ZStack parent.
/// La safe area top est gérée par .background(.ignoresSafeArea) seulement.
struct NavBar: View {
    let title: String
    let subtitle: String
    let visible: Bool

    /// Hauteur des deux lignes de contenu (hors safe area top)
    static let height: CGFloat = 89

    private let bg   = Color(red: 0.13, green: 0.13, blue: 0.13)
    private let line = Color(white: 0.20)
    private let col1 = Color(white: 0.82)
    private let col2 = Color(white: 0.55)

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(col1)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 44)

            Divider().overlay(line)

            Text(subtitle)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(col2)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 44)

            Divider().overlay(line)
        }
        // Le fond s'étend sous le notch/Dynamic Island
        .background(bg.ignoresSafeArea(edges: .top))
        .offset(y: visible ? 0 : -(NavBar.height + 200))
        .animation(.easeInOut(duration: 0.22), value: visible)
    }
}
