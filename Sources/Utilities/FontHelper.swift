import AppKit
import SwiftUI

extension Font {
    static func popup(name: String, size: CGFloat) -> Font {
        name.isEmpty ? .system(size: size) : .custom(name, size: size)
    }
}

extension NSFont {
    static func popup(name: String, size: CGFloat) -> NSFont {
        if name.isEmpty { return .systemFont(ofSize: size) }
        return NSFont(name: name, size: size) ?? .systemFont(ofSize: size)
    }

    var lineHeight: CGFloat {
        ceil(ascender - descender + leading)
    }
}
