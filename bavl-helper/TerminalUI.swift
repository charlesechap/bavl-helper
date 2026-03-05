import SwiftUI

// MARK: - Palette globale

extension Color {
    static let termBg     = Color(red: 0.13, green: 0.13, blue: 0.13)
    static let termFg     = Color(red: 0.80, green: 0.80, blue: 0.80)
    static let termDim    = Color(red: 0.50, green: 0.50, blue: 0.50)
    static let termFaint  = Color(red: 0.30, green: 0.30, blue: 0.30)
}

// MARK: - Cadre terminal

struct TerminalFrame<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    init(title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            HStack(alignment: .top, spacing: 0) {
                Text("│")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.termFaint)
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("│")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.termFaint)
            }
            bottomBar
        }
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            Text("┌─")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color.termFaint)
            if let title {
                Text("[ \(title) ]─")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.termDim)
            }
            expandingLine
            Text("┐")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color.termFaint)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Text("└─")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color.termFaint)
            expandingLine
            Text("┘")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color.termFaint)
        }
    }

    private var expandingLine: some View {
        GeometryReader { geo in
            Text(String(repeating: "─", count: max(0, Int(geo.size.width / 6.3))))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color.termFaint)
                .lineLimit(1)
        }
        .frame(height: 16)
    }
}

// MARK: - Signature

struct TerminalSignature: View {
    var body: some View {
        HStack {
            Spacer()
            Text("canard v0.1  //  non affilié à BAVL ou PressReader")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color.termFaint)
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Séparateur

struct TerminalSeparator: View {
    var body: some View {
        Text(String(repeating: "· ", count: 24))
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(Color.termFaint)
            .lineLimit(1)
    }
}

// MARK: - Champ de saisie

struct TerminalField: View {
    let label: String
    @Binding var text: String
    var secure: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("> \(label)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color.termFaint)
            Group {
                if secure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                        .keyboardType(.asciiCapable)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(Color.termFg)
            .tint(Color.termFg)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.04))
            .overlay(Rectangle().stroke(Color.termFaint, lineWidth: 1))
        }
    }
}

// MARK: - Bouton terminal

struct TerminalButton: View {
    let label: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Spacer()
                Text(label)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(enabled ? Color.termFg : Color.termFaint)
                Spacer()
            }
            .padding(.vertical, 13)
            .overlay(Rectangle().stroke(enabled ? Color.termDim : Color.termFaint, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

