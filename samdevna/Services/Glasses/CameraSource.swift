import CoreGraphics
import Foundation
import UIKit

/// Where Lens, the guide and "Fix it together" get their picture from.
enum CameraSource: String, CaseIterable, Identifiable, Sendable {
    case iPhone = "iphone"
    case glasses = "glasses"

    var id: String { rawValue }
    var label: String { self == .iPhone ? "iPhone" : "Meta glasses" }
    var symbol: String { self == .iPhone ? "iphone" : "eyeglasses" }
}

/// State of the Ray-Ban Meta connection, shown in Settings and on the Lens.
enum GlassesState: Equatable, Sendable {
    case unavailable(String)      // SDK not linked / not configured
    case notRegistered            // needs "Connect" (opens the Meta AI app)
    case registering
    case waitingForDevice         // registered, no glasses in range (or folded / off)
    case needsPermission          // camera permission not granted in Meta AI
    case starting
    case streaming(mock: Bool)
    case error(String)

    var label: String {
        switch self {
        case .unavailable(let why): why
        case .notRegistered: "Not connected"
        case .registering: "Connecting in Meta AI…"
        case .waitingForDevice: "Waiting for glasses (power on, unfold)"
        case .needsPermission: "Allow camera access in Meta AI"
        case .starting: "Starting glasses camera…"
        case .streaming(let mock): mock ? "Streaming · Mock Device (simulated glasses)" : "Streaming from your glasses"
        case .error(let message): message
        }
    }

    var isStreaming: Bool { if case .streaming = self { true } else { false } }
}

/// The latest frames from whichever camera is active, with a short history so a Helper's tap
/// (which refers to the frame they saw, by seq) can be segmented on that exact frame.
final class FrameRing: @unchecked Sendable {
    struct Frame: Sendable {
        let seq: UInt32
        let image: UIImage
        let at: TimeInterval
    }

    private let lock = NSLock()
    private var frames: [Frame] = []
    private var nextSeq: UInt32 = 0
    let capacity: Int

    init(capacity: Int = 36) { self.capacity = capacity }

    @discardableResult
    func push(_ image: UIImage, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Frame {
        lock.lock(); defer { lock.unlock() }
        nextSeq &+= 1
        let frame = Frame(seq: nextSeq, image: image, at: time)
        frames.append(frame)
        if frames.count > capacity { frames.removeFirst(frames.count - capacity) }
        return frame
    }

    var latest: Frame? { lock.lock(); defer { lock.unlock() }; return frames.last }

    /// The frame with `seq`, or the newest one before it (it may have aged out), or the latest.
    func frame(seq: UInt32) -> Frame? {
        lock.lock(); defer { lock.unlock() }
        return frames.last(where: { $0.seq == seq }) ?? frames.last(where: { $0.seq < seq }) ?? frames.last
    }

    func clear() { lock.lock(); frames.removeAll(); lock.unlock() }
}
