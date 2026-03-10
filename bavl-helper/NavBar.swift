import SwiftUI

// Barre de navigation lecture — intégrée via .safeAreaInset(edge: .top, spacing: 0)
// Le scroll gère seul l'espace : pas de contentMargins, pas de barVisible.

struct ReadingBar: View {
    let title: String
    let subtitle: String
    let theme: ReadingTheme   // reçoit le même thème que la vue parente

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular, design: .serif).italic())
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            Rectangle()
                .fill(theme.divider)
                .frame(height: 0.5)
        }
        .background(theme.background)
    }
}

// Variante pour ArticleReaderView qui utilise NewsTheme
struct ReadingBarNight: View {
    let title: String
    let subtitle: String
    let theme: NewsTheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular, design: .serif).italic())
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            Rectangle()
                .fill(theme.divider)
                .frame(height: 0.5)
        }
        .background(theme.background)
    }
}
