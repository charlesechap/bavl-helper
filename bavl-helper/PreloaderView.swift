import SwiftUI
import WebKit

/// Vue invisible montée pendant l'animation canard.
/// Lance un _PressReaderWebViewBridge par journal pour capturer
/// bearer token + TOC + éditions avant que l'utilisateur ouvre un journal.
/// Les données sont stockées dans AppViewModel.preloadedData.
struct PreloaderView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        ZStack {
            ForEach(vm.newspapers) { newspaper in
                // Ne pas re-précharger si déjà en cache
                if vm.preloadedData[newspaper.pressReaderPath] == nil,
                   let url = newspaper.resolvedURL ?? newspaper.archiveURL {
                    SingleJournalPreloader(
                        newspaper: newspaper,
                        url: url,
                        onComplete: { data in
                            vm.storePreload(path: newspaper.pressReaderPath, data: data)
                        }
                    )
                    .frame(width: 1, height: 1)
                    .opacity(0)
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
    }
}

// MARK: - Préchargeur d'un seul journal

private struct SingleJournalPreloader: View {
    let newspaper: Newspaper
    let url: URL
    let onComplete: (JournalPreloadData) -> Void

    // Accumulateur mutable partagé avec le coordinator
    @State private var accumulator = PreloadAccumulator()

    var body: some View {
        _PressReaderWebViewBridge(
            initialURL: url,
            pressReaderPath: newspaper.pressReaderPath,
            onCoordinatorReady: { coord in
                coord.onEditionsLoaded = { editions in
                    accumulator.editions = editions
                    accumulator.tryFlush(path: newspaper.pressReaderPath, onComplete: onComplete)
                }
                coord.onBearerReady = { token, path in
                    accumulator.bearerToken = token
                    accumulator.pressReaderPath = path
                    accumulator.tryFlush(path: newspaper.pressReaderPath, onComplete: onComplete)
                }
                coord.onTOCLoaded = { ids, issueId in
                    accumulator.tocIds = ids
                    accumulator.tocIssueId = issueId
                    accumulator.tryFlush(path: newspaper.pressReaderPath, onComplete: onComplete)
                }
                coord.onArticleReady = { _ in }
            },
            onURLChange: { url in
                if let dateStr = url?.absoluteString.extractDateStr() {
                    accumulator.currentDate = dateStr
                }
            }
        )
    }
}

// MARK: - Accumulateur

private class PreloadAccumulator {
    var bearerToken: String = ""
    var pressReaderPath: String = ""
    var editions: [PressReaderEdition] = []
    var tocIds: [Int64] = []
    var tocIssueId: String = ""
    var currentDate: String = ""
    private var flushed = false

    // Flush dès qu'on a au minimum le bearer token + le TOC
    func tryFlush(path: String, onComplete: (JournalPreloadData) -> Void) {
        guard !flushed, !bearerToken.isEmpty, !tocIds.isEmpty else { return }
        flushed = true
        onComplete(JournalPreloadData(
            bearerToken: bearerToken,
            pressReaderPath: pressReaderPath.isEmpty ? path : pressReaderPath,
            editions: editions,
            tocIds: tocIds,
            tocIssueId: tocIssueId,
            currentDate: currentDate
        ))
    }
}

// MARK: - Helpers

private extension String {
    func extractDateStr() -> String? {
        guard let r = self.range(of: "[0-9]{8}", options: .regularExpression) else { return nil }
        return String(self[r])
    }
}
