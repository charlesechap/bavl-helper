import SwiftUI
import Combine

// Palette fidèle au script Python duck.py
private let dkGreen  = Color(red: 0.20, green: 0.90, blue: 0.20)  // C_GRN — tête
private let dkWhite  = Color(red: 1.00, green: 1.00, blue: 1.00)  // C_WHT — oeil
private let dkYellow = Color(red: 1.00, green: 0.90, blue: 0.10)  // C_YLW — bec, pattes
private let dkGray   = Color(red: 0.55, green: 0.55, blue: 0.55)  // C_GRA — corps

private struct S {
    let t: String; let c: Color
    init(_ t: String, _ c: Color = Color(white: 0.82)) { self.t = t; self.c = c }
}

@ViewBuilder
private func duckLine(_ segs: [S]) -> some View {
    HStack(spacing: 0) {
        ForEach(Array(segs.enumerated()), id: \.offset) { _, s in
            Text(s.t).foregroundStyle(s.c)
        }
    }
    .font(.system(.body, design: .monospaced))
    .lineLimit(1)
    .fixedSize()
}

// ── frame_couch (titre, repos) ─────────────────────────────────────────────
//    __
// __( o)>
private let frameCouch: [[S]] = [
    [S("               ")],
    [S("   "), S("__", dkGreen)],
    [S("__( "), S("o", dkWhite), S(")"), S(">", dkYellow)],
    [S("               ")],
]

// frame clignement — oeil fermé
private let frameBlink: [[S]] = [
    [S("               ")],
    [S("   "), S("__", dkGreen)],
    [S("__( "), S("-", dkGray), S(")"), S(">", dkYellow)],
    [S("               ")],
]

// ── frame_lev (se lève — transition) ──────────────────────────────────────
//     __
//  __(o)>
//  \ <_ )
//    _ _
private let frameLev: [[S]] = [
    [S("    "), S("__", dkGreen)],
    [S(" __("), S("o", dkWhite), S(")"), S(">", dkYellow)],
    [S("  <_ )", dkGray)],
    [S(" "), S("_ _", dkYellow)],
]

// ── marche A — patte avant ─────────────────────────────────────────────────
//       __
//    __(o)>
//    \ <_ )
//     _ .
private let marcheA: [[S]] = [
    [S("      "), S("__", dkGreen)],
    [S("   __("), S("o", dkWhite), S(")"), S(">", dkYellow)],
    [S("   <_ )", dkGray)],
    [S("    "), S("_ .", dkYellow)],
]

// ── marche B — patte arrière ───────────────────────────────────────────────
//       __
//    __(o)>
//    \ <_ )
//     . _
private let marcheB: [[S]] = [
    [S("      "), S("__", dkGreen)],
    [S("   __("), S("o", dkWhite), S(")"), S(">", dkYellow)],
    [S("   <_ )", dkGray)],
    [S("    "), S(". _", dkYellow)],
]

// MARK: - DuckHeaderView

struct DuckHeaderView: View {
    let walking:        Bool
    let authReady:      Bool
    let onWalkComplete: () -> Void

    @State private var frame:     [[S]]  = frameCouch
    @State private var positionX: CGFloat = 0
    @State private var walkDone           = false
    @State private var started            = false
    @State private var blinkTimer: Timer? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(frame.enumerated()), id: \.offset) { _, segs in
                        duckLine(segs)
                    }
                }
                .offset(x: positionX)
            }
            .onChange(of: walking) { _, isWalking in
                if isWalking {
                    stopBlink()
                    startWalk(screenWidth: geo.size.width)
                } else {
                    started   = false
                    walkDone  = false
                    positionX = 0
                    frame     = frameCouch
                    startBlink()
                }
            }
            .onChange(of: authReady) { _, ready in
                if ready && walkDone { onWalkComplete() }
            }
        }
        .frame(height: 88)
        .clipped()
        .onAppear { startBlink() }
        .onDisappear { stopBlink() }
    }

    // ── Clignement toutes les 2s ──────────────────────────────────────────
    private func startBlink() {
        stopBlink()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            guard !started else { return }
            frame = frameBlink
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { frame = frameCouch }
        }
    }
    private func stopBlink() { blinkTimer?.invalidate(); blinkTimer = nil }

    // ── Séquence fidèle à duck.py ─────────────────────────────────────────
    // 1. couché 1.0s
    // 2. se lève (frameLev) 0.7s
    // 3. marche A/B, avance de x=0 → screenWidth, cycleTime=0.18s
    private func startWalk(screenWidth: CGFloat) {
        guard !started else { return }
        started   = true
        walkDone  = false
        frame     = frameCouch
        positionX = 0

        // Phase 1 : couché
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Phase 2 : se lève
            frame = frameLev
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                // Phase 3 : marche — distance = screenWidth, step = 3 px par demi-cycle
                // vitesse cible : 0.18s/cycle → screenWidth / (0.18/2) cycles en vol
                // On calcule le step pour traverser screenWidth en ~3s (durée totale)
                let cycleTime: Double = 0.18
                let totalTime: Double = 3.0
                let nCycles           = totalTime / cycleTime        // ~16.7
                let step              = screenWidth / CGFloat(nCycles)

                func tick() {
                    frame = marcheA
                    DispatchQueue.main.asyncAfter(deadline: .now() + cycleTime * 0.5) {
                        frame = marcheB
                        withAnimation(.linear(duration: cycleTime * 0.4)) {
                            positionX += step
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + cycleTime * 0.5) {
                            if positionX < screenWidth {
                                tick()
                            } else {
                                walkDone = true
                                if authReady { onWalkComplete() }
                            }
                        }
                    }
                }
                tick()
            }
        }
    }
}

// MARK: - WalkLogView

struct WalkLogView: View {
    let log:            [String]
    let currentMessage: String

    var body: some View {
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
        .padding(.horizontal)
        .padding(.top, 12)
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

// DuckStaticView = frame_couch avec clignement
typealias DuckStaticView = _DuckStaticView
struct _DuckStaticView: View {
    @State private var blink = false
    @State private var blinkTimer: Timer? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array((blink ? frameBlink : frameCouch).enumerated()), id: \.offset) { _, segs in
                duckLine(segs)
            }
        }
        .onAppear {
            blinkTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                blink = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { blink = false }
            }
        }
        .onDisappear { blinkTimer?.invalidate(); blinkTimer = nil }
    }
}
