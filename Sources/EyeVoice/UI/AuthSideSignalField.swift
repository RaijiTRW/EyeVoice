import SwiftUI

/// Peripheral signal graphics for the main authentication window.
/// Everything is intentionally constrained to the side zones so the eye and form stay quiet.
struct AuthSideSignalField: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas(rendersAsynchronously: true) { context, size in
                drawRings(in: &context, size: size, time: time)
                drawRails(in: &context, size: size, time: time)
                drawParticles(in: &context, size: size, time: time)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawRings(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        let centers = [
            CGPoint(x: -size.width * 0.035, y: size.height * 0.58),
            CGPoint(x: size.width * 1.035, y: size.height * 0.43),
        ]
        let baseRadius = min(size.width, size.height) * 0.23

        for (side, center) in centers.enumerated() {
            for ring in 0..<3 {
                let radius = baseRadius + CGFloat(ring) * 62
                let drift = sin(time * (0.16 + Double(ring) * 0.035) + Double(side) * 1.8) * 8
                var path = Path()
                path.addArc(
                    center: CGPoint(x: center.x, y: center.y + CGFloat(drift)),
                    radius: radius,
                    startAngle: .degrees(side == 0 ? -78 : 102),
                    endAngle: .degrees(side == 0 ? 78 : 258),
                    clockwise: side != 0
                )
                let opacity = ring == 0 ? 0.15 : ring == 1 ? 0.085 : 0.045
                let color = ring == 0 ? Theme.accent.opacity(opacity) : Color.white.opacity(opacity)
                context.stroke(
                    path,
                    with: .color(color),
                    style: StrokeStyle(
                        lineWidth: ring == 0 ? 1.15 : 0.8,
                        dash: ring == 1 ? [3, 8] : [],
                        dashPhase: CGFloat(time * (side == 0 ? 3.2 : -2.6))
                    )
                )
            }
        }
    }

    private func drawRails(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        let railXs = [
            size.width * 0.055,
            size.width * 0.105,
            size.width * 0.895,
            size.width * 0.945,
        ]

        for (index, x) in railXs.enumerated() {
            var rail = Path()
            rail.move(to: CGPoint(x: x, y: size.height * 0.17))
            rail.addLine(to: CGPoint(x: x, y: size.height * 0.86))
            context.stroke(rail, with: .color(.white.opacity(0.035)), lineWidth: 0.7)

            let travel = (time * (0.055 + Double(index) * 0.007) + Double(index) * 0.21)
                .truncatingRemainder(dividingBy: 1)
            let y = size.height * (0.2 + travel * 0.58)
            let pulseHeight: CGFloat = index.isMultiple(of: 2) ? 46 : 28
            var pulse = Path()
            pulse.move(to: CGPoint(x: x, y: y))
            pulse.addLine(to: CGPoint(x: x, y: y + pulseHeight))
            context.stroke(
                pulse,
                with: .linearGradient(
                    Gradient(colors: [.clear, Theme.accent.opacity(0.46), .clear]),
                    startPoint: CGPoint(x: x, y: y),
                    endPoint: CGPoint(x: x, y: y + pulseHeight)
                ),
                lineWidth: 1.2
            )
        }
    }

    private func drawParticles(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        for index in 0..<46 {
            let leftSide = index.isMultiple(of: 2)
            let horizontalNoise = CGFloat(Self.hash(index, 13))
            let verticalNoise = CGFloat(Self.hash(index, 71))
            let sideWidth = size.width * 0.19
            let x = leftSide
                ? 18 + horizontalNoise * sideWidth
                : size.width - 18 - horizontalNoise * sideWidth
            let y = 64 + verticalNoise * max(1, size.height - 128)
            let flicker = 0.45 + 0.55 * sin(time * 1.25 + Double(index) * 0.73)
            let radius: CGFloat = index.isMultiple(of: 7) ? 1.45 : 0.75
            let color = index.isMultiple(of: 5)
                ? Theme.accent.opacity(0.16 + 0.12 * flicker)
                : Color.white.opacity(0.055 + 0.06 * flicker)
            context.fill(
                Path(ellipseIn: CGRect(
                    x: x - radius,
                    y: y - radius,
                    width: radius * 2,
                    height: radius * 2
                )),
                with: .color(color)
            )
        }
    }

    private static func hash(_ x: Int, _ y: Int) -> Double {
        let value = sin(Double(x) * 91.7 + Double(y) * 173.3) * 31_337.412
        return value - floor(value)
    }
}
