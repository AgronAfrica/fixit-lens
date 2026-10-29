import CoreGraphics
import SwiftUI
import UIKit

// MARK: - SAM 3.1 output

struct SAMBox: Equatable, Sendable {
    var x1: Int
    var y1: Int
    var x2: Int
    var y2: Int
    var width: Int
    var height: Int
    var confidence: Double?

    /// SAM boxes are inclusive of `x2`/`y2`.
    var rect: CGRect {
        CGRect(x: x1, y: y1, width: max(1, x2 - x1 + 1), height: max(1, y2 - y1 + 1))
    }
}

struct SAMObject: Identifiable {
    var id: Int
    var box: SAMBox
    var maskWidth: Int
    var maskHeight: Int
    var raster: [UInt8]
    var overlay: UIImage?
    /// True for the hand-placed regions used by demo replay (not live SAM output).
    var isDemoRegion = false

    var confidence: Double? { box.confidence }
    var hasRaster: Bool { maskWidth > 0 && raster.count == maskWidth * maskHeight }
    var area: Int { hasRaster ? raster.reduce(0) { $0 + Int($1) } : Int(box.rect.width * box.rect.height) }

    /// Masks cover the box region, starting at its top-left corner.
    var maskRect: CGRect {
        hasRaster
            ? CGRect(x: box.x1, y: box.y1, width: maskWidth, height: maskHeight)
            : box.rect
    }

    /// A box-only region from a rect normalised to 0…1 in `imageSize`. Used by demo replay.
    static func region(_ normalized: CGRect, in imageSize: CGSize, id: Int = 1) -> SAMObject {
        let w = Int(imageSize.width), h = Int(imageSize.height)
        let x1 = Int((normalized.minX * imageSize.width).rounded())
        let y1 = Int((normalized.minY * imageSize.height).rounded())
        let x2 = min(w - 1, Int((normalized.maxX * imageSize.width).rounded()))
        let y2 = min(h - 1, Int((normalized.maxY * imageSize.height).rounded()))
        return SAMObject(
            id: id,
            box: SAMBox(x1: x1, y1: y1, x2: max(x1, x2), y2: max(y1, y2), width: w, height: h, confidence: nil),
            maskWidth: 0, maskHeight: 0, raster: [], overlay: nil, isDemoRegion: true
        )
    }
}

// MARK: - Pipeline

/// The four beats of the Fix-it Lens pipeline, shown as a rail on the lens.
enum PipelineStep: String, CaseIterable, Identifiable {
    case see, hear, reason, guide

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var model: String {
        switch self {
        case .see: "SAM 3.1"
        case .hear: "Voice Transcribe"
        case .reason: "Spark · Wonder"
        case .guide: "Guide · Image"
        }
    }

    var glyph: String {
        switch self {
        case .see: "viewfinder"
        case .hear: "waveform"
        case .reason: "brain"
        case .guide: "wrench.and.screwdriver.fill"
        }
    }
}

enum PipelineStage: Equatable {
    case idle
    case listening
    case transcribing
    case segmenting
    case diagnosing
    case planning
    case ready
    case stopped
    case failed(String)

    var message: String {
        switch self {
        case .idle: "Tap the broken part, or hold the mic and say what's wrong."
        case .listening: "Listening… let go when you're done."
        case .transcribing: "Muse Voice Transcribe is reading what you said…"
        case .segmenting: "SAM 3.1 is outlining the exact part…"
        case .diagnosing: "Muse Spark 1.3 is working out the fault…"
        case .planning: "Plan ready. Safety check running (Muse Wonder) while Muse Image draws it…"
        case .ready: "Repair plan ready. Start the hands-free guide."
        case .stopped: "Safety stop. This one is for a professional."
        case .failed(let message): message
        }
    }

    var isBusy: Bool {
        switch self {
        // .planning is background work (review + illustration): the plan is already usable.
        case .transcribing, .segmenting, .diagnosing: true
        default: false
        }
    }

    var activeStep: PipelineStep? {
        switch self {
        case .listening, .transcribing: .hear
        case .segmenting: .see
        case .diagnosing: .reason
        case .planning, .ready: .guide
        default: nil
        }
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

enum IllustrationState: Equatable {
    case none
    case drawing
    case ready
    case failed
}

struct TapMark: Identifiable, Equatable {
    let id = UUID()
    let point: CGPoint
}

// MARK: - Hands-free guide

enum GuidePhase: Equatable {
    /// SAM 3.1 is finding this step's part on the photo.
    case locating
    case speaking
    case listening
    /// Muse Voice Transcribe is turning the reply into text.
    case hearing
    /// Muse Spark is answering a question.
    case thinking
    /// Hands-free is off: waiting for a button.
    case waiting
    case finished

    var label: String {
        switch self {
        case .locating: "Finding the part"
        case .speaking: "Speaking"
        case .listening: "Listening — say “done” or ask a question"
        case .hearing: "Transcribing"
        case .thinking: "Thinking"
        case .waiting: "Tap Next when you're ready"
        case .finished: "All done"
        }
    }

    var glyph: String {
        switch self {
        case .locating: "viewfinder"
        case .speaking: "speaker.wave.2.fill"
        case .listening: "mic.fill"
        case .hearing: "waveform"
        case .thinking: "brain"
        case .waiting: "hand.tap.fill"
        case .finished: "checkmark.seal.fill"
        }
    }

    var tint: Color {
        switch self {
        case .listening: Palette.sky
        case .finished: Palette.teal
        default: Palette.amber
        }
    }
}

struct GuideExchange: Identifiable, Equatable {
    let id = UUID()
    let question: String
    let answer: String
}

// MARK: - Colours for model enums

extension RepairDomain {
    var tint: Color {
        switch self {
        case .home: Palette.sky
        case .vehicle: Palette.amber
        case .appliance: Palette.teal
        }
    }
}

extension Hazard {
    var tint: Color {
        switch self {
        case .none: Palette.teal
        case .caution: Palette.saffron
        case .stop: Palette.coral
        }
    }
}

// MARK: - Background safety review

/// Muse Wonder's review runs after the plan is on screen; this drives the "Safety check running" badge.
enum ReviewState: Equatable {
    case idle
    case running
    /// Reviewed; wording or order improved, hazard unchanged.
    case passed
    /// Reviewed and raised to caution, with the reviewer's reason.
    case raised(String)
    /// Reviewed and stopped for a real professional-only category.
    case stopped(String)
    /// The review claimed a stop without a valid category; the plan was kept at caution.
    case overruled(String)
    case failed

    var label: String {
        switch self {
        case .idle: ""
        case .running: "Safety check running · Muse Wonder"
        case .passed: "Safety-checked · Muse Wonder"
        case .raised: "Safety-checked · extra caution added"
        case .stopped: "Safety check stopped this job"
        case .overruled: "Safety-checked · kept at caution"
        case .failed: "Safety check unavailable · local rules applied"
        }
    }
}

// MARK: - Live progress timeline

/// One row in the live pipeline timeline: which Meta model is doing what, and how long it took.
struct ProgressItem: Identifiable, Equatable {
    enum Status: Equatable { case running, done, skipped, failed }

    let id: String
    let model: String
    let label: String
    let started: Date
    var finished: Date?
    var status: Status = .running
    var detail: String = ""

    var seconds: Double? { finished.map { $0.timeIntervalSince(started) } }
}
