import Foundation
import Combine
import WebKit
import SwiftUI

enum LoginState {
    case idle
    case loading
    case success
    case failure(String)
}

@MainActor
class AppViewModel: NSObject, ObservableObject {
    @Published var loginState: LoginState = .idle
    @Published var statusMessage: String = ""
    @Published var statusLog: [String] = []
    @Published var newspapers: [Newspaper] = []

    private var webView: WKWebView?
    private let sessionDateKey = "lastLoginDate"
    // Session BAVL via portail web : ~48h, on renouvelle après 25h
    private let sessionDuration: TimeInterval = 25 * 3600

    override init() {
        super.init()
        loadNewspapers()
    }

    // MARK: - Credentials
    var cardNumber: String {
        get { KeychainHelper.load(forKey: "cardNumber") ?? "" }
        set { KeychainHelper.save(newValue, forKey: "cardNumber") }
    }

    var password: String {
        get { KeychainHelper.load(forKey: "password") ?? "" }
        set { KeychainHelper.save(newValue, forKey: "password") }
    }

    // MARK: - Session check
    func checkExistingSession() {
        guard let lastLogin = UserDefaults.standard.object(forKey: sessionDateKey) as? Date else {
            login()
            return
        }
        let elapsed = Date().timeIntervalSince(lastLogin)
        if elapsed < sessionDuration {
            let hoursLeft = Int((sessionDuration - elapsed) / 3600)
            print("Session valide — expire dans ~\(hoursLeft)h")
            loginState = .success
        } else {
            print("Session expiree — reconnexion automatique")
            login()
        }
    }

    private func markSessionStart() {
        UserDefaults.standard.set(Date(), forKey: sessionDateKey)
    }

    // MARK: - Newspapers
    func loadNewspapers() {
        if let data = UserDefaults.standard.data(forKey: "newspapers"),
           let decoded = try? JSONDecoder().decode([Newspaper].self, from: data) {
            newspapers = decoded
        } else {
            newspapers = Newspaper.defaults
            saveNewspapers()
        }
    }

    func saveNewspapers() {
        if let data = try? JSONEncoder().encode(newspapers) {
            UserDefaults.standard.set(data, forKey: "newspapers")
        }
    }

    func addNewspaper(_ newspaper: Newspaper) {
        newspapers.append(newspaper)
        saveNewspapers()
    }

    func removeNewspaper(at offsets: IndexSet) {
        newspapers.remove(atOffsets: offsets)
        saveNewspapers()
    }

    // MARK: - Status logging
    func appendLog(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        statusLog.append("[\(ts)] \(msg)")
        statusMessage = msg
        print(msg)
    }

    // MARK: - Login
    func login() {
        guard !cardNumber.isEmpty, !password.isEmpty else {
            loginState = .failure("Veuillez configurer vos identifiants dans les reglages.")
            return
        }

        // FIX: nettoyer le WebView précédent avant d'en créer un nouveau
        teardownWebView()

        loginState = .loading
        statusLog = []
        appendLog("Connexion au portail BAVL...")

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        wv.navigationDelegate = self
        // Attacher à la fenêtre pour que WebKit exécute les scripts JS
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first {
            window.addSubview(wv)
            wv.isHidden = true
            wv.isUserInteractionEnabled = false
        }
        self.webView = wv

        let url = URL(string: "https://bavl.lausanne.ch/iguana/www.main.cls?surl=offre-numerique-pressreader")!
        wv.load(URLRequest(url: url))
    }

    // MARK: - Teardown WebView
    private func teardownWebView() {
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
    }

    // MARK: - Etape 2 : navigation directe vers PressReader
    private func performAccessScript() {
        guard let wv = webView else { return }
        // On navigue directement plutôt que de cliquer (target="_blank" serait bloqué)
        let script = """
        (function() {
            var prLink = document.querySelector('a[href*="pressreader"]');
            if (prLink) {
                prLink.removeAttribute('target');
                prLink.click();
                return 'navigating to: ' + prLink.href;
            }
            return 'link_not_found';
        })();
        """
        wv.evaluateJavaScript(script) { result, error in
            if let result = result { print("Access script: \(result)") }
            if let error  = error  { print("JS error acceder: \(error)") }
        }
    }

    // MARK: - Etape 1 : remplir et soumettre le formulaire
    private func performLoginScript() {
        guard let wv = webView else { return }
        let card = cardNumber.replacingOccurrences(of: "\"", with: "\\\"")
        let pwd  = password.replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        (function() {
            var loginLink = document.querySelector('a[logon="1"]');
            if (loginLink) {
                loginLink.click();
                setTimeout(fillAndSubmit, 1500);
            } else {
                fillAndSubmit();
            }

            function fillAndSubmit() {
                var userField = document.getElementById('loginUser');
                var pwField   = document.getElementById('loginPassword');
                var cookieBox = document.getElementById('setCookie');
                var okBtn     = document.getElementById('dijit_form_Button_0');

                if (userField && pwField) {
                    var setter = Object.getOwnPropertyDescriptor(
                        window.HTMLInputElement.prototype, 'value').set;
                    setter.call(userField, "\(card)");
                    userField.dispatchEvent(new Event('input', { bubbles: true }));
                    setter.call(pwField, "\(pwd)");
                    pwField.dispatchEvent(new Event('input', { bubbles: true }));

                    if (cookieBox && !cookieBox.checked) { cookieBox.click(); }
                    if (okBtn) { okBtn.click(); return 'submitted'; }
                }
                return 'fields_not_found';
            }
        })();
        """

        wv.evaluateJavaScript(script) { result, error in
            if let error = error { print("JS error login: \(error)") }
        }
    }
}

// MARK: - WKNavigationDelegate
extension AppViewModel: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            guard let url = webView.url?.absoluteString else { return }
            print("Page chargee: \(url)")

            if url.contains("offre-numerique-pressreader-acces") {
                appendLog("Auth réussie — ouverture PressReader...")
                try? await Task.sleep(nanoseconds: 800_000_000)
                performAccessScript()

            } else if url.contains("offre-numerique-pressreader") {
                appendLog("Formulaire détecté — saisie des identifiants...")
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                appendLog("Envoi des identifiants...")
                performLoginScript()

            } else if url.contains("pressreader.com") {
                appendLog("Connecté ! Chargement des journaux...")
                loginState = .success
                markSessionStart()
                // FIX: retirer le WebView de la hiérarchie proprement
                teardownWebView()

            } else {
                print("Page intermediaire: \(url)")
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView,
                             decidePolicyFor navigationAction: WKNavigationAction,
                             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // FIX: suppression du dead code — toutes les URLs sont autorisées,
        // la détection pressreader.com est gérée dans didFinish
        decisionHandler(.allow)
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            loginState = .failure("Erreur reseau: \(error.localizedDescription)")
            teardownWebView()
        }
    }
}
