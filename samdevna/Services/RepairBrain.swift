import CoreGraphics
import Foundation
import UIKit

/// Reasoning on `POST /v1/responses`: Muse Spark 1.3 (see + diagnose + answer) and Muse Wonder 1.0 (plan review).
struct RepairBrain {
    let client = MetaClient.shared

    /// Muse Spark 1.3, multi-image: the close-up around what the user pointed at (if any) plus the whole scene
    /// with an amber ring at the tap. Runs in parallel with the SAM 3.1 point prompt, so it never waits for the mask.
    /// Returns the fault, the plan, and a normalized point/box for every step's part (used later as SAM prompts).
    func assess(closeUp: UIImage?, scene: UIImage, tap: CGPoint?, partHint: String, domain: RepairDomain, transcript: String, language: AppLanguage) async throws -> RepairPlan {
        let (closeURL, sceneURL) = await Task.detached(priority: .userInitiated) {
            (closeUp.flatMap { ImageCodec.jpegDataURL(ImageCodec.normalized($0, maxEdge: 768), quality: 0.8) },
             ImageCodec.jpegDataURL(ImageCodec.marked(ImageCodec.normalized(scene, maxEdge: 768), at: tap), quality: 0.7))
        }.value
        guard let sceneURL else { throw FixError.noImage }
        var content: [[String: Any]] = [
            ["type": "input_text", "text": Prompts.assessUser(domain: domain, partHint: partHint, transcript: transcript, language: language, hasCloseUp: closeURL != nil, tap: tap)],
        ]
        if let closeURL { content.append(["type": "input_image", "image_url": closeURL]) }
        content.append(["type": "input_image", "image_url": sceneURL])

        let response = try await client.responses(model: MetaModel.spark, purpose: "Identify the fault", body: [
            "instructions": Prompts.assessor,
            "input": [["type": "message", "role": "user", "content": content]],
            "reasoning": ["effort": "low"],
        ])
        var plan = try ModelJSON.plan(response.text, fallbackDomain: domain)
        plan.usedModel = MetaModel.spark
        plan.isDemo = false
        if plan.target == nil, let tap { plan.target = PartLocation(x: tap.x, y: tap.y) }
        return SafetyGuard.enforce(plan, transcript: transcript)
    }

    /// Muse Wonder 1.0: an independent safety and clarity review that runs in the background after the plan is shown.
    /// Merged by `PlanReview.merge`: it can never delete steps, and can only stop the job for a real stop category.
    func refine(_ plan: RepairPlan, language: AppLanguage) async throws -> (plan: RepairPlan, outcome: PlanReview.Outcome) {
        let encoded = String(decoding: try JSONEncoder().encode(plan), as: UTF8.self)
        let response = try await client.responses(model: MetaModel.wonder, purpose: "Check the repair plan", body: [
            "instructions": Prompts.reviewer,
            "input": Prompts.refineInput(encoded, language: language),
            "reasoning": ["effort": "low"],
        ])
        var reviewed = try ModelJSON.plan(response.text, fallbackDomain: plan.domain)
        reviewed.usedModel = MetaModel.wonder
        var (merged, outcome) = PlanReview.merge(original: plan, reviewed: reviewed)
        merged.id = plan.id
        merged.isDemo = false
        let enforced = SafetyGuard.enforce(merged, transcript: "")
        if enforced.hazard == .stop, merged.hazard != .stop { outcome = .stopped(enforced.hazardReason) }
        return (enforced, outcome)
    }

    /// Muse Spark 1.3 during the guide: answer a spoken question about the current step, looking at the photo.
    func answer(_ question: String, plan: RepairPlan, stepIndex: Int, scene: UIImage, language: AppLanguage) async throws -> GuideAnswer {
        let sceneURL = await Task.detached(priority: .userInitiated) {
            ImageCodec.jpegDataURL(ImageCodec.normalized(scene, maxEdge: 768), quality: 0.7)
        }.value
        var content: [[String: Any]] = [["type": "input_text", "text": Prompts.question(question, plan: plan, stepIndex: stepIndex, language: language)]]
        if let sceneURL { content.append(["type": "input_image", "image_url": sceneURL]) }
        let response = try await client.responses(model: MetaModel.spark, purpose: "Answer a question mid-repair", body: [
            "instructions": Prompts.guide,
            "input": [["type": "message", "role": "user", "content": content]],
            "reasoning": ["effort": "low"],
        ])
        var answer = ModelJSON.answer(response.text)
        if answer.answer.isEmpty { throw FixError.reasoning("No answer came back.") }
        if SafetyGuard.reason(for: question) != nil { answer.safetyStop = true }
        return answer
    }
}

