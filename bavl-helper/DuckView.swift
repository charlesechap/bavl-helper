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

// iOS 26 : Text + Text deprecated → HStack de Text
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

// frame_couch
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
    [S("   "), S("\\", Color(white: 0.82)), S(" "), S("<_ )", dkGray)],
    [S("    "), S("_ .", dkYellow)],
]

// marche_B — patte arrière ". _"
private let marcheB: [[S]] = [
    [S("      "), S("__", dkGreen), S("       ")],
    [S("   __("), S("o", dkWhite), S(")"), S(">", dkYellow), S("     ")],
    [S("   "), S("\\", Color(white: 0.82)), S(" "), S("<_ )", dkGray)],
    [S("    "), S(". _", dkYellow)],
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
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(frame.enumerated()), id: \.offset) { _, segs in
                        duckLine(segs)
                    }
                }
                .offset(x: positionX)
            }
            .clipped()
            .onChange(of: walking) { _, isWalking in
                if isWalking {
                    startWalk(screenWidth: geo.size.width)
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
        .frame(height: 60)
    }

    private func startWalk(screenWidth: CGFloat) {
        guard !started else { return }
        started   = true
        walkDone  = false

        let duckW: CGFloat = 120
        positionX = -duckW

        let endX      = screenWidth + duckW
        let totalDist = endX + duckW             // screenWidth + 240
        let cycleTime: Double = 0.18
        let nCycles   = 3.0 / cycleTime          // 16.67
        let step      = totalDist / CGFloat(nCycles)

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
                duckLine(segs)
            }
        }
    }
}
