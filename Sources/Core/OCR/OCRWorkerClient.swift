import Foundation
import os

/// Runs OCR in a one-shot helper process so Vision state is not resident in MoePeek.
enum OCRWorkerClient {
    private static let logger = Logger(subsystem: "com.nahida.MoePeek", category: "OCRWorker")

    struct Output: Codable, Sendable {
        let text: String
        let duration: TimeInterval
    }

    static func recognizeText(
        at imageURL: URL,
        timeout: TimeInterval = 45,
        warmup: Bool = false
    ) async throws -> String {
        try await withThrowingTaskGroup(of: Output.self) { group in
            group.addTask {
                try await runWorker(imageURL: imageURL, warmup: warmup)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw OCRError.timeout
            }

            guard let first = try await group.next() else { throw OCRError.timeout }
            group.cancelAll()
            return first.text
        }
    }

    private static func runWorker(imageURL: URL, warmup: Bool) async throws -> Output {
        let executableURL = Bundle.main.url(
            forResource: "MoePeekOCRWorker",
            withExtension: nil,
            subdirectory: "Contents/MacOS"
        ) ?? Bundle.main.url(forResource: "MoePeekOCRWorker", withExtension: nil)

        guard let executableURL else {
            logger.error("OCR worker executable is missing from the app bundle")
            throw OCRError.workerUnavailable
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [imageURL.path]
        if warmup {
            process.environment = ProcessInfo.processInfo.environment.merging(
                ["MOEPEEK_OCR_WARMUP": "1"]
            ) { _, newValue in newValue }
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        let data = try await withCheckedThrowingContinuation { continuation in
            let gate = ProcessContinuationGate()
            process.terminationHandler = { terminated in
                guard gate.claimOnce() else { return }
                if terminated.terminationStatus == 0 {
                    continuation.resume(returning: pipe.fileHandleForReading.readDataToEndOfFile())
                } else {
                    continuation.resume(throwing: OCRError.workerFailed(terminated.terminationStatus))
                }
            }
        }

        do {
            return try JSONDecoder().decode(Output.self, from: data)
        } catch {
            logger.error("Could not decode OCR worker output: \(String(decoding: data, as: UTF8.self), privacy: .public)")
            throw OCRError.workerResponseInvalid
        }
    }
}
