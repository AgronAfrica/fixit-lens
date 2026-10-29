import CoreGraphics
import Foundation

/// Built-in demo replay so anyone can try Fix-it Lens without a Meta API key.
///
/// The photos are real sample images. Everything else here is SCRIPTED: the plans, the answers and
/// the highlight regions (hand-placed rectangles, normalised 0…1, not live SAM 3.1 masks). The app labels
/// replay as "Demo replay" and makes no network calls in it. With a key and replay off, the same samples
/// run through the live Meta pipeline instead.
struct DemoScene: Identifiable {
    let id: String
    let domain: RepairDomain
    let title: String
    let subtitle: String
    let assetName: String
    /// What the scripted user "says" when the mic is used in replay.
    let utterance: String
    /// Where the scripted tap lands, normalised.
    let tapPoint: CGPoint
    /// The part that gets outlined first.
    let targetPart: String
    let plan: RepairPlan
    /// Highlight regions keyed by the `part` noun phrases used in the plan and answers.
    let regions: [String: CGRect]
    let answers: [DemoAnswer]

    /// The best hand-placed region for a part phrase: exact key, then containment either way.
    func region(for part: String) -> CGRect? {
        let key = part.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        if let exact = regions[key] { return exact }
        return regions
            .filter { key.contains($0.key) || $0.key.contains(key) }
            .max { $0.key.count < $1.key.count }?
            .value
    }

    /// The smallest region containing a normalised tap, or the target part.
    func region(containing point: CGPoint) -> (part: String, rect: CGRect) {
        if let hit = regions
            .filter({ $0.value.contains(point) })
            .min(by: { $0.value.width * $0.value.height < $1.value.width * $1.value.height }) {
            return (hit.key, hit.value)
        }
        return (targetPart, regions[targetPart] ?? CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
    }

    /// Scripted answer for a question, matched by keyword; a generic answer otherwise.
    func answer(to question: String, step: RepairStep?) -> GuideAnswer {
        if let reason = SafetyGuard.reason(for: question) {
            return GuideAnswer(answer: "Stop there. \(reason)", highlight: "", safetyStop: true)
        }
        let q = question.lowercased()
        if let match = answers.first(where: { $0.keywords.contains(where: q.contains) }) {
            return GuideAnswer(answer: match.answer, highlight: match.highlight)
        }
        let part = step?.part ?? targetPart
        return GuideAnswer(
            answer: "Focus on the \(part) I've highlighted. \(step?.instruction ?? "") Say done when you're ready.",
            highlight: part
        )
    }

    /// The quick question offered as a chip for each step.
    func suggestedQuestion(for step: RepairStep?) -> String {
        guard let step else { return "What should I check first?" }
        return answers.first { $0.highlight == step.part && !$0.chip.isEmpty }?.chip
            ?? answers.first { !$0.chip.isEmpty }?.chip
            ?? "What's this part?"
    }
}

struct DemoAnswer {
    let keywords: [String]
    let answer: String
    var highlight: String = ""
    var chip: String = ""
}

enum DemoLibrary {
    static let scenes: [DemoScene] = [sink, bike]

    static func scene(id: String) -> DemoScene? {
        (scenes + [safety]).first { $0.id == id }
    }

    // MARK: Leaking sink trap (DemoHome)

