import CoreGraphics
import Foundation

/// Local, deterministic safety net that runs before and after every model call.
/// The model is also told to raise `hazard: "stop"`; this guard catches what it misses.
enum SafetyGuard {
    static let spokenStop = "Stop here. This job needs a qualified professional. Please don't touch it, and call a licensed engineer or electrician."

    /// The professional-only job categories. Nothing else may produce a stop from a model review.
    enum Category: String, CaseIterable, Sendable {
        case gas
        case mainsElectrics = "mains_electrics"
        case refrigerant
        case airbags
        case fuelOrBrakeLeak = "fuel_or_brake_leak"
        case structural

        /// Lenient: "Mains electrics", "electrical", "fuel leak"…
        init?(lenient raw: String) {
            let v = raw.lowercased().replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: " ", with: "_")
            if let exact = Category(rawValue: v) { self = exact; return }
            if v.contains("gas") { self = .gas }
            else if v.contains("mains") || v.contains("electric") { self = .mainsElectrics }
            else if v.contains("refrigerant") || v.contains("microwave") || v.contains("crt") { self = .refrigerant }
            else if v.contains("airbag") { self = .airbags }
            else if v.contains("fuel") || v.contains("brake") { self = .fuelOrBrakeLeak }
            else if v.contains("struct") { self = .structural }
            else { return nil }
        }
    }

    private struct Rule {
        let pattern: NSRegularExpression
        let reason: String
        let category: Category
    }

    private static let rules: [Rule] = [
        rule(#"\b(gas|lpg|propane|butane|carbon monoxide)\b"#,
             "Gas appliances and pipework must only be worked on by a registered gas engineer. If you smell gas, leave the area and call your gas emergency line.", .gas),
        rule(#"\b(mains|fuse ?box|breaker (panel|box)|consumer unit|live wir(e|es|ing)|exposed (live )?wir(e|es|ing)|hard[- ]?wired|high voltage|\d{3} ?v(olts?)?)\b"#,
             "Mains electricity can kill. Switch off only if it is safe to do so, and call a qualified electrician.", .mainsElectrics),
        rule(#"\b(sparking|sparks|burning smell|smells? of burning)\b"#,
             "Sparks or a burning smell point to an electrical fault. Unplug only if it is safe, and call a qualified electrician.", .mainsElectrics),
        rule(#"\b(refrigerant|magnetron|microwave (inside|interior|capacitor)|crt)\b"#,
             "Refrigerant circuits and microwave or CRT interiors are dangerous even when unplugged. This is a job for a qualified technician.", .refrigerant),
        rule(#"\b(airbags?|srs module)\b"#,
             "Airbags can fire and injure you even with the battery off. This is a job for a qualified mechanic.", .airbags),
        rule(#"\b(fuel (line|leak|tank leak)|petrol leak|diesel leak|brake (line|hose|fluid) leak|leaking brake (line|fluid))\b"#,
             "Fuel leaks and brake-line leaks are a job for a qualified mechanic.", .fuelOrBrakeLeak),
        rule(#"\b(structural crack|load[- ]bearing|ceiling (is )?sagging)\b"#,
             "Structural damage needs a qualified surveyor or builder.", .structural),
    ]

    private static func rule(_ pattern: String, _ reason: String, _ category: Category) -> Rule {
        // Patterns are compile-time constants covered by unit tests.
        Rule(pattern: try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), reason: reason, category: category)
    }

    /// Every professional-only category mentioned in `text`.
    static func categories(in text: String) -> Set<Category> {
        let range = NSRange(text.startIndex..., in: text)
        return Set(rules.filter { $0.pattern.firstMatch(in: text, range: range) != nil }.map(\.category))
    }

    /// The reason to stop, or nil if nothing in `text` needs a professional.
    static func reason(for text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        return rules.first { $0.pattern.firstMatch(in: text, range: range) != nil }?.reason
    }

    /// Raises a plan to a safety stop if the model said so, or if the user's words or the
    /// identified object/fault match a rule. A stop plan never carries repair steps.
    static func enforce(_ plan: RepairPlan, transcript: String) -> RepairPlan {
        let localReason = [transcript, plan.objectName, plan.partName, plan.fault]
            .lazy
            .compactMap(reason(for:))
            .first
        guard plan.hazard == .stop || localReason != nil else { return plan }
        var stopped = plan
        stopped.hazard = .stop
        stopped.hazardReason = plan.hazard == .stop && !plan.hazardReason.isEmpty ? plan.hazardReason : (localReason ?? plan.hazardReason)
        stopped.steps = []
        stopped.spokenIntro = spokenStop
        return stopped
    }
}

