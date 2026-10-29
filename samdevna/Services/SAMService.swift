import CoreGraphics
import Foundation
import UIKit

/// SAM 3.1 on `POST /v1/responses`: point prompts (a tap) and concept prompts (a noun phrase).
struct SAMService {
    let client = MetaClient.shared

    /// `image` must come from `ImageCodec.normalized` so prompt and box coordinates share its pixel space.
    func segment(image: UIImage, prompt: String, purpose: String) async throws -> [SAMObject] {
        let dataURL = await Task.detached(priority: .userInitiated) { ImageCodec.jpegDataURL(image) }.value
        guard let dataURL else { throw FixError.noImage }
        let response = try await client.responses(model: MetaModel.sam, purpose: purpose, body: [
            "input": [[
                "type": "message",
                "role": "user",
                "content": [
                    ["type": "input_text", "text": prompt],
                    ["type": "input_image", "image_url": dataURL],
                ],
            ]],
            "metadata": [
                "mask_encoding": "one_bit",
                "include_confidence": "true",
            ],
        ])
        let text = response.text
        let objects = await Task.detached(priority: .userInitiated) { SAMParser.parse(text) }.value
        if objects.isEmpty, !text.isEmpty {
            throw FixError.segmentation("Couldn't read the segmentation output.")
        }
        return objects
    }

    /// Segments whatever is under a tap at `pixel` (in the normalized image's pixel space).
    func object(at pixel: CGPoint, in image: UIImage) async throws -> SAMObject? {
        let prompt = SAMPrompt.point(
            x: Int(pixel.x), y: Int(pixel.y),
            width: Int(image.size.width), height: Int(image.size.height)
        )
        return try await segment(image: image, prompt: prompt, purpose: "Outline the tapped part").first
    }

    /// The most confident match for a noun phrase, or nil.
    func best(_ concept: String, in image: UIImage, purpose: String) async throws -> SAMObject? {
        let objects = try await segment(image: image, prompt: SAMPrompt.concept(concept), purpose: purpose)
        return objects.max { ($0.confidence ?? 0, $0.area) < ($1.confidence ?? 0, $1.area) }
    }
}
