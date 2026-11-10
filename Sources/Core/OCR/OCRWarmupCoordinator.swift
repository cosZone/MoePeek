import CoreGraphics
import CoreText
import Foundation
import IOKit
import ImageIO
import os

/// Best-effort warmup of OS caches. A fresh helper still has to initialize its own Vision runtime.
@MainActor
enum OCRWarmupCoordinator {
    private static let logger = Logger(subsystem: "com.nahida.MoePeek", category: "OCRWarmup")
    private static let warmupVersion = 2
    private static var warmupTask: Task<Void, Never>?

    private static var warmupStateKey: String {
        let bootTime = systemBootTime()
        return "ocrWarmup.v\(warmupVersion).boot.\(bootTime)"
    }

    static func warmUpIfNeeded() {
        let key = warmupStateKey
        let defaults = UserDefaults.standard
        guard warmupTask == nil, !defaults.bool(forKey: key) else { return }

        warmupTask = Task(priority: .utility) {
            defer { warmupTask = nil }
            do {
                let started = Date()
                let url = try writeWarmupImage()
                defer { try? FileManager.default.removeItem(at: url) }
                _ = try await OCRWorkerClient.recognizeText(at: url, warmup: true)
                defaults.set(true, forKey: key)
                cleanupOldWarmupKeys(currentKey: key)
                logger.info("OCR warmup completed in \(Date().timeIntervalSince(started), privacy: .public) seconds")
            } catch is CancellationError {
                // A later app run or real OCR request can warm Vision again.
            } catch {
                logger.error("OCR warmup failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private static func writeWarmupImage() throws -> URL {
        let width = 640
        let height = 120
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
        // Exercise real scripts so warmup also initializes non-Latin recognizers.
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String):
                CTFontCreateWithName("Helvetica" as CFString, 28, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                CGColor(gray: 0, alpha: 1),
        ]
        for (index, text) in ["MoePeek OCR 123", "文字识别 日本語 한국어"].enumerated() {
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: text, attributes: attributes)
            )
            context.textPosition = CGPoint(x: 12, y: 76 - index * 48)
            CTLineDraw(line, context)
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
