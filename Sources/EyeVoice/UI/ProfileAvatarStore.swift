import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ProfileAvatarStore: ObservableObject {
    static let shared = ProfileAvatarStore()

    @Published private(set) var image: NSImage?

    private let fileURL: URL

    private init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let directory = support.appendingPathComponent("EyeVoice", isDirectory: true)
        fileURL = directory.appendingPathComponent("profile-avatar.png")
        image = NSImage(contentsOf: fileURL)
    }

    func chooseImage() {
        let panel = NSOpenPanel()
        panel.title = "Выберите фото профиля"
        panel.message = "Изображение будет сохранено только на этом Mac."
        panel.prompt = "Выбрать"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]

        guard panel.runModal() == .OK,
              let selectedURL = panel.url,
              let source = NSImage(contentsOf: selectedURL),
              let data = Self.squarePNG(from: source) else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
            image = NSImage(data: data)
        } catch {
            NSSound.beep()
        }
    }

    private static func squarePNG(from image: NSImage) -> Data? {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }

        let side = min(sourceSize.width, sourceSize.height)
        let sourceRect = NSRect(
            x: (sourceSize.width - side) / 2,
            y: (sourceSize.height - side) / 2,
            width: side,
            height: side
        )
        let targetSize = NSSize(width: 512, height: 512)
        let target = NSImage(size: targetSize)

        target.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: sourceRect,
            operation: .copy,
            fraction: 1
        )
        target.unlockFocus()

        guard let tiff = target.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
