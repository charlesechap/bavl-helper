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

                // Canard couché — sans indicateur de points, sans divider
                DuckStaticView()
                    .padding(.leading, 20)
                    .padding(.top, 52)
                    .padding(.bottom, 24)

                Group {
                    switch page {
                    case 0: pageBienvenue
                    case 1: pageCondition
                    case 2: pageSetup
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

                // Footer : masqué sur page 2 (clavier présent)
                if page != 2 {
                    VStack(spacing: 8) {
                        TerminalButton(
                            label: page == 0 ? "> C'EST PARTI_" : "> CONTINUER_",
                            enabled: buttonEnabled, action: handleAction
                        )
                        .padding(.horizontal, 16)
                        TerminalSignature()
                    }
                    .padding(.bottom, 20)
                } else {
                    // Page identifiants : bouton uniquement, pas de signature
                    TerminalButton(
                        label: "> COMMENCER_",
                        enabled: buttonEnabled, action: handleAction
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var pageBienvenue: some View {
        Text("Canard automatise l'accès à PressReader via votre carte des Bibliothèques de la Ville de Lausanne.")
            .font(.system(.title3, design: .monospaced).weight(.bold))
            .foregroundStyle(Color.termFg)
            .lineSpacing(5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pageCondition: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Cette app est réservée aux titulaires d'une carte des Bibliothèques de la Ville de Lausanne valide donnant accès à PressReader.")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Color.termDim).lineSpacing(3)
            TerminalSeparator()
            Button { confirmed.toggle() } label: {
                HStack(alignment: .top, spacing: 10) {
                    Text(confirmed ? "[✓]" : "[ ]")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(confirmed ? Color.termFg : Color.termDim)
                    Text("Je confirme être titulaire d'une carte valide.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.termDim).lineSpacing(3)
                        .multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(.plain)
            .offset(x: shake ? -6 : 0)
            .animation(shake ? .default.repeatCount(4, autoreverses: true).speed(6) : .default, value: shake)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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

    private var buttonEnabled: Bool {
        switch page {
        case 1: return confirmed
        case 2: return !cardNumber.isEmpty && !password.isEmpty
        default: return true
        }
    }

    private func handleAction() {
        switch page {
        case 0: withAnimation { page = 1 }
        case 1: confirmed ? withAnimation { page = 2 } : triggerShake()
        case 2:
            vm.cardNumber = cardNumber; vm.password = password
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
