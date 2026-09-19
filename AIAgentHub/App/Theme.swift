import SwiftUI

/// Dark "AI IDE" look shared by every screen.
enum Theme {
    static let bg = Color(red: 0.05, green: 0.06, blue: 0.09)
    static let surface = Color(red: 0.09, green: 0.10, blue: 0.14)
    static let surfaceElevated = Color(red: 0.13, green: 0.14, blue: 0.19)
    static let stroke = Color.white.opacity(0.08)
    static let accent = Color(red: 1.0, green: 0.82, blue: 0.24)    // HF yellow
    static let accent2 = Color(red: 0.36, green: 0.66, blue: 1.0)
    static let good = Color(red: 0.35, green: 0.85, blue: 0.53)
    static let bad = Color(red: 1.0, green: 0.42, blue: 0.42)
    static let warn = Color(red: 1.0, green: 0.71, blue: 0.30)
    static let textDim = Color.white.opacity(0.58)
    static let mono = Font.system(.footnote, design: .monospaced)
}

struct CardBackground: ViewModifier {
    var padding: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.stroke))
    }
}

extension View {
    func card(padding: CGFloat = 14) -> some View { modifier(CardBackground(padding: padding)) }

    func screenBackground() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
    }
}

struct Pill: View {
    let text: String
    var color: Color = Theme.accent2
    var icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .bold)) }
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.16), in: Capsule())
        .foregroundStyle(color)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.textDim)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(Theme.textDim.opacity(0.8))
            }
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var action: (() -> Void)?
    var actionTitle: String?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(Theme.textDim)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textDim)
            if let action, let actionTitle {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).tint(Theme.accent2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }
}
