import SwiftUI

@main
struct BAVLHelper: App {
    @StateObject private var vm = AppViewModel()
    @State private var onboardingComplete: Bool = UserDefaults.standard.bool(forKey: "onboardingComplete")

    var body: some Scene {
        WindowGroup {
            if onboardingComplete {
                ContentView(vm: vm)
            } else {
                OnboardingView(isComplete: $onboardingComplete, vm: vm)
            }
        }
    }
}
