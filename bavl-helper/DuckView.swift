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
                    let w = max(geo.size.width * 3, 1200)
                    startWalk(screenWidth: w)
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
            .onChange(of: walkDone) { _, done in
                if done && authReady { onWalkComplete() }
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
    // 1. couché 2.2s
    // 2. se lève (frameDebout) 1.0s
    // 3. marche boitante : appui 0.5s + pas1 0.15s + pas2 0.15s, avance 4px/cycle
    private func startWalk(screenWidth: CGFloat) {
        guard !started else { return }
        started   = true
        walkDone  = false
        frame     = frameCouch
        positionX = 0

        // Phase 1 : couché 2.2s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            // Phase 2 : se lève 1.0s
            frame = frameDebout
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Phase 3 : marche boitante (rythme asymétrique duck.py)
                func tick() {
                    // Appui / hésitation
                    frame = frameDebout
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        // Pas 1 (rapide)
                        frame = marcheA
                        withAnimation(.linear(duration: 0.1)) { positionX += 2 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            // Pas 2 (rapide)
                            frame = marcheB
                            withAnimation(.linear(duration: 0.1)) { positionX += 2 }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                if positionX < screenWidth {
                                    tick()
                                } else {
                                    walkDone = true
                                    if authReady { onWalkComplete() }
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

// ── canard_couch — fidèle à duck.py ───────────────────────────────────────
//                (ligne 1 vide)
//    __          (ligne 2)
// __( o)>        (ligne 3)
//  \ <_ )        (ligne 4)
private let frameCouch: [[S]] = [
    [S("               ")],
    [S("   "), S("__", dkGreen)],
    [S("__("), S(" "), S("o", dkWhite), S(")"), S(">", dkYellow)],
    [S(" \\ "), S("<_ )", dkGray)],
]

// clignement — oeil fermé
private let frameBlink: [[S]] = [
    [S("               ")],
    [S("   "), S("__", dkGreen)],
    [S("__("), S(" "), S("-", dkGray), S(")"), S(">", dkYellow)],
    [S(" \\ "), S("<_ )", dkGray)],
]

// ── corps_souleve — fidèle à duck.py ──────────────────────────────────────
//       __         (ligne 1)
//    __(o)>         (ligne 2)
//    \ <_ )         (ligne 3)
private let corpsSouleve: [[S]] = [
    [S("      "), S("__", dkGreen)],
    [S("   __("), S("o", dkWhite), S(")"), S(">", dkYellow)],
    [S("   \\ "), S("<_ )", dkGray)],
]

private let frameLev: [[S]] = corpsSouleve + [[S("    "), S("_ _", dkYellow)]]
private let marcheA:  [[S]] = corpsSouleve + [[S("    "), S("_ .", dkYellow)]]
private let marcheB:  [[S]] = corpsSouleve + [[S("    "), S(". _", dkYellow)]]

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
                    let w = max(geo.size.width * 3, 1200)
                    startWalk(screenWidth: w)
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
            .onChange(of: walkDone) { _, done in
                if done && authReady { onWalkComplete() }
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
    // 1. couché 2.2s  2. se lève 1.0s  3. marche A/B
    private func startWalk(screenWidth: CGFloat) {
        guard !started else { return }
        started   = true
        walkDone  = false
        frame     = frameCouch
        positionX = 0

        // Phase 1 : couché (2.2s comme duck.py)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            // Phase 2 : se lève (1.0s)
            frame = frameLev
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Phase 3 : marche — rythme asymétrique duck.py
                // appui 0.5s + mouvement 0.15s + 0.15s = 0.8s/cycle
                let step: CGFloat = 4   // px par demi-pas

                func tick() {
                    // Appui (hésitation)
                    frame = frameLev
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        // Demi-pas 1
                        frame = marcheA
                        withAnimation(.linear(duration: 0.15)) { positionX += step }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            // Demi-pas 2
                            frame = marcheB
                            withAnimation(.linear(duration: 0.15)) { positionX += step }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                if positionX < screenWidth {
                                    tick()
                                } else {
                                    walkDone = true
                                    if authReady { onWalkComplete() }
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
