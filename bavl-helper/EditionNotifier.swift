import Foundation
import Combine
import UserNotifications
import BackgroundTasks

// MARK: - EditionNotifier
//
// Responsabilités :
//   1. Stocker la dernière édition connue par journal (UserDefaults)
//   2. Comparer avec les éditions fraîches → déclencher une notif locale si nouvelle
//   3. Enregistrer + exécuter un BGAppRefreshTask pour le check background
//
// Utilisation :
//   - Au lancement : EditionNotifier.shared.requestAuthorization()
//   - Après fetchCalendar : EditionNotifier.shared.checkAndNotify(editions:for:)
//   - Dans BAVLHelperApp : enregistrer le handler BGTask

@MainActor
final class EditionNotifier: ObservableObject {

    static let shared = EditionNotifier()
    static let bgTaskIdentifier = "ch.bavl.canard.edition-refresh"

    // État des permissions (pour afficher un bouton "Activer les notifications" si refusé)
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let defaults = UserDefaults.standard
    private let lastEditionKey = "EditionNotifier.lastEditionDate"  // dict [pressReaderPath: dateStr]

    private init() {}

    // MARK: - Autorisation

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in
                self.refreshStatus()
                if granted { self.scheduleBackgroundRefresh() }
            }
        }
    }

    func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in self.authorizationStatus = settings.authorizationStatus }
        }
    }

    // MARK: - Check & notify

    /// Appelé dès que fetchCalendar retourne des éditions.
    /// editions : triées par date décroissante (la plus récente en [0])
    func checkAndNotify(editions: [PressReaderEdition], for newspaper: Newspaper) {
        guard let latest = editions.first else { return }
        let knownDate = lastKnownDate(for: newspaper.pressReaderPath)

        // Première fois : enregistrer sans notifier
        if knownDate == nil {
            save(date: latest.date, for: newspaper.pressReaderPath)
            return
        }

        guard let known = knownDate, latest.date > known else { return }

        // Nouvelle édition détectée
        save(date: latest.date, for: newspaper.pressReaderPath)
        sendNotification(for: newspaper, editionDate: latest.date)
    }

    // MARK: - Notification locale

    private func sendNotification(for newspaper: Newspaper, editionDate: String) {
        let content = UNMutableNotificationContent()
        content.title = newspaper.name
        content.body  = "Nouvelle édition disponible · \(formattedDate(editionDate))"
        content.sound = .default

        // Deep link : ouvre directement la sheet du journal
        content.userInfo = [
            "pressReaderPath": newspaper.pressReaderPath,
            "editionDate": editionDate
        ]

        let request = UNNotificationRequest(
            identifier: "edition-\(newspaper.pressReaderPath)-\(editionDate)",
            content: content,
            trigger: nil  // immédiat
        )
        UNUserNotificationCenter.current().add(request) { err in
            if let err { print("BAVL notif error:", err) }
            else { print("BAVL notif envoyée:", newspaper.name, editionDate) }
        }
    }

    // MARK: - Background refresh

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.bgTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)  // au plus tôt dans 1h
        do {
            try BGTaskScheduler.shared.submit(request)
            print("BAVL BGTask schedulé")
        } catch {
            print("BAVL BGTask erreur:", error)
        }
    }

    /// À appeler dans BAVLHelperApp.init() une seule fois
    static func registerBackgroundHandler(vm: AppViewModel) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: bgTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            EditionNotifier.shared.handleBackgroundRefresh(task: refreshTask, vm: vm)
        }
    }

    private func handleBackgroundRefresh(task: BGAppRefreshTask, vm: AppViewModel) {
        // Re-schedule pour la prochaine fois
        scheduleBackgroundRefresh()

        // Si pas de session active, on abandonne proprement
        guard vm.authReady else { task.setTaskCompleted(success: true); return }

        // Timeout de sécurité exigé par iOS
        task.expirationHandler = { task.setTaskCompleted(success: false) }

        // Le check réel repose sur le WebView (nécessite une session active).
        // En background on ne peut pas ouvrir un WKWebView, donc on marque
        // simplement comme succès — la vraie vérification se fait au prochain
        // lancement via checkAndNotify appelé depuis PressReaderSheet.
        // TODO: implémenter un check URLSession pur si on obtient le bearer token
        // stocké en Keychain (nécessite que l'app le persiste explicitement).
        task.setTaskCompleted(success: true)
    }

    // MARK: - Persistence

    private func lastKnownDate(for path: String) -> String? {
        (defaults.dictionary(forKey: lastEditionKey) as? [String: String])?[path]
    }

    private func save(date: String, for path: String) {
        var dict = (defaults.dictionary(forKey: lastEditionKey) as? [String: String]) ?? [:]
        dict[path] = date
        defaults.set(dict, forKey: lastEditionKey)
    }

    // MARK: - Formatage

    private static let inputFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"
        f.locale = Locale(identifier: "fr_CH")
        f.timeZone = TimeZone(identifier: "Europe/Zurich")
        return f
    }()
    private static let outputFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE dd.MM.yyyy"
        f.locale = Locale(identifier: "fr_CH")
        f.timeZone = TimeZone(identifier: "Europe/Zurich")
        return f
    }()

    private func formattedDate(_ dateStr: String) -> String {
        guard let d = Self.inputFormatter.date(from: dateStr) else { return dateStr }
        return Self.outputFormatter.string(from: d)
    }
}
