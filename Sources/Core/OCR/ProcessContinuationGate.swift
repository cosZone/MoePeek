import Foundation

/// Atomically claims a one-shot flag. Each instance returns `true` once only.
final class ProcessContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    init() {}

    func claimOnce() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return false }
        resumed = true
        return true
    }
}
