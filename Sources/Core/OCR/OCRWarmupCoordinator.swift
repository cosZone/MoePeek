import Foundation
import IOKit
import AppKit
import os

/// Warms macOS' system Vision cache once per boot without keeping Vision loaded in MoePeek.
enum OCRWarmupCoordinator: Sendable {
    private static let logger = Logger(subsystem: "com.nahida.MoePeek", category: "OCRWarmup")
    private static let warmupVersion = 1

    private static var warmupStateKey: String {
        let bootTime = systemBootTime()
        return "ocrWarmup.v\(warmupVersion).boot.\(bootTime)"
    }

    static func warmUpIfNeeded() {
        let key = warmupStateKey
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        cleanupOldWarmupKeys(currentKey: key)

        Task.detached(priority: .utility) {
            do {
                let started = Date()
                let url = try writeWarmupImage()
                defer { try? FileManager.default.removeItem(at: url) }
                _ = try await OCRWorkerClient.recognizeText(at: url)
                logger.info("OCR warmup completed in \(Date().timeIntervalSince(started), privacy: .public) seconds")
            } catch is CancellationError {
                // A later app run or real OCR request can warm Vision again.
            } catch {
                logger.error("OCR warmup failed: \(String(describing: error), privacy: .public)")
                UserDefaults.standard.set(false, forKey: key)
            }
        }
    }

    private static func writeWarmupImage() throws -> URL {
        let size = NSSize(width: 128, height: 32)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.black,
        ]
        "OCR 0".draw(at: NSPoint(x: 8, y: 7), withAttributes: attributes)
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw OCRError.warmupImageCreationFailed
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("moepeek_ocr_warmup_\(UUID().uuidString).png")
        try png.write(to: url, options: .atomic)
        return url
    }

    private static func systemBootTime() -> String {
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        var bootTime = timeval()
        var length = MemoryLayout<timeval>.size
        let result = sysctl(&mib, 2, &bootTime, &length, nil, 0)
        return result == 0 ? "\(bootTime.tv_sec)" : "unknown"
    }

    private static func cleanupOldWarmupKeys(currentKey: String) {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("ocrWarmup.") && key != currentKey {
            defaults.removeObject(forKey: key)
        }
    }
}
