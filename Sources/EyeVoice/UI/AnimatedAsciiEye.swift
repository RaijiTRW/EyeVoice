import SwiftUI

/// Native SwiftUI adaptation of the landing-page ASCII eye.
/// It blinks, breathes and looks around autonomously without following the pointer.
struct AnimatedAsciiEye: View {
    var width: CGFloat = 560
    var height: CGFloat = 188
    var columns = 66
    var rows = 30

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas(rendersAsynchronously: true) { context, size in
                draw(in: &context, size: size, time: time)
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        // Keep every character cell square. Independent X/Y sizing distorted the eye
        // whenever the view's aspect ratio did not match the grid.
        let cellSize = min(
            size.width / CGFloat(columns),
            size.height / CGFloat(rows)
        )
        let gridSize = CGSize(
            width: cellSize * CGFloat(columns),
            height: cellSize * CGFloat(rows)
        )
        let origin = CGPoint(
            x: (size.width - gridSize.width) / 2,
            y: (size.height - gridSize.height) / 2
        )
        let fontSize = cellSize * 0.92
        let blink = Self.blink(time)

        // A slow, layered gaze path feels intentional rather than mechanically periodic.
        let gazeX = sin(time * 0.54) * 0.085 + sin(time * 0.19 + 1.4) * 0.035
        let gazeY = sin(time * 0.38 + 2.1) * 0.052
        let pupilPulse = 0.105 + (0.5 + 0.5 * sin(time * 0.82 + 0.7)) * 0.032

        for row in 0..<rows {
            for column in 0..<columns {
                let nx = (Double(column) - Double(columns) / 2) / (Double(rows) * 0.9)
                let ny = (Double(row) - Double(rows) / 2) / (Double(rows) * 0.48)
                let noiseA = Self.hash(column, row)
                let noiseB = Self.hash(column + 91, row + 17)
                let flicker = 0.76 + 0.24 * sin(time * 2.0 + noiseA * .pi * 2)

                let star = pow(abs(nx), 0.7) + pow(abs(ny), 0.7)
                let lensHalfWidth = 0.72
                let lensY: Double
                if abs(nx) < lensHalfWidth {
                    lensY = 0.38
                        * blink
                        * pow(max(0, 1 - pow(nx / lensHalfWidth, 2)), 0.72)
                } else {
                    lensY = 0
                }

                let insideLens = abs(ny) < lensY
                let irisX = nx - gazeX
                let irisY = ny - gazeY
                let radius = sqrt(irisX * irisX + irisY * irisY * 1.15)

                var character: Character?
                var color = Color.clear

                if insideLens {
                    // The pupil is negative space; its changing radius makes the eye breathe.
                    if radius < pupilPulse * blink { continue }

                    if radius < 0.3 {
                        if noiseA < 0.88 {
                            character = noiseB > 0.5 ? "#" : "+"
                            let alpha = (0.5 + 0.5 * noiseB) * flicker
                            color = Theme.accent.opacity(alpha)
                            if irisX < -0.05, irisY < -0.06, radius < 0.22, noiseB > 0.72 {
                                color = Color.white.opacity(alpha)
                            }
                        }
                    } else {
                        let edge = lensY - abs(ny)
                        if edge < 0.055, noiseA < 0.86 {
                            character = ":"
                            color = Theme.text.opacity(0.82 * flicker)
                        } else if noiseA < 0.1 {
                            character = noiseB < 0.5 ? "." : ":"
                            color = Theme.dim.opacity(0.5 * flicker)
                        }
                    }
                } else if star < 1 {
                    let base = min(1, (1 - star) * 2.2)
                    if noiseA < 0.72 + base * 0.28 {
                        let density = base * (0.55 + 0.45 * noiseB)
                        character = density > 0.6 ? "#" : density > 0.38 ? "+" : density > 0.2 ? ":" : "."
                        let brightness = min(1, 0.55 + base * 0.35) * flicker
                        color = Theme.text.opacity(brightness * 0.9)
                    }
                } else if star < 1.5, noiseA < 0.04 {
                    character = "."
                    color = Theme.faint.opacity(0.4 * flicker)
                }

                guard let character else { continue }
                let text = Text(String(character))
                    .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
                    .foregroundColor(color)
                context.draw(
                    text,
                    at: CGPoint(
                        x: origin.x + CGFloat(column) * cellSize,
                        y: origin.y + CGFloat(row) * cellSize
                    ),
                    anchor: .topLeading
                )
            }
        }
    }

    private static func blink(_ time: TimeInterval) -> Double {
        let phase = time.truncatingRemainder(dividingBy: 4.7)
        if phase < 0.28 {
            return max(0.055, abs(cos(.pi * (phase / 0.28))))
        }
        // A subtle second blink sometimes follows the first one.
        if phase > 0.43, phase < 0.59 {
            return max(0.16, abs(cos(.pi * ((phase - 0.43) / 0.16))))
        }
        return 1
    }

    private static func hash(_ x: Int, _ y: Int) -> Double {
        let value = sin(Double(x) * 127.1 + Double(y) * 311.7) * 43_758.5453
        return value - floor(value)
    }
}
