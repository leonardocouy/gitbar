import AppKit
import Foundation

extension NSImage {
    static func loadImageAsync(from url: URL, completion: @MainActor @escaping (NSImage?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let image = data.flatMap(NSImage.init(data:))
            Task { @MainActor in
                completion(image)
            }
        }.resume()
    }

    func tinted(with color: NSColor) -> NSImage {
        let image = copy() as? NSImage ?? self
        image.lockFocus()
        color.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }

    func resized(to size: NSSize) -> NSImage {
        guard self.size != size else { return self }

        let image = NSImage(size: size)
        image.lockFocus()
        draw(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()
        return image
    }
}
