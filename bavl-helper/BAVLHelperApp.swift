import SwiftUI
import BackgroundTasks

@main
struct BAVLHelper: App {
    @StateObject private var vm = AppViewModel()
    @State private var onboardingComplete: Bool = UserDefaults.standard.bool(forKey: "onboardingComplete")

    init() {
        // DEV ONLY — retirer avant TestFlight
        UserDefaults.standard.removeObject(forKey: "onboardingComplete")
        // Enregistrer le handler BGTask (doit se faire avant la fin du launch)
        // On passe vm via une closure différée car @StateObject n'est pas encore initialisé ici
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if onboardingComplete {
                    ContentView(vm: vm)
                } else {
                    OnboardingView(isComplete: $onboardingComplete, vm: vm)
                }
            }
            .onAppear {
                // Permissions notifications + enregistrement BGTask
                EditionNotifier.shared.requestAuthorization()
                EditionNotifier.registerBackgroundHandler(vm: vm)
            }
        }
    }
}
