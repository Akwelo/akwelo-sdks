import Foundation

/// Resumes exactly once, whichever caller gets there first.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

/// The value of `work`, or nil when it has not answered within `timeout` seconds.
///
/// A task group would not do: it waits for every child before returning, and the system calls
/// behind `work` (App Attest) do not stop when cancelled. `work` is left to finish on its own.
func firstResult<T: Sendable>(within timeout: TimeInterval, _ work: @escaping @Sendable () async -> T?) async -> T? {
    await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
        let once = Once()
        Task {
            let value = await work()
            if once.claim() { continuation.resume(returning: value) }
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
            if once.claim() { continuation.resume(returning: nil) }
        }
    }
}
