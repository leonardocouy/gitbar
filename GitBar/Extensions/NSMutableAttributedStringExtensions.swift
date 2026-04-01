import AppKit
import Foundation

extension NSMutableAttributedString {
    @discardableResult
    func appendString(_ string: String, color: NSColor = .secondaryLabelColor, font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)) -> NSMutableAttributedString {
        append(NSAttributedString(string: string, attributes: [
            .foregroundColor: color,
            .font: font,
        ]))
        return self
    }

    @discardableResult
    func appendSeparator() -> NSMutableAttributedString {
        append(NSAttributedString(string: "   "))
        return self
    }

    @discardableResult
    func appendNewLine() -> NSMutableAttributedString {
        append(NSAttributedString(string: "\n"))
        return self
    }

    @discardableResult
    @MainActor
    func appendIcon(named name: String, color: NSColor = .secondaryLabelColor, size: NSSize = .init(width: 12, height: 12)) -> NSMutableAttributedString {
        guard let image = NSImage(named: name)?.tinted(with: color) else { return self }
        image.size = size

        let attachment = NSTextAttachment()
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
        attachment.image = image

        let icon = NSMutableAttributedString(attachment: attachment)
        let range = NSRange(location: 0, length: icon.length)
        icon.addAttribute(.baselineOffset, value: -1.0, range: range)
        append(icon)
        appendString(" ")
        return self
    }
}

func hexColor(_ hex: String) -> NSColor {
    var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    hex = hex.replacingOccurrences(of: "#", with: "")

    guard hex.count == 6, let value = Int(hex, radix: 16) else {
        return .secondaryLabelColor
    }

    return NSColor(
        red: CGFloat((value >> 16) & 0xFF) / 255.0,
        green: CGFloat((value >> 8) & 0xFF) / 255.0,
        blue: CGFloat(value & 0xFF) / 255.0,
        alpha: 1
    )
}
