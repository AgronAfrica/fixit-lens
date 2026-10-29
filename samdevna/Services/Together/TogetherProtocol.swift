import CoreGraphics
import Foundation

/// Wire protocol for "Fix it together", shared with the relay (`relay/src/room.js`) and the web helper (`web/`).
///
/// Control messages are JSON text frames: `{"t": "<type>", ...}`.
/// Media are binary frames: 1 byte kind + 4 byte big-endian sequence number + payload.
///   kind 0x01 = JPEG video frame (Fixer → Helpers)
///   kind 0x02 = WAV clip (Helper → Fixer, for Muse Voice Transcribe on the Fixer's phone)
///
/// All Meta model calls run on the Fixer's phone (its key never leaves the device); Helpers are thin clients.
enum Together {
    /// Max people in a room: the Fixer plus up to three Helpers. Keeps rooms small and the relay cheap.
    static let maxPeers = 4

    /// Join codes avoid look-alike characters (no 0/O, 1/I/L) so they can be read aloud.
    static let codeAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    static func newCode<G: RandomNumberGenerator>(length: Int = 6, using generator: inout G) -> String {
        String((0..<length).map { _ in codeAlphabet.randomElement(using: &generator)! })
    }

    static func newCode(length: Int = 6) -> String {
        var g = SystemRandomNumberGenerator()
        return newCode(length: length, using: &g)
    }

    /// Normalizes what someone typed or read out ("abc-123", " ab c123 ") to a code, or nil.
    static func normalize(code raw: String) -> String? {
        let cleaned = raw.uppercased().filter { !" -_".contains($0) }
        guard (4...8).contains(cleaned.count), cleaned.allSatisfy({ codeAlphabet.contains($0) }) else { return nil }
        return cleaned
    }

    /// The share link a Helper opens in a browser (`web/`), or in the app via the `fixitlens://` scheme.
    static func shareURL(relay: URL, code: String) -> URL {
        relay.appendingPathComponent("j").appendingPathComponent(code)
    }

    static func appURL(code: String) -> URL {
        URL(string: "fixitlens://join?code=\(code)")!
    }

    /// Extracts a join code from a share link, app link or bare code.
    static func code(from text: String) -> String? {
        if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme != nil {
            if let item = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value {
                return normalize(code: item)
            }
            let parts = url.pathComponents
            if let index = parts.firstIndex(of: "j"), parts.indices.contains(index + 1) { return normalize(code: parts[index + 1]) }
        }
        return normalize(code: text)
    }
}

enum TogetherRole: String, Codable, Sendable {
    case fixer, helper
}

/// Binary media frame.
struct TogetherMedia: Equatable, Sendable {
    enum Kind: UInt8, Sendable {
        case jpeg = 0x01
        case wav = 0x02
    }

    var kind: Kind
    var seq: UInt32
    var payload: Data

    func encoded() -> Data {
        var data = Data([kind.rawValue])
        withUnsafeBytes(of: seq.bigEndian) { data.append(contentsOf: $0) }
        data.append(payload)
        return data
    }

    init(kind: Kind, seq: UInt32, payload: Data) {
        self.kind = kind
        self.seq = seq
        self.payload = payload
    }

    init?(_ data: Data) {
        let bytes = [UInt8](data.prefix(5))
        guard bytes.count == 5, let kind = Kind(rawValue: bytes[0]) else { return nil }
        self.kind = kind
        seq = bytes[1...4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        payload = data.dropFirst(5)
        payload = Data(payload)
    }
}

/// A part outline shared with everyone in the room. Coordinates are normalized to the frame (0–1, top-left).
struct SharedMask: Codable, Equatable, Sendable {
    var id: Int
    var seq: UInt32
    var box: [Double]
    /// PNG of the mask (white on transparent), cropped to `box`, base64. Empty if box-only.
    var png: String
    var label: String
    var confidence: Double?
    /// Who asked for it ("helper" or "fixer") and which model produced it ("sam-3.1").
    var by: String
    var model: String

    var rect: CGRect { CGRect(x: box[0], y: box[1], width: box[2] - box[0], height: box[3] - box[1]) }
    var centre: CGPoint { CGPoint(x: (box[0] + box[2]) / 2, y: (box[1] + box[3]) / 2) }
}

/// One line of the conversation, as heard and as translated for the other side.
struct Caption: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var from: TogetherRole
    var name: String
    var original: String
    var originalLanguage: String
    var translated: String
    var translatedLanguage: String
    var at: Double
}

/// Control messages. Unknown types decode as `.unknown` so older clients ignore new features.
enum TogetherMessage: Equatable, Sendable {
    case hello(role: TogetherRole, name: String, language: String, platform: String)
    case peers(count: Int, helpers: [String])
    case tap(seq: UInt32, x: Double, y: Double, by: String)
    case mask(SharedMask)
    case clearMask
    case caption(Caption)
    case memory(steps: [String], title: String)
    case safety(reason: String)
    case mode(String)
    case ack(seq: UInt32)
    case status(String)
    case unknown(String)

    var type: String {
        switch self {
        case .hello: "hello"
        case .peers: "peers"
        case .tap: "tap"
        case .mask: "mask"
        case .clearMask: "clear_mask"
        case .caption: "caption"
        case .memory: "memory"
        case .safety: "safety"
        case .mode: "mode"
        case .ack: "ack"
        case .status: "status"
        case .unknown(let t): t
        }
    }

