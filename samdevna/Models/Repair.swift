import CoreGraphics
import Foundation

// Pure model types (Foundation only) so they can be unit-tested anywhere.

enum RepairDomain: String, Codable, CaseIterable, Identifiable, Sendable {
    case home
    case vehicle
    case appliance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .vehicle: "Bikes"
        case .appliance: "Appliances"
        }
    }

    var glyph: String {
        switch self {
        case .home: "spigot.fill"
        case .vehicle: "bicycle"
        case .appliance: "washer.fill"
        }
    }

    /// Default SAM 3.1 concept when the user didn't say what's broken.
    var samHint: String {
        switch self {
        case .home: "leaking pipe joint"
        case .vehicle: "loose chain"
        case .appliance: "broken appliance part"
        }
    }

    /// Lenient: models say "homes", "plumbing", "bike", "motorcycle", "machines"…
    init(lenient raw: String) {
        let value = raw.lowercased()
        if let exact = RepairDomain(rawValue: value) {
            self = exact
        } else if ["homes", "house", "plumbing", "sink", "fixture"].contains(where: value.contains) {
            self = .home
        } else if ["bike", "bicycle", "motor", "vehicle", "machine", "car", "scooter"].contains(where: value.contains) {
            self = .vehicle
        } else {
            self = .appliance
        }
    }
}

enum Hazard: String, Codable, Comparable, Sendable {
    case none
    case caution
    case stop

    var title: String {
        switch self {
        case .none: "Safe to DIY"
        case .caution: "Take care"
        case .stop: "Safety stop"
        }
    }

    var glyph: String {
        switch self {
        case .none: "checkmark.shield.fill"
        case .caution: "exclamationmark.shield.fill"
        case .stop: "hand.raised.fill"
        }
    }

    private var rank: Int {
        switch self {
        case .none: 0
        case .caution: 1
        case .stop: 2
        }
    }

    static func < (lhs: Hazard, rhs: Hazard) -> Bool { lhs.rank < rhs.rank }

    init(lenient raw: String) {
        let value = raw.lowercased()
        if value.contains("stop") || value.contains("danger") || value.contains("professional") || value.contains("urgent") {
            self = .stop
        } else if value.contains("caution") || value.contains("care") || value.contains("warn") || value.contains("medium") {
            self = .caution
        } else {
            self = .none
        }
    }
}

/// Where a part is on the full photo, in normalized 0–1 coordinates (top-left origin), as estimated by Muse Spark.
/// Used to give SAM 3.1 a point prompt for small parts that concept text misses ("slip nut").
struct PartLocation: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    /// Optional box [x0, y0, x1, y1], normalized.
    var box: [Double]?

    init(x: Double, y: Double, box: [Double]? = nil) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
        self.box = box
    }

    var point: CGPoint { CGPoint(x: x, y: y) }
    var rect: CGRect? {
        guard let box, box.count == 4 else { return nil }
        return CGRect(x: box[0], y: box[1], width: box[2] - box[0], height: box[3] - box[1])
    }

    /// Lenient read of `point` ([x, y] or {x, y}) and/or `box` ([x0, y0, x1, y1] or {x0, y0, x1, y1}).
    /// Accepts 0–1, 0–100 or 0–1000 scales. A box alone yields its centre. Returns nil if nothing usable.
    static func lenient(point: [Double]?, box: [Double]?) -> PartLocation? {
        func scaled(_ values: [Double]) -> [Double] {
            let top = values.max() ?? 0
            let divisor = top > 100 ? 1000.0 : (top > 1.0001 ? 100.0 : 1.0)
            return values.map { min(max($0 / divisor, 0), 1) }
        }
        var normBox: [Double]?
        if let box, box.count == 4 {
            let b = scaled(box)
            let x0 = min(b[0], b[2]), x1 = max(b[0], b[2]), y0 = min(b[1], b[3]), y1 = max(b[1], b[3])
            if x1 - x0 > 0.005, y1 - y0 > 0.005 { normBox = [x0, y0, x1, y1] }
        }
        if let point, point.count == 2 {
            let p = scaled(point)
            return PartLocation(x: p[0], y: p[1], box: normBox)
        }
        if let b = normBox { return PartLocation(x: (b[0] + b[2]) / 2, y: (b[1] + b[3]) / 2, box: b) }
        return nil
    }
}

