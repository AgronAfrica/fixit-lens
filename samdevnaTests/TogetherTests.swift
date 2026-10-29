import Foundation
import Testing
@testable import samdevna

/// Fix it together: wire protocol (shared with together/web and the relay), join codes, pacing and tracking.
/// The same checks also run on Linux in a plain harness.
@Suite("Fix it together protocol")
struct TogetherTests {
    private struct Seeded: RandomNumberGenerator {
        var s: UInt64
        mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s }
    }

    @Test func protocolCodesPacingAndTracking() {
        // Codes and links
        var g = Seeded(s: 42)
        let code = Together.newCode(using: &g)
        #expect(code.count == 6 && code.allSatisfy { Together.codeAlphabet.contains($0) }, "code alphabet/length")
        #expect(!code.contains("0") && !code.contains("O") && !code.contains("I") && !code.contains("1"), "no look-alikes")
        #expect(Together.normalize(code: " k7m-2qx ") == "K7M2QX", "normalize spaced/dashed")
        #expect(Together.normalize(code: "AB") == nil && Together.normalize(code: "ABCDEFGHJ") == nil, "length bounds")
        #expect(Together.normalize(code: "K7M0QX") == nil, "reject 0")
        let share = Together.shareURL(relay: URL(string: "https://fixit-together.example.workers.dev")!, code: "K7M2QX")
        #expect(share.absoluteString == "https://fixit-together.example.workers.dev/j/K7M2QX", "share URL")
        #expect(Together.code(from: share.absoluteString) == "K7M2QX", "code from share link")
        #expect(Together.code(from: "fixitlens://join?code=k7m2qx") == "K7M2QX", "code from app link")
        #expect(Together.code(from: "K7M2QX") == "K7M2QX", "bare code")
        #expect(Together.code(from: "https://example.com/other") == nil, "no code in random link")

        // Binary media
        let m = TogetherMedia(kind: .jpeg, seq: 0x01020304, payload: Data([0xFF, 0xD8, 0xFF]))
        let enc = m.encoded()
        #expect(Array(enc.prefix(5)) == [0x01, 0x01, 0x02, 0x03, 0x04], "media header BE seq")
        #expect(TogetherMedia(enc) == m, "media round trip")
        #expect(TogetherMedia(Data([0x09, 0, 0, 0, 1])) == nil, "unknown kind rejected")
        #expect(TogetherMedia(Data([0x01, 0, 0])) == nil, "short frame rejected")
        let w = TogetherMedia(kind: .wav, seq: 7, payload: Data("RIFF".utf8))
        #expect(TogetherMedia(w.encoded())?.kind == .wav, "wav kind")

        // Messages (wire-compatible with web/app.js, key "t")
        let tap = TogetherMessage.tap(seq: 12, x: 0.25, y: 0.75, by: "Sam")
        #expect(tap.json().contains("\"t\":\"tap\""), "tap json has t")
        #expect(TogetherMessage.parse(tap.json()) == tap, "tap round trip")
        #expect(TogetherMessage.parse(#"{"t":"tap","seq":3,"x":0.5,"y":0.4,"by":"web"}"#) == .tap(seq: 3, x: 0.5, y: 0.4, by: "web"), "parse web tap")
        let mask = SharedMask(id: 1, seq: 12, box: [0.1, 0.2, 0.3, 0.4], png: "", label: "slip nut", confidence: 0.9, by: "Sam", model: "sam-3.1")
        #expect(TogetherMessage.parse(TogetherMessage.mask(mask).json()) == .mask(mask), "mask round trip")
        let cap = Caption(id: "c1", from: .fixer, name: "Ana", original: "¿Cuál tuerca?", originalLanguage: "es", translated: "Which nut?", translatedLanguage: "en", at: 1)
        #expect(TogetherMessage.parse(TogetherMessage.caption(cap).json()) == .caption(cap), "caption round trip (unicode)")
        #expect(TogetherMessage.parse(TogetherMessage.safety(reason: "Gas smell").json()) == .safety(reason: "Gas smell"), "safety round trip")
        #expect(TogetherMessage.parse(TogetherMessage.memory(steps: ["a", "b"], title: "T").json()) == .memory(steps: ["a", "b"], title: "T"), "memory round trip")
        #expect(TogetherMessage.parse(TogetherMessage.clearMask.json()) == .clearMask, "clear round trip")
        #expect(TogetherMessage.parse(#"{"t":"future_thing","x":1}"#) == .unknown("future_thing"), "unknown type tolerated")
        #expect(TogetherMessage.parse("not json") == nil, "garbage rejected")

        // Pacer: live → snapshot when acks stop → live again
        var p = StreamPacer()
        #expect(p.shouldSend(now: 0, hasViewers: false) == false, "no viewers no send")
        #expect(p.shouldSend(now: 0, hasViewers: true), "first frame")
        p.didSend(seq: 1, now: 0)
        #expect(!p.shouldSend(now: 0.01, hasViewers: true), "respect live interval")
        #expect(p.shouldSend(now: 0.1, hasViewers: true), "second frame")
        p.didSend(seq: 2, now: 0.1)
        #expect(!p.shouldSend(now: 0.3, hasViewers: true), "max in flight")
        _ = p.shouldSend(now: 4.0, hasViewers: true)
        #expect(p.mode == .snapshot, "degrade to snapshot without acks")
        #expect(p.shouldSend(now: 5.1, hasViewers: true), "snapshot 1/s")
        p.didSend(seq: 3, now: 5.1)
        for (i, s) in [UInt32(3), 4, 5].enumerated() { p.didSend(seq: s, now: 6 + Double(i)); p.didAck(seq: s, now: 6.05 + Double(i)) }
        #expect(p.mode == .live, "recover to live after acks")

        // Tracker
        var t = MaskTracker()
        t.reset(to: [0.4, 0.4, 0.5, 0.5], now: 0)
        #expect(t.nextPrompt(now: 0.5) == nil, "not yet")
        let pt = t.nextPrompt(now: 1.3)
        #expect(pt != nil && abs(pt!.x - 0.45) < 1e-9, "prompt at centre")
        #expect(t.nextPrompt(now: 3) == nil, "busy while in flight")
        #expect(t.update(with: [0.42, 0.41, 0.52, 0.51]), "accept nearby")
        _ = t.nextPrompt(now: 3)
        #expect(!t.update(with: [0.0, 0.0, 1.0, 1.0]), "reject huge jump/growth")
        for k in 0..<3 { _ = t.nextPrompt(now: 5 + Double(k) * 2); t.update(with: nil) }
        #expect(t.isLost, "lost after misses")


    }
}
