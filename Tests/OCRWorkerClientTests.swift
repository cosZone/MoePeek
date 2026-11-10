import Darwin
import Foundation
import Testing
@testable import MoePeek

@Suite(.timeLimit(.minutes(1)))
struct OCRWorkerClientTests {
    @Test func sequentialRequestsReleaseTheSlot() async throws {
        let fixture = try WorkerFixture(script: WorkerFixture.success)
        defer { fixture.remove() }
        let client = OCRWorkerClient(executableURL: fixture.executable)
        #expect(try await client.recognizeText(at: fixture.image, timeout: 5) == "recognized")
        #expect(try await client.recognizeText(at: fixture.image, timeout: 5) == "recognized")
    }

    @Test func concurrentRequestsNeverOverlapEvenForTheSameImage() async throws {
        let fixture = try WorkerFixture(script: """
        /bin/mkdir "$1.active" || exit 99
        /bin/sleep 0.03
        /bin/rmdir "$1.active"
        \(WorkerFixture.success)
        """)
        defer { fixture.remove() }
        let client = OCRWorkerClient(executableURL: fixture.executable)
        try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<8 {
                group.addTask { try await client.recognizeText(at: fixture.image, timeout: 5) }
            }
            for try await result in group { #expect(result == "recognized") }
        }
    }

    @Test func largeOutputAndDiagnosticsCannotFillAPipe() async throws {
        let fixture = try WorkerFixture(script: """
        /usr/bin/awk 'BEGIN { for (i=0;i<200000;i++) printf "x" }' >&2
        /usr/bin/awk 'BEGIN { printf "{\\"text\\":\\""; for (i=0;i<200000;i++) printf "x"; printf "\\",\\"duration\\":0}" }'
        """)
        defer { fixture.remove() }
        let client = OCRWorkerClient(executableURL: fixture.executable)
        #expect(try await client.recognizeText(at: fixture.image, timeout: 5).count == 200_000)
    }

    @Test func timeoutReapsAWorkerThatIgnoresTerminationAndAllowsAnotherRequest() async throws {
        let fixture = try WorkerFixture(script: """
        if [ -f "$1.block" ]; then
            echo $$ > "$1.pid"
            trap '' TERM
            exec /bin/sleep 30
        fi
        \(WorkerFixture.success)
        """)
        defer { fixture.remove() }
        try Data().write(to: fixture.image.appendingPathExtension("block"))
        let client = OCRWorkerClient(executableURL: fixture.executable)
        // Give the shell time to start under a loaded test host. Verify it is running
        // before checking that the deadline can reap a child which ignores SIGTERM.
        let work = Task { try await client.recognizeText(at: fixture.image, timeout: 5) }
        try await fixture.waitForStart()
        do {
            _ = try await work.value
            Issue.record("Expected timeout")
        } catch OCRError.timeout {}
        try fixture.expectWorkerExited()
        try FileManager.default.removeItem(at: fixture.image.appendingPathExtension("block"))
        #expect(try await client.recognizeText(at: fixture.image, timeout: 5) == "recognized")
    }

    @Test func cancellationReapsOnlyTheActiveWorker() async throws {
        let fixture = try WorkerFixture(script: """
        echo $$ > "$1.pid"
        exec /bin/sleep 30
        """)
        defer { fixture.remove() }
        let client = OCRWorkerClient(executableURL: fixture.executable)
        let active = Task { try await client.recognizeText(at: fixture.image, timeout: 20) }
        try await fixture.waitForStart()
        let queued = Task { try await client.recognizeText(at: fixture.image, timeout: 20) }
        await Task.yield()
        queued.cancel()
        do {
            _ = try await queued.value
            Issue.record("Expected queued cancellation")
        } catch is CancellationError {}
        let pid = try fixture.workerPID()
        #expect(kill(pid, 0) == 0)
        active.cancel()
        do {
            _ = try await active.value
            Issue.record("Expected active cancellation")
        } catch is CancellationError {}
        try fixture.expectWorkerExited()
    }

