import SwiftUI
import Combine

// MARK: - DuckLoadingView
// Animation 3 secondes. Pendant ce temps l'auth tourne en background.
// onComplete() déclenché quand canard sorti À DROITE et authReady == true.
// Si auth finie avant → attend fin traversée.
// Si traversée finie avant → attend authReady.

struct DuckLoadingView: View {
    let onComplete: () -> Void
    let authReady: Bool
    let log: [String]
    let currentMessage: String

    // Deux frames — boiterie Python fidèle
    private let frameA = ["      __     ", "   __( o)>   ", "   \\ <_ )    ", "    `--'     ", "     J       "]
    private let frameB = ["               ", "      __       ", "   __( o)>     ", "   \\ <_ )      ", "    `--'J      "]

    @State private var frameIndex = 0
    @State private var positionX: CGFloat = -140
    @State private var duckDone  = false

    private var frame: [String] { frameIndex == 0 ? frameA : frameB }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Zone canard
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
                .onAppear { startWalk(width: geo.size.width) }
            }
            .frame(height: 88)
            .padding(.bottom, 10)

            TerminalSeparator()
                .padding(.bottom, 10)

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

    // MARK: - Animation 3 secondes
    // Écran ~390pt, départ -140pt → total ~550pt
    // Durée cible : 3.0s
    // Cycle : frameA(0.18s) + frameB(0.12s) = 0.30s/cycle → ~10 cycles
    // Pas/cycle : 550 / 10 = 55pt

    private func startWalk(width: CGFloat) {
        let totalDistance = width + 160   // de -140 jusqu'à width+20
        let cycleDuration = 0.30          // secondes par cycle
        let stepSize = totalDistance / (3.0 / cycleDuration)   // pts/cycle ≈ 55pt

        func step() {
            frameIndex = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.linear(duration: 0.10)) {
                    positionX += stepSize
                    frameIndex = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    if positionX < width + 20 {
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

// MARK: - Spinner inline

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
