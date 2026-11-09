import AppKit
enum ScreenCaptureOCR {
    /// Launch interactive screen capture, OCR the captured image, and return recognized text.
    static func captureAndRecognize() async throws -> String {
        // Generate a unique temp file path to avoid concurrency conflicts
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("moepeek_ocr_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        // Run screencapture -i <tmpPath> (interactive selection → temp file, clipboard untouched)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", tmpURL.path]

        let status = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                let resumed = ProcessContinuationGate()

                process.terminationHandler = { proc in
                    guard resumed.claimOnce() else { return }
                    continuation.resume(returning: proc.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    guard resumed.claimOnce() else { return }
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            process.terminate()
        }

        guard !Task.isCancelled else { throw CancellationError() }

        guard status == 0 else {
            throw OCRError.captureCancelled
        }

        // Validate the capture before handing its file path to the helper process.
        try autoreleasepool {
            guard let image = NSImage(contentsOf: tmpURL),
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else {
                throw OCRError.captureReadFailed
            }
        }

        let text = try await OCRWorkerClient.recognizeText(at: tmpURL)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OCRError.noTextRecognized
        }
        return text
    }
}

enum OCRError: LocalizedError {
    case captureCancelled
    case captureReadFailed
    case noTextRecognized
    case timeout
    case recognitionFailed(any Error)
    case workerUnavailable
    case workerFailed(Int32, reason: String = "")
    case workerResponseInvalid
    case warmupImageCreationFailed

    var errorDescription: String? {
        switch self {
        case .captureCancelled:  String(localized: "Screen capture was cancelled")
        case .captureReadFailed: String(localized: "Failed to read the captured image")
        case .noTextRecognized:  String(localized: "No text was recognized in the captured image")
        case .timeout:           String(localized: "Text recognition timed out")
        case .recognitionFailed(let error):
            String(localized: "Vision recognition failed: \(error.localizedDescription)")
        case .workerUnavailable: String(localized: "OCR helper is unavailable")
        case let .workerFailed(status, reason):
            reason.isEmpty
                ? String(localized: "OCR helper exited with status \(status)")
                : String(localized: "OCR helper exited with status \(status): \(reason)")
        case .workerResponseInvalid:
            String(localized: "OCR helper returned an invalid response")
        case .warmupImageCreationFailed:
            String(localized: "Could not create the OCR warmup image")
        }
    }
}