/// Merges Muse Wonder's review into Muse Spark's plan without ever losing the repair.
///
/// Rules:
/// - The review can never remove steps. If it returns none, Spark's steps stay.
/// - The review can raise the hazard (never lower it), but it may raise it to **stop** only with an explicit
///   `stop_category` that is one of `SafetyGuard.Category` **and** a `hazard_reason` that actually names that
///   category (checked by the same local rules). Proximity remarks such as "water near a socket" stay at caution.
/// - Step locations from Spark are carried over when the reviewed steps keep the same part.
enum PlanReview {
    enum Outcome: Equatable, Sendable {
        case unchanged
        case improved
        case raisedToCaution
        case stopped(String)
        case stopRejected(String)
    }

    private static let proximity = try! NSRegularExpression(
        pattern: #"\b(near|nearby|next to|close to|beside|above|below|under|around|away from|keep .* away)\b"#,
        options: [.caseInsensitive]
    )

    static func merge(original: RepairPlan, reviewed: RepairPlan) -> (plan: RepairPlan, outcome: Outcome) {
        if original.hazard == .stop { return (original, .unchanged) }

        // 1. Decide whether a reviewer stop is legitimate.
        if reviewed.hazard == .stop {
            let claimed = SafetyGuard.Category(lenient: reviewed.stopCategory)
            let named = SafetyGuard.categories(in: reviewed.hazardReason)
            let reason = reviewed.hazardReason
            let proximityOnly = proximity.firstMatch(in: reason, range: NSRange(reason.startIndex..., in: reason)) != nil
                && named.isSubset(of: [.mainsElectrics])
            if let claimed, named.contains(claimed), !proximityOnly {
                var stopped = original
                stopped.hazard = .stop
                stopped.stopCategory = claimed.rawValue
                stopped.hazardReason = reason
                stopped.steps = []
                stopped.spokenIntro = SafetyGuard.spokenStop
                stopped.usedModel = "\(original.usedModel)+\(reviewed.usedModel)"
                return (stopped, .stopped(reason))
            }
            // Not a real stop category: keep the repair, at caution, with the reviewer's warning as a caution note.
            var kept = mergeContent(original: original, reviewed: reviewed)
            kept.hazard = max(original.hazard, .caution)
            kept.stopCategory = ""
            kept.hazardReason = original.hazardReason.isEmpty ? reason : original.hazardReason
            return (kept, .stopRejected(reason.isEmpty ? "no reason given" : reason))
        }

        // 2. Normal review: improve wording, keep steps, raise (never lower) hazard.
        var merged = mergeContent(original: original, reviewed: reviewed)
        merged.hazard = max(original.hazard, reviewed.hazard)
        if merged.hazard > original.hazard, !reviewed.hazardReason.isEmpty {
            merged.hazardReason = reviewed.hazardReason
            return (merged, .raisedToCaution)
        }
        merged.hazardReason = original.hazardReason.isEmpty ? reviewed.hazardReason : original.hazardReason
        return (merged, reviewed.steps.isEmpty ? .unchanged : .improved)
    }

    private static func mergeContent(original: RepairPlan, reviewed: RepairPlan) -> RepairPlan {
        var merged = original
        merged.usedModel = reviewed.usedModel.isEmpty ? original.usedModel : "\(original.usedModel)+\(reviewed.usedModel)"
        let reviewedSteps = reviewed.steps.filter { !$0.instruction.isEmpty }
        // A review that returns fewer than half the steps is treated as a summary, not a better plan.
        if !reviewedSteps.isEmpty, reviewedSteps.count * 2 >= original.steps.count {
            merged.steps = reviewedSteps.enumerated().map { index, step in
                var step = step
                if step.part.isEmpty, original.steps.indices.contains(index) { step.part = original.steps[index].part }
                if step.location == nil {
                    let key = step.part.lowercased()
                    step.location = original.steps.first { $0.part.lowercased() == key && $0.location != nil }?.location
                        ?? (original.steps.indices.contains(index) && original.steps[index].part.lowercased() == key
                            ? original.steps[index].location : nil)
                }
                return step
            }
        }
        if !reviewed.fault.isEmpty { merged.fault = reviewed.fault }
        if !reviewed.faultDetail.isEmpty { merged.faultDetail = reviewed.faultDetail }
        if !reviewed.likelyCause.isEmpty { merged.likelyCause = reviewed.likelyCause }
        if !reviewed.tools.isEmpty { merged.tools = reviewed.tools }
        if !reviewed.avoid.isEmpty { merged.avoid = reviewed.avoid }
        if !reviewed.spokenIntro.isEmpty, reviewed.spokenIntro != SafetyGuard.spokenStop { merged.spokenIntro = reviewed.spokenIntro }
        if !reviewed.illustrationPrompt.isEmpty { merged.illustrationPrompt = reviewed.illustrationPrompt }
        if merged.target == nil { merged.target = reviewed.target }
        return merged
    }
}

