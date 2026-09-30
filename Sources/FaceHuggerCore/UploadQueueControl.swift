import Foundation

/// Scheduling and cancellation intent are deliberately independent. A user can
/// restart the queue while the old process is still acknowledging a stop.
public struct UploadQueueControl: Sendable {
    public private(set) var isRunning = false
    public private(set) var activeJobID: UUID?
    private var cancellationRequested = false
    private var preferredJobID: UUID?

    public init() {}

    public mutating func start(preferredJobID: UUID? = nil) {
        isRunning = true
        if let preferredJobID { self.preferredJobID = preferredJobID }
    }

    /// Marks one queued job active before any asynchronous launch work begins.
    public mutating func beginNext(in jobs: [UploadJob]) -> UUID? {
        guard isRunning, activeJobID == nil else { return nil }
        let preferred = jobs.first { $0.id == preferredJobID && $0.state == .queued }
        guard let next = preferred ?? jobs.first(where: { $0.state == .queued }) else {
            isRunning = false
            preferredJobID = nil
            return nil
        }
        preferredJobID = nil
        activeJobID = next.id
        cancellationRequested = false
        return next.id
    }

    public mutating func stop() {
        isRunning = false
        if activeJobID != nil { cancellationRequested = true }
    }

    /// Rejects stale completion callbacks, and pauses scheduling on a failure.
    /// A successful exit is completion even if a stop arrived just afterward.
    public mutating func finish(_ id: UUID, exitStatus: Int32) -> JobState? {
        guard activeJobID == id else { return nil }
        let state: JobState
        if exitStatus == 0 { state = .completed }
        else if cancellationRequested { state = .stopped }
        else { state = .failed; isRunning = false }
        activeJobID = nil
        cancellationRequested = false
        return state
    }
}
