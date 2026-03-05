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

                // Canard couché + indicateur
                HStack(alignment: .bottom) {
                    DuckStaticView()
                        .padding(.leading, 20)
                        .padding(.top, 52)
                    Spacer()
                    pageIndicator
                        .padding(.trailing, 20)
                        .padding(.top, 52)
                }
                .padding(.bottom, 20)

                Divider().overlay(Color.termFaint).padding(.horizontal, 16).padding(.bottom, 24)

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

                VStack(spacing: 8) {
                    TerminalButton(
                        label: page == 2 ? "> COMMENCER_" : "> CONTINUER_",
                        enabled: buttonEnabled, action: handleAction
                    )
                    .padding(.horizontal, 16)
                    TerminalSignature()
                }
                .padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Text(i == page ? "●" : "○")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(i == page ? Color.termFg : Color.termFaint)
            }
        }
    }

    private var pageBienvenue: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Vos journaux BAVL,\nsans friction.")
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.termFg).lineSpacing(3)
            TerminalSeparator()
            Text("Canard automatise l'accès à PressReader via votre carte de bibliothèque BAVL. Ouvrez vos journaux en un tap.")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.termFaint).lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pageCondition: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Cette app est réservée aux\ntitulaires d'une carte de\nbibliothèque valide donnant\naccès à PressReader.")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Color.termDim).lineSpacing(3)
            TerminalSeparator()
            Button { confirmed.toggle() } label: {
                HStack(alignment: .top, spacing: 10) {
                    Text(confirmed ? "[✓]" : "[ ]")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(confirmed ? Color.termFg : Color.termDim)
                    Text("Je confirme être titulaire\nd'une carte BAVL active.")
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