/// What the user said during the hands-free guide.
enum VoiceIntent: Equatable, Sendable {
    case next
    case back
    case repeatStep
    case stop
    case question(String)

    private static let nextPhrases: Set<String> = [
        "done", "next", "finished", "ok", "okay", "got it", "its done", "it's done", "i'm done", "im done",
        "all done", "next step", "continue", "ready", "ho gaya", "listo", "siguiente", "fait", "suivant",
        "pronto", "próximo", "proximo", "selesai", "lanjut", "yes done",
    ]
    private static let backPhrases: Set<String> = ["back", "go back", "previous", "previous step", "last step", "atrás", "retour"]
    private static let repeatPhrases: Set<String> = [
        "repeat", "again", "say again", "say that again", "repeat that", "pardon", "sorry", "come again", "one more time",
    ]
    private static let stopPhrases: Set<String> = ["stop", "cancel", "quit", "exit", "end", "end guide", "close", "stop guide"]
    private static let questionStarters: Set<String> = [
        "what", "what's", "whats", "which", "how", "why", "where", "is", "are", "can", "should", "does", "do", "will", "could",
    ]

    static func parse(_ raw: String) -> VoiceIntent {
        let cleaned = raw.lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s']"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !cleaned.isEmpty else { return .repeatStep }
        let words = cleaned.split(separator: " ")
        if let first = words.first, questionStarters.contains(String(first)) || raw.contains("?") {
            return .question(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        // Commands are short; strip polite fillers so "okay done thanks" still advances.
        let fillers: Set<Substring> = ["please", "thanks", "thank", "you", "now", "um", "uh", "so", "and", "that's", "thats"]
        let core = words.filter { !fillers.contains($0) }.joined(separator: " ")
        if words.count <= 6 {
            if stopPhrases.contains(core) { return .stop }
            if backPhrases.contains(core) { return .back }
            if repeatPhrases.contains(core) { return .repeatStep }
            if nextPhrases.contains(core) || core.split(separator: " ").allSatisfy({ nextPhrases.contains(String($0)) }) {
                return .next
            }
        }
        return .question(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Energy-based end-of-speech detector for hands-free listening.
struct VoiceActivity: Sendable {
    enum Decision: Equatable, Sendable {
        case listening
        case speechEnded
        case noSpeech
    }

    let startedAt: Date
    var silenceToEnd: TimeInterval = 1.1
    var maxWaitForSpeech: TimeInterval = 7
    var maxLength: TimeInterval = 15
    private(set) var noiseFloor: Float = 0.008
    private(set) var heardSpeech = false
    private var lastVoiceAt: Date?

    init(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }

    mutating func feed(_ rms: Float, at now: Date = Date()) -> Decision {
        let elapsed = now.timeIntervalSince(startedAt)
        let threshold = max(0.02, noiseFloor * 3)
        if rms > threshold {
            heardSpeech = true
            lastVoiceAt = now
        } else {
            noiseFloor = noiseFloor * 0.95 + rms * 0.05
        }
        if heardSpeech, let last = lastVoiceAt, now.timeIntervalSince(last) >= silenceToEnd { return .speechEnded }
        if !heardSpeech, elapsed >= maxWaitForSpeech { return .noSpeech }
        if elapsed >= maxLength { return heardSpeech ? .speechEnded : .noSpeech }
        return .listening
    }
}

/// Decides whether a SAM 3.1 mask from a point prompt is plausibly the small part Muse Spark meant,
/// rather than the whole cabinet or wheel the point happened to land on.
enum Locator {
    /// Masks covering more than this share of the photo are treated as "the whole object", not the part.
    static let maxMaskFraction = 0.45

    /// - Parameters:
    ///   - maskFraction: mask area / photo area.
    ///   - maskBoxFraction: mask bounding-box area / photo area.
    ///   - estimate: Spark's location for the part (its box, if any, bounds how big the mask may be).
    static func plausible(maskFraction: Double, maskBoxFraction: Double, estimate: PartLocation) -> Bool {
        guard maskFraction > 0, maskFraction < maxMaskFraction else { return false }
        if let rect = estimate.rect {
            let estimated = Double(rect.width * rect.height)
            return maskBoxFraction <= max(estimated * 6, 0.02)
        }
        return true
    }
}