    static let sink = DemoScene(
        id: "sink",
        domain: .home,
        title: "Leaking sink trap",
        subtitle: "Drip under the basin",
        assetName: "DemoHome",
        utterance: "Why is the pipe under my sink dripping?",
        tapPoint: CGPoint(x: 0.54, y: 0.41),
        targetPart: "leaking pipe joint",
        plan: RepairPlan(
            domain: .home,
            objectName: "Sink waste trap",
            partName: "Slip-joint nut and washer",
            fault: "The slip joint on the trap is leaking",
            faultDetail: "Water is beading where the curved trap meets the pipe above. Plastic slip nuts work loose over time, and the flat washer inside can flatten or sit crooked.",
            likelyCause: "A loose slip nut, or a worn or misaligned washer.",
            hazard: .caution,
            hazardReason: "There's a light and a socket near the sink. Keep water away from them and dry your hands before touching anything electrical.",
            confidence: 0.82,
            difficulty: "easy",
            minutes: 15,
            tools: ["Bucket", "Old towel", "Your hands", "Groove-joint pliers (only if stuck)"],
            parts: ["Slip-joint washer (if worn)"],
            avoid: [
                "Don't crank plastic nuts with pliers. They crack.",
                "Don't put tape or sealant on a slip joint.",
            ],
            steps: [
                RepairStep(
                    title: "Catch the drips",
                    instruction: "Keep the bucket right under the trap and lay a towel around it. Don't run the tap while you work.",
                    part: "bucket", tool: "Bucket and towel"
                ),
                RepairStep(
                    title: "Find the leaking joint",
                    instruction: "Dry the pipe with the towel, then watch. The first drop forms at the leaking joint, here where the trap meets the pipe above.",
                    part: "leaking pipe joint", tool: "Towel"
                ),
                RepairStep(
                    title: "Hand-tighten the slip nut",
                    instruction: "Grip this large plastic nut and turn it clockwise, as seen from above, until it's snug. Hand-tight is enough.",
                    part: "slip nut", tool: "Your hands",
                    caution: "Stop if it creaks. Overtightening cracks the nut."
                ),
                RepairStep(
                    title: "Reseat the washer",
                    instruction: "If it still drips, unscrew the nut and slide it up. Seat the flat washer square, bevelled side down into the trap, then hand-tighten again.",
                    part: "upper slip nut", tool: "Your hands"
                ),
                RepairStep(
                    title: "Test it",
                    instruction: "Run the tap for thirty seconds, then wipe the joint with a dry tissue. If the tissue stays dry, you're done.",
                    part: "tailpiece", tool: "Dry tissue"
                ),
            ],
            spokenIntro: "That drip is coming from the slip joint on the trap under your sink. It's an easy fix, about fifteen minutes, and I'll walk you through it.",
            illustrationPrompt: "Exploded view of a sink P-trap slip joint: slip nut, bevelled washer and tailpiece.",
            usedModel: "demo replay",
            isDemo: true
        ),
        regions: [
            "leaking pipe joint": CGRect(x: 0.43, y: 0.34, width: 0.22, height: 0.15),
            "bucket": CGRect(x: 0.35, y: 0.58, width: 0.51, height: 0.33),
            "slip nut": CGRect(x: 0.52, y: 0.42, width: 0.12, height: 0.07),
            "upper slip nut": CGRect(x: 0.52, y: 0.30, width: 0.12, height: 0.06),
            "waste arm": CGRect(x: 0.0, y: 0.35, width: 0.46, height: 0.06),
            "tailpiece": CGRect(x: 0.50, y: 0.20, width: 0.16, height: 0.10),
        ],
        answers: [
            DemoAnswer(
                keywords: ["nut", "screw", "what's this", "what is this", "plastic ring"],
                answer: "That's the slip nut. It squeezes a washer against the pipe to seal the joint. Turn it clockwise by hand.",
                highlight: "slip nut",
                chip: "What's this nut?"
            ),
            DemoAnswer(
                keywords: ["pliers", "tool", "wrench", "spanner"],
                answer: "Hands first. Only use groove-joint pliers if it's stuck, and wrap the jaws in a cloth so you don't crack the plastic.",
                chip: "Do I need pliers?"
            ),
            DemoAnswer(
                keywords: ["washer", "seal", "rubber", "bevel"],
                answer: "The washer is the flat ring inside the nut. Its bevelled side faces down into the trap.",
                highlight: "upper slip nut",
                chip: "Which way does the washer go?"
            ),
            DemoAnswer(
                keywords: ["bucket", "water", "drip"],
                answer: "Keep the bucket under the curved part of the trap. That's where the water sits.",
                highlight: "bucket",
                chip: "Where does the bucket go?"
            ),
            DemoAnswer(
                keywords: ["still", "test", "dry"],
                answer: "If the tissue gets damp, give the nut another quarter turn, or replace the washer. They cost very little at any hardware store.",
                highlight: "tailpiece",
                chip: "What if it still drips?"
            ),
        ]
    )

    // MARK: Slipping chain (DemoMachine)

