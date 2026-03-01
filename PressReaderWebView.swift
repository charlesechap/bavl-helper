import SwiftUI
import WebKit

// MARK: - PressReaderWebView

/// WKWebView plein écran présenté en sheet.
/// Injecte du JS pour :
///   1. Fermer le popup "Bienvenue sur PressReader"
///   2. Détecter une page blanche (date inexistante) → rediriger vers /archive
struct PressReaderWebView: UIViewRepresentable {

    let initialURL: URL
    let archiveURL: URL?

    // JS exécuté après chaque chargement de page
    private static let injectedJS = """
    (function() {
        // --- 1. Fermer le popup "Bienvenue" ---
        // PressReader utilise plusieurs sélecteurs selon la version
        var selectors = [
            'button[aria-label="Close"]',
            'button.welcome-dialog__close',
            '.modal-close',
            '[data-testid="welcome-dismiss"]',
            'button.dismiss',
            '.welcome-overlay button'
        ];
        function dismissPopup() {
            for (var i = 0; i < selectors.length; i++) {
                var btn = document.querySelector(selectors[i]);
                if (btn) { btn.click(); return true; }
            }
            // Fallback : chercher un bouton dont le texte contient "fermer" ou "close"
            var buttons = document.querySelectorAll('button');
            for (var j = 0; j < buttons.length; j++) {
                var t = buttons[j].innerText.toLowerCase().trim();
                if (t === 'close' || t === 'fermer' || t === '×' || t === 'x') {
                    buttons[j].click(); return true;
                }
            }
            return false;
        }
        // Tenter immédiatement, puis surveiller le DOM
        if (!dismissPopup()) {
            var observer = new MutationObserver(function(mutations, obs) {
                if (dismissPopup()) { obs.disconnect(); }
            });
            observer.observe(document.body || document.documentElement, { childList: true, subtree: true });
            // Arrêter après 10s pour ne pas fuiter
            setTimeout(function() { observer.disconnect(); }, 10000);
        }

        // --- 2. Détecter page blanche (textview avec date invalide) ---
        // On retourne un signal que Swift peut lire via window.webkit.messageHandlers
        var isBlank = false;
        // Heuristique : le contenu principal est vide
        setTimeout(function() {
            var article = document.querySelector('article, .article-content, .text-content, [class*="article"]');
            var isEmpty = !article || article.innerText.trim().length < 50;
            // Vérifier aussi si l'URL contient une date et que le titre indique "not found" / 404
            var title = document.title || '';
            var notFound = title.toLowerCase().includes('not found') ||
                           title.toLowerCase().includes('404') ||
                           title === '';
            if ((isEmpty || notFound) && window.location.pathname.includes('/textview')) {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pageBlank) {
                    window.webkit.messageHandlers.pageBlank.postMessage(window.location.href);
                }
            }
        }, 2500);
    })();
    """

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()  // partage les cookies avec l'auth WebView
        config.userContentController.add(context.coordinator, name: "pageBlank")
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = wv
        context.coordinator.archiveURL = archiveURL
        wv.load(URLRequest(url: initialURL))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var archiveURL: URL?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(PressReaderWebView.injectedJS, completionHandler: nil)
        }

        // Réception du message "pageBlank"
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "pageBlank" else { return }
            // Rediriger vers la page d'archive du journal
            let target: URL
            if let archive = archiveURL {
                target = archive
            } else if let current = webView?.url {
                // Construire l'URL d'archive à partir de l'URL courante
                // Ex: https://pressreader.com/switzerland/le-temps/20250301/textview
                //  → https://pressreader.com/switzerland/le-temps/archive
                var components = URLComponents(url: current, resolvingAgainstBaseURL: false)
                components?.path = current.pathComponents
                    .prefix(3) // ["", "switzerland", "le-temps"]
                    .joined(separator: "/")
                    .replacingOccurrences(of: "//", with: "/")
                    + "/archive"
                target = components?.url ?? current
            } else {
                return
            }
            DispatchQueue.main.async {
                self.webView?.load(URLRequest(url: target))
            }
        }
    }
}

// MARK: - PressReaderSheet

/// Vue sheet complète avec bouton Fermer flottant.
struct PressReaderSheet: View {
    let newspaper: Newspaper
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let url = newspaper.resolvedURL {
                PressReaderWebView(
                    initialURL: url,
                    archiveURL: newspaper.archiveURL
                )
                .ignoresSafeArea()
            } else {
                ContentUnavailableView("URL invalide", systemImage: "xmark.circle")
            }

            // Bouton fermer flottant
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .padding(.top, 56)
            .padding(.trailing, 16)
        }
    }
}
