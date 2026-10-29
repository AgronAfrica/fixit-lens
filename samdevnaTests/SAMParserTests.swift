import CoreGraphics
import XCTest
@testable import samdevna

final class SAMParserTests: XCTestCase {
    /// A real `sam-3.1` point-prompt response recorded on an 853×1280 photo.
    private let liveLine = #"<0f>1<|box;x1=420;y1=709;x2=640;y2=851;w=853;h=1280;c=0.84765625|><|mask;x=0;y=0;c=0.84765625;data=143,221,!!!!#jDSfvunjOg$y32+Ds?A(v?8son1`X9_qL+xX^=SxabDwlA5myc7H0O4(3J9Z)wf1x6A_ELV'dxLyk1nS&mFu+kmZIog9/8%V*2R_YN]Z#*=`#Mx3P'If5/0*oqX?N3wWqddfEdC#3SOj%PL4I+gF&j-uX9Z+I@I]ho8G3sL@+qMNW'u_&1e!5C5OSp.U)s:|>"#

    func testDecodesLiveMaskExactlyLikeMetaParser() throws {
        let objects = SAMParser.parse(liveLine)
        XCTAssertEqual(objects.count, 1)
        let object = try XCTUnwrap(objects.first)
        XCTAssertEqual(object.id, 1)
        XCTAssertEqual(object.box, SAMBox(x1: 420, y1: 709, x2: 640, y2: 851, width: 853, height: 1280, confidence: 0.84765625))
        XCTAssertEqual(object.maskWidth, 221)
        XCTAssertEqual(object.maskHeight, 143)
        XCTAssertTrue(object.hasRaster)

        // Reference values from @meta-sam/parser 0.1.0 decodeMaskToRaster on the same payload.
        var ones = 0
        var weighted = 0
        for (index, bit) in object.raster.enumerated() where bit == 1 {
            ones += 1
            weighted = (weighted + index) % 1_000_000_007
        }
        XCTAssertEqual(ones, 16313)
        XCTAssertEqual(weighted, 265_885_117)
        XCTAssertNotNil(object.overlay)
        XCTAssertEqual(object.maskRect, CGRect(x: 420, y: 709, width: 221, height: 143))
    }

    func testRejectsCorruptMask() {
        XCTAssertNil(SAMMaskCodec.decode("!!!!#jDSfvunjOg", width: 221, height: 143))
        XCTAssertNil(SAMMaskCodec.decode("~abc", width: 10, height: 10))
    }

    func testPointPromptGrammar() {
        XCTAssertEqual(
            SAMPrompt.point(x: 300, y: 150, width: 1920, height: 1080),
            "<0f>1<|point;x=300;y=150;w=1920;h=1080|>"
        )
    }

    func testFillTransformRoundTrip() {
        // 853×1280 photo shown aspect-fill on a 402×874 screen: scaled by height, cropped left/right.
        let transform = FillTransform(imageSize: CGSize(width: 853, height: 1280), viewSize: CGSize(width: 402, height: 874))
        XCTAssertEqual(transform.scale, 874.0 / 1280.0, accuracy: 0.0001)
        let center = transform.toImage(CGPoint(x: 201, y: 437))
        XCTAssertEqual(center.x, 426.5, accuracy: 0.5)
        XCTAssertEqual(center.y, 640, accuracy: 0.5)
        let rect = transform.toView(CGRect(x: 0, y: 0, width: 853, height: 1280))
        XCTAssertEqual(rect.midX, 201, accuracy: 0.5)
        XCTAssertEqual(rect.height, 874, accuracy: 0.5)
    }

    func testLenientPlanDecoding() throws {
        let json = #"{"domain":"Plumbing","hazard":"Caution","confidence":"0.8","tools":"Spanner","steps":["Turn off the water"],"fault":"Dripping tap"}"#
        let plan = try ModelJSON.plan(json, fallbackDomain: .appliance)
        XCTAssertEqual(plan.domain, .home)
        XCTAssertEqual(plan.hazard, .caution)
        XCTAssertEqual(plan.confidence, 0.8, accuracy: 0.001)
        XCTAssertEqual(plan.tools, ["Spanner"])
        XCTAssertEqual(plan.steps.map(\.instruction), ["Turn off the water"])
    }

    func testDemoRegionMapsIntoImagePixels() {
        let object = SAMObject.region(CGRect(x: 0.5, y: 0.25, width: 0.25, height: 0.5), in: CGSize(width: 800, height: 1200))
        XCTAssertEqual(object.box.rect, CGRect(x: 400, y: 300, width: 201, height: 601))
        XCTAssertTrue(object.isDemoRegion)
        XCTAssertFalse(object.hasRaster)
    }
}
