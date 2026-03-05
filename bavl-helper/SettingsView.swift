import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: AppViewModel
    @Environment(\.dismiss) var dismiss

    @State private var cardNumber = ""
    @State private var password   = ""
    @State private var showAdd    = false
    @State private var newName    = ""
    @State private var newPath    = ""
    @State private var newMode: ViewMode = .text

    var body: some View {
        NavigationStack {
            ZStack {
                Color.termBg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        // Identifiants
                        TerminalFrame(title: "IDENTIFIANTS") {
                            VStack(alignment: .leading, spacing: 12) {
                                TerminalField(label: "N° de carte",  text: $cardNumber, secure: false)
                                TerminalField(label: "Mot de passe", text: $password,   secure: true)
                            }
                            .padding(12)
                        }

                        // Journaux
                        TerminalFrame(title: "JOURNAUX") {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(vm.newspapers.enumerated()), id: \.element.id) { i, paper in
                                    newspaperRow(paper)
                                    if i < vm.newspapers.count - 1 {
                                        TerminalSeparator().padding(.horizontal, 12)
                                    }
                                }

                                TerminalSeparator().padding(.horizontal, 12)

                                Button {
                                    showAdd = true
                                } label: {
                                    Text("+ AJOUTER_")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(Color.termFg)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                        }

                        // Aide
                        TerminalFrame(title: "AIDE") {
                            Text("  Chemin PressReader : ouvrez un journal sur pressreader.com et copiez la portion après pressreader.com/\n  ex: switzerland/le-temps")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Color.termFaint)
                                .lineSpacing(3)
                                .padding(12)
                        }

                        TerminalSignature()
                    }
                    .padding(16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.termBg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("[CFG]")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color.termFg)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") {
                        let changed = cardNumber != vm.cardNumber || password != vm.password
                        vm.cardNumber = cardNumber
                        vm.password   = password
                        dismiss()
                        if changed { vm.login() }
                    }
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.termFg)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("X") { dismiss() }
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color.termDim)
                }
            }
            .onAppear {
                cardNumber = vm.cardNumber
                password   = vm.password
            }
            .sheet(isPresented: $showAdd) { addSheet }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Rangée journal

    private func newspaperRow(_ paper: Newspaper) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(paper.name.uppercased())
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.termFg)
                Text("[\(paper.viewMode.label.uppercased())] \(paper.pressReaderPath)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.termFaint)
            }
            Spacer()
            // Toggle TXT/PDF
            Button {
                if let idx = vm.newspapers.firstIndex(where: { $0.id == paper.id }) {
                    vm.newspapers[idx].viewMode = paper.viewMode == .text ? .layout : .text
                    vm.saveNewspapers()
                }
            } label: {
                Text(paper.viewMode == .text ? "[TXT]" : "[PDF]")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.termDim)
                    .padding(4)
                    .overlay(Rectangle().stroke(Color.termFaint, lineWidth: 1))
            }
            .buttonStyle(.plain)

            // Supprimer
            Button {
                if let idx = vm.newspapers.firstIndex(where: { $0.id == paper.id }) {
                    vm.newspapers.remove(at: idx)
                    vm.saveNewspapers()
                }
            } label: {
                Text("[X]")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.termFaint)
                    .padding(4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Sheet ajout journal

    private var addSheet: some View {
        NavigationStack {
            ZStack {
                Color.termBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        TerminalFrame(title: "NOM") {
                            TerminalField(label: "ex: Le Monde", text: $newName).padding(12)
                        }
                        TerminalFrame(title: "CHEMIN PRESSREADER") {
                            TerminalField(label: "ex: france/le-monde", text: $newPath).padding(12)
                        }
                        TerminalFrame(title: "MODE PAR DÉFAUT") {
                            Picker("", selection: $newMode) {
                                ForEach(ViewMode.allCases, id: \.self) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .padding(12)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.termBg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("[+ JOURNAL]")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.termFg)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") {
                        guard !newName.isEmpty, !newPath.isEmpty else { return }
                        vm.addNewspaper(Newspaper(name: newName, pressReaderPath: newPath, viewMode: newMode))
                        newName = ""; newPath = ""; newMode = .text
                        showAdd = false
                    }
                    .disabled(newName.isEmpty || newPath.isEmpty)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.termFg)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("X") { showAdd = false }
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color.termDim)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }
}
