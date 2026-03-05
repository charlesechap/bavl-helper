import SwiftUI
import Combine

private let dkGreen   = Color(red: 0.20, green: 0.90, blue: 0.20)
private let dkWhite   = Color(red: 1.00, green: 1.00, blue: 1.00)
private let dkYellow  = Color(red: 1.00, green: 0.90, blue: 0.10)
private let dkGray    = Color(red: 0.50, green: 0.50, blue: 0.50)

private struct S {
    let t: String; let c: Color
    init(_ t: String, _ c: Color = Color(white: 0.82)) { self.t = t; self.c = c }
}

private func duckText(_ segs: [S]) -> Text {
    segs.reduce(Text("")) { acc, s in acc + Text(s.t).foregroundColor(s.c) }
}

private let couch: [[S]] = [
    [S("               ")],
    [S("   "), S("__", dkGreen), S("        ")],
    [S("__( "), S("o", dkWhite), S(")"), S(">", dkYellow), S("      ")],
    [S("               ")],
]

private let marcheA: [[S]] = [
    [S("      "), S("__", dkGreen), S("       ")],
    [S("   __("), S("o", dkWhite), S(")"), S(">", dkYellow), S("     ")],
    [S("   \\ "), S("<_ )", dkGray), S("      ")],
    [S("    "), S("_ .", dkYellow), S("       ")],
]
private let marcheB: [[S]] = [
    [S("      "), S("__", dkGreen), S("       ")],
    [S("   __("), S("o", dkWhite), S(")"), S(">", dkYellow), S("     ")],
    [S("   \\ "), S("<_ )", dkGray), S("      ")],
    [S("    "), S(". _", dkYellow), S("       ")],
]

// MARK: - DuckHeaderView

struct DuckHeaderView: View {
    let walking:        Bool
    let authReady:      Bool
    let onWalkComplete: () -> Void

    @State private var frame:     [[S]]   = couch
    @State private var positionX: CGFloat = 0
    @State private var walkDone           = false
    @State private var started            = false

    var body: some View {
        // Utiliser UIScreen pour avoir la vraie largeur, indépendamment du GeometryReader parent
        let screenW = UIScreen.main.bounds.width

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
        .frame(width: screenW, height: 56, alignment: .topLeading)
        .clipped()
        .onChange(of: walking) { _, isWalking in
            if isWalking {
                startWalk(screenWidth: screenW)
            } else {
                started   = false
                walkDone  = false
                positionX = 0
                frame     = couch
            }
        }
        .onChange(of: authReady) { _, ready in
            if ready && walkDone { onWalkComplete() }
        }
    }

    // Walk : entre hors écran à gauche (-canardWidth ≈ -120)
    // et sort complètement à droite (screenW + 120)
    // Durée totale 3s, rythme 0.18s/cycle
    private func startWalk(screenWidth: CGFloat) {
        guard !started else { return }
        started   = true
        walkDone  = false

        let duckWidth: CGFloat = 120
        let startX    = -duckWidth
        let endX      = screenWidth + duckWidth
        positionX     = startX

        let totalDist = endX - startX          // screenWidth + 240
        let cycleTime = 0.18
        let nCycles   = 3.0 / cycleTime        // 16.67
        let step      = totalDist / CGFloat(nCycles)

        func tick() {
            frame = marcheA
            DispatchQueue.main.asyncAfter(deadline: .now() + cycleTime * 0.5) {
                frame = marcheB
                withAnimation(.linear(duration: cycleTime * 0.5)) {
                    positionX += step
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + cycleTime * 0.5) {
                    if positionX < endX {
                        tick()
                    } else {
                        positionX = 0
                        frame     = couch
                        walkDone  = true
                        if authReady { onWalkComplete() }
                    }
                }
            }
        }
        tick()
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
            ForEach(Array(couch.enumerated()), id: \.offset) { _, segs in
                duckText(segs)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1).fixedSize()
            }
        }
    }
}

#Preview {
    ZStack {
        Color.termBg.ignoresSafeArea()
        VStack(spacing: 0) {
            DuckHeaderView(walking: true, authReady: false, onWalkComplete: {})
            Divider().overlay(Color.termFaint)
            WalkLogView(log: ["Connexion BAVL..."], currentMessage: "Envoi identifiants...")
        }
    }
}
