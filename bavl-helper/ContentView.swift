import SwiftUI
import Combine

struct ContentView: View {
    @ObservedObject var vm: AppViewModel
    @State private var showSettings  = false
    @State private var selectedPaper: Newspaper? = nil
    @State private var showNewspapers = false
    @State private var animating      = false   // true pendant le walk du canard
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isIPad: Bool { hSizeClass == .regular }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.termBg.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {

                    // ── Header fixe ─────────────────────────────────────────
                    headerBar
                    Divider().overlay(Color.termFaint).padding(.horizontal)

                    // ── Canard couché — toujours présent ────────────────────
                    duckHeader

                    Divider().overlay(Color.termFaint).padding(.horizontal)
                        .padding(.top, 4)

                    // ── Contenu variable ────────────────────────────────────
                    if animating {
                        // Animation en cours → log terminal sous le canard
                        walkLogView
                    } else if showNewspapers {
                        newspaperListView
                    } else {
                        idleView
                    }

                    Spacer(minLength: 0)
                    TerminalSignature()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.termBg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Text("[CFG]")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Color.termFg)
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView(vm: vm) }
            .fullScreenCover(item: $selectedPaper) { paper in
                PressReaderSheet(newspaper: paper, vm: vm)
            }
            .onAppear {
                showNewspapers = false
                animating      = false
                vm.authReady   = false
                vm.checkExistingSession()
            }
            .onChange(of: vm.loginState) { _, state in
                switch state {
                case .loading:
                    animating      = true
                    showNewspapers = false
                case .success, .failure, .idle:
                    break   // animating reste true jusqu'à ce que le canard finisse
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header label

    private var headerBar: some View {
        HStack {
            Text("CANARD // BAVL PRESSE")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color.termFaint)
            Spacer()
            if isIPad {
                Text("[ iPad ]")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.termFaint)
            }
        }
        .padding(.horizontal).padding(.top, 6).padding(.bottom, 4)
    }

    // MARK: - Canard couché fixe

    private var duckHeader: some View {
        HStack(alignment: .bottom) {
            DuckStaticView()
                .padding(.leading, 20)
                .padding(.vertical, 12)
            Spacer()
            // Indicateur d'état discret
            Text(stateLabel)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color.termFaint)
                .padding(.trailing, 20)
                .padding(.bottom, 12)
        }
    }

    private var stateLabel: String {
        if animating           { return "[ … ]" }
        if showNewspapers      { return "[ OK ]" }
        switch vm.loginState {
        case .failure:         return "[ ERR ]"
        case .idle:            return "[ — ]"
        default:               return ""
        }
    }

    // MARK: - Vue pendant l'animation

    // Une seule instance de DuckLoadingView — évite le double démarrage
    private var walkLogView: some View {
        DuckLoadingView(
            onComplete: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    animating      = false
                    if case .success = vm.loginState { showNewspapers = true }
                }
            },
            authReady:      vm.authReady,
            log:            vm.statusLog,
            currentMessage: vm.statusMessage
        )
        .padding(.top, 8)
        .frame(maxWidth: isIPad ? 600 : .infinity)
    }

    // MARK: - Vue idle / erreur

    private var idleView: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch vm.loginState {
            case .failure(let msg):
                Text("  # [ERR] \(msg)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.termDim)
                    .padding(.horizontal)
                    .padding(.top, 16)
                TerminalButton(label: "> RÉESSAYER_") { vm.login() }
                    .padding(.horizontal)

            case .idle:
                TerminalButton(label: "> CONNEXION_") { vm.login() }
                    .padding(.horizontal)
                    .padding(.top, 16)

            default:
                EmptyView()
            }
        }
        .frame(maxWidth: isIPad ? 600 : .infinity, alignment: .leading)
    }

    // MARK: - Liste journaux

    private var newspaperListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("# [OK] session active")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color.termFaint)
                    Spacer()
                }
                .padding(.horizontal).padding(.vertical, 6)

                Divider().overlay(Color.termFaint).padding(.horizontal)

                if isIPad { iPadGrid } else { phoneList }
            }
        }
    }

    private var phoneList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(vm.newspapers.enumerated()), id: \.element.id) { i, paper in
                newspaperRow(paper: paper, index: i)
                if i < vm.newspapers.count - 1 {
                    TerminalSeparator().padding(.horizontal)
                }
            }
        }
    }

    private var iPadGrid: some View {
        let pairs = stride(from: 0, to: vm.newspapers.count, by: 2).map {
            ($0, $0 + 1 < vm.newspapers.count ? $0 + 1 : nil as Int?)
        }
        return LazyVStack(spacing: 0) {
            ForEach(pairs, id: \.0) { left, right in
                HStack(alignment: .top, spacing: 0) {
                    if let p = vm.newspapers[safe: left] {
                        newspaperRow(paper: p, index: left).frame(maxWidth: .infinity)
                    }
                    Rectangle().fill(Color.termFaint).frame(width: 1).padding(.vertical, 4)
                    if let r = right, let p = vm.newspapers[safe: r] {
                        newspaperRow(paper: p, index: r).frame(maxWidth: .infinity)
                    } else {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                if pairs.last?.0 != left { TerminalSeparator().padding(.horizontal) }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func newspaperRow(paper: Newspaper, index: Int) -> some View {
        Button {
            selectedPaper = paper
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Text(String(format: "%02d.", index + 1))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.termFaint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(paper.name.uppercased())
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color.termFg)
                    Text("[\(paper.viewMode.label.uppercased())] \(paper.pressReaderPath)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color.termFaint)
                }
                Spacer()
                Text("→")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.termDim)
            }
            .padding(.vertical, 10)
            .padding(.horizontal)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

#Preview { ContentView(vm: AppViewModel()) }
