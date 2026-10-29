import CoreGraphics
import XCTest

/// Demo replay end to end: no network or API key needed. Screenshots are attached for the submission.
final class FixitLensDemoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSinkDemoRunsTheGuide() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-hasOnboarded", "YES", "-language", "english", "-preferReplay", "YES", "-handsFree", "NO"]
        app.launch()

        let sample = app.buttons["sample.sink"]
        XCTAssertTrue(sample.waitForExistence(timeout: 15))
        attach(app, "1 Lens")
        sample.tap()

        let tapIt = app.buttons["lens.tapScripted"]
        XCTAssertTrue(tapIt.waitForExistence(timeout: 5))
        tapIt.tap()

        XCTAssertTrue(app.staticTexts["plan.fault"].waitForExistence(timeout: 15), "No repair plan")
        attach(app, "2 Plan")

        let start = app.buttons["plan.startGuide"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        XCTAssertTrue(app.staticTexts["guide.stepTitle"].waitForExistence(timeout: 10), "Guide didn't open")
        XCTAssertTrue(app.descendants(matching: .any)["guide.highlight"].waitForExistence(timeout: 5), "No highlight")
        attach(app, "3 Guide step 1")

        app.buttons["guide.next"].tap()
        app.buttons["guide.next"].tap()
        app.buttons["guide.ask"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["guide.answer"].waitForExistence(timeout: 10), "No answer")
        attach(app, "4 Question answered")

        app.buttons["guide.gas"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["guide.safetyStop"].waitForExistence(timeout: 10), "No safety stop")
        attach(app, "5 Safety stop")
    }

    @MainActor
    func testSafetyDemoRefusesToGuide() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-hasOnboarded", "YES", "-preferReplay", "YES"]
        app.launch()
        let sample = app.buttons["sample.safety"]
        XCTAssertTrue(sample.waitForExistence(timeout: 15))
        sample.tap()
        XCTAssertTrue(app.descendants(matching: .any)["plan.safetyStop"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["plan.startGuide"].exists)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Live Meta pipeline. Skipped unless LIVE_META=1 and MODEL_API_KEY are set in the test scheme.
final class FixitLensLiveUITests: XCTestCase {
    @MainActor
    func testLiveSinkPipelineCallsMeta() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["LIVE_META"] == "1", "Set LIVE_META=1 to run against the Meta Model API")
        let app = XCUIApplication()
        app.launchArguments += ["-hasOnboarded", "YES", "-language", "english", "-preferReplay", "NO"]
        if let key = env["MODEL_API_KEY"] { app.launchEnvironment["MODEL_API_KEY"] = key }
        app.launch()

        app.buttons["sample.sink"].tap()
        app.buttons["lens.tapScripted"].tap()
        XCTAssertTrue(app.staticTexts["plan.fault"].waitForExistence(timeout: 120), "No plan from Muse Spark")
        for model in ["sam-3.1", "muse-spark-1.3", "muse-wonder-1.0", "muse-image-1.0"] {
            XCTAssertTrue(app.descendants(matching: .any)["trace.\(model).ok"].waitForExistence(timeout: 180), "\(model) not called")
        }
    }
}
