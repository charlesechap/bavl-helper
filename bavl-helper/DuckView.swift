import SwiftUI
import Combine

// MARK: - Couleurs canard (fidèles au script Python duck.py)
private let dkGreen   = Color(red: 0.20, green: 0.90, blue: 0.20)
private let dkWhite   = Color(red: 1.00, green: 1.00, blue: 1.00)
private let dkYellow  = Color(red: 1.00, green: 0.90, blue: 0.10)
private let dkGray    = Color(red: 0.50, green: 0.50, blue: 0.50)

// MARK: - Segment coloré

private struct S {
    let t: String; let c: Color
    init(_ t: String, _ c: Color = Color(white: 0.82)) { self.t = t; self.c = c }
}

private func duckText(_ segs: [S]) -> Text {
    segs.reduce(Text("")) { acc, s in acc + Text(s.t).foregroundColor(s.c) }
}

// MARK: - Frames

// frame_couch — couché, position de départ (x = 0)
private let couch: [[S]] = [
    [S("               ")],
    [S("   "), S("__", dkGreen), S("        ")],
    [S("__( "), S("o", dkWhite), S(")"), S(">", dkYellow), S("      ")],
    [S("               ")],
]

// marche_A / marche_B — alternance pattes
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
//
// Canard UNIQUE affiché en haut de ContentView et Settings.
// Quand `walking` est true : le canard traverse l'écran de gauche à droite (3s)
// puis revient au repos à gauche. `onWalkComplete` est appelé quand la traversée
// se termine ET que `authReady` est true.

struct DuckHeaderView: View {
    let walking:       Bool          // piloté par ContentView
    let authReady:     Bool          // piloté par vm.authReady
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
            .onChange(of: walking) { _, isWalking in
                if isWalking {
                    startWalk(screenWidth: geo.size.width)
                } else {
                    // Reset pour la prochaine fois
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
        .frame(height: 56)
    }

    // MARK: - Walk 3 secondes, rythme 0.18s
    private func startWalk(screenWidth: CGFloat) {
        guard !started else { return }
        started   = true
        walkDone  = false
        positionX = -screenWidth   // démarre hors écran à gauche

        let totalDist = screenWidth + screenWidth + 40   // traverse tout l'écran
        let cycleTime = 0.18
        let step      = totalDist / (3.0 / cycleTime)

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
                        // Revenir au repos à gauche sans animation
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
// Juste le log terminal (plus de canard ici — il est dans le header)

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

// Alias rétrocompatibilité — utilisé dans OnboardingView
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
                .padding(.horizontal, 20).padding(.vertical, 12)
            Divider().overlay(Color.termFaint)
            WalkLogView(log: ["Connexion BAVL...", "Formulaire..."],
                        currentMessage: "Envoi identifiants...")
        }
    }
}
