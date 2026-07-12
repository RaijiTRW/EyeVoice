#!/usr/bin/env swift
import AppKit
import Foundation

let output = CommandLine.arguments.dropFirst().first ?? "build/dmg-assets/background.png"
let version = CommandLine.arguments.dropFirst(2).first ?? "DEV"
let size = NSSize(width: 720, height: 460)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { fatalError("Unable to create DMG artwork") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let canvas = NSRect(origin: .zero, size: size)
NSColor(calibratedRed: 0.025, green: 0.022, blue: 0.032, alpha: 1).setFill()
canvas.fill()

// One restrained EyeVoice accent glow; the rest stays neutral and utilitarian.
let glow = NSGradient(colors: [
    NSColor(calibratedRed: 1, green: 0.20, blue: 0.61, alpha: 0.16),
    NSColor(calibratedRed: 1, green: 0.20, blue: 0.61, alpha: 0)
])!
glow.draw(in: NSBezierPath(ovalIn: NSRect(x: 165, y: 55, width: 390, height: 390)), relativeCenterPosition: .zero)

NSColor(calibratedWhite: 1, alpha: 0.035).setStroke()
for x in stride(from: 0.0, through: size.width, by: 40) {
    let line = NSBezierPath()
    line.move(to: NSPoint(x: x, y: 0))
    line.line(to: NSPoint(x: x, y: size.height))
    line.lineWidth = 1
    line.stroke()
}
for y in stride(from: 0.0, through: size.height, by: 40) {
    let line = NSBezierPath()
    line.move(to: NSPoint(x: 0, y: y))
    line.line(to: NSPoint(x: size.width, y: y))
    line.lineWidth = 1
    line.stroke()
}

let pink = NSColor(calibratedRed: 1, green: 0.25, blue: 0.63, alpha: 1)
let ink = NSColor(calibratedWhite: 0.96, alpha: 1)
let muted = NSColor(calibratedWhite: 0.62, alpha: 1)

// Brand eye.
let eye = NSBezierPath()
eye.move(to: NSPoint(x: 331, y: 395))
eye.curve(to: NSPoint(x: 389, y: 395), controlPoint1: NSPoint(x: 345, y: 415), controlPoint2: NSPoint(x: 375, y: 415))
eye.curve(to: NSPoint(x: 331, y: 395), controlPoint1: NSPoint(x: 375, y: 375), controlPoint2: NSPoint(x: 345, y: 375))
eye.lineWidth = 3
pink.setStroke()
eye.stroke()
pink.setFill()
NSBezierPath(ovalIn: NSRect(x: 353, y: 388, width: 14, height: 14)).fill()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let title = "EYEVOICE"
title.draw(
    in: NSRect(x: 0, y: 344, width: 720, height: 34),
    withAttributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 22, weight: .bold),
        .foregroundColor: ink,
        .kern: 5.0,
        .paragraphStyle: paragraph
    ]
)
"ПЕРЕТАЩИТЕ ПРИЛОЖЕНИЕ В APPLICATIONS".draw(
    in: NSRect(x: 0, y: 315, width: 720, height: 24),
    withAttributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
        .foregroundColor: muted,
        .kern: 1.5,
        .paragraphStyle: paragraph
    ]
)

// Directional cue between the two Finder icons.
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 292, y: 213))
arrow.line(to: NSPoint(x: 420, y: 213))
arrow.move(to: NSPoint(x: 404, y: 229))
arrow.line(to: NSPoint(x: 420, y: 213))
arrow.line(to: NSPoint(x: 404, y: 197))
arrow.lineWidth = 3
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
pink.setStroke()
arrow.stroke()

let betaPanel = NSBezierPath(
    roundedRect: NSRect(x: 44, y: 38, width: 632, height: 70),
    xRadius: 10,
    yRadius: 10
)
NSColor(calibratedRed: 0.08, green: 0.065, blue: 0.08, alpha: 0.96).setFill()
betaPanel.fill()
pink.withAlphaComponent(0.46).setStroke()
betaPanel.lineWidth = 1
betaPanel.stroke()

"[ ! ]  BETA · ЕСЛИ MACOS ЗАБЛОКИРУЕТ ЗАПУСК".draw(
    in: NSRect(x: 62, y: 78, width: 596, height: 18),
    withAttributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
        .foregroundColor: pink,
        .kern: 0.8,
        .paragraphStyle: paragraph
    ]
)
"НАСТРОЙКИ → КОНФИДЕНЦИАЛЬНОСТЬ И БЕЗОПАСНОСТЬ → «ВСЁ РАВНО ОТКРЫТЬ»".draw(
    in: NSRect(x: 54, y: 55, width: 612, height: 18),
    withAttributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
        .foregroundColor: ink,
        .kern: 0.3,
        .paragraphStyle: paragraph
    ]
)

"DRAG TO INSTALL  /  VERSION \(version)".draw(
    in: NSRect(x: 0, y: 14, width: 720, height: 16),
    withAttributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
        .foregroundColor: NSColor(calibratedWhite: 0.42, alpha: 1),
        .kern: 1.2,
        .paragraphStyle: paragraph
    ]
)

NSGraphicsContext.restoreGraphicsState()

let url = URL(fileURLWithPath: output)
try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode DMG artwork")
}
try data.write(to: url)
print(output)
