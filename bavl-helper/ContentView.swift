import SwiftUI
import Combine
import WebKit

struct ContentView: View {
    @ObservedObject var vm: AppViewModel
    @State private var showSettings    = false
    @State private var selectedPaper:  Newspaper? = nil
    @State private var selectedPreload: WKWebView? = nil   // capturé au tap
    @State private var showNewspapers  = false
    @State private var walking         = false
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isIPad: Bool { hSizeClass == .regular }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.termBg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 0) {
                    headerBar
                    Divider().overlay(Color.termFaint).padding(.horizontal)

                    if showNewspapers {
                        // ── Liste journaux : pas de canard ───────────────────
                        newspaperListView
                    } else {
                        // ── Écran login / chargement / idle ──────────────────
                        // Canard + contenu sous lui
                        HStack(alignment: .bottom) {
                            DuckHeaderView(
                                walking:        walking,
                                authReady:      vm.authReady,
                                onWalkComplete: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        walking        = false
                                        showNewspapers = true
                                    }
                                }
                            )
                            .padding(.leading, 20)
                            .padding(.vertical, 12)
                            Spacer()
                            Text(stateLabel)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Color.termFaint)
                                .padding(.trailing, 20)
                                .padding(.bottom, 12)
                        }

                        if walking {
                            WalkLogView(
                                log:            vm.statusLog,
                                currentMessage: vm.statusMessage
                            )
                            .frame(maxWidth: isIPad ? 600 : .infinity)
                        } else {
                            idleView
                        }

                        Spacer(minLength: 0)
                        TerminalSignature()
                    }
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
                PressReaderSheet(newspaper: paper, preloadedWebView: selectedPreload, vm: vm)
            }
            .onAppear {
                showNewspapers = false
                walking        = false
                vm.authReady   = false
                vm.checkExistingSession()
            }
            // Login en cours → animation
            .onChange(of: vm.loginState) { _, state in
                if case .loading = state {
                    walking        = true
                    showNewspapers = false
                }
                if case .failure = state {
                    walking = false
                }
            }

        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Indicateur (visible seulement pendant le chargement)

    private var stateLabel: String {
        if walking { return "[ … ]" }
        switch vm.loginState {
        case .failure: return "[ ERR ]"
        case .idle:    return "[ — ]"
        default:       return ""
        }
    }

    // MARK: - Header titre

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

    // MARK: - Liste journaux (sans canard)

    private var newspaperListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("# [OK] session active")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color.termFaint)
                    Spacer()
                    // Bouton settings discret dans la liste aussi
                }
                .padding(.horizontal).padding(.vertical, 6)
                Divider().overlay(Color.termFaint).padding(.horizontal)
                if isIPad { iPadGrid } else { phoneList }
                Spacer(minLength: 20)
                TerminalSignature()
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
            selectedPreload = vm.consumePreloaded(for: paper.pressReaderPath)
            selectedPaper   = paper
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
