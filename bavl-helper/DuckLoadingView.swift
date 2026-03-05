import SwiftUI
import Combine

// MARK: - DuckLoadingView
//
// Frames du script Python duck.py :
//   marche_A : patte avant posée
//   marche_B : patte arrière posée
//
// Timing Python : 0.18s/cycle, pas = 3 chars ≈ 8pt/cycle
// Sur iPhone (375pt utile) depuis x = -120 jusqu'à x = 400 → ~520pt
// À ~8pt/cycle → 65 cycles → 65 × 0.18s ≈ 11.7s  (trop long)
//
// Cible 3s → stepSize = 520 / (3.0 / 0.18) ≈ 31pt/cycle
// On garde le rythme 0.18s mais on agrandit le pas proportionnellement.
//
// onComplete() : quand canard sorti à droite ET authReady == true.

struct DuckLoadingView: View {
    let onComplete:     () -> Void
    let authReady:      Bool
    let log:            [String]
    let currentMessage: String

    // Frames exactes du script Python (sans codes ANSI)
    private let frameA = [
        "      __       ",
        "   __(o)>      ",
        "   \\ <_ )      ",
        "    _ .        ",
    ]
    private let frameB = [
        "      __       ",
        "   __(o)>      ",
        "   \\ <_ )      ",
        "    . _        ",
    ]

    @State private var frameIndex = 0
    @State private var positionX: CGFloat = -120
    @State private var duckDone  = false

    private var frame: [String] { frameIndex == 0 ? frameA : frameB }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Zone canard pleine largeur
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(frame.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(Color.termFg)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .offset(x: positionX)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .onAppear { startWalk(screenWidth: geo.size.width) }
            }
            .frame(height: 72)
            .padding(.bottom, 10)

            Divider().overlay(Color.termFaint).padding(.bottom, 10)

            // Log
            VStack(alignment: .leading, spacing: 5) {
                ForEach(log.dropLast(), id: \.self) { line in
                    Text("  ✓ \(line)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.termDim)
                }
                if !currentMessage.isEmpty {
                    HStack(spacing: 6) {
                        SpinnerView()
                        Text(currentMessage)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Color.termFg)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .onChange(of: authReady) { _, ready in
            if ready && duckDone { onComplete() }
        }
    }

    // MARK: - Walk
    //
    // Rythme Python : 0.18s/cycle
    // Pas ajusté pour traverser en ~3s : stepSize = totalDist / (3.0 / 0.18)

    private func startWalk(screenWidth: CGFloat) {
        // Distance totale : de -120 jusqu'à screenWidth + 20
        let totalDist  = screenWidth + 140.0
        let cycleTime  = 0.18                          // rythme Python fidèle
        let nCycles    = 3.0 / cycleTime               // ~16.7 cycles pour 3s
        let stepSize   = totalDist / nCycles           // pts par cycle

        func step() {
            // Frame A
            frameIndex = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + cycleTime * 0.6) {
                // Frame B + déplacement
                withAnimation(.linear(duration: cycleTime * 0.3)) {
                    positionX  += stepSize
                    frameIndex  = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + cycleTime * 0.4) {
                    if positionX < screenWidth + 20 {
                        step()
                    } else {
                        duckDone = true
                        if authReady { onComplete() }
                    }
                }
            }
        }

        step()
    }
}

// MARK: - Spinner

private struct SpinnerView: View {
    private let frames = ["|", "/", "─", "\\"]
    @State private var idx = 0
    private let timer = Timer.publish(every: 0.12, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(frames[idx])
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(Color.termFg)
            .onReceive(timer) { _ in idx = (idx + 1) % frames.count }
    }
}

#Preview {
    ZStack {
        Color.termBg.ignoresSafeArea()
        DuckLoadingView(
            onComplete: {},
            authReady: false,
            log: ["Connexion BAVL...", "Formulaire détecté..."],
            currentMessage: "Envoi des identifiants..."
        )
    }
}
