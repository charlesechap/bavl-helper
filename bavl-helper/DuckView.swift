import SwiftUI
import Combine

private let dkGreen   = Color(red: 0.20, green: 0.90, blue: 0.20)
private let dkWhite   = Color(red: 1.00, green: 1.00, blue: 1.00)
private let dkYellow  = Color(red: 1.00, green: 0.90, blue: 0.10)
private let dkGray    = Color(red: 0.55, green: 0.55, blue: 0.55)  // tête + corps

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

// ── Frames couché ──────────────────────────────────────────────────────────
// couchOpen : oeil ouvert  "o"
// couchBlink : oeil fermé  "-"
//
//    __
// __( o)>
//
// Tête = dkGray, oeil = dkWhite (open) ou dkGray (blink), bec = dkYellow

private let couchOpen: [[S]] = [
    [S("               ")],
    [S("   "), S("__", dkGray)],
    [S("__("), S("o", dkWhite), S(")", dkGray), S(">", dkYellow)],
    [S("               ")],
]

private let couchBlink: [[S]] = [
    [S("               ")],
    [S("   "), S("__", dkGray)],
    [S("__("), S("-", dkGray), S(")", dkGray), S(">", dkYellow)],
    [S("               ")],
]

// Alias pour DuckStaticView et reset
private let couch = couchOpen

// ── Frames marche ──────────────────────────────────────────────────────────
//       __
//    __(o)>
//    \ <_ )
//     _ .      ← patte A
//
//       __
//    __(o)>
//    \ <_ )
//     . _      ← patte B

private let marcheA: [[S]] = [
    [S("      "), S("__", dkGray)],
    [S("   __("), S("o", dkWhite), S(")", dkGray), S(">", dkYellow)],
    [S("   \\", dkGray), S(" <_ )", dkGray)],
    [S("    "), S("_ .", dkYellow)],
]

private let marcheB: [[S]] = [
    [S("      "), S("__", dkGray)],
    [S("   __("), S("o", dkWhite), S(")", dkGray), S(">", dkYellow)],
    [S("   \\", dkGray), S(" <_ )", dkGray)],
    [S("    "), S(". _", dkYellow)],
]

// MARK: - DuckHeaderView

struct DuckHeaderView: View {
    let walking:        Bool
    let authReady:      Bool
    let onWalkComplete: () -> Void

    @State private var frame:     [[S]]   = couchOpen
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
                    frame     = couchOpen
                    startBlink()
                }
            }
            .onChange(of: authReady) { _, ready in
                if ready && walkDone { onWalkComplete() }
            }
        }
        .frame(height: 60)
        .clipped()
        .onAppear { startBlink() }
        .onDisappear { stopBlink() }
    }

    // ── Clignement toutes les 2s ─────────────────────────────────────────
    private func startBlink() {
        stopBlink()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            guard !started else { return }   // pas de clignotement pendant la marche
            frame = couchBlink
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                frame = couchOpen
            }
        }
    }

    private func stopBlink() {
        blinkTimer?.invalidate()
        blinkTimer = nil
    }

    // ── Marche ───────────────────────────────────────────────────────────
    // Séquence : pause couché 0.6s → marche de x=0 jusqu'à x=screenWidth+150
    private func startWalk(screenWidth: CGFloat) {
        guard !started else { return }
        started   = true
        walkDone  = false
        frame     = couchOpen
        positionX = 0

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let duckW: CGFloat    = 150
            let endX              = screenWidth + duckW
            let totalDist         = endX          // de 0 → endX
            let cycleTime: Double = 0.18
            let nCycles           = 3.0 / cycleTime
            let step              = totalDist / CGFloat(nCycles)

            func tick() {
                frame = marcheA
                DispatchQueue.main.asyncAfter(deadline: .now() + cycleTime * 0.5) {
                    frame = marcheB
                    withAnimation(.linear(duration: cycleTime * 0.4)) {
                        positionX += step
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + cycleTime * 0.5) {
                        if positionX < endX {
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

typealias DuckStaticView = _DuckStaticView
struct _DuckStaticView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(couchOpen.enumerated()), id: \.offset) { _, segs in
                duckLine(segs)
            }
        }
    }
}
