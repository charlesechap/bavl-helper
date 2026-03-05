import SwiftUI

// MARK: - DuckLoadingView
// Canard boiteux ASCII qui traverse l'écran pendant le chargement

struct DuckLoadingView: View {
    let log: [String]
    let currentMessage: String

    // Frames ASCII — boiterie fidèle au script Python original
    private let frameA: [String] = [
        "      __     ",
        "   __( o)>   ",
        "   \\ <_ )    ",
        "    `--'     ",
        "     J       "
    ]
    private let frameB: [String] = [
        "               ",
        "      __       ",
        "   __( o)>     ",
        "   \\ <_ )      ",
        "    `--'J      "
    ]

    @State private var frameIndex: Int = 0       // 0 = A, 1 = B
    @State private var positionX: CGFloat = -120  // démarre hors écran gauche
    @State private var running: Bool = false

    // Largeur d'un caractère monospaced ~8.5pt à caption size
    private let charWidth: CGFloat = 8.0

    private var currentFrame: [String] {
        frameIndex == 0 ? frameA : frameB
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Zone canard
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    // Frame ASCII
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(currentFrame.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Color(white: 0.82))
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .offset(x: positionX)
                    .onAppear {
                        startAnimation(screenWidth: geo.size.width)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            }
            .frame(height: 80)
            .padding(.bottom, 16)

            Divider()
                .overlay(Color(white: 0.30))
                .padding(.bottom, 12)

            // Log de statut
            VStack(alignment: .leading, spacing: 6) {
                ForEach(log.dropLast(), id: \.self) { line in
                    Text("  ✓ \(line)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color(white: 0.45))
                }
                if !currentMessage.isEmpty {
                    HStack(spacing: 6) {
                        SpinnerView()
                        Text(currentMessage)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Color(white: 0.82))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
    }

    // MARK: - Animation

    private func startAnimation(screenWidth: CGFloat) {
        guard !running else { return }
        running = true
        positionX = -120

        func step() {
            // Frame A : appui — reste un peu plus longtemps
            withAnimation(.linear(duration: 0)) {
                frameIndex = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                // Frame B : chute + bond en avant
                withAnimation(.linear(duration: 0.12)) {
                    positionX += 24
                    frameIndex = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
                    // Repart si pas arrivé au bout
                    if positionX < screenWidth + 20 {
                        step()
                    } else {
                        // Repart depuis la gauche
                        positionX = -120
                        frameIndex = 0
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            step()
                        }
                    }
                }
            }
        }

        step()
    }
}

// MARK: - SpinnerView (inline, remplace ASCIISpinnerView dans ce contexte)

private struct SpinnerView: View {
    private let frames = ["|", "/", "─", "\\"]
    @State private var idx = 0
    private let timer = Timer.publish(every: 0.12, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(frames[idx])
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(Color(white: 0.82))
            .onReceive(timer) { _ in idx = (idx + 1) % frames.count }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color(red: 0.13, green: 0.13, blue: 0.13).ignoresSafeArea()
        DuckLoadingView(
            log: [
                "Connexion au portail BAVL...",
                "Formulaire détecté — saisie des identifiants..."
            ],
            currentMessage: "Envoi des identifiants..."
        )
    }
}
