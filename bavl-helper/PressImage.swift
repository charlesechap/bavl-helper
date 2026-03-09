import SwiftUI

/// Charge une image depuis i.prcdn.co avec Accept: image/webp pour la pleine qualité.
struct PressImage: View {
    let url: URL
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    var contentMode: ContentMode = .fill

    @State private var uiImage: UIImage? = nil
    @State private var failed = false

    var body: some View {
        Group {
            if let img = uiImage {
                Image(uiImage: img)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
            } else if failed {
                EmptyView()
            } else {
                Rectangle()
                    .fill(Color(white: 0.18))
            }
        }
        .frame(width: width, height: height)
        .task(id: url) { await load() }
    }

    private func load() async {
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("image/webp,image/jpeg,image/*", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let img = UIImage(data: data) {
                await MainActor.run { uiImage = img }
            } else {
                await MainActor.run { failed = true }
            }
        } catch {
            await MainActor.run { failed = true }
        }
    }
}