    func json() -> String {
        var object: [String: Any] = ["t": type]
        switch self {
        case let .hello(role, name, language, platform):
            object.merge(["role": role.rawValue, "name": name, "lang": language, "platform": platform]) { $1 }
        case let .peers(count, helpers):
            object.merge(["count": count, "helpers": helpers]) { $1 }
        case let .tap(seq, x, y, by):
            object.merge(["seq": seq, "x": x, "y": y, "by": by]) { $1 }
        case .mask(let mask):
            if let data = try? JSONEncoder().encode(mask), let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                object["mask"] = dict
            }
        case .clearMask, .unknown:
            break
        case .caption(let caption):
            if let data = try? JSONEncoder().encode(caption), let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                object["caption"] = dict
            }
        case let .memory(steps, title):
            object.merge(["steps": steps, "title": title]) { $1 }
        case .safety(let reason):
            object["reason"] = reason
        case .mode(let mode):
            object["mode"] = mode
        case .ack(let seq):
            object["seq"] = seq
        case .status(let text):
            object["text"] = text
        }
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    static func parse(_ text: String) -> TogetherMessage? {
        guard let data = text.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = o["t"] as? String else { return nil }
        func str(_ k: String) -> String { (o[k] as? String) ?? "" }
        func num(_ k: String) -> Double? { (o[k] as? NSNumber)?.doubleValue ?? (o[k] as? String).flatMap(Double.init) }
        func sub<T: Decodable>(_ k: String, _ type: T.Type) -> T? {
            guard let value = o[k], let d = try? JSONSerialization.data(withJSONObject: value) else { return nil }
            return try? JSONDecoder().decode(T.self, from: d)
        }
        switch t {
        case "hello":
            return .hello(role: TogetherRole(rawValue: str("role")) ?? .helper, name: str("name"), language: str("lang"), platform: str("platform"))
        case "peers":
            return .peers(count: Int(num("count") ?? 0), helpers: (o["helpers"] as? [String]) ?? [])
        case "tap":
            guard let x = num("x"), let y = num("y"), (0...1).contains(x), (0...1).contains(y) else { return nil }
            return .tap(seq: UInt32(max(0, num("seq") ?? 0)), x: x, y: y, by: str("by"))
        case "mask":
            return sub("mask", SharedMask.self).map(TogetherMessage.mask)
        case "clear_mask":
            return .clearMask
        case "caption":
            return sub("caption", Caption.self).map(TogetherMessage.caption)
        case "memory":
            return .memory(steps: (o["steps"] as? [String]) ?? [], title: str("title"))
        case "safety":
            return .safety(reason: str("reason"))
        case "mode":
            return .mode(str("mode"))
        case "ack":
            return .ack(seq: UInt32(max(0, num("seq") ?? 0)))
        case "status":
            return .status(str("text"))
        default:
            return .unknown(t)
        }
    }
}

/// Flow control for the live stream: the Fixer sends a new frame only when the Helper has acknowledged
/// recent ones, so latency stays low on slow links instead of building a queue. If acks stop for
/// `snapshotAfter` seconds (or the socket drops), the stream falls back to one snapshot per second.
struct StreamPacer: Sendable {
    enum Mode: String, Sendable { case live, snapshot }

    var maxInFlight = 2
    var liveInterval: TimeInterval = 1.0 / 12
    var snapshotInterval: TimeInterval = 1.0
    var snapshotAfter: TimeInterval = 3.0
    var recoverAfterAcks = 3

    private(set) var mode: Mode = .live
    private(set) var lastSentSeq: UInt32 = 0
    private(set) var lastAckSeq: UInt32 = 0
    private var lastSentAt: TimeInterval = -.infinity
    private var lastAckAt: TimeInterval?
    private var startedAt: TimeInterval?
    private var acksSinceSnapshot = 0

    var inFlight: Int { Int(lastSentSeq &- lastAckSeq) }

    /// Whether to send a frame now. `hasViewers` false → never send.
    mutating func shouldSend(now: TimeInterval, hasViewers: Bool) -> Bool {
        guard hasViewers else { return false }
        if startedAt == nil { startedAt = now }
        updateMode(now: now)
        switch mode {
        case .live:
            return inFlight < maxInFlight && now - lastSentAt >= liveInterval
        case .snapshot:
            return now - lastSentAt >= snapshotInterval
        }
    }

    mutating func didSend(seq: UInt32, now: TimeInterval) {
        lastSentSeq = seq
        lastSentAt = now
    }

    mutating func didAck(seq: UInt32, now: TimeInterval) {
        guard seq > lastAckSeq || lastAckSeq &- seq > UInt32.max / 2 else { return }
        lastAckSeq = seq
        lastAckAt = now
        if mode == .snapshot {
            acksSinceSnapshot += 1
            if acksSinceSnapshot >= recoverAfterAcks { mode = .live; acksSinceSnapshot = 0 }
        }
    }

    /// The socket dropped or reconnected: go to snapshot mode until acks flow again.
    mutating func linkDegraded() {
        mode = .snapshot
        acksSinceSnapshot = 0
        lastAckSeq = lastSentSeq
    }

    private mutating func updateMode(now: TimeInterval) {
        guard mode == .live, inFlight >= maxInFlight else { return }
        let since = lastAckAt ?? startedAt ?? now
        if now - since > snapshotAfter { linkDegraded() }
    }
}
