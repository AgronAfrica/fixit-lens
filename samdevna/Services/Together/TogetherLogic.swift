import CoreGraphics
import Foundation

/// Keeps a shared SAM 3.1 outline on the part as the live camera moves.
///
/// SAM 3.1 segments single images, so tracking is done by re-anchoring on keyframes: every
/// `interval` seconds (when no other SAM call is in flight) the Fixer re-runs a SAM point prompt at the
/// centre of the last box on the newest frame. The new mask is accepted only if it is plausibly the same
/// part (similar size, nearby); otherwise the old outline is kept and, after `maxMisses`, marked lost.
struct MaskTracker: Sendable {
    var interval: TimeInterval = 1.2
    var maxMisses = 3
    var maxGrowth = 3.0
    var maxJump = 0.25

    private(set) var box: [Double]?
    private(set) var misses = 0
    private(set) var lastRun: TimeInterval = -.infinity
    private(set) var busy = false

    var isTracking: Bool { box != nil }
    var isLost: Bool { box != nil && misses >= maxMisses }

    /// A new outline from a tap: start tracking it.
    mutating func reset(to box: [Double], now: TimeInterval) {
        self.box = box
        misses = 0
        lastRun = now
        busy = false
    }

    mutating func clear() {
        box = nil
        misses = 0
        busy = false
    }

    /// The point prompt to run now, or nil if it's not time (or nothing is tracked, or a call is in flight).
    mutating func nextPrompt(now: TimeInterval) -> CGPoint? {
        guard let box, !busy, now - lastRun >= interval else { return nil }
        busy = true
        lastRun = now
        return CGPoint(x: (box[0] + box[2]) / 2, y: (box[1] + box[3]) / 2)
    }

    /// Result of a keyframe SAM call. Returns true if the new box was accepted.
    @discardableResult
    mutating func update(with candidate: [Double]?) -> Bool {
        busy = false
        guard let old = box else { return false }
        guard let new = candidate, new.count == 4 else { misses += 1; return false }
        let area = { (b: [Double]) in max((b[2] - b[0]) * (b[3] - b[1]), 1e-6) }
        let growth = area(new) / area(old)
        let dx = (new[0] + new[2]) / 2 - (old[0] + old[2]) / 2
        let dy = (new[1] + new[3]) / 2 - (old[1] + old[3]) / 2
        guard growth <= maxGrowth, growth >= 1 / maxGrowth, (dx * dx + dy * dy).squareRoot() <= maxJump else {
            misses += 1
            return false
        }
        box = new
        misses = 0
        return true
    }
}

/// What the conversation turned into: a replayable guide saved on the phone ("Repair memory").
struct RepairMemory: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var createdAt: Date
    var plan: RepairPlan
    var transcript: [Caption]
    /// File name of the keyframe JPEG stored next to the JSON.
    var photoFile: String
    var participants: [String]

    static func == (lhs: RepairMemory, rhs: RepairMemory) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.plan.steps == rhs.plan.steps && lhs.transcript == rhs.transcript
    }
}

/// Saves and loads repair memories under Application Support/RepairMemory (JSON + one JPEG each).
struct RepairMemoryStore: Sendable {
    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent("RepairMemory", isDirectory: true)
        }
    }

    func save(_ memory: RepairMemory, photoJPEG: Data?) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(memory).write(to: directory.appendingPathComponent("\(memory.id.uuidString).json"), options: .atomic)
        if let photoJPEG {
            try photoJPEG.write(to: directory.appendingPathComponent(memory.photoFile), options: .atomic)
        }
    }

    func all() -> [RepairMemory] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(RepairMemory.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func photoURL(for memory: RepairMemory) -> URL { directory.appendingPathComponent(memory.photoFile) }

    func delete(_ memory: RepairMemory) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(memory.id.uuidString).json"))
        try? FileManager.default.removeItem(at: photoURL(for: memory))
    }
}

/// Prompts for the session. Kept here (Foundation-only) so they are unit-testable and the verify script can read them.
enum TogetherPrompts {
    static func translate(_ text: String, from: String, to: String) -> String {
        """
        Translate what a person said during a hands-on repair from \(from) to \(to).
        Keep part names, numbers and directions (left, right, clockwise) exact. Keep it short and spoken.
        Return only the translation, no quotes.
        Text: \(text)
        """
    }

    static let memory = """
    You are Fix-it Lens's repair memory. A Fixer is doing a repair while a remote Helper guides them over live video.
    From the conversation (and the parts the Helper outlined with SAM 3.1, with their normalized boxes), write the repair
    as a replayable guide someone could follow next time without the Helper.

    Return ONLY JSON with keys: domain (home|vehicle|appliance), object_name, part_name, fault, fault_detail, likely_cause,
    hazard (none|caution|stop), stop_category ("" unless stop), hazard_reason, confidence (0-1), difficulty, minutes, tools, parts, avoid,
    steps (array of objects {title, instruction, part, tool, caution, point, box}), spoken_intro, illustration_prompt.
    Only include steps that were actually discussed or done, in order. Use the outlined part boxes as each step's "box" and
    its centre as "point" when the step is about that part. If the conversation involved gas, mains electrics, refrigerant,
    airbags, fuel or brake leaks or structural damage, set hazard "stop" with stop_category and no steps.
    Write in the Fixer's language; keep JSON keys and every "part" in English.
    """

    static func memoryInput(lines: [Caption], masks: [SharedMask], fixerLanguage: String) -> String {
        let talk = lines.map { "[\($0.from.rawValue)] \($0.original)" }.joined(separator: "\n")
        let parts = masks.map { mask in
            "- \(mask.label.isEmpty ? "outlined part" : mask.label): box " + mask.box.map { String(format: "%.3f", $0) }.joined(separator: ", ")
        }.joined(separator: "\n")
        return """
        Fixer's language: \(fixerLanguage).
        Conversation:
        \(talk.isEmpty ? "(nothing said yet)" : talk)
        Outlined parts:
        \(parts.isEmpty ? "(none)" : parts)
        """
    }
}
