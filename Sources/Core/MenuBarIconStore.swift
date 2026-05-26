import AppKit
import Defaults
import Foundation

/// Manages on-disk storage for the user-supplied menu bar icon.
///
/// Files are stored under `Application Support/MoePeek/` with a fixed basename
/// (`menuBarIcon.<ext>`) so we can locate the icon without persisting a path.
@MainActor
enum MenuBarIconStore {
    static let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "svg", "pdf", "tiff", "icns"]

    /// Recommended on-screen point size for a macOS menu bar icon.
    static let recommendedPointSize: CGFloat = 18

    /// Hard upper bound — anything larger is almost certainly wrong for a status item.
    static let maxFileSize: Int = 2 * 1024 * 1024 // 2 MB

    enum ImportError: LocalizedError {
        case unsupportedFormat
        case fileTooLarge
        case invalidImage
        case copyFailed(Error)

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat:
                String(localized: "Unsupported image format. Use PNG, JPG, SVG, PDF, TIFF, or ICNS.")
            case .fileTooLarge:
                String(localized: "Image file too large. Maximum 2 MB.")
            case .invalidImage:
                String(localized: "Could not decode image.")
            case .copyFailed(let error):
                String(localized: "Failed to save image: \(error.localizedDescription)")
            }
        }
    }

    /// Validate, copy into Application Support, bump the revision counter so observers refresh.
    @discardableResult
    static func importIcon(from sourceURL: URL) throws -> URL {
        let ext = sourceURL.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            throw ImportError.unsupportedFormat
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
        if let size = attrs[.size] as? Int, size > maxFileSize {
            throw ImportError.fileTooLarge
        }

        guard NSImage(contentsOf: sourceURL) != nil else {
            throw ImportError.invalidImage
        }

        let directory = try ensureCustomIconDirectory()

        // Wipe any pre-existing icon (possibly a different extension) so the lookup is unambiguous.
        removeCustomIconFiles()

        let destURL = directory.appendingPathComponent("menuBarIcon.\(ext)")
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        } catch {
            throw ImportError.copyFailed(error)
        }

        Defaults[.menuBarCustomIconRevision] += 1
        return destURL
    }

    static func removeCustomIcon() {
        removeCustomIconFiles()
        Defaults[.menuBarCustomIconRevision] += 1
    }

    /// Loads the custom icon sized for the menu bar, applying the template flag.
    /// Returns nil when no custom icon is present.
    static func loadCustomIcon(isTemplate: Bool) -> NSImage? {
        guard let url = currentCustomIconURL, let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.size = NSSize(width: recommendedPointSize, height: recommendedPointSize)
        image.isTemplate = isTemplate
        return image
    }

    // MARK: - Private

    private static var customIconDirectory: URL {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return supportDir.appendingPathComponent("MoePeek", isDirectory: true)
    }

    private static func ensureCustomIconDirectory() throws -> URL {
        let directory = customIconDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static var currentCustomIconURL: URL? {
        let directory = customIconDirectory
        for ext in supportedExtensions {
            let url = directory.appendingPathComponent("menuBarIcon.\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private static func removeCustomIconFiles() {
        let directory = customIconDirectory
        for ext in supportedExtensions {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("menuBarIcon.\(ext)"))
        }
    }
}
