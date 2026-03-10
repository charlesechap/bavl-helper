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

// ── canard_couch ───────────────────────────────────────────────────────────
//                    (vide)
//    __
// __( o)>
//  \ <_ )
private let frameCouch: [[S]] = [
    [S("               ")],
    [S("   "), S("__", dkGreen)],
    [S("__("), S("o", dkWhite), S(")"), S(">", dkYellow)],
    [S(" \\ "), S("<_ )", dkGray)],
]

// frame clignement — oeil fermé
private let frameBlink: [[S]] = [
    [S("               ")],
    [S("   "), S("__", dkGreen)],
    [S("__("), S("-", dkGray), S(")"), S(">", dkYellow)],
    [S(" \\ "), S("<_ )", dkGray)],
]

// ── corps_souleve + pattes ─────────────────────────────────────────────────
//      __
//   __( o)>
//   \ <_ )
//     _ _   / _ .   / . _
private let corpsSouleve: [[S]] = [
    [S("      "), S("__", dkGreen)],
    [S("   __("), S("o", dkWhite), S(")"), S(">", dkYellow)],
    [S("   \\ "), S("<_ )", dkGray)],
]

private let frameDebout: [[S]] = corpsSouleve + [[S("    "), S("_ _", dkYellow)]]
private let marcheA:     [[S]] = corpsSouleve + [[S("    "), S("_ .", dkYellow)]]
private let marcheB:     [[S]] = corpsSouleve + [[S("    "), S(". _", dkYellow)]]

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
                    let w = max(geo.size.width, 400)
                    startWalk(screenWidth: w)
                } else {
                    started   = false
                    walkDone  = false
                    positionX = 0
                    frame     = frameCouch
                    startBlink()
                }
            }
            .onChange(of: authReady) { _, _ in
                // authReady arrivé pendant la marche → le prochain tick() sortira
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

    // ── Séquence fidèle à duck.py ──────────────────────────────────────────
    // Durée totale cible : ~4s (2.2s couché + 0.6s lever + marche)
    // Si authReady arrive pendant la marche → on finit le cycle en cours et on sort
    private func startWalk(screenWidth: CGFloat) {
        guard !started else { return }
        started   = true
        walkDone  = false
        frame     = frameCouch
        positionX = 0

        // Phase 1 : couché 2.2s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            // Phase 2 : se lève 0.6s
            frame = frameDebout
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                // Phase 3 : marche — cycle 0.8s, step = largeur / nb_cycles_cibles
                // On vise ~6 cycles visibles (4.8s de marche), step = screenWidth / 6
                // mais on sort dès qu'authReady est true ET qu'on a fait au moins 1 cycle
                let cycleTime: Double = 0.8  // 0.5 appui + 0.15 + 0.15
                let targetWidth = max(screenWidth, 400)
                let step = targetWidth / 6.0
                var cyclesDone = 0

                func tick() {
                    frame = frameDebout
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        frame = marcheA
                        withAnimation(.linear(duration: 0.12)) { positionX += step * 0.5 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            frame = marcheB
                            withAnimation(.linear(duration: 0.12)) { positionX += step * 0.5 }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                cyclesDone += 1
                                // Sortir si : écran traversé OU (authReady et au moins 1 cycle)
                                if positionX >= targetWidth || (authReady && cyclesDone >= 1) {
                                    walkDone = true
                                    onWalkComplete()
                                } else {
                                    tick()
                                }
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

// DuckStaticView = frameCouch avec clignement
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
