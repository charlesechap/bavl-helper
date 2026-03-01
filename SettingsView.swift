import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: AppViewModel
    @Environment(\.dismiss) var dismiss

    @State private var cardNumber: String = ""
    @State private var password: String = ""
    @State private var showAddNewspaper = false
    @State private var newName: String = ""
    @State private var newPath: String = ""
    @State private var newMode: ViewMode = .text

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                List {
                    // Identifiants
                    Section {
                        monoField("N° de carte", text: $cardNumber)
                        monoSecure("Mot de passe", text: $password)
                    } header: {
                        monoHeader("// IDENTIFIANTS")
                    }

                    // Journaux
                    Section {
                        ForEach(Array(vm.newspapers.enumerated()), id: \.element.id) { _, paper in
                            newspaperRow(paper)
                        }
                        .onDelete { vm.removeNewspaper(at: $0) }

                        Button {
                            showAddNewspaper = true
                        } label: {
                            Text("+ AJOUTER_")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .listRowBackground(Color.black)
                    } header: {
                        monoHeader("// JOURNAUX")
                    }

                    // Aide
                    Section {
                        Text("Chemin PressReader : ouvrez un journal sur pressreader.com et copiez la portion après pressreader.com/ (ex: switzerland/le-temps)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                            .listRowBackground(Color.black)
                    } header: {
                        monoHeader("// AIDE")
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.black)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("[CFG]")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") {
                        vm.cardNumber = cardNumber
                        vm.password = password
                        dismiss()
                    }
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("X") { dismiss() }
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .onAppear {
                cardNumber = vm.cardNumber
                password = vm.password
            }
            .sheet(isPresented: $showAddNewspaper) {
                addNewspaperSheet
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sous-vues helpers

    private func monoHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.white.opacity(0.5))
    }

    private func monoField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text("> ")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
            TextField(label, text: text)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.white)
                .keyboardType(.asciiCapable)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .listRowBackground(Color.white.opacity(0.05))
    }

    private func monoSecure(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text("> ")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
            SecureField(label, text: text)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.white)
        }
        .listRowBackground(Color.white.opacity(0.05))
    }

    private func newspaperRow(_ paper: Newspaper) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(paper.name.uppercased())
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white)
                Text("[\(paper.viewMode.label.uppercased())] \(paper.pressReaderPath)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            // Toggle mode
            Button {
                if let idx = vm.newspapers.firstIndex(where: { $0.id == paper.id }) {
                    vm.newspapers[idx].viewMode = paper.viewMode == .text ? .layout : .text
                    vm.saveNewspapers()
                }
            } label: {
                Text(paper.viewMode == .text ? "[TXT]" : "[PDF]")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.3)))
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(Color.black)
    }

    private var addNewspaperSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                List {
                    Section {
                        monoField("ex: Le Monde", text: $newName)
                    } header: { monoHeader("// NOM") }

                    Section {
                        monoField("ex: france/le-monde", text: $newPath)
                    } header: { monoHeader("// CHEMIN PRESSREADER") }

                    Section {
                        Picker("Mode", selection: $newMode) {
                            ForEach(ViewMode.allCases, id: \.self) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.black)
                    } header: { monoHeader("// MODE PAR DÉFAUT") }
                }
                .scrollContentBackground(.hidden)
                .background(Color.black)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("[+ JOURNAL]")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") {
                        guard !newName.isEmpty, !newPath.isEmpty else { return }
                        vm.addNewspaper(Newspaper(name: newName, pressReaderPath: newPath, viewMode: newMode))
                        newName = ""; newPath = ""
                        newMode = .text
                        showAddNewspaper = false
                    }
                    .disabled(newName.isEmpty || newPath.isEmpty)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("X") { showAddNewspaper = false }
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }
}
