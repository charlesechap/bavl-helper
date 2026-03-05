import SwiftUI
import Combine

// MARK: - ContentView

struct ContentView: View {
    @ObservedObject var vm: AppViewModel
    @State private var showSettings   = false
    @State private var selectedPaper: Newspaper? = nil
    @State private var showNewspapers = false
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isIPad: Bool { hSizeClass == .regular }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.termBg.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    headerBar
                    Divider().overlay(Color.termFaint).padding(.horizontal)

                    switch vm.loginState {
                    case .loading:
                        centeredContent {
                            DuckLoadingView(
                                onComplete: { withAnimation(.easeInOut(duration: 0.35)) { showNewspapers = true } },
                                authReady: vm.authReady,
                                log: vm.statusLog,
                                currentMessage: vm.statusMessage
                            )
                        }

                    case .success:
                        if showNewspapers {
                            newspaperListView
                        } else {
                            // Auth OK mais canard pas fini — on garde l'animation
                            centeredContent {
                                DuckLoadingView(
                                    onComplete: { withAnimation(.easeInOut(duration: 0.35)) { showNewspapers = true } },
                                    authReady: vm.authReady,
                                    log: vm.statusLog,
                                    currentMessage: vm.statusMessage
                                )
                            }
                        }

                    case .failure(let msg):
                        centeredContent {
                            VStack(alignment: .leading, spacing: 12) {
                                TerminalFrame(title: "ERREUR") {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("  \(msg)")
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(Color.termDim)
                                            .padding(.vertical, 8)
                                    }
                                }
                                TerminalButton(label: "> RÉESSAYER_") { vm.login() }
                            }
                            .padding(.horizontal)
                            .padding(.top, 24)
                        }

                    case .idle:
                        centeredContent {
                            VStack(alignment: .leading, spacing: 0) {
                                TerminalButton(label: "> CONNEXION_") { vm.login() }
                                    .padding(.horizontal)
                                    .padding(.top, 24)
                            }
                        }
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
            .fullScreenCover(item: $selectedPaper) { PressReaderSheet(newspaper: $0) }
            .onAppear {
                showNewspapers = false
                vm.authReady   = false
                vm.checkExistingSession()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

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
        .padding(.horizontal)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    // MARK: - Liste journaux

    private var newspaperListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Status ligne
                HStack {
                    Text("# [OK] session active")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color.termFaint)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)

                Divider().overlay(Color.termFaint).padding(.horizontal)

                if isIPad {
                    iPadGrid
                } else {
                    phoneList
                }
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
        let pairs = stride(from: 0, to: vm.newspapers.count, by: 2).map { i in
            (i, i + 1 < vm.newspapers.count ? i + 1 : nil as Int?)
        }
        return LazyVStack(spacing: 0) {
            ForEach(pairs, id: \.0) { left, right in
                HStack(alignment: .top, spacing: 0) {
                    if let p = vm.newspapers[safe: left] { newspaperRow(paper: p, index: left).frame(maxWidth: .infinity) }
                    Rectangle().fill(Color.termFaint).frame(width: 1).padding(.vertical, 4)
                    if let r = right, let p = vm.newspapers[safe: r] { newspaperRow(paper: p, index: r).frame(maxWidth: .infinity) }
                    else { Color.clear.frame(maxWidth: .infinity) }
                }
                if pairs.last?.0 != left { TerminalSeparator().padding(.horizontal) }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func newspaperRow(paper: Newspaper, index: Int) -> some View {
        if paper.resolvedURL != nil {
            Button { selectedPaper = paper } label: {
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

    // MARK: - Helpers

    @ViewBuilder
    private func centeredContent<C: View>(@ViewBuilder content: () -> C) -> some View {
        HStack {
            Spacer(minLength: 0)
            content().frame(maxWidth: isIPad ? 600 : .infinity)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

#Preview("iPhone") { ContentView(vm: AppViewModel()) }
#Preview("iPad") { ContentView(vm: AppViewModel()) }
