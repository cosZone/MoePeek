import CoreGraphics
import Foundation
import IOKit
import ImageIO
import os

/// Warms macOS' system Vision cache once per boot without keeping Vision loaded in MoePeek.
enum OCRWarmupCoordinator {
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
                _ = try await OCRWorkerClient.recognizeText(at: url, timeout: 90, warmup: true)
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
        let width = 128
        let height = 32
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw OCRError.warmupImageCreationFailed
        }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        // Bold synthetic strokes exercise text detection without AppKit font rendering.
        let strokes: [(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)] = [
            (8, 7, 4, 18), (8, 7, 14, 4), (8, 14, 10, 4), (8, 21, 14, 4),
            (30, 7, 4, 18), (34, 7, 12, 4), (30, 7, 4, 4),
            (54, 7, 14, 4), (59, 7, 4, 18), (54, 21, 14, 4), (59, 13, 9, 4),
            (78, 7, 14, 18),
        ]
        for stroke in strokes {
            context.fill(
                CGRect(
                    x: stroke.x,
                    y: stroke.y,
                    width: stroke.width,
                    height: stroke.height
                )
            )
        }

        guard let image = context.makeImage() else {
            throw OCRError.warmupImageCreationFailed
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("moepeek_ocr_warmup_\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        ) else {
            throw OCRError.warmupImageCreationFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            throw OCRError.warmupImageCreationFailed
        }
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
