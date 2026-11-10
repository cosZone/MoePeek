import Foundation

struct TaskTimeoutError: Error, Sendable {}

enum TaskTimeout {
    /// Races an operation against a deadline without blocking a caller actor.
    ///
    /// Like Easydict's implementation, the losing task is cancelled only after the caller has
    /// resumed. That matters for Vision because a timed-out synchronous request may still be
    /// unwinding and must not delay delivery of the timeout to the UI.
    static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let normalizedSeconds = max(seconds, 0)
        guard normalizedSeconds > 0 else { throw TaskTimeoutError() }

        let operationTask = Task<T, Error> { try await operation() }
        let timeoutTask = Task<Void, Error> {
            try await Task.sleep(for: .seconds(normalizedSeconds))
            throw TaskTimeoutError()
        }

        return try await withCheckedThrowingContinuation { continuation in
            let gate = TimeoutContinuationGate(continuation)

            _Concurrency.Task.detached {
                do {
                    let value = try await operationTask.value
                    await gate.resume(with: .success(value))
                    timeoutTask.cancel()
                    return
                } catch {
                    await gate.resume(with: .failure(error))
                    timeoutTask.cancel()
                    return
                }
            }

            _Concurrency.Task.detached {
                do {
                    try await timeoutTask.value
                } catch is CancellationError {
                    // The operation won the race.
                    return
                } catch {
                    await gate.resume(with: .failure(error))
                    operationTask.cancel()
                    return
                }
            }
        }
    }
}

private actor TimeoutContinuationGate<T: Sendable> {
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<T, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}
