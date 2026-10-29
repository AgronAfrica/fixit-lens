# Third-party notices and asset provenance

| Item | Where | Source | Licence / rights | Status |
|---|---|---|---|---|
| `one_bit` SAM mask decoder | `samdevna/Services/SAMParser.swift` (`SAMMaskCodec`) | Swift port of `mask-codec.js` in Meta's [`@meta-sam/parser` 0.1.0](https://cdn.jsdelivr.net/npm/@meta-sam/parser@0.1.0/) | SAM License. The full text is in `LICENSES/SAM-LICENSE.txt`, and the licence requires it to ship with derivative works | OK, with the licence included |
| Demo photo `DemoHome.png` (sink trap) | `Assets.xcassets/DemoHome.imageset` | Generated with Meta **Muse Image 1.0** via `scripts/generate_brand.py`. XMP tag `DigitalSourceType = trainedAlgorithmicMedia` | Meta Model API output terms | **Confirm** that the hackathon / Meta API terms let you use outputs in a public repo and demo video |
| Demo photo `DemoMachine.png` (chain and sprocket) | `Assets.xcassets/DemoMachine.imageset` | As above | As above | **Confirm** as above |
| App icon and logo | `AppIcon.appiconset`, `Logo.imageset` | Drawn from primitives by `scripts/generate_icon.py` (Pillow) during the hackathon. No model, font or third-party art | MIT, as part of this repo | OK. This replaces the received icon and logo, whose provenance was unknown |
| SF Symbols | used throughout the UI | Apple | Apple SF Symbols licence: use only in apps on Apple platforms; don't redistribute the glyphs as images | OK |
| Apple frameworks (SwiftUI, AVFoundation, Security) | system | Apple | Apple SDK licence | OK |

There are no Swift packages, CocoaPods or vendored code beyond the decoder above. The Python scripts need `requests` (Apache-2.0) and `Pillow` (MIT-CMU), both installed with pip and not vendored.

## Demo video concept clips

- `demo-video/public/concept/glasses_wearer_sink.mp4`, `glasses_wearer_together.mp4`: AI-generated video (not app output), trimmed to 4 s. Tagged on screen "Glasses mode, simulated device".
