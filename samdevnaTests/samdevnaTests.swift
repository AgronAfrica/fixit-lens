import CoreGraphics
import Foundation
import Testing
@testable import samdevna

@Suite("Voice commands")
struct VoiceIntentTests {
    @Test("Short replies drive the guide", arguments: [
        ("Done", VoiceIntent.next), ("okay, done thanks", .next), ("next step please", .next), ("listo", .next),
        ("go back", .back), ("say that again", .repeatStep), ("stop", .stop),
    ])
    func commands(_ input: String, _ expected: VoiceIntent) {
        #expect(VoiceIntent.parse(input) == expected)
    }

    @Test func questionsAreQuestions() {
        #expect(VoiceIntent.parse("what's this screw?") == .question("what's this screw?"))
        #expect(VoiceIntent.parse("the nut won't turn") == .question("the nut won't turn"))
    }
}

@Suite("Safety stop")
struct SafetyGuardTests {
    @Test(arguments: [
        "I can smell gas near the boiler", "the fuse box is sparking", "there's an exposed wire", "it's a 230V socket",
        "refrigerant is leaking", "fuel leak under the scooter", "propane heater",
    ])
    func stops(_ text: String) {
        #expect(SafetyGuard.reason(for: text) != nil)
    }

    @Test(arguments: ["replace the spark plug on my mower", "my bike chain slips", "the gasket is leaking", "dripping tap"])
    func allows(_ text: String) {
        #expect(SafetyGuard.reason(for: text) == nil)
    }

    @Test func enforceStripsSteps() {
        var plan = DemoLibrary.sink.plan
        plan.hazard = .none
        let stopped = SafetyGuard.enforce(plan, transcript: "there's a live wire behind it")
        #expect(stopped.hazard == .stop)
        #expect(stopped.steps.isEmpty)
        #expect(stopped.spokenIntro == SafetyGuard.spokenStop)
    }

    @Test func modelStopIsKept() {
        var plan = DemoLibrary.bike.plan
        plan.hazard = .stop
        plan.hazardReason = "Brake line damaged"
        let stopped = SafetyGuard.enforce(plan, transcript: "")
        #expect(stopped.steps.isEmpty)
        #expect(stopped.hazardReason == "Brake line damaged")
    }
}

@Suite("End of speech")
struct VoiceActivityTests {
    private func at(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }

    @Test func endsAfterSilence() {
        var vad = VoiceActivity(startedAt: at(0))
        for i in 0..<10 { #expect(vad.feed(0.005, at: at(Double(i) * 0.1)) == .listening) }
        for i in 10..<20 { _ = vad.feed(0.2, at: at(Double(i) * 0.1)) }
        #expect(vad.heardSpeech)
        var last = VoiceActivity.Decision.listening
        for i in 20..<33 { last = vad.feed(0.004, at: at(Double(i) * 0.1)) }
        #expect(last == .speechEnded)
    }

    @Test func givesUpWithoutSpeech() {
        var vad = VoiceActivity(startedAt: at(0))
        #expect(vad.feed(0.004, at: at(7.1)) == .noSpeech)
    }
}

@Suite("Model JSON")
struct ModelJSONTests {
    @Test func lenientPlan() throws {
        let raw = """
        Sure! ```json
        {"domain":"bike","object_name":"Bike","fault":"Slack chain","hazard":"none","confidence":78,"minutes":"20",
         "steps":[{"title":"Check","instruction":"Push the chain","part":"chain"},{"instruction":""}]}
        ```
        """
        let plan = try ModelJSON.plan(raw, fallbackDomain: .home)
        #expect(plan.domain == .vehicle)
        #expect(abs(plan.confidence - 0.78) < 0.001)
        #expect(plan.minutes == 20)
        #expect(plan.steps.count == 1)
        #expect(plan.steps.first?.part == "chain")
    }

    @Test func proseFallsBackWithoutInventedSteps() throws {
        let plan = try ModelJSON.plan("The washer inside the tap is worn and needs replacing.", fallbackDomain: .home)
        #expect(plan.steps.isEmpty)
        #expect(plan.fault.contains("washer"))
    }

    @Test func emptyReplyThrows() {
        #expect(throws: FixError.self) { try ModelJSON.plan("  ", fallbackDomain: .home) }
    }

    @Test func answerWithStringBool() {
        let answer = ModelJSON.answer(#"{"answer":"It's a slip nut","highlight":"slip nut","safety_stop":"false"}"#)
        #expect(answer == GuideAnswer(answer: "It's a slip nut", highlight: "slip nut"))
    }
}

@Suite("Demo replay data")
struct DemoLibraryTests {
    @Test(arguments: DemoLibrary.scenes.map(\.id))
    func everyHighlightResolves(_ id: String) throws {
        let scene = try #require(DemoLibrary.scene(id: id))
        for step in scene.plan.steps { #expect(scene.region(for: step.part) != nil, "\(step.part)") }
        for answer in scene.answers where !answer.highlight.isEmpty { #expect(scene.region(for: answer.highlight) != nil) }
        for rect in scene.regions.values { #expect(CGRect(x: 0, y: 0, width: 1, height: 1).insetBy(dx: -0.001, dy: -0.001).contains(rect)) }
        #expect(SafetyGuard.reason(for: scene.utterance) == nil)
        #expect(scene.plan.isDemo)
    }

    @Test func safetyDemoStops() throws {
        let scene = try #require(DemoLibrary.scene(id: "safety"))
        #expect(scene.plan.hazard == .stop)
        #expect(scene.plan.steps.isEmpty)
        #expect(SafetyGuard.reason(for: scene.utterance) != nil)
    }

    @Test func scriptedAnswersHighlight() {
        #expect(DemoLibrary.bike.answer(to: "what's this nut?", step: nil).highlight == "rear axle nut")
        #expect(DemoLibrary.sink.answer(to: "I smell gas", step: nil).safetyStop)
    }
}