enum Prompts {
    static let assessor = """
    You are Fix-it Lens, a calm, practical repair guide for everyday household repairs: sinks, taps, drains, \
    bikes, motorbikes, scooters, small appliances, furniture and fixtures. You get up to two images: an optional close-up \
    of exactly what the user pointed at, and the WHOLE SCENE (the last image) with an amber ring where they tapped. \
    Use both: the close-up for detail, the scene for context and for locating parts.

    Identify the object, the specific part, the most likely fault and its cause, then write a short, safe, \
    step-by-step repair a first-timer can do with common tools.

    SAFETY RULES (non-negotiable):
    - Set hazard to "stop", stop_category, hazard_reason, and an EMPTY steps array ONLY if the job itself involves: \
    gas or gas appliances (stop_category "gas"); mains or hard-wired electricity, fuse boxes, breaker panels, exposed live wiring, \
    sparking or burning smells ("mains_electrics"); refrigerant, microwave or CRT interiors ("refrigerant"); airbags ("airbags"); \
    fuel or brake-line leaks ("fuel_or_brake_leak"); structural damage ("structural"). Tell them to call a qualified professional.
    - Ordinary plumbing (traps, taps, washers, drains), bike and motorbike chains, brakes adjustment, hinges and furniture are "caution" \
    or "none", never "stop". A socket or light NEAR water is "caution": say to keep it dry or switch it off first.
    - Only describe objects and machines. If the image shows a person, an animal, an injury, medicine or anything medical, \
    do not assess it: set hazard to "stop", stop_category "not_a_repair", hazard_reason "Fix-it Lens only helps with objects and repairs.", and empty steps.
    - Never guess at certainty you don't have. If the photo is unclear, say what to check first as step 1.

    LOCATIONS: coordinates are normalized to the WHOLE-SCENE image, 0 to 1, origin top-left.
    For each step whose "part" is visible, give "point": [x, y] at the centre of that part and "box": [x0, y0, x1, y1] around it. \
    Small parts (nuts, washers, screws, valves) need a tight box. Use null if the part is not visible.

    Return ONLY JSON with keys:
    domain (home|vehicle|appliance), object_name, part_name, fault, fault_detail, likely_cause,
    hazard (none|caution|stop), stop_category ("" unless stop), hazard_reason, confidence (0-1), difficulty (easy|medium|hard), minutes (integer),
    target_point ([x, y] of the faulty part), target_box ([x0, y0, x1, y1]),
    tools (array), parts (array of spare parts, may be empty), avoid (array),
    steps (array of 3-7 objects: {title, instruction, part, tool, caution, point, box}),
    spoken_intro (two short spoken sentences: what's wrong and that you'll guide them),
    illustration_prompt (English prompt for a clean exploded-view illustration of the fix).
    "part" in each step is a SHORT ENGLISH NOUN PHRASE naming one visible thing in the photo to highlight (e.g. "slip nut", "rear axle nut"), or "" if nothing visible.
    Each instruction is one or two short sentences that can be read aloud. Write every sentence in the reply language; keep JSON keys and "part" in English.
    """

    static let reviewer = """
    You are an independent safety reviewer for repair plans written by another model, before they are read aloud, hands-free, \
    to someone holding tools. Improve the plan; do not replace it.

    ALWAYS return the full steps array (same schema, including each step's "point" and "box" unchanged). Never return an empty steps array.
    - Check the order. Add a missing "make it safe" step at the start if needed (isolate the water, unplug, put the bike on a stand, engine off and cool).
    - Make each instruction short and speakable. Keep every "part" a short English noun phrase visible in the photo.
    - You may raise hazard from "none" to "caution" with a hazard_reason. Never lower it.
    - Set hazard to "stop" ONLY if the job itself is one of these, and then set stop_category to exactly one of: \
    "gas", "mains_electrics" (working on mains or hard-wired circuits, fuse boxes, live wiring, sparking), "refrigerant", \
    "airbags", "fuel_or_brake_leak", "structural"; hazard_reason must name it explicitly (for example "This is a gas appliance").
    - These are NOT stops: sink traps, taps, washers, drains, toilets, bike or motorbike chains, sprockets, brake adjustment, hinges, \
    furniture. Water near a socket or light is "caution" (keep it dry, switch off at the socket), never "stop".
    If unsure, keep the original hazard and steps.
    """