    @Test func foregroundRequestPreemptsWarmup() async throws {
        let fixture = try WorkerFixture(script: """
        if [ "$MOEPEEK_OCR_WARMUP" = 1 ]; then
            echo $$ > "$1.pid"
            exec /bin/sleep 30
        fi
        \(WorkerFixture.success)
        """)
        defer { fixture.remove() }
        let client = OCRWorkerClient(executableURL: fixture.executable)
        let warmup = Task { try await client.recognizeText(at: fixture.image, timeout: 20, warmup: true) }
        try await fixture.waitForStart()
        #expect(try await client.recognizeText(at: fixture.image, timeout: 5) == "recognized")
        do {
            _ = try await warmup.value
            Issue.record("Expected warmup cancellation")
        } catch is CancellationError {}
        try fixture.expectWorkerExited()
    }

    @Test func failuresReleaseTheSlotAndPreserveDiagnostics() async throws {
        let fixture = try WorkerFixture(script: """
        if [ -f "$1.fail" ]; then
            echo 'invalid-image' >&2
            exit 65
        fi
        \(WorkerFixture.success)
        """)
        defer { fixture.remove() }
        try Data().write(to: fixture.image.appendingPathExtension("fail"))
        let client = OCRWorkerClient(executableURL: fixture.executable)
        do {
            _ = try await client.recognizeText(at: fixture.image, timeout: 5)
            Issue.record("Expected worker failure")
        } catch let OCRError.workerFailed(status, reason) {
            #expect(status == 65)
            #expect(reason == "invalid-image")
        }
        try FileManager.default.removeItem(at: fixture.image.appendingPathExtension("fail"))
        #expect(try await client.recognizeText(at: fixture.image, timeout: 5) == "recognized")
    }

    @Test func invalidResponseIsReported() async throws {
        let fixture = try WorkerFixture(script: "echo invalid-json")
        defer { fixture.remove() }
        let client = OCRWorkerClient(executableURL: fixture.executable)
        do {
            _ = try await client.recognizeText(at: fixture.image, timeout: 5)
            Issue.record("Expected invalid response")
        } catch OCRError.workerResponseInvalid {}
    }

    @Test func missingExecutableReleasesTheSlot() async throws {
        let fixture = try WorkerFixture(script: WorkerFixture.success)
        defer { fixture.remove() }
        try FileManager.default.removeItem(at: fixture.executable)
        let client = OCRWorkerClient(executableURL: fixture.executable)
        do {
            _ = try await client.recognizeText(at: fixture.image)
            Issue.record("Expected missing worker")
        } catch OCRError.workerUnavailable {}
        try ("#!/bin/sh\n" + WorkerFixture.success).write(
            to: fixture.executable, atomically: true, encoding: .utf8
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.executable.path)
        #expect(try await client.recognizeText(at: fixture.image, timeout: 5) == "recognized")
    }

    @Test func cancellationBeforeLaunchDoesNotLeaveTheQueueBusy() async throws {
        let fixture = try WorkerFixture(script: WorkerFixture.success)
        defer { fixture.remove() }
        let client = OCRWorkerClient(executableURL: fixture.executable)
        let cancelled = Task { try await client.recognizeText(at: fixture.image, timeout: 5) }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {}
        #expect(try await client.recognizeText(at: fixture.image, timeout: 5) == "recognized")
    }
}

private struct WorkerFixture: Sendable {
    static let success = #"printf '{"text":"recognized","duration":0}'"#
    let directory: URL
    let executable: URL
    let image: URL

    init(script: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ocr test \(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        executable = directory.appendingPathComponent("worker")
        image = directory.appendingPathComponent("capture with spaces.png")
        try ("#!/bin/sh\n" + script + "\n").write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }

    func waitForStart() async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: image.appendingPathExtension("pid").path) {
            guard ContinuousClock.now < deadline else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func workerPID() throws -> Int32 {
        let contents = try String(contentsOf: image.appendingPathExtension("pid"), encoding: .utf8)
        return try #require(Int32(contents.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    func expectWorkerExited() throws {
        let pid = try workerPID()
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
    }
}
