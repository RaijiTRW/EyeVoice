import AppKit
import SwiftUI

// Vercel-style monochrome theme
enum Theme {
    static let bg = Color(white: 0.02)
    static let panel = Color(white: 0.09)
    static let border = Color(white: 0.30)
    static let text = Color(white: 0.97)
    static let dim = Color(white: 0.68)
    static let faint = Color(white: 0.52)
    static let accent = Color(red: 1.0, green: 0.31, blue: 0.64)

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Compact, consistently rendered flags for interface-language controls.
/// Drawn in SwiftUI so they keep the same shape on every macOS version.
struct LanguageFlag: View {
    let language: UILanguage
    var width: CGFloat = 24

    var body: some View {
        Group {
            switch language {
            case .ru:
                VStack(spacing: 0) {
                    Color.white
                    Color(red: 0.0, green: 0.22, blue: 0.65)
                    Color(red: 0.83, green: 0.17, blue: 0.12)
                }
            case .en:
                Canvas { context, size in
                    context.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .color(.white)
                    )

                    let stripeHeight = size.height / 13
                    let red = Color(red: 0.70, green: 0.05, blue: 0.12)
                    for stripe in stride(from: 0, to: 13, by: 2) {
                        context.fill(
                            Path(CGRect(
                                x: 0,
                                y: CGFloat(stripe) * stripeHeight,
                                width: size.width,
                                height: stripeHeight
                            )),
                            with: .color(red)
                        )
                    }

                    let canton = CGRect(
                        x: 0,
                        y: 0,
                        width: size.width * 0.44,
                        height: stripeHeight * 7
                    )
                    context.fill(
                        Path(canton),
                        with: .color(Color(red: 0.03, green: 0.15, blue: 0.35))
                    )

                    let starRadius = max(0.24, size.width * 0.012)
                    for row in 0..<4 {
                        for column in 0..<5 {
                            let x = canton.width * (0.12 + CGFloat(column) * 0.19)
                            let y = canton.height * (0.16 + CGFloat(row) * 0.23)
                            context.fill(
                                Path(ellipseIn: CGRect(
                                    x: x - starRadius,
                                    y: y - starRadius,
                                    width: starRadius * 2,
                                    height: starRadius * 2
                                )),
                                with: .color(.white)
                            )
                        }
                    }
                }
            }
        }
        .frame(width: width, height: width * 0.64)
        .clipShape(RoundedRectangle(cornerRadius: max(2, width * 0.12), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: max(2, width * 0.12), style: .continuous)
                .stroke(Color.black.opacity(0.22), lineWidth: 0.75)
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// Rounded card: continuous-corner clip + hairline stroke.
    func panelCard(radius: CGFloat = 9, color: Color = Theme.border) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(color, lineWidth: 1)
            )
    }

    /// Makes the complete custom input surface use the native text cursor.
    /// SwiftUI's plain fields otherwise expose the I-beam only over their intrinsic text area.
    func textInputCursor() -> some View {
        modifier(TextInputCursorModifier())
    }
}

private struct TextInputCursorModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { isHovering in
            (isHovering ? NSCursor.iBeam : NSCursor.arrow).set()
        }
    }
}

/// Almond eye with a pupil — the brand glyph (same drawing as the menu bar icon).
struct EyeGlyph: View {
    var width: CGFloat = 18
    var color: Color = Theme.text

    var body: some View {
        ZStack {
            EyeShape()
                .stroke(color, lineWidth: max(1.2, width * 0.075))
            Circle()
                .fill(color)
                .frame(width: width * 0.28, height: width * 0.28)
        }
        .frame(width: width, height: width * 0.62)
    }
}

/// Animated status eye: blinks when idle, scans while listening,
/// pulses while translating, droops on error.
struct EyeStatusView: View {
    let status: EngineStatus
    var width: CGFloat = 20

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let w = size.width
                let h = size.height
                let midY = h / 2
                let strokeWidth = max(1.2, w * 0.035)
                let horizontalInset = strokeWidth / 2

                var openness: Double
                var pupilX = w / 2
                var pupilR = h * 0.22
                var color = Theme.dim

                switch status {
                case .idle:
                    openness = Self.blink(t, period: 3.4)
                    color = Theme.faint
                case .connecting:
                    openness = 0.65 + 0.2 * sin(t * 5)
                    pupilR *= 0.85
                    color = Theme.dim
                case .listening:
                    openness = Self.blink(t, period: 5.0)
                    pupilX = w / 2 + CGFloat(sin(t * 1.1) * 0.55 + sin(t * 0.37) * 0.45) * w * 0.14
                    color = Theme.text
                case .translating:
                    openness = 1
                    pupilR *= 1.0 + 0.35 * abs(sin(t * 5.5))
                    color = Theme.text
                case .standby:
                    // dozing: almost closed, slow breathing
                    openness = 0.35 + 0.08 * sin(t * 1.4)
                    pupilR *= 0.7
                    color = Theme.faint
                case .error:
                    openness = 0.4
                    pupilR *= 0.8
                    color = Theme.dim
                }

                let lift = h * 0.62 * openness
                var eye = Path()
                eye.move(to: CGPoint(x: horizontalInset, y: midY))
                eye.addQuadCurve(
                    to: CGPoint(x: w - horizontalInset, y: midY),
                    control: CGPoint(x: w / 2, y: midY - lift)
                )
                eye.addQuadCurve(
                    to: CGPoint(x: horizontalInset, y: midY),
                    control: CGPoint(x: w / 2, y: midY + lift)
                )
                eye.closeSubpath()
                ctx.stroke(eye, with: .color(color), lineWidth: strokeWidth)

                if openness > 0.3 {
                    let r = pupilR * openness
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: pupilX - r, y: midY - r, width: r * 2, height: r * 2)),
                        with: .color(color)
                    )
                }
            }
        }
        .frame(width: width, height: width * 0.65)
    }

    /// 1.0 most of the time, quick close-and-open dip once per period.
    private static func blink(_ t: Double, period: Double) -> Double {
        let phase = t.truncatingRemainder(dividingBy: period)
        let dip = 0.24
        guard phase < dip else { return 1 }
        let x = phase / dip
        return max(0.08, abs(cos(.pi * x)))
    }
}

struct EyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.55)
        )
        p.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.55)
        )
        p.closeSubpath()
        return p
    }
}
