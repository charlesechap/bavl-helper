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
    private let sessionDuration: TimeInterval = 25 * 3600

    // MARK: - Retry
    private var retryCount = 0
    private let maxRetries = 2

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

    // MARK: - Session check (amélioration 2 : vérification réelle)
    func checkExistingSession() {
        guard !cardNumber.isEmpty, !password.isEmpty else {
            loginState = .idle
            return
        }

        // Vérification rapide via timestamp d'abord
        if let lastLogin = UserDefaults.standard.object(forKey: sessionDateKey) as? Date {
            let elapsed = Date().timeIntervalSince(lastLogin)
            if elapsed < sessionDuration {
                // Le timestamp suggère que la session est valide,
                // mais on vérifie quand même en chargeant PressReader
                appendLog("Vérification session...")
                verifySessionLive()
                return
            }
        }

        // Pas de timestamp ou session expirée → login direct
        login()
    }

    /// Charge PressReader silencieusement pour vérifier si la session est toujours active
    private func verifySessionLive() {
        teardownWebView()
        loginState = .loading

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let wv = makeWebView(config: config)
        self.webView = wv

        // Flag pour distinguer le mode vérification du mode login
        isVerifyingSession = true

        let url = URL(string: "https://www.pressreader.com/")!
        wv.load(URLRequest(url: url))
    }

    private var isVerifyingSession = false

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

    // MARK: - WebView factory
    private func makeWebView(config: WKWebViewConfiguration) -> WKWebView {
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        wv.navigationDelegate = self
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first {
            window.addSubview(wv)
            wv.isHidden = true
            wv.isUserInteractionEnabled = false
        }
        return wv
    }

    // MARK: - Login
    func login() {
        guard !cardNumber.isEmpty, !password.isEmpty else {
            loginState = .failure("Veuillez configurer vos identifiants dans les réglages.")
            return
        }

        teardownWebView()
        isVerifyingSession = false
        retryCount = 0
        loginState = .loading
        statusLog = []
        appendLog("Connexion au portail BAVL...")

        startLoginFlow()
    }

    private func startLoginFlow() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let wv = makeWebView(config: config)
        self.webView = wv

        let url = URL(string: "https://bavl.lausanne.ch/iguana/www.main.cls?surl=offre-numerique-pressreader")!
        wv.load(URLRequest(url: url))
    }

    // MARK: - Retry (amélioration 1)
    private func retryLoginIfPossible(reason: String) {
        if retryCount < maxRetries {
            retryCount += 1
            appendLog("Tentative \(retryCount)/\(maxRetries) — \(reason)")
            teardownWebView()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.startLoginFlow()
            }
        } else {
            loginState = .failure("Échec après \(maxRetries) tentatives : \(reason)")
            teardownWebView()
        }
    }

    // MARK: - Teardown WebView
    private func teardownWebView() {
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
    }

    // MARK: - Étape 2 : navigation vers PressReader
    private func performAccessScript() {
        guard let wv = webView else { return }
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

    // MARK: - Étape 1 : remplir et soumettre le formulaire
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

        wv.evaluateJavaScript(script) { [weak self] result, error in
            if let error = error {
                print("JS error login: \(error)")
            }
            // Si le script retourne fields_not_found, on réessaie
            if let result = result as? String, result == "fields_not_found" {
                Task { @MainActor in
                    self?.retryLoginIfPossible(reason: "formulaire introuvable")
                }
            }
        }
    }
}

// MARK: - WKNavigationDelegate
extension AppViewModel: WKNavigationDelegate {

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            guard let url = webView.url?.absoluteString else { return }
            print("Page chargée: \(url)")

            // MODE VÉRIFICATION SESSION
            if isVerifyingSession {
                if url.contains("pressreader.com") && !url.contains("login") {
                    // On est bien sur PressReader → session encore valide
                    appendLog("Session active — accès direct.")
                    loginState = .success
                    teardownWebView()
                } else {
                    // Redirigé ailleurs → session expirée, on relance le login
                    appendLog("Session expirée — reconnexion...")
                    isVerifyingSession = false
                    teardownWebView()
                    login()
                }
                return
            }

            // MODE LOGIN NORMAL
            if url.contains("offre-numerique-pressreader-acces") {
                appendLog("Auth réussie — ouverture PressReader...")
                // Pas de sleep : on réagit directement à didFinish
                performAccessScript()

            } else if url.contains("offre-numerique-pressreader") {
                appendLog("Formulaire détecté — saisie des identifiants...")
                // Pas de sleep : la page est chargée, on exécute le script
                appendLog("Envoi des identifiants...")
                performLoginScript()

            } else if url.contains("pressreader.com") {
                appendLog("Connecté ! Chargement des journaux...")
                loginState = .success
                markSessionStart()
                teardownWebView()

            } else {
                print("Page intermédiaire: \(url)")
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView,
                             decidePolicyFor navigationAction: WKNavigationAction,
                             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            let nsError = error as NSError
            // Ignorer les annulations volontaires (changement de page pendant navigation)
            guard nsError.code != NSURLErrorCancelled else { return }
            retryLoginIfPossible(reason: error.localizedDescription)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }
            retryLoginIfPossible(reason: error.localizedDescription)
        }
    }
}
