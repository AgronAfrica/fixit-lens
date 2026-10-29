import CoreGraphics
import Foundation
import Testing
@testable import samdevna

@Suite("Muse Wonder review merge")
struct PlanReviewTests {
    let sink = DemoLibrary.sink.plan

    private func review(_ hazard: Hazard, _ category: String, _ reason: String, steps: [RepairStep] = []) -> RepairPlan {
        var plan = sink
        plan.hazard = hazard
        plan.stopCategory = category
        plan.hazardReason = reason
        plan.steps = steps
        plan.usedModel = MetaModel.wonder
        return plan
    }

    @Test("The live bug: a stop with no category and no steps keeps the sink plan at caution")
    func sinkStopWithoutCategory() {
        let merged = PlanReview.merge(original: sink, reviewed: review(.stop, "", "Water near an electrical socket"))
        #expect(merged.plan.hazard == .caution)
        #expect(merged.plan.steps.count == 5)
        #expect(merged.plan.spokenIntro != SafetyGuard.spokenStop)
    }

    @Test("A socket near the sink is not a mains-electrics job")
    func proximityIsCaution() {
        let merged = PlanReview.merge(original: sink, reviewed: review(.stop, "mains_electrics", "There is a socket near the sink"))
        #expect(merged.plan.hazard != .stop)
        #expect(merged.plan.steps.count == 5)
    }

    @Test("A real category with a matching reason stops the job")
    func realStop() {
        let merged = PlanReview.merge(original: sink, reviewed: review(.stop, "gas", "This is a gas water heater; call a registered gas engineer"))
        #expect(merged.plan.hazard == .stop)
        #expect(merged.plan.steps.isEmpty)
        #expect(merged.plan.stopCategory == "gas")
    }

    @Test("A category without a matching reason is rejected")
    func categoryWithoutReason() {
        #expect(PlanReview.merge(original: sink, reviewed: review(.stop, "gas", "Hazard")).plan.hazard != .stop)
    }

    @Test("Empty or truncated reviews never remove steps; hazard never drops")
    func keepsSteps() {
        #expect(PlanReview.merge(original: sink, reviewed: review(.caution, "", "")).plan.steps.count == 5)
        let one = [RepairStep(title: "Fix", instruction: "Fix it.", part: "slip nut")]
        #expect(PlanReview.merge(original: sink, reviewed: review(.caution, "", "", steps: one)).plan.steps.count == 5)
        #expect(PlanReview.merge(original: sink, reviewed: review(.none, "", "")).plan.hazard == .caution)
    }

    @Test("Spark's step locations survive the review")
    func locationsCarryOver() {
        var original = sink
        original.steps[2].location = PartLocation(x: 0.5, y: 0.6, box: [0.45, 0.55, 0.55, 0.65])
        let reworded = sink.steps.map { RepairStep(title: $0.title, instruction: $0.instruction + " Gently.", part: $0.part) }
        let merged = PlanReview.merge(original: original, reviewed: review(.caution, "", "", steps: reworded))
        #expect(merged.plan.steps[2].location?.x == 0.5)
        #expect(merged.plan.steps[2].instruction.hasSuffix("Gently."))
    }
}

@Suite("Part locations from Muse Spark")
struct PartLocationTests {
    @Test("Points and boxes decode leniently and round-trip")
    func decode() throws {
        let json = #"{"object_name":"Sink","fault":"Leak","hazard":"caution","target_point":[540,780],"steps":[{"title":"A","instruction":"Do it","part":"slip nut","point":{"x":0.52,"y":0.61},"box":[0.48,0.57,0.56,0.65]},{"title":"B","instruction":"Then","part":"","point":null}]}"#
        let plan = try JSONDecoder().decode(RepairPlan.self, from: Data(json.utf8))
        #expect(abs((plan.target?.x ?? 0) - 0.54) < 0.001)
        #expect(plan.steps[0].location?.rect != nil)
        #expect(plan.steps[1].location == nil)
        let again = try JSONDecoder().decode(RepairPlan.self, from: JSONEncoder().encode(plan))
        #expect(again.steps[0].location == plan.steps[0].location)
    }

    @Test("Point-prompt masks that swallow the photo are rejected")
    func plausibility() {
        let estimate = PartLocation(x: 0.5, y: 0.5, box: [0.45, 0.45, 0.55, 0.55])
        #expect(Locator.plausible(maskFraction: 0.01, maskBoxFraction: 0.012, estimate: estimate))
        #expect(!Locator.plausible(maskFraction: 0.6, maskBoxFraction: 0.7, estimate: estimate))
        #expect(!Locator.plausible(maskFraction: 0.2, maskBoxFraction: 0.3, estimate: estimate))
    }
}
