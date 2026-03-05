import SwiftUI
import Combine

// MARK: - DuckLoadingView
// Le canard traverse l'écran UNE seule fois.
// Pendant ce temps, l'auth tourne en arrière-plan (vm.authReady).
// Quand le canard sort à droite ET que l'auth est prête → onComplete()
// Si l'auth finit avant → on attend la fin de la traversée.
// Si le canard finit avant → on attend authReady.

struct DuckLoadingView: View {
    /// Appelé quand la traversée est terminée ET l'auth prête
    let onComplete: () -> Void
    /// true quand l'auth backend est terminée (set par AppViewModel)
    let authReady: Bool
    /// Messages de log à afficher
    let log: [String]
    let currentMessage: String

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

    @State private var frameIndex: Int = 0
    @State private var positionX: CGFloat = -160
    @State private var duckDone: Bool = false
    @State private var screenWidth: CGFloat = 0

    private var currentFrame: [String] { frameIndex == 0 ? frameA : frameB }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Zone canard — pleine largeur
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(currentFrame.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(Color(white: 0.82))
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .offset(x: positionX)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .onAppear {
                    screenWidth = geo.size.width
                    startWalk(screenWidth: geo.size.width)
                }
                .onChange(of: geo.size.width) { _, w in
                    screenWidth = w
                }
            }
            .frame(height: 90)
            .padding(.bottom, 12)

            Divider()
                .overlay(Color(white: 0.30))
                .padding(.bottom, 10)

            // Log
            VStack(alignment: .leading, spacing: 5) {
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
        // Quand authReady passe à true après la traversée → on complète
        .onChange(of: authReady) { _, ready in
            if ready && duckDone {
                onComplete()
            }
        }
    }

    // MARK: - Walk

    private func startWalk(screenWidth: CGFloat) {
        // Durée d'un cycle complet : ~0.35s (frameA 0.22 + frameB 0.13)
        // Pas par cycle : 28pt
        // Nombre de cycles pour traverser l'écran (~390pt + marge) : ~20 cycles
        // Durée totale traversée : ~7s — suffisant pour l'auth BAVL

        func step() {
            // Frame A — appui
            frameIndex = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                // Frame B — bond
                withAnimation(.linear(duration: 0.10)) {
                    positionX += 28
                    frameIndex = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
                    if positionX < screenWidth + 20 {
                        step()
                    } else {
                        // Canard sorti à droite
                        duckDone = true
                        if authReady {
                            onComplete()
                        }
                        // Sinon on attend onChange(authReady)
                    }
                }
            }
        }

        step()
    }
}

// MARK: - SpinnerView

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
            onComplete: { print("done") },
            authReady: false,
            log: ["Connexion au portail BAVL...", "Formulaire détecté..."],
            currentMessage: "Envoi des identifiants..."
        )
    }
}
