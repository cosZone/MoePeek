import Foundation
import os

/// Runs OCR in a one-shot helper process so Vision state is not resident in MoePeek.
enum OCRWorkerClient {
    private static let logger = Logger(subsystem: "com.nahida.MoePeek", category: "OCRWorker")
    private static let inFlightLock = NSLock()
    private nonisolated(unsafe) static var inFlightTask: InFlightWorker?
    private static let activeProcessLock = NSLock()
    private nonisolated(unsafe) static var activeProcess: Process?

    struct Output: Codable, Sendable {
        let text: String
        let duration: TimeInterval
    }

    private final class InFlightWorker: @unchecked Sendable {
        let imageURL: URL
        let isWarmup: Bool
        let task: Task<String, Error>

        init(imageURL: URL, isWarmup: Bool, operation: @escaping @Sendable () async throws -> String) {
            self.imageURL = imageURL
            self.isWarmup = isWarmup
            self.task = Task(operation: operation)
        }
    }

    static func recognizeText(
        at imageURL: URL,
        timeout: TimeInterval = 45,
        warmup: Bool = false
    ) async throws -> String {
        inFlightLock.lock()
        defer { inFlightLock.unlock() }

        while let currentTask = inFlightTask {
            if currentTask.imageURL.path == imageURL.path {
                let awaitedTask = currentTask
                inFlightLock.unlock()
                defer { inFlightLock.lock() }
                return try await awaitedTask.task.value
            }
            inFlightLock.unlock()
            _ = try? await currentTask.task.value
            inFlightLock.lock()
        }

        let workerTask = InFlightWorker(imageURL: imageURL, isWarmup: warmup) {
            try await performWorker(imageURL: imageURL, timeout: timeout, warmup: warmup)
        }
        inFlightTask = workerTask
        do {
            let text = try await workerTask.task.value
            clearInFlightTask(workerTask)
            return text
        } catch {
            clearInFlightTask(workerTask)
            throw error
        }
    }

    private static func clearInFlightTask(_ workerTask: InFlightWorker) {
        inFlightLock.lock()
        if inFlightTask === workerTask {
            inFlightTask = nil
        }
        inFlightLock.unlock()
    }

    private static func performWorker(
        imageURL: URL,
        timeout: TimeInterval,
        warmup: Bool
    ) async throws -> String {
        try await withThrowingTaskGroup(of: Output.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try await runWorker(imageURL: imageURL, warmup: warmup)
                } onCancel: {
                    // A stalled Vision process must not outlive its deadline.
                    activeProcessLock.lock()
                    let process = activeProcess
                    activeProcessLock.unlock()
                    process?.terminate()
                }
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
        let executableURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/MoePeekOCRWorker")

        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
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
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        setActiveProcess(process)
        let data = try await withCheckedThrowingContinuation { continuation in
            let gate = ProcessContinuationGate()
            process.terminationHandler = { terminated in
                guard gate.claimOnce() else { return }
                if terminated.terminationStatus == 0 {
                    let output = stdout.fileHandleForReading.readDataToEndOfFile()
                    logWorkerDiagnostics(
                        stderr: stderr.fileHandleForReading.readDataToEndOfFile(),
                        status: terminated.terminationStatus
                    )
                    continuation.resume(returning: output)
                } else {
                    let diagnostics = stderr.fileHandleForReading.readDataToEndOfFile()
                    logWorkerDiagnostics(stderr: diagnostics, status: terminated.terminationStatus)
                    continuation.resume(
                        throwing: OCRError.workerFailed(
                            terminated.terminationStatus,
                            reason: String(
                                decoding: diagnostics,
                                as: UTF8.self
                            ).trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    )
                }
            }
        }

        setActiveProcess(nil)

        do {
            return try JSONDecoder().decode(Output.self, from: data)
        } catch {
            logger.error("Could not decode OCR worker output: \(String(decoding: data, as: UTF8.self), privacy: .public)")
            throw OCRError.workerResponseInvalid
        }
    }

    private static func setActiveProcess(_ process: Process?) {
        activeProcessLock.lock()
        activeProcess = process
        activeProcessLock.unlock()
    }

    private static func logWorkerDiagnostics(stderr: Data, status: Int32) {
        let diagnostics = String(decoding: stderr, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !diagnostics.isEmpty else { return }
        logger.error("OCR worker exit \(status, privacy: .public): \(diagnostics, privacy: .public)")
    }
}
