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
                    VStack(alignment: .leading, spacing: 0) {

                        // Canard couché header
                        HStack {
                            DuckStaticView().padding(.leading, 20).padding(.top, 24)
                            Spacer()
                        }
                        .padding(.bottom, 16)

                        Divider().overlay(Color.termFaint).padding(.horizontal, 16).padding(.bottom, 20)

                        // Identifiants
                        sectionHeader("// IDENTIFIANTS")
                        VStack(spacing: 12) {
                            TerminalField(label: "N° de carte",  text: $cardNumber)
                            TerminalField(label: "Mot de passe", text: $password, secure: true)
                        }
                        .padding(.horizontal, 16).padding(.bottom, 24)

                        // Journaux
                        sectionHeader("// JOURNAUX")
                        VStack(spacing: 0) {
                            ForEach(Array(vm.newspapers.enumerated()), id: \.element.id) { i, paper in
                                newspaperRow(paper)
                                if i < vm.newspapers.count - 1 {
                                    TerminalSeparator().padding(.horizontal, 16)
                                }
                            }
                            Divider().overlay(Color.termFaint).padding(.horizontal, 16).padding(.top, 8)
                            Button { showAdd = true } label: {
                                Text("  + AJOUTER_")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(Color.termFg)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 16)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.bottom, 24)

                        // Aide
                        sectionHeader("// AIDE")
                        Text("  Chemin PressReader : ouvrez un journal sur\n  pressreader.com et copiez la portion après\n  pressreader.com/\n  ex: switzerland/le-temps")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Color.termFaint).lineSpacing(3)
                            .padding(.horizontal, 16).padding(.bottom, 24)

                        TerminalSignature()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.termBg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("[CFG]").font(.system(.body, design: .monospaced)).foregroundStyle(Color.termFg)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") {
                        let changed = cardNumber != vm.cardNumber || password != vm.password
                        vm.cardNumber = cardNumber; vm.password = password
                        dismiss()
                        if changed { vm.login() }
                    }
                    .font(.system(.body, design: .monospaced)).foregroundStyle(Color.termFg)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("X") { dismiss() }
                        .font(.system(.body, design: .monospaced)).foregroundStyle(Color.termDim)
                }
            }
            .onAppear { cardNumber = vm.cardNumber; password = vm.password }
            .sheet(isPresented: $showAdd) { addSheet }
        }
        .preferredColorScheme(.dark)
    }

    private func sectionHeader(_ t: String) -> some View {
        Text(t)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(Color.termDim)
            .padding(.horizontal, 16).padding(.bottom, 8)
    }

    private func newspaperRow(_ paper: Newspaper) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(paper.name.uppercased())
                    .font(.system(.body, design: .monospaced)).foregroundStyle(Color.termFg)
                Text("[\(paper.viewMode.label.uppercased())] \(paper.pressReaderPath)")
                    .font(.system(.caption2, design: .monospaced)).foregroundStyle(Color.termFaint)
            }
            Spacer()
            Button {
                if let idx = vm.newspapers.firstIndex(where: { $0.id == paper.id }) {
                    vm.newspapers[idx].viewMode = paper.viewMode == .text ? .layout : .text
                    vm.saveNewspapers()
                }
            } label: {
                Text(paper.viewMode == .text ? "[TXT]" : "[PDF]")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(Color.termDim)
                    .padding(4).overlay(Rectangle().stroke(Color.termFaint, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button {
                vm.newspapers.removeAll { $0.id == paper.id }
                vm.saveNewspapers()
            } label: {
                Text("[X]").font(.system(.caption, design: .monospaced)).foregroundStyle(Color.termFaint)
                    .padding(4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var addSheet: some View {
        NavigationStack {
            ZStack {
                Color.termBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        TerminalField(label: "Nom  ex: Le Monde",         text: $newName).padding(.horizontal, 16)
                        TerminalField(label: "Chemin  ex: france/le-monde", text: $newPath).padding(.horizontal, 16)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("  > Mode par défaut")
                                .font(.system(.caption2, design: .monospaced)).foregroundStyle(Color.termFaint)
                                .padding(.horizontal, 16)
                            Picker("", selection: $newMode) {
                                ForEach(ViewMode.allCases, id: \.self) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented).padding(.horizontal, 16)
                        }
                    }
                    .padding(.top, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.termBg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("[+ JOURNAL]").font(.system(.caption, design: .monospaced)).foregroundStyle(Color.termFg)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") {
                        guard !newName.isEmpty, !newPath.isEmpty else { return }
                        vm.addNewspaper(Newspaper(name: newName, pressReaderPath: newPath, viewMode: newMode))
                        newName = ""; newPath = ""; newMode = .text; showAdd = false
                    }
                    .disabled(newName.isEmpty || newPath.isEmpty)
                    .font(.system(.body, design: .monospaced)).foregroundStyle(Color.termFg)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("X") { showAdd = false }
                        .font(.system(.body, design: .monospaced)).foregroundStyle(Color.termDim)
                }
            }
        }
        .preferredColorScheme(.dark).presentationDetents([.medium])
    }
}
