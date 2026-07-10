// Generates the EyeVoice app icon: an ASCII-art eye — ragged 4-point star of dots,
// almond eyelid, pink dotted iris with an empty pupil — on a black squircle.
// Usage: swift Scripts/make_icon.swift <output.png>
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let size: CGFloat = 1024
srand48(7) // fixed seed → reproducible icon

func rnd() -> Double { drand48() }

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Background: black squircle with a faint border
let inset: CGFloat = size * 0.06
let bgRect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let bg = NSBezierPath(roundedRect: bgRect, xRadius: size * 0.185, yRadius: size * 0.185)
NSColor.black.setFill()
bg.fill()
NSColor(white: 0.35, alpha: 1).setStroke()
bg.lineWidth = size * 0.006
bg.stroke()
bg.setClip()

// ASCII grid
let cell: CGFloat = 14
let cols = Int(size / cell)
let rows = Int(size / cell)
let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold)

let pink = NSColor(red: 1.0, green: 0.42, blue: 0.78, alpha: 1)
let pinkDim = NSColor(red: 0.88, green: 0.32, blue: 0.64, alpha: 1)

func draw(_ char: String, _ col: Int, _ row: Int, _ color: NSColor) {
    let jx = CGFloat(rnd() - 0.5) * 3
    let jy = CGFloat(rnd() - 0.5) * 3
    let point = NSPoint(x: CGFloat(col) * cell + jx, y: CGFloat(row) * cell + jy)
    (char as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
}

func glyph(_ density: Double) -> String {
    switch density {
    case 0.80...: return "#"
    case 0.60..<0.80: return "+"
    case 0.38..<0.60: return ":"
    default: return "."
    }
}

for row in 0..<rows {
    for col in 0..<cols {
        // normalized coords, y slightly compressed (eye is wider than tall)
        let nx = (Double(col) - Double(cols) / 2) / (Double(cols) * 0.42)
        let ny = (Double(row) - Double(rows) / 2) / (Double(rows) * 0.40)

        // 4-point concave star (spikes on the axes)
        let star = pow(abs(nx), 0.7) + pow(abs(ny), 0.7)

        // almond eyelid opening
        let lensHalfW = 0.72
        let inLensX = abs(nx) < lensHalfW
        let lensY = inLensX ? 0.38 * pow(max(0, 1 - pow(nx / lensHalfW, 2)), 0.72) : 0
        let inLens = inLensX && abs(ny) < lensY

        // iris / pupil
        let r = sqrt(nx * nx + ny * ny * 1.15)

        if inLens {
            if r < 0.12 {
                continue // pupil — pure black
            }
            if r < 0.30 {
                // pink dotted iris with dropouts
                if rnd() < 0.88 {
                    let d = 0.4 + rnd() * 0.6
                    // small white highlight, upper-left
                    if nx < -0.06 && ny > 0.08 && r < 0.22 && rnd() < 0.3 {
                        draw(glyph(d), col, row, NSColor(white: 1.0, alpha: 1))
                    } else {
                        draw(glyph(d), col, row, rnd() < 0.7 ? pink : pinkDim)
                    }
                }
                continue
            }
            // bright dotted eyelid rim, then dark sclera with sparse speckles
            let edge = lensY - abs(ny)
            if edge < 0.05 {
                if rnd() < 0.85 { draw(":", col, row, NSColor(white: 0.95, alpha: 1)) }
            } else if rnd() < 0.10 {
                draw(rnd() < 0.5 ? "." : ":", col, row, NSColor(white: 0.65, alpha: 1))
            }
            continue
        }

        // dense ragged star body around the eye
        if star < 1.0 {
            let base = min(1.0, (1.0 - star) * 2.0)
            // ragged edges: more dropouts near the boundary
            if rnd() < 0.62 + base * 0.38 {
                let d = base * (0.55 + rnd() * 0.45)
                let brightness = min(1.0, 0.7 + base * 0.25 + rnd() * 0.1)
                draw(glyph(max(0.2, d)), col, row, NSColor(white: brightness, alpha: 1))
            }
            continue
        }

        // faint scattered specks outside
        if star < 1.5 && rnd() < 0.025 {
            draw(".", col, row, NSColor(white: 0.5, alpha: 1))
        }
    }
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("failed to render icon")
}
try png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
