import SwiftUI

// MARK: - Palette
private extension Color {
    static let bg      = Color(red: 0.13, green: 0.13, blue: 0.13)
    static let fg      = Color(red: 0.80, green: 0.80, blue: 0.80)
    static let fgDim   = Color(red: 0.50, green: 0.50, blue: 0.50)
    static let fgFaint = Color(red: 0.30, green: 0.30, blue: 0.30)
}

// MARK: - Canard ASCII statique

struct DuckStaticView: View {
    private let lines = [
        "      __     ",
        "   __( o)>   ",
        "   \\ <_ )    ",
        "    `--'     ",
        "     |       "
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.fg)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

// MARK: - OnboardingView

struct OnboardingView: View {
    @Binding var isComplete: Bool
    @ObservedObject var vm: AppViewModel

    @State private var page: Int = 0
    @State private var confirmed: Bool = false
    @State private var cardNumber: String = ""
    @State private var password: String = ""
    @State private var shake: Bool = false

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // Canard ASCII en haut à gauche + indicateur de page
                HStack(alignment: .bottom) {
                    DuckStaticView()
                        .padding(.leading, 32)
                        .padding(.top, 48)
                    Spacer()
                    pageIndicator
                        .padding(.trailing, 32)
                        .padding(.top, 48)
                }
                .padding(.bottom, 24)

                Divider().overlay(Color.fgFaint).padding(.horizontal, 32)
                    .padding(.bottom, 32)

                // Contenu par page
                Group {
                    switch page {
                    case 0: pageBienvenue
                    case 1: pageCondition
                    case 2: pageSetup
                    default: EmptyView()
                    }
                }
                .frame(maxWidth: 360)
                .padding(.horizontal, 32)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .id(page)

                Spacer()

                actionButton
                    .padding(.horizontal, 32)
                    .padding(.bottom, 48)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.3), value: page)
    }

    // MARK: - Indicateur de page

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { i in
                Text(i == page ? "●" : "○")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(i == page ? Color.fg : Color.fgFaint)
            }
        }
    }

    // MARK: - Page 1 : Bienvenue

    private var pageBienvenue: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Vos journaux BAVL,\nsans friction.")
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.fg)
                .lineSpacing(4)

            Divider().overlay(Color.fgFaint)

            Text("Canard automatise l'accès à PressReader via votre carte de bibliothèque BAVL. Ouvrez vos journaux en un tap.")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.fgFaint)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Page 2 : Condition

    private var pageCondition: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("// UNE SEULE\n   CONDITION")
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.fg)
                .lineSpacing(2)

            Divider().overlay(Color.fgFaint)

            Text("Canard est réservé aux titulaires d'une carte de bibliothèque valide donnant accès à PressReader.")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Color.fgDim)
                .lineSpacing(4)

            Button {
                confirmed.toggle()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text(confirmed ? "[✓]" : "[ ]")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(confirmed ? Color.fg : Color.fgDim)
                    Text("Je confirme être titulaire d'une carte BAVL active.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.fgDim)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(.plain)
            .offset(x: shake ? -6 : 0)
            .animation(shake ? .default.repeatCount(4, autoreverses: true).speed(6) : .default, value: shake)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Page 3 : Setup

    private var pageSetup: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("// VOS\n   IDENTIFIANTS")
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.fg)
                .lineSpacing(2)

            Divider().overlay(Color.fgFaint)

            VStack(alignment: .leading, spacing: 12) {
                monoField(label: "N° de carte", text: $cardNumber, secure: false)
                monoField(label: "Mot de passe", text: $password, secure: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Stockage sécurisé sur votre appareil.")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.fgFaint)
                Text("Aucune donnée transmise à des tiers.")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.fgFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Champ mono

    @ViewBuilder
    private func monoField(label: String, text: Binding<String>, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("> \(label)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color.fgFaint)
            if secure {
                SecureField("", text: text)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.fg)
                    .tint(Color.fg)
                    .padding(8)
                    .background(Color.white.opacity(0.05))
                    .overlay(Rectangle().stroke(Color.fgFaint, lineWidth: 1))
            } else {
                TextField("", text: text)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.fg)
                    .tint(Color.fg)
                    .keyboardType(.asciiCapable)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(8)
                    .background(Color.white.opacity(0.05))
                    .overlay(Rectangle().stroke(Color.fgFaint, lineWidth: 1))
            }
        }
    }

    // MARK: - Bouton action

    private var actionButton: some View {
        VStack(spacing: 12) {
            Button {
                handleAction()
            } label: {
                HStack {
                    Spacer()
                    Text(page == 2 ? "> COMMENCER_" : "> CONTINUER_")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(buttonEnabled ? Color.fg : Color.fgFaint)
                    Spacer()
                }
                .padding(.vertical, 14)
                .overlay(Rectangle().stroke(buttonEnabled ? Color.fgDim : Color.fgFaint, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!buttonEnabled)

            if page >= 1 {
                Text("Application non officielle — non affiliée à BAVL ou PressReader")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.fgFaint)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var buttonEnabled: Bool {
        switch page {
        case 1: return confirmed
        case 2: return !cardNumber.isEmpty && !password.isEmpty
        default: return true
        }
    }

    // MARK: - Actions

    private func handleAction() {
        switch page {
        case 0: withAnimation { page = 1 }
        case 1:
            if confirmed { withAnimation { page = 2 } }
            else { triggerShake() }
        case 2:
            vm.cardNumber = cardNumber
            vm.password = password
            UserDefaults.standard.set(true, forKey: "onboardingComplete")
            isComplete = true
        default: break
        }
    }

    private func triggerShake() {
        shake = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { shake = false }
    }
}

#Preview {
    OnboardingView(isComplete: .constant(false), vm: AppViewModel())
}
