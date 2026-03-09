import SwiftUI

/// Charge une image PressReader via URLSession.
/// L'URL doit déjà contenir le bon paramètre width (ex: &width=1170).
struct PressImage: View {
    let url: URL
    var contentMode: ContentMode = .fill

    @State private var uiImage: UIImage? = nil
    @State private var loading = true

    var body: some View {
        Group {
            if let img = uiImage {
                Image(uiImage: img)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
            } else if loading {
                Rectangle()
                    .fill(Color(white: 0.18))
            }
            // Si loading=false et pas d'image → EmptyView implicite
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        loading = true
        uiImage = nil
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("image/jpeg,image/*", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let img = UIImage(data: data) {
                await MainActor.run { uiImage = img; loading = false }
            } else {
                await MainActor.run { loading = false }
            }
        } catch {
            await MainActor.run { loading = false }
        }
    }
}
