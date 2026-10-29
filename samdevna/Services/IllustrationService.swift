import CoreGraphics
import Foundation
import UIKit

/// Muse Image 1.0 on `POST /v1/responses` with the `image_generation` tool: an exploded-view guide of the fix.
struct IllustrationService {
    let client = MetaClient.shared

    func illustrate(_ plan: RepairPlan, reference: UIImage?, language: AppLanguage) async throws -> UIImage {
        let referenceURL: String? = await Task.detached(priority: .utility) {
            reference.flatMap { ImageCodec.jpegDataURL(ImageCodec.normalized($0, maxEdge: 1024), quality: 0.8) }
        }.value
        var content: [[String: Any]] = [["type": "input_text", "text": prompt(for: plan, language: language)]]
        if let referenceURL { content.append(["type": "input_image", "image_url": referenceURL]) }

        let response = try await client.responses(model: MetaModel.image, purpose: "Draw the repair guide", body: [
            "input": [["type": "message", "role": "user", "content": content]],
            "tools": [[
                "type": "image_generation",
                "enable_web_search": false,
                "enable_shell": true,
                "reasoning_strength": "low",
                "size": "1024x1024",
                "output_format": "png",
            ]],
        ])
        guard let data = response.imageData, let image = UIImage(data: data) else {
            throw FixError.illustration("No image came back.")
        }
        return image
    }

    private func prompt(for plan: RepairPlan, language: AppLanguage) -> String {
        let base = plan.illustrationPrompt.isEmpty
            ? "Exploded-view repair illustration: how to fix the \(plan.partName.isEmpty ? plan.objectName : plan.partName) — \(plan.fault)."
            : plan.illustrationPrompt
        let steps = plan.steps.prefix(4).enumerated().map { "\($0.offset + 1). \($0.element.title)" }.joined(separator: "\n")
        return """
        \(base)
        Show these steps as numbered panels:
        \(steps)
        Style: clean technical manual illustration, dark charcoal background, signal-amber highlights on the part being worked on, \
        large readable labels in \(language.label), hands holding tools, no brand logos, no people's faces. The reference photo shows the real object.
        """
    }
}
