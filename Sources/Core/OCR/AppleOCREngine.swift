import Foundation
@preconcurrency import Vision

/// A process-wide Vision OCR engine modeled after Easydict's mature implementation.
///
/// The engine deliberately keeps its serialization state outside the caller's actor: a
/// coordinator or SwiftUI task may time out, while the underlying Vision request keeps
/// ownership of the single accurate-recognition slot until it exits.
enum AppleOCREngine: Sendable {
    /// A timed-out accurate attempt gets one bounded fast fallback, matching Easydict.
    ///
    /// The first system Vision load can exceed this deadline. The timeout still keeps requests
    /// bounded, prevents work from piling up, and mirrors Easydict's production behavior.
    private static let recognitionTimeout: TimeInterval = 5

    /// Easydict uses a lock rather than an actor here so slot ownership survives caller
    /// cancellation and cannot be starved by actor-isolated work.
    private static let accurateRecognitionLock = NSLock()
    private nonisolated(unsafe) static var hasAccurateRecognitionInFlight = false

    static func recognizeText(in image: CGImage) async throws -> String {
        let observations = try await performVisionOCR(on: image)
        return observations
            .map(\.text)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    private static func performVisionOCR(on cgImage: CGImage) async throws -> [RecognizedLine] {
        // Easydict found the modern request unstable on macOS 15 and enables it only on 26+.
        if #available(macOS 26.0, *) {
            return try await performModernVisionOCRWithFallback(on: cgImage)
        }
        return try await performLegacyVisionOCR(on: cgImage)
    }

    // MARK: - Legacy API

    private static func performLegacyVisionOCR(on cgImage: CGImage) async throws -> [RecognizedLine] {
        let observations = try await performSingleLegacyVisionOCR(on: cgImage)

        // Easydict found Japanese samples that auto language detection misses entirely.
        if observations.isEmpty {
            return try await performSingleLegacyVisionOCR(
                on: cgImage,
                recognitionLanguages: ["ja-JP"],
                automaticallyDetectsLanguage: false
            )
        }
        return observations
    }

    private static func performSingleLegacyVisionOCR(
        on cgImage: CGImage,
        recognitionLanguages: [String] = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"],
        automaticallyDetectsLanguage: Bool = true
    ) async throws -> [RecognizedLine] {
        try await withCheckedThrowingContinuation { continuation in
            let continuationGate = ContinuationGate(continuation: continuation)
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuationGate.resume(throwing: OCRError.recognitionFailed(error))
                    return
                }

                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                continuationGate.resume(
                    returning: observations.compactMap { observation in
                        guard let candidate = observation.topCandidates(1).first else { return nil }
                        return RecognizedLine(text: candidate.string)
                    }
                )
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = recognitionLanguages
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = automaticallyDetectsLanguage

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuationGate.resume(throwing: OCRError.recognitionFailed(error))
                }
            }
        }
    }

    // MARK: - Modern API

    @available(macOS 26.0, *)
    private static func performModernVisionOCRWithFallback(on cgImage: CGImage) async throws -> [RecognizedLine] {
        do {
            return try await TaskTimeout.withTimeout(seconds: recognitionTimeout) {
                while !claimAccurateRecognition() {
                    try await Task.sleep(for: .milliseconds(50))
                }
                defer { releaseAccurateRecognition() }
                try Task.checkCancellation()
                return try await performModernVisionOCR(
                    on: cgImage,
                    recognitionLevel: .accurate
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
        }

        do {
            return try await TaskTimeout.withTimeout(seconds: recognitionTimeout) {
                try await performModernVisionOCR(on: cgImage, recognitionLevel: .fast)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw OCRError.timeout
        }
    }

    @available(macOS 26.0, *)
    private static func performModernVisionOCR(
        on cgImage: CGImage,
        recognitionLevel: RecognizeTextRequest.RecognitionLevel
    ) async throws -> [RecognizedLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = recognitionLevel
        request.recognitionLanguages = [
            Locale.Language(identifier: "zh-Hans"),
            Locale.Language(identifier: "zh-Hant"),
            Locale.Language(identifier: "en-US"),
            Locale.Language(identifier: "ja-JP"),
            Locale.Language(identifier: "ko-KR"),
        ]
        request.usesLanguageCorrection = recognitionLevel == .accurate
        request.automaticallyDetectsLanguage = true

        let observations = try await request.perform(on: cgImage)
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedLine(text: candidate.string)
        }
    }

    private static func claimAccurateRecognition() -> Bool {
        accurateRecognitionLock.lock()
        defer { accurateRecognitionLock.unlock() }
        guard !hasAccurateRecognitionInFlight else { return false }
        hasAccurateRecognitionInFlight = true
        return true
    }

    private static func releaseAccurateRecognition() {
        accurateRecognitionLock.lock()
        hasAccurateRecognitionInFlight = false
        accurateRecognitionLock.unlock()
    }
}

private struct RecognizedLine: Sendable {
    let text: String
}

/// Race-safe one-shot continuation wrapper for the legacy callback/perform API.
private final class ContinuationGate<T, E: Error>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, E>?

    init(continuation: CheckedContinuation<T, E>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        takeContinuation()?.resume(returning: value)
    }

    func resume(throwing error: E) {
        takeContinuation()?.resume(throwing: error)
    }

    private func takeContinuation() -> CheckedContinuation<T, E>? {
        lock.lock()
        defer { lock.unlock() }
        let continuation = continuation
        self.continuation = nil
        return continuation
    }
}
