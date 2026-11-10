import Darwin
import Foundation
import os

/// Serializes one-shot helpers without loading Vision into the menu bar process.
actor OCRWorkerClient {
    static let shared = OCRWorkerClient()
    private static let logger = Logger(subsystem: "com.nahida.MoePeek", category: "OCRWorker")
    private let executableURL: URL
    private var busy = false
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []
    private var currentInvocation: OCRWorkerInvocation?
    private var isWarmingUp = false

    struct Output: Codable, Sendable {
        let text: String
        let duration: TimeInterval
    }

    init(executableURL: URL = Bundle.main.bundleURL
        .appendingPathComponent("Contents/MacOS/MoePeekOCRWorker")) {
        self.executableURL = executableURL
    }

    static func recognizeText(
        at imageURL: URL,
        // Cold OS model compilation must finish once before later processes can reuse it.
        timeout: TimeInterval = 120,
        warmup: Bool = false
    ) async throws -> String {
        try await shared.recognizeText(at: imageURL, timeout: timeout, warmup: warmup)
    }

    func recognizeText(
        at imageURL: URL,
        timeout: TimeInterval = 120,
        warmup: Bool = false
    ) async throws -> String {
        try Task.checkCancellation()
        // Startup work must never delay a user-initiated capture.
        if warmup, busy { throw CancellationError() }
        if !warmup, isWarmingUp { currentInvocation?.cancel() }
        try await acquireSlot()
        defer { releaseSlot() }
        try Task.checkCancellation()

        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw OCRError.workerUnavailable
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("moepeek_ocr_worker_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("result.json")
        let diagnosticsURL = directory.appendingPathComponent("diagnostics.log")
        let invocation = OCRWorkerInvocation()
        currentInvocation = invocation
        isWarmingUp = warmup
        defer {
            currentInvocation = nil
            isWarmingUp = false
        }
        let status = try await invocation.run(
            executableURL: executableURL, imageURL: imageURL, warmup: warmup,
            timeout: timeout, outputURL: outputURL, diagnosticsURL: diagnosticsURL
        )
        let diagnostics = (try? String(contentsOf: diagnosticsURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard status == 0 else {
            Self.logger.error("OCR worker exit \(status, privacy: .public): \(diagnostics, privacy: .public)")
            throw OCRError.workerFailed(status, reason: diagnostics)
        }
        try Task.checkCancellation()
        do {
            return try JSONDecoder().decode(Output.self, from: Data(contentsOf: outputURL)).text
        } catch {
            throw OCRError.workerResponseInvalid
        }
    }

    private func acquireSlot() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if busy {
                    waiters.append((id, continuation))
                } else {
                    busy = true
                    continuation.resume()
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func releaseSlot() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }
}

/// All process state lives on this queue, including launch, cancellation and exit callbacks.
/// Each request owns its child; cancelling one can never terminate a later request's child.
private final class OCRWorkerInvocation: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.nahida.MoePeek.OCRWorker")
    private var process: Process?
    private var continuation: CheckedContinuation<Int32, Error>?
    private var terminalError: (any Error)?
    private var deadline: DispatchWorkItem?
    private var outputHandles: [FileHandle] = []
    private var finished = false

    func run(
        executableURL: URL, imageURL: URL, warmup: Bool,
        timeout: TimeInterval, outputURL: URL, diagnosticsURL: URL
    ) async throws -> Int32 {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    self.continuation = continuation
                    if let error = self.terminalError {
                        self.finish(.failure(error))
                        return
                    }
                    guard timeout.isFinite, timeout > 0 else {
                        self.finish(.failure(OCRError.timeout))
                        return
                    }
                    do {
                        let child = Process()
                        child.executableURL = executableURL
                        child.arguments = [imageURL.path]
                        if warmup {
                            child.environment = ProcessInfo.processInfo.environment.merging(
                                ["MOEPEEK_OCR_WARMUP": "1"]
                            ) { _, newValue in newValue }
                        }
                        // Files avoid pipe-buffer deadlocks on large OCR results or diagnostics.
                        for url in [outputURL, diagnosticsURL] {
                            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                                throw CocoaError(.fileWriteUnknown)
                            }
                            self.outputHandles.append(try FileHandle(forWritingTo: url))
                        }
                        child.standardOutput = self.outputHandles[0]
                        child.standardError = self.outputHandles[1]
                        child.terminationHandler = { [weak self] terminated in
                            guard let self else { return }
                            self.queue.async {
                                if let error = self.terminalError {
                                    self.finish(.failure(error))
                                } else {
                                    self.finish(.success(terminated.terminationStatus))
                                }
                            }
                        }
                        self.process = child
                        try child.run()
                        let deadline = DispatchWorkItem { [weak self] in
                            self?.stop(with: OCRError.timeout)
                        }
                        self.deadline = deadline
                        self.queue.asyncAfter(deadline: .now() + timeout, execute: deadline)
                    } catch {
                        self.finish(.failure(error))
                    }
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        queue.async { self.stop(with: CancellationError()) }
    }

    private func stop(with error: any Error) {
        guard !finished, terminalError == nil else { return }
        terminalError = error
        if let process, process.isRunning {
            // Vision can ignore cooperative cancellation (and SIGTERM). Reap the child
            // before releasing the slot or deleting files it may still be reading.
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private func finish(_ result: Result<Int32, Error>) {
        guard !finished else { return }
        finished = true
        deadline?.cancel()
        deadline = nil
        process?.terminationHandler = nil
        process = nil
        for handle in outputHandles { try? handle.close() }
        outputHandles.removeAll()
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }
}