    static let bike = DemoScene(
        id: "bike",
        domain: .vehicle,
        title: "Slipping drive chain",
        subtitle: "Motorbike rear wheel",
        assetName: "DemoMachine",
        utterance: "My bike chain keeps slipping, what's wrong?",
        tapPoint: CGPoint(x: 0.48, y: 0.45),
        targetPart: "drive chain",
        plan: RepairPlan(
            domain: .vehicle,
            objectName: "Motorcycle drive chain",
            partName: "Drive chain",
            fault: "The chain is too slack and dry",
            faultDetail: "The chain hangs well below the swingarm and the links look rusty. A slack chain can ride up and jump the sprocket teeth, which is the slipping you feel.",
            likelyCause: "Normal chain stretch, plus missed lubrication.",
            hazard: .caution,
            hazardReason: "Engine off and key out. Let the exhaust cool, and never turn the wheel with the engine running.",
            confidence: 0.78,
            difficulty: "medium",
            minutes: 30,
            tools: ["Rear or paddock stand", "Socket for the axle nut", "Spanners for the adjusters", "Ruler", "Chain cleaner and chain lube", "Rag"],
            parts: [],
            avoid: [
                "Don't run the engine to turn the wheel.",
                "Don't overtighten. Most bikes want 20–30 mm of play.",
                "Don't use WD-40 as chain lube.",
            ],
            steps: [
                RepairStep(
                    title: "Make it safe",
                    instruction: "Engine off, key out, and put the bike on its stand with the rear wheel off the ground. Let the exhaust cool.",
                    part: "rear wheel", tool: "Rear stand"
                ),
                RepairStep(
                    title: "Check the slack",
                    instruction: "Push the lower run of the chain up and down at its midpoint. More than about three centimetres of movement means it needs adjusting.",
                    part: "lower chain run", tool: "Ruler"
                ),
                RepairStep(
                    title: "Loosen the axle nut",
                    instruction: "Loosen this big axle nut just enough for the wheel to slide. Don't take it off.",
                    part: "rear axle nut", tool: "Socket"
                ),
                RepairStep(
                    title: "Adjust both sides evenly",
                    instruction: "Turn each chain adjuster the same amount, a quarter turn at a time, until the slack is in spec. Match the marks on both sides, then retighten the axle nut.",
                    part: "chain adjuster", tool: "Spanners",
                    caution: "Uneven adjusters pull the wheel crooked."
                ),
                RepairStep(
                    title: "Clean and lube",
                    instruction: "Wipe the chain with cleaner on a rag while you turn the wheel by hand, then put lube on the inside of the chain.",
                    part: "drive chain", tool: "Chain cleaner and lube"
                ),
                RepairStep(
                    title: "Check the sprocket",
                    instruction: "Look at the sprocket teeth. If they're hooked or sharp like shark fins, replace the chain and sprockets together.",
                    part: "rear sprocket"
                ),
            ],
            spokenIntro: "Your chain is too slack and it's dry, so it's jumping the sprocket teeth. We can adjust and lube it in about half an hour. I'll go step by step.",
            illustrationPrompt: "Exploded view of a motorcycle rear axle with chain adjusters, axle nut, chain and sprocket.",
            usedModel: "demo replay",
            isDemo: true
        ),
        regions: [
            "drive chain": CGRect(x: 0.38, y: 0.13, width: 0.21, height: 0.68),
            "rear sprocket": CGRect(x: 0.07, y: 0.11, width: 0.33, height: 0.38),
            "rear axle nut": CGRect(x: 0.47, y: 0.26, width: 0.09, height: 0.09),
            "lower chain run": CGRect(x: 0.0, y: 0.48, width: 0.40, height: 0.17),
            "rear wheel": CGRect(x: 0.0, y: 0.45, width: 0.30, height: 0.50),
            "chain adjuster": CGRect(x: 0.40, y: 0.20, width: 0.20, height: 0.20),
        ],
        answers: [
            DemoAnswer(
                keywords: ["nut", "bolt", "screw", "what's this", "what is this"],
                answer: "That's the rear axle nut. It clamps the wheel in place. Loosen it only enough to slide the wheel.",
                highlight: "rear axle nut",
                chip: "What's this nut?"
            ),
            DemoAnswer(
                keywords: ["slack", "how tight", "how much", "play"],
                answer: "Most bikes want twenty to thirty millimetres of up-and-down play. The exact figure is in your manual or on a sticker on the swingarm.",
                highlight: "lower chain run",
                chip: "How much slack is right?"
            ),
            DemoAnswer(
                keywords: ["sprocket", "teeth", "worn", "shark"],
                answer: "Healthy teeth are symmetrical with rounded tips. Hooked or pointed teeth mean the sprocket is worn out.",
                highlight: "rear sprocket",
                chip: "Are these teeth worn?"
            ),
            DemoAnswer(
                keywords: ["lube", "oil", "wd", "grease"],
                answer: "Use proper chain lube on the inside of the chain, let it sit for a few minutes, then wipe off the excess.",
                highlight: "drive chain",
                chip: "Which lube should I use?"
            ),
            DemoAnswer(
                keywords: ["stand", "safe", "wheel"],
                answer: "A paddock stand under the swingarm lifts the rear wheel so it can spin freely. On the side stand, the wheel stays on the ground.",
                highlight: "rear wheel",
                chip: "Do I need a stand?"
            ),
        ]
    )

    // MARK: Safety stop (DemoHome photo, gas utterance)

    static let safety = DemoScene(
        id: "safety",
        domain: .home,
        title: "Safety stop demo",
        subtitle: "“I can smell gas…”",
        assetName: "DemoHome",
        utterance: "I can smell gas near the boiler. Can you help me fix it?",
        tapPoint: CGPoint(x: 0.5, y: 0.3),
        targetPart: "tailpiece",
        plan: .safetyStop(
            reason: SafetyGuard.reason(for: "gas") ?? "Gas work needs a registered engineer.",
            domain: .home, objectName: "Gas boiler", fault: "Possible gas leak", isDemo: true
        ),
        regions: [:],
        answers: []
    )
}