    static let guide = """
    You are Fix-it Lens, talking someone through a repair hands-free. They asked a question out loud mid-repair.
    Look at the photo and the current step. Answer in at most two short spoken sentences.
    If they ask what something is, name it and set "highlight" to a SHORT ENGLISH NOUN PHRASE for that visible thing, \
    and "point" to [x, y], its centre normalized 0-1 on the photo (origin top-left); otherwise "" and null.
    If the question involves gas, mains electricity, sparking, burning smells, or anything medical or about a person, \
    set safety_stop true and tell them to stop and call a professional.
    Return ONLY JSON: {"answer": string, "highlight": string, "point": [x, y] or null, "safety_stop": boolean}.
    """

    static func assessUser(domain: RepairDomain, partHint: String, transcript: String, language: AppLanguage, hasCloseUp: Bool, tap: CGPoint?) -> String {
        let pointed = tap.map { String(format: "The user tapped at x=%.2f, y=%.2f (amber ring on the scene).", $0.x, $0.y) }
            ?? "The user did not tap; find the part they describe in the scene."
        return """
        Domain: \(domain.rawValue).
        \(pointed) \(hasCloseUp ? "The first image is a close-up around that point." : "Only the scene image is attached.")
        \(partHint.isEmpty ? "" : "Already outlined: \(partHint).")
        Reply language: \(language.label).
        User said: \(transcript.isEmpty ? "(nothing — they tapped it; tell them what's wrong and how to fix it)" : transcript)
        Write JSON only.
        """
    }

    static func refineInput(_ planJSON: String, language: AppLanguage) -> String {
        """
        Reply in \(language.label). Keep JSON keys and every "part" in English.
        Input plan JSON:
        \(planJSON)
        Return the same JSON schema, improved.
        """
    }

    static func question(_ question: String, plan: RepairPlan, stepIndex: Int, language: AppLanguage) -> String {
        let step = plan.steps.indices.contains(stepIndex) ? plan.steps[stepIndex] : nil
        return """
        Object: \(plan.objectName). Fault: \(plan.fault).
        Current step \(stepIndex + 1) of \(plan.steps.count): \(step.map { "\($0.title) — \($0.instruction)" } ?? "none").
        Tools in the plan: \(plan.tools.joined(separator: ", ")).
        Reply language: \(language.label).
        Question: \(question)
        """
    }
}

extension ImageCodec {
    /// Square close-up around a normalized point (side = `fraction` of the shorter edge), for Muse Spark to read
    /// detail while SAM 3.1 is still segmenting. `image` should already be normalized (1x scale).
    static func closeUp(_ image: UIImage, around point: CGPoint, fraction: CGFloat = 0.42) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let side = min(w, h) * fraction
        let cx = point.x * w, cy = point.y * h
        let rect = CGRect(x: min(max(cx - side / 2, 0), w - side), y: min(max(cy - side / 2, 0), h - side), width: side, height: side).integral
        guard let cropped = cg.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped)
    }

    /// The scene with an amber ring at the tap, so Spark knows which thing in the scene the user meant.
    static func marked(_ image: UIImage, at point: CGPoint?) -> UIImage {
        guard let point else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            image.draw(at: .zero)
            let radius = max(image.size.width, image.size.height) * 0.035
            let centre = CGPoint(x: point.x * image.size.width, y: point.y * image.size.height)
            let ring = CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
            context.cgContext.setStrokeColor(UIColor(red: 1, green: 0.69, blue: 0.125, alpha: 1).cgColor)
            context.cgContext.setLineWidth(max(3, radius * 0.18))
            context.cgContext.strokeEllipse(in: ring)
        }
    }
}
