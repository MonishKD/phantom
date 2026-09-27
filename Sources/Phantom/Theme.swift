import SwiftUI

/// Phantom's jet-black palette and the shared styles built on it.
enum Theme {
    static let background = Color.black
    static let surface = Color(white: 0.055)
    static let surfaceRaised = Color(white: 0.105)
    static let hover = Color.white.opacity(0.06)
    static let border = Color.white.opacity(0.09)
    static let borderStrong = Color.white.opacity(0.16)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.38)

    /// The cool blue of the app icon's glow.
    static let accent = Color(red: 0.45, green: 0.58, blue: 1.0)
    static let success = Color(red: 0.32, green: 0.86, blue: 0.56)
    static let warning = Color(red: 1.0, green: 0.74, blue: 0.32)
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.42)

    /// Panels floating over the map: near-black, with a trace of the map showing through.
    static let overlay = Color.black.opacity(0.8)

    /// Tint for the glass panels, dark enough to keep the jet-black look.
    static let glassTint = Color.black.opacity(0.55)
}

// MARK: - Buttons

struct PhantomButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }

    var kind: Kind = .primary
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, kind: kind, fullWidth: fullWidth)
    }

    private struct StyledButton: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        let fullWidth: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
            // Disabled buttons go flat and dark instead of fading: faded white on black turns muddy grey.
            let filled = kind == .primary && isEnabled
            configuration.label
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(!isEnabled ? Theme.textTertiary : (filled ? Color.black : Theme.textPrimary))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .background(filled ? Color.white : Theme.surfaceRaised, in: shape)
                .overlay(shape.strokeBorder(filled ? .clear : (isEnabled ? Theme.borderStrong : Theme.border), lineWidth: 1))
                .contentShape(shape)
                .opacity(configuration.isPressed ? 0.78 : 1)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
        }
    }
}

struct PhantomLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Theme.accent.opacity(configuration.isPressed ? 0.6 : 1))
            .contentShape(Rectangle())
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconButton(configuration: configuration)
    }

    private struct IconButton: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 30, height: 28)
                .background(configuration.isPressed ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.3)
        }
    }
}

// MARK: - Rows, labels and panels

final class HoverState: ObservableObject {
    @Published var isHovered = false
}

/// A list row that lights up under the pointer.
struct HoverRow: ViewModifier {
    @StateObject private var hover = HoverState()

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hover.isHovered ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .onHover { hover.isHovered = $0 }
    }
}

struct SectionLabel<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension SectionLabel where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}

extension View {
    /// A dark card for sidebar content.
    func phantomCard(padding: CGFloat = 14) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: shape)
            .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
    }

    /// A dark glass panel for controls floating over the map, on macOS 26's Liquid Glass.
    func floatingPanel(cornerRadius: CGFloat = 14) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .glassEffect(.regular.tint(Theme.glassTint), in: shape)
            .overlay(shape.strokeBorder(Theme.borderStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 18, y: 6)
    }
}
