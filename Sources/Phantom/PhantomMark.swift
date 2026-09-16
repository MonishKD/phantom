import SwiftUI

/// The ghost from the app icon as a vector shape. The eyes are holes, so fill it with `eoFill: true`.
/// Geometry mirrors scripts/make-icon.swift, flipped into SwiftUI's y-down coordinates.
struct PhantomMark: Shape {
    func path(in rect: CGRect) -> Path {
        var ghost = Path()
        ghost.move(to: CGPoint(x: 762, y: 524))
        ghost.addCurve(to: CGPoint(x: 556, y: 212), control1: CGPoint(x: 762, y: 302), control2: CGPoint(x: 676, y: 212))
        ghost.addCurve(to: CGPoint(x: 356, y: 504), control1: CGPoint(x: 436, y: 212), control2: CGPoint(x: 356, y: 308))
        ghost.addCurve(to: CGPoint(x: 116, y: 692), control1: CGPoint(x: 356, y: 588), control2: CGPoint(x: 296, y: 636))
        ghost.addCurve(to: CGPoint(x: 372, y: 702), control1: CGPoint(x: 236, y: 694), control2: CGPoint(x: 300, y: 726))
        ghost.addCurve(to: CGPoint(x: 548, y: 724), control1: CGPoint(x: 452, y: 678), control2: CGPoint(x: 470, y: 724))
        ghost.addCurve(to: CGPoint(x: 722, y: 694), control1: CGPoint(x: 626, y: 724), control2: CGPoint(x: 652, y: 672))
        ghost.addCurve(to: CGPoint(x: 762, y: 524), control1: CGPoint(x: 752, y: 704), control2: CGPoint(x: 762, y: 620))
        ghost.closeSubpath()

        let eyes: [(center: CGPoint, angle: CGFloat)] = [(CGPoint(x: 486, y: 376), 0.22), (CGPoint(x: 628, y: 376), -0.22)]
        for eye in eyes {
            ghost.addPath(
                Path(ellipseIn: CGRect(x: -36, y: -52, width: 72, height: 104)),
                transform: CGAffineTransform(translationX: eye.center.x, y: eye.center.y).rotated(by: eye.angle)
            )
        }

        // The icon's forward lean, pivoting where the icon does.
        let lean = CGAffineTransform(translationX: 512, y: 474).rotated(by: 0.07).translatedBy(x: -512, y: -474)
        let leaning = ghost.applying(lean)

        let bounds = leaning.boundingRect
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        let fit = CGAffineTransform(translationX: rect.midX - bounds.midX * scale, y: rect.midY - bounds.midY * scale)
            .scaledBy(x: scale, y: scale)
        return leaning.applying(fit)
    }
}

/// The white ghost with a faint blue glow, sized by height.
struct PhantomLogo: View {
    var size: CGFloat = 24
    var glow = true

    var body: some View {
        PhantomMark()
            .fill(Theme.textPrimary, style: FillStyle(eoFill: true))
            .frame(width: size * 1.25, height: size)
            .shadow(color: glow ? Theme.accent.opacity(0.6) : .clear, radius: size * 0.4)
    }
}
