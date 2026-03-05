import SwiftUI
import Combine

// MARK: - Couleurs canard (fidèles au script Python duck.py)
// C_GRN  = vert brillant  → tête __
// C_WHT  = blanc brillant → œil  o
// C_YLW  = jaune brillant → bec  >  et pattes  _ . / . _
// C_GRA  = gris           → corps <_ )

private let dkGreen  = Color(red: 0.20, green: 0.90, blue: 0.20)
private let dkWhite  = Color(red: 1.00, green: 1.00, blue: 1.00)
private let dkYellow = Color(red: 1.00, green: 0.90, blue: 0.10)
private let dkGray   = Color(red: 0.50, green: 0.50, blue: 0.50)
private let dkNeutral = Color(white: 0.82)

// MARK: - Segment coloré

private struct S { // segment
    let t: String   // texte
    let c: Color    // couleur
    init(_ t: String, _ c: Color = Color(white: 0.82)) { self.t = t; self.c = c }
}

private func duckText(_ segs: [S]) -> Text {
    segs.reduce(Text("")) { acc, s in
        acc + Text(s.t).foregroundColor(s.c)
    }
}

// MARK: - Frames (4 lignes chacune)

// frame_couch — canard couché, 1ère frame du script
private let couch: [[S]] = [
    [S("               ")],
    [S("   "), S("__", dkGreen), S("        ")],
    [S("__( "), S("o", dkWhite), S(")"), S(">", dkYellow), S("      ")],
    [S("               ")],
]

// marche_A — patte avant "_ ."
private let marcheA: [[S]] = [
    [S("      "), S("__", dkGreen), S("       ")],
    [S("   __("), S("o", dkWhite), S(")"), S(">", dkYellow), S("     ")],
    [S("   \\ "), S("<_ )", dkGray), S("      ")],
    [S("    "), S("_ .", dkYellow), S("       ")],
]

// marche_B — patte arrière ". _"
private let marcheB: [[S]] = [
    [S("      "), S("__", dkGreen), S("       ")],
    [S("   __("), S("o", dkWhite), S(")"), S(">", dkYellow), S("     ")],
    [S("   \\ "), S("<_ )", dkGray), S("      ")],
    [S("    "), S(". _", dkYellow), S("       ")],
]

// MARK: - DuckStaticView — canard couché (onboarding, settings, idle)

struct DuckStaticView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(couch.enumerated()), id: \.offset) { _, segs in
                duckText(segs)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

// MARK: - DuckLoadingView

struct DuckLoadingView: View {
    let onComplete:     () -> Void
    let authReady:      Bool
    let log:            [String]
    let currentMessage: String

    @State private var frame:     [[S]]  = marcheA
    @State private var positionX: CGFloat = -120
    @State private var duckDone  = false
    @State private var started   = false   // anti-double onAppear

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Zone canard
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(frame.enumerated()), id: \.offset) { _, segs in
                            duckText(segs)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .offset(x: positionX)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .onAppear {
                    guard !started else { return }
                    started   = true
                    positionX = -120
                    startWalk(screenWidth: geo.size.width)
                }
            }
            .frame(height: 72)
            .padding(.bottom, 10)

            Divider().overlay(Color.termFaint).padding(.bottom, 10)

            // Log terminal
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

    // MARK: - Walk 3 secondes, rythme 0.18s (fidèle Python)

    private func startWalk(screenWidth: CGFloat) {
        let totalDist = screenWidth + 140.0   // -120 → screenWidth+20
        let cycleTime = 0.18                  // rythme Python exact
        let nCycles   = 3.0 / cycleTime       // 16.7 cycles
        let step      = totalDist / nCycles   // pts/cycle

        func tick() {
            frame = marcheA
            DispatchQueue.main.asyncAfter(deadline: .now() + cycleTime * 0.55) {
                withAnimation(.linear(duration: cycleTime * 0.25)) {
                    positionX += step
                    frame = marcheB
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + cycleTime * 0.45) {
                    if positionX < screenWidth + 20 {
                        tick()
                    } else {
                        duckDone = true
                        if authReady { onComplete() }
                    }
                }
            }
        }
        tick()
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
        VStack(spacing: 32) {
            DuckStaticView()
            Divider().overlay(Color.termFaint)
            DuckLoadingView(onComplete: {}, authReady: false,
                log: ["Connexion BAVL...", "Formulaire..."],
                currentMessage: "Envoi identifiants...")
        }
        .padding()
    }
}
