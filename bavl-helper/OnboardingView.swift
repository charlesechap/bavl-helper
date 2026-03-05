import SwiftUI

struct OnboardingView: View {
    @Binding var isComplete: Bool
    @ObservedObject var vm: AppViewModel

    @State private var page: Int = 0
    @State private var confirmed = false
    @State private var cardNumber = ""
    @State private var password = ""
    @State private var shake = false

    var body: some View {
        ZStack {
            Color.termBg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {

                DuckStaticView()
                    .padding(.leading, 20)
                    .padding(.top, 52)
                    .padding(.bottom, 20)

                Group {
                    switch page {
                    case 0: pageAccueil
                    case 1: pageSetup
                    default: EmptyView()
                    }
                }
                .padding(.horizontal, 24)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
                .id(page)
                .animation(.easeInOut(duration: 0.25), value: page)

                Spacer()

                if page == 0 {
                    VStack(spacing: 8) {
                        TerminalButton(
                            label: "> C'EST PARTI_",
                            enabled: confirmed, action: handleAction
                        )
                        .padding(.horizontal, 16)
                        TerminalSignature()
                    }
                    .padding(.bottom, 20)
                } else {
                    TerminalButton(
                        label: "> COMMENCER_",
                        enabled: !cardNumber.isEmpty && !password.isEmpty,
                        action: handleAction
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Page 0 : accueil + confirmation fusionnés

    private var pageAccueil: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Canard automatise l'accès à PressReader via votre carte des Bibliothèques de la Ville de Lausanne.")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(Color.termFg)
                .lineSpacing(4)

            TerminalSeparator()

            Text("Cette app est réservée aux titulaires d'une carte valide donnant accès à PressReader.")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color.termDim)
                .lineSpacing(3)

            Button { confirmed.toggle() } label: {
                HStack(alignment: .top, spacing: 10) {
                    Text(confirmed ? "[✓]" : "[ ]")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(confirmed ? Color.termFg : Color.termDim)
                    Text("Je confirme être titulaire d'une carte valide.")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color.termDim)
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

    // MARK: - Page 1 : identifiants

    private var pageSetup: some View {
        VStack(alignment: .leading, spacing: 14) {
            TerminalField(label: "N° de carte",  text: $cardNumber)
            TerminalField(label: "Mot de passe", text: $password, secure: true)
            TerminalSeparator()
            VStack(alignment: .leading, spacing: 3) {
                Text("  Stockage sécurisé sur votre appareil.")
                    .font(.system(.caption2, design: .monospaced)).foregroundStyle(Color.termFaint)
                Text("  Aucune donnée transmise à des tiers.")
                    .font(.system(.caption2, design: .monospaced)).foregroundStyle(Color.termFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func handleAction() {
        switch page {
        case 0:
            if confirmed { withAnimation { page = 1 } } else { triggerShake() }
        case 1:
            vm.cardNumber = cardNumber
            vm.password   = password
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

#Preview { OnboardingView(isComplete: .constant(false), vm: AppViewModel()) }