/// Reads a coordinate list that may come as [1, 2], {"x": 1, "y": 2}, {"x0":…}, or strings.
struct LenientNumbers: Decodable {
    let values: [Double]

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
    }

    init(from decoder: Decoder) throws {
        if let numbers = try? decoder.singleValueContainer().decode([Double].self) {
            values = numbers
        } else if let strings = try? decoder.singleValueContainer().decode([String].self) {
            values = strings.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        } else {
            let c = try decoder.container(keyedBy: AnyKey.self)
            func value(_ names: [String]) -> Double? {
                for name in names {
                    guard let key = AnyKey(stringValue: name) else { continue }
                    if let v = (try? c.decodeIfPresent(Double.self, forKey: key)) ?? nil { return v }
                }
                return nil
            }
            if let x = value(["x"]), let y = value(["y"]) {
                values = [x, y]
            } else {
                // x0/y0/x1/y1 or left/top/right/bottom.
                if let x0 = value(["x0", "left", "xmin"]), let y0 = value(["y0", "top", "ymin"]),
                   let x1 = value(["x1", "right", "xmax"]), let y1 = value(["y1", "bottom", "ymax"]) {
                    values = [x0, y0, x1, y1]
                } else {
                    values = []
                }
            }
        }
    }
}

struct RepairStep: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var instruction: String
    /// Short English noun phrase naming the visible thing to highlight with SAM 3.1.
    var part: String
    var tool: String
    var caution: String
    /// Muse Spark's estimate of where `part` is on the full photo (normalized), for a SAM point prompt.
    var location: PartLocation?

    enum CodingKeys: String, CodingKey {
        case title, instruction, part, tool, caution, point, box
    }

    init(title: String, instruction: String, part: String, tool: String = "", caution: String = "", location: PartLocation? = nil) {
        self.title = title
        self.instruction = instruction
        self.part = part
        self.tool = tool
        self.caution = caution
        self.location = location
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(instruction, forKey: .instruction)
        try c.encode(part, forKey: .part)
        try c.encode(tool, forKey: .tool)
        try c.encode(caution, forKey: .caution)
        if let location {
            try c.encode([location.x, location.y], forKey: .point)
            try c.encodeIfPresent(location.box, forKey: .box)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String {
            ((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        instruction = text(.instruction)
        title = text(.title).isEmpty ? String(instruction.prefix(40)) : text(.title)
        part = text(.part)
        tool = text(.tool)
        caution = text(.caution)
        location = PartLocation.lenient(
            point: ((try? c.decodeIfPresent(LenientNumbers.self, forKey: .point)) ?? nil)?.values,
            box: ((try? c.decodeIfPresent(LenientNumbers.self, forKey: .box)) ?? nil)?.values
        )
    }
}

struct RepairPlan: Codable, Identifiable, Sendable {
    var id = UUID()
    var domain: RepairDomain
    var objectName: String
    var partName: String
    var fault: String
    var faultDetail: String
    var likelyCause: String
    var hazard: Hazard
    var hazardReason: String
    var confidence: Double
    var difficulty: String
    var minutes: Int
    var tools: [String]
    var parts: [String]
    var avoid: [String]
    var steps: [RepairStep]
    var spokenIntro: String
    var illustrationPrompt: String
    var usedModel: String
    var isDemo: Bool
    /// For a stop: which professional-only category applies (gas, mains_electrics, refrigerant, airbags,
    /// fuel_or_brake_leak, structural), as named by the model. Used to validate a reviewer's stop.
    var stopCategory: String = ""
    /// Muse Spark's estimate of where the faulty part is on the photo (voice-only flow: seeds the SAM point prompt).
    var target: PartLocation?

    enum CodingKeys: String, CodingKey {
        case domain, fault, hazard, confidence, difficulty, minutes, tools, parts, avoid, steps
        case stopCategory = "stop_category"
        case targetPoint = "target_point"
        case targetBox = "target_box"
        case objectName = "object_name"
        case partName = "part_name"
        case faultDetail = "fault_detail"
        case likelyCause = "likely_cause"
        case hazardReason = "hazard_reason"
        case spokenIntro = "spoken_intro"
        case illustrationPrompt = "illustration_prompt"
        case usedModel = "used_model"
        case isDemo = "is_demo"
    }

    init(
        domain: RepairDomain,
        objectName: String,
        partName: String,
        fault: String,
        faultDetail: String,
        likelyCause: String,
        hazard: Hazard,
        hazardReason: String,
        confidence: Double,
        difficulty: String,
        minutes: Int,
        tools: [String],
        parts: [String],
        avoid: [String],
        steps: [RepairStep],
        spokenIntro: String,
        illustrationPrompt: String,
        usedModel: String,
        isDemo: Bool,
        stopCategory: String = "",
        target: PartLocation? = nil
    ) {
        self.domain = domain
        self.objectName = objectName
        self.partName = partName
        self.fault = fault
        self.faultDetail = faultDetail
        self.likelyCause = likelyCause
        self.hazard = hazard
        self.hazardReason = hazardReason
        self.confidence = confidence
        self.difficulty = difficulty
        self.minutes = minutes
        self.tools = tools
        self.parts = parts
        self.avoid = avoid
        self.steps = steps
        self.spokenIntro = spokenIntro
        self.illustrationPrompt = illustrationPrompt
        self.usedModel = usedModel
        self.isDemo = isDemo
        self.stopCategory = stopCategory
        self.target = target
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(domain.rawValue, forKey: .domain)
        try c.encode(objectName, forKey: .objectName)
        try c.encode(partName, forKey: .partName)
        try c.encode(fault, forKey: .fault)
        try c.encode(faultDetail, forKey: .faultDetail)
        try c.encode(likelyCause, forKey: .likelyCause)
        try c.encode(hazard.rawValue, forKey: .hazard)
        try c.encode(hazardReason, forKey: .hazardReason)
        try c.encode(confidence, forKey: .confidence)
        try c.encode(difficulty, forKey: .difficulty)
        try c.encode(minutes, forKey: .minutes)
        try c.encode(tools, forKey: .tools)
        try c.encode(parts, forKey: .parts)
        try c.encode(avoid, forKey: .avoid)
        try c.encode(steps, forKey: .steps)
        try c.encode(spokenIntro, forKey: .spokenIntro)
        try c.encode(illustrationPrompt, forKey: .illustrationPrompt)
        try c.encode(usedModel, forKey: .usedModel)
        try c.encode(isDemo, forKey: .isDemo)
        if !stopCategory.isEmpty { try c.encode(stopCategory, forKey: .stopCategory) }
        if let target {
            try c.encode([target.x, target.y], forKey: .targetPoint)
            try c.encodeIfPresent(target.box, forKey: .targetBox)
        }
    }

    /// Lenient: models sometimes return "Caution", a string confidence, one string instead of a list,
    /// or steps as plain strings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String? {
            ((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func list(_ key: CodingKeys) -> [String] {
            if let items = (try? c.decodeIfPresent([String].self, forKey: key)) ?? nil { return items.filter { !$0.isEmpty } }
            if let single = text(key), !single.isEmpty { return [single] }
            return []
        }
        func number(_ key: CodingKeys) -> Double? {
            if let value = (try? c.decodeIfPresent(Double.self, forKey: key)) ?? nil { return value }
            return text(key).flatMap { Double($0.filter { "0123456789.".contains($0) }) }
        }

        domain = text(.domain).map(RepairDomain.init(lenient:)) ?? .appliance
        objectName = text(.objectName).flatMap { $0.isEmpty ? nil : $0 } ?? "Object"
        partName = text(.partName) ?? ""
        fault = text(.fault) ?? ""
        faultDetail = text(.faultDetail) ?? ""
        likelyCause = text(.likelyCause) ?? ""
        hazard = text(.hazard).map(Hazard.init(lenient:)) ?? .caution
        hazardReason = text(.hazardReason) ?? ""
        let rawConfidence = number(.confidence) ?? 0
        confidence = rawConfidence > 1 ? min(rawConfidence / 100, 1) : max(rawConfidence, 0)
        difficulty = text(.difficulty)?.lowercased() ?? ""
        minutes = Int(number(.minutes) ?? 0)
        tools = list(.tools)
        parts = list(.parts)
        avoid = list(.avoid)
        if let typed = (try? c.decodeIfPresent([RepairStep].self, forKey: .steps)) ?? nil {
            steps = typed.filter { !$0.instruction.isEmpty }
        } else {
            steps = list(.steps).map { RepairStep(title: String($0.prefix(40)), instruction: $0, part: "") }
        }
        spokenIntro = text(.spokenIntro) ?? fault
        illustrationPrompt = text(.illustrationPrompt) ?? ""
        usedModel = text(.usedModel) ?? ""
        isDemo = ((try? c.decodeIfPresent(Bool.self, forKey: .isDemo)) ?? nil) ?? false
        stopCategory = text(.stopCategory)?.lowercased() ?? ""
        target = PartLocation.lenient(
            point: ((try? c.decodeIfPresent(LenientNumbers.self, forKey: .targetPoint)) ?? nil)?.values,
            box: ((try? c.decodeIfPresent(LenientNumbers.self, forKey: .targetBox)) ?? nil)?.values
        )
    }

    /// A plan that refuses to guide: shown for gas, mains electricity and other jobs for a professional.
    static func safetyStop(reason: String, domain: RepairDomain, objectName: String = "", fault: String = "", isDemo: Bool = false) -> RepairPlan {
        RepairPlan(
            domain: domain,
            objectName: objectName.isEmpty ? "This job" : objectName,
            partName: "",
            fault: fault.isEmpty ? "This needs a qualified professional" : fault,
            faultDetail: "",
            likelyCause: "",
            hazard: .stop,
            hazardReason: reason,
            confidence: 0,
            difficulty: "",
            minutes: 0,
            tools: [],
            parts: [],
            avoid: [],
            steps: [],
            spokenIntro: SafetyGuard.spokenStop,
            illustrationPrompt: "",
            usedModel: "",
            isDemo: isDemo
        )
    }

    /// Plain-text summary for the share sheet.
    var shareText: String {
        var lines = ["Fix-it Lens — \(objectName)", fault]
        if hazard == .stop {
            lines.append("SAFETY STOP: \(hazardReason)")
        } else {
            lines.append("")
            for (index, step) in steps.enumerated() { lines.append("\(index + 1). \(step.title): \(step.instruction)") }
            if !tools.isEmpty { lines.append("\nTools: " + tools.joined(separator: ", ")) }
        }
        return lines.joined(separator: "\n")
    }
}

struct GuideAnswer: Codable, Equatable, Sendable {
    var answer: String
    /// Short English noun phrase for SAM 3.1 to highlight, or empty.
    var highlight: String
    var safetyStop: Bool
    /// Where `highlight` is on the photo (normalized), if the model gave it.
    var location: PartLocation?

    enum CodingKeys: String, CodingKey {
        case answer, highlight, point, box
        case safetyStop = "safety_stop"
    }

    init(answer: String, highlight: String = "", safetyStop: Bool = false, location: PartLocation? = nil) {
        self.answer = answer
        self.highlight = highlight
        self.safetyStop = safetyStop
        self.location = location
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(answer, forKey: .answer)
        try c.encode(highlight, forKey: .highlight)
        try c.encode(safetyStop, forKey: .safetyStop)
        if let location { try c.encode([location.x, location.y], forKey: .point) }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        answer = ((try? c.decodeIfPresent(String.self, forKey: .answer)) ?? nil) ?? ""
        highlight = ((try? c.decodeIfPresent(String.self, forKey: .highlight)) ?? nil)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let flag = (try? c.decodeIfPresent(Bool.self, forKey: .safetyStop)) ?? nil {
            safetyStop = flag
        } else {
            safetyStop = (((try? c.decodeIfPresent(String.self, forKey: .safetyStop)) ?? nil)?.lowercased() == "true")
        }
        location = PartLocation.lenient(
            point: ((try? c.decodeIfPresent(LenientNumbers.self, forKey: .point)) ?? nil)?.values,
            box: ((try? c.decodeIfPresent(LenientNumbers.self, forKey: .box)) ?? nil)?.values
        )
    }
}

enum ModelJSON {
    /// The first `{…}` object in a model reply (models sometimes wrap JSON in prose or code fences).
    static func object(in raw: String) -> Data? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return Data(text[start...end].utf8)
    }

    static func plan(_ raw: String, fallbackDomain: RepairDomain) throws -> RepairPlan {
        if let data = object(in: raw), let plan = try? JSONDecoder().decode(RepairPlan.self, from: data) {
            return plan
        }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 12 else { throw FixError.reasoning("The model returned an empty answer.") }
        // Prose instead of JSON: show the words as-is, with no invented steps.
        return RepairPlan(
            domain: fallbackDomain, objectName: fallbackDomain.title, partName: "",
            fault: String(text.prefix(160)), faultDetail: text, likelyCause: "",
            hazard: .caution, hazardReason: "", confidence: 0, difficulty: "", minutes: 0,
            tools: [], parts: [], avoid: [], steps: [],
            spokenIntro: String(text.prefix(240)), illustrationPrompt: "", usedModel: "", isDemo: false
        )
    }

    static func answer(_ raw: String) -> GuideAnswer {
        if let data = object(in: raw), let answer = try? JSONDecoder().decode(GuideAnswer.self, from: data), !answer.answer.isEmpty {
            return answer
        }
        return GuideAnswer(answer: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english, hindi, bengali, tamil, telugu, marathi, kannada, spanish, french, portuguese, indonesian

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var voiceCode: String {
        switch self {
        case .english: "en-US"
        case .hindi: "hi-IN"
        case .bengali: "bn-IN"
        case .tamil: "ta-IN"
        case .telugu: "te-IN"
        case .marathi: "mr-IN"
        case .kannada: "kn-IN"
        case .spanish: "es-ES"
        case .french: "fr-FR"
        case .portuguese: "pt-BR"
        case .indonesian: "id-ID"
        }
    }

    /// Language names as Muse Voice Transcribe expects them in `languageBias`.
    var transcribeBias: [String] { self == .english ? ["English"] : [label, "English"] }
}

enum FixError: LocalizedError, Equatable {
    case missingKey
    case noImage
    case micDenied
    case micUnavailable
    case nothingHeard
    case segmentation(String)
    case reasoning(String)
    case illustration(String)
    case network(String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingKey: "Add your Meta Model API key in Settings, or open a sample to watch the demo replay."
        case .noImage: "Take or pick a photo first."
        case .micDenied: "Microphone access is off. Turn it on in Settings › Fix-it Lens."
        case .micUnavailable: "The microphone isn't available right now."
        case .nothingHeard: "Didn't catch that. Hold the mic and speak a little louder."
        case .segmentation(let m): "SAM 3.1: \(m)"
        case .reasoning(let m): "Muse Spark: \(m)"
        case .illustration(let m): "Muse Image: \(m)"
        case .network(let m): "Network problem: \(m)"
        case .http(let code, let body):
            switch code {
            case 401, 403: "Meta Model API rejected the key (HTTP \(code)). Check it in Settings."
            case 429: "Meta Model API rate limit reached. Wait a moment and try again."
            default: "Meta Model API error \(code): \(body)"
            }
        }
    }
}
