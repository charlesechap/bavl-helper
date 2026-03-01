import SwiftUI
import Combine

// MARK: - Palette
private extension Color {
    static let bg      = Color(red: 0.13, green: 0.13, blue: 0.13)
    static let fg      = Color(red: 0.80, green: 0.80, blue: 0.80)
    static let fgDim   = Color(red: 0.50, green: 0.50, blue: 0.50)
    static let fgFaint = Color(red: 0.30, green: 0.30, blue: 0.30)
}

// MARK: - ASCII Log View

struct ASCIISpinnerView: View {
    let log: [String]
    let currentMessage: String
    private let frames = ["|", "/", "─", "\\"]
    @State private var idx = 0
    private let timer = Timer.publish(every: 0.12, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(log.dropLast(), id: \.self) { line in
                Text("  ✓ \(line)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.fgDim)
            }
            if !currentMessage.isEmpty {
                HStack(spacing: 6) {
                    Text(frames[idx])
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color.fg)
                        .onReceive(timer) { _ in idx = (idx + 1) % frames.count }
                    Text(currentMessage)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.fg)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var vm = AppViewModel()
    @State private var showSettings = false
    @State private var selectedNewspaper: Newspaper? = nil
    @Environment(\.horizontalSizeClass) private var hSizeClass

    private var isIPad: Bool { hSizeClass == .regular }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack {
                        Text("BAVL // PRESSE")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Color.fgFaint)
                        Spacer()
                        if isIPad {
                            Text("[ iPad ]")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Color.fgFaint)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 6)
                    .padding(.bottom, 4)

                    Divider().overlay(Color.fgFaint).padding(.horizontal)

                    // Contenu principal
                    if case .loading = vm.loginState {
                        centeredContent {
                            ASCIISpinnerView(log: vm.statusLog, currentMessage: vm.statusMessage)
                        }
                    } else if case .success = vm.loginState {
                        if isIPad {
                            iPadNewspaperView
                        } else {
                            newspaperListView
                        }
                    } else {
                        centeredContent {
                            statusView.padding(.horizontal)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Text("[CFG]")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Color.fg)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(vm: vm)
            }
            .sheet(item: $selectedNewspaper) { paper in
                PressReaderSheet(newspaper: paper)
            }
            .onAppear {
                if vm.cardNumber.isEmpty || vm.password.isEmpty {
                    showSettings = true
                } else {
                    vm.checkExistingSession()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // Centrage avec largeur max pour iPad
    @ViewBuilder
    private func centeredContent<C: View>(@ViewBuilder content: () -> C) -> some View {
        HStack {
            Spacer(minLength: 0)
            content()
                .frame(maxWidth: isIPad ? 600 : .infinity)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Status (idle / erreur)

    @ViewBuilder
    private var statusView: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch vm.loginState {
            case .idle:
                Button(action: { vm.login() }) {
                    Text("> CONNEXION_")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color.fg)
                }
            case .failure(let msg):
                Text("# [ERR] \(msg)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.fgDim)
                Button(action: { vm.login() }) {
                    Text("> RÉESSAYER_")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.fg)
                }
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Liste iPhone (colonne unique)

    private var newspaperListView: some View {
        ScrollView {
            sessionHeader
            Divider().overlay(Color.fgFaint).padding(.horizontal)
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(vm.newspapers.enumerated()), id: \.element.id) { i, paper in
                    newspaperRow(paper: paper, index: i)
                    if i < vm.newspapers.count - 1 {
                        separatorLine.padding(.horizontal)
                    }
                }
            }
        }
    }

    // MARK: - Liste iPad (deux colonnes)

    private var iPadNewspaperView: some View {
        ScrollView {
            sessionHeader.padding(.horizontal)
            Divider().overlay(Color.fgFaint).padding(.horizontal)

            // Deux colonnes côte à côte
            let pairs = stride(from: 0, to: vm.newspapers.count, by: 2).map { i in
                (i, i + 1 < vm.newspapers.count ? i + 1 : nil as Int?)
            }

            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(pairs, id: \.0) { left, right in
                    HStack(alignment: .top, spacing: 0) {
                        // Colonne gauche
                        if let paper = vm.newspapers[safe: left] {
                            newspaperRow(paper: paper, index: left)
                                .frame(maxWidth: .infinity)
                        }

                        // Séparateur vertical
                        Rectangle()
                            .fill(Color.fgFaint)
                            .frame(width: 1)
                            .padding(.vertical, 4)

                        // Colonne droite
                        if let idx = right, let paper = vm.newspapers[safe: idx] {
                            newspaperRow(paper: paper, index: idx)
                                .frame(maxWidth: .infinity)
                        } else {
                            // Cellule vide pour équilibrer
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }

                    if pairs.last?.0 != left {
                        separatorLine.padding(.horizontal)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Composants partagés

    private var sessionHeader: some View {
        HStack {
            Text("# [OK] session active")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color.fgFaint)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var separatorLine: some View {
        Text("· · · · · · · · · · · · · · · · · · · ·")
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(Color.fgFaint)
    }

    @ViewBuilder
    private func newspaperRow(paper: Newspaper, index: Int) -> some View {
        if paper.resolvedURL != nil {
            Button {
                selectedNewspaper = paper
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Text("\(String(format: "%02d", index + 1)).")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color.fgFaint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(paper.name.uppercased())
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(Color.fg)
                        Text("[\(paper.viewMode.label.uppercased())] \(paper.pressReaderPath)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Color.fgFaint)
                    }
                    Spacer()
                    Text("→")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color.fgDim)
                }
                .padding(.vertical, 10)
                .padding(.horizontal)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Previews

#Preview("iPhone — Log connexion") {
    ZStack {
        Color.bg.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("BAVL // PRESSE")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.fgFaint)
                Spacer()
            }
            .padding(.horizontal).padding(.top, 6).padding(.bottom, 4)
            ASCIISpinnerView(
                log: [
                    "Connexion au portail BAVL...",
                    "Formulaire détecté — saisie des identifiants...",
                    "Envoi des identifiants..."
                ],
                currentMessage: "Auth réussie — ouverture PressReader..."
            )
        }
    }
}

#Preview("iPad — deux colonnes") {
    ContentView()
}


