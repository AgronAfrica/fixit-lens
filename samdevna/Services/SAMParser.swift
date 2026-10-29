// The `one_bit` mask decoder in this file is a Swift port of Meta's `@meta-sam/parser` 0.1.0 (mask-codec.js),
// so that part is a derivative of the SAM Materials and is distributed under the SAM License (LICENSES/SAM-LICENSE.txt),
// not the MIT licence that covers the rest of Fix-it Lens. See THIRD_PARTY_NOTICES.md.

import CoreGraphics
import Foundation
import UIKit

/// Maps between a view showing an image with aspect-fill and the image's own pixels.
struct FillTransform {
    let imageSize: CGSize
    let viewSize: CGSize

    var scale: CGFloat {
        max(viewSize.width / max(imageSize.width, 1), viewSize.height / max(imageSize.height, 1))
    }

    var offset: CGPoint {
        CGPoint(
            x: (viewSize.width - imageSize.width * scale) / 2,
            y: (viewSize.height - imageSize.height * scale) / 2
        )
    }

    func toImage(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(0, (point.x - offset.x) / scale), imageSize.width - 1),
            y: min(max(0, (point.y - offset.y) / scale), imageSize.height - 1)
        )
    }

    func toView(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX * scale + offset.x,
            y: rect.minY * scale + offset.y,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }
}

enum SAMPrompt {
    static func point(id: Int = 1, x: Int, y: Int, width: Int, height: Int) -> String {
        "<0f>\(id)<|point;x=\(x);y=\(y);w=\(width);h=\(height)|>"
    }

    static func concept(_ nounPhrase: String) -> String {
        nounPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SAMParser {
    private static let record = try! NSRegularExpression(pattern: #"(\d+)<\|box;([^|]+)\|><\|mask;([^|]+)\|>"#)

    static func parse(_ text: String) -> [SAMObject] {
        let ns = text as NSString
        return record.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let box = fields(ns.substring(with: match.range(at: 2)))
            let mask = fields(ns.substring(with: match.range(at: 3)))
            guard
                let x1 = box["x1"].flatMap(Int.init), let y1 = box["y1"].flatMap(Int.init),
                let x2 = box["x2"].flatMap(Int.init), let y2 = box["y2"].flatMap(Int.init),
                let w = box["w"].flatMap(Int.init), let h = box["h"].flatMap(Int.init)
            else { return nil }

            var object = SAMObject(
                id: Int(ns.substring(with: match.range(at: 1))) ?? 0,
                box: SAMBox(x1: x1, y1: y1, x2: x2, y2: y2, width: w, height: h,
                            confidence: box["c"].flatMap(Double.init) ?? mask["c"].flatMap(Double.init)),
                maskWidth: 0, maskHeight: 0, raster: []
            )
            // data=H,W,<marker><payload>
            if let data = mask["data"] {
                let parts = data.split(separator: ",", maxSplits: 2).map(String.init)
                if parts.count == 3, let mh = Int(parts[0]), let mw = Int(parts[1]),
                   let raster = SAMMaskCodec.decode(parts[2], width: mw, height: mh) {
                    object.maskWidth = mw
                    object.maskHeight = mh
                    object.raster = raster
                    object.overlay = SAMRender.overlay(raster: raster, width: mw, height: mh)
                }
            }
            return object
        }
    }

    /// Crops a padded region around the object. `image` must be the same (normalized) image sent to SAM.
    static func crop(_ image: UIImage, to object: SAMObject, padding: CGFloat = 0.15) -> UIImage {
        guard let cg = image.cgImage, object.box.width > 0 else { return image }
        let scale = CGFloat(cg.width) / CGFloat(object.box.width)
        var rect = object.box.rect.applying(CGAffineTransform(scaleX: scale, y: scale))
        rect = rect.insetBy(dx: -rect.width * padding, dy: -rect.height * padding)
            .intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            .integral
        guard rect.width > 16, rect.height > 16, let cropped = cg.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped)
    }

    private static func fields(_ raw: String) -> [String: String] {
        var out: [String: String] = [:]
        for part in raw.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { out[kv[0]] = kv[1] }
        }
        return out
    }
}

/// Swift port of the `one_bit` decoder in Meta's `@meta-sam/parser` (mask-codec.js):
/// a length-prefixed base85 payload carrying an adaptive binary range-coded raster.
enum SAMMaskCodec {
    private static let alphabet: [UInt8] = {
        let excluded = Set("\"\\,;<>|".utf8)
        return (UInt8(0x21)...UInt8(0x7e)).filter { !excluded.contains($0) }
    }()

    private static let digits: [Int] = {
        var table = [Int](repeating: -1, count: 128)
        for (index, character) in alphabet.enumerated() { table[Int(character)] = index }
        return table
    }()

    /// Returns a row-major raster of 0/1, or nil if the payload isn't a valid `one_bit` mask.
    static func decode(_ payload: String, width: Int, height: Int) -> [UInt8]? {
        guard width > 0, height > 0, payload.first == "!",
              let packed = unpack(Array(payload.utf8.dropFirst())),
              var decoder = RangeDecoder(packed) else { return nil }

        let padding = 2
        let paddedWidth = width + 2 * padding
        var padded = [UInt8](repeating: 0, count: paddedWidth * (height + padding))
        var counts = [UInt16](repeating: 1, count: 4096 * 2)
        var output = [UInt8](repeating: 0, count: width * height)

        for y in 0..<height {
            let row = (y + padding) * paddedWidth + padding
            for x in 0..<width {
                let p = row + x
                let prior = p - paddedWidth
                let earlier = p - 2 * paddedWidth
                var context = Int(padded[p - 1])
                context |= Int(padded[p - 2]) << 1
                context |= Int(padded[prior - 2]) << 2
                context |= Int(padded[prior - 1]) << 3
                context |= Int(padded[prior]) << 4
                context |= Int(padded[prior + 1]) << 5
                context |= Int(padded[prior + 2]) << 6
                context |= Int(padded[earlier - 2]) << 7
                context |= Int(padded[earlier - 1]) << 8
                context |= Int(padded[earlier]) << 9
                context |= Int(padded[earlier + 1]) << 10
                context |= Int(padded[earlier + 2]) << 11

                let offset = context << 1
                let zero = UInt32(counts[offset])
                let one = UInt32(counts[offset + 1])
                let bit = decoder.frequency(zero + one) < zero ? 0 : 1
                if bit == 0 { decoder.decode(0, zero) } else { decoder.decode(zero, one) }
                padded[p] = UInt8(bit)
                output[y * width + x] = UInt8(bit)

                counts[offset + bit] += 14
                if counts[offset] + counts[offset + 1] >= 4096 {
                    counts[offset] = max(counts[offset] >> 1, 1)
                    counts[offset + 1] = max(counts[offset + 1] >> 1, 1)
                }
            }
        }
        return decoder.failed ? nil : output
    }

    static func unpack(_ chars: [UInt8]) -> [UInt8]? {
        guard chars.count >= 5 else { return nil }
        func digit(_ c: UInt8) -> UInt64? {
            guard c < 128 else { return nil }
            let value = digits[Int(c)]
            return (0..<85).contains(value) ? UInt64(value) : nil
        }
        var length: UInt64 = 0
        for i in 0..<5 {
            guard let d = digit(chars[i]) else { return nil }
            length = length * 85 + d
        }
        let count = Int(length)
        let remainder = count % 4
        guard chars.count == 5 + (count / 4) * 5 + (remainder == 0 ? 0 : remainder + 1) else { return nil }

        var output = [UInt8](repeating: 0, count: count)
        var source = 5
        var destination = 0
        while destination < count - remainder {
            var value: UInt64 = 0
            for i in 0..<5 {
                guard let d = digit(chars[source + i]) else { return nil }
                value = value * 85 + d
            }
            guard value <= 0xFFFF_FFFF else { return nil }
            for i in 0..<4 { output[destination + i] = UInt8((value >> UInt64(24 - i * 8)) & 0xFF) }
            source += 5
            destination += 4
        }
        if remainder > 0 {
            var value: UInt64 = 0
            for i in 0..<5 {
                if i < remainder + 1 {
                    guard let d = digit(chars[source + i]) else { return nil }
                    value = value * 85 + d
                } else {
                    value = value * 85 + 84
                }
            }
            guard value <= 0xFFFF_FFFF else { return nil }
            for i in 0..<remainder { output[destination + i] = UInt8((value >> UInt64(24 - i * 8)) & 0xFF) }
        }
        return output
    }

    private struct RangeDecoder {
        private static let top: UInt32 = 1 << 24
        private static let bottom: UInt32 = 1 << 16

        private let input: [UInt8]
        private var position = 0
        private var low: UInt32 = 0
        private var range: UInt32 = 0xFFFF_FFFF
        private var code: UInt32 = 0
        private var scaled: UInt32 = 0
        private(set) var failed = false

        init?(_ input: [UInt8]) {
            guard input.count >= 4 else { return nil }
            self.input = input
            for _ in 0..<4 { code = (code << 8) | UInt32(read()) }
        }

        mutating func frequency(_ total: UInt32) -> UInt32 {
            scaled = range / total
            guard scaled > 0 else { failed = true; return 0 }
            let value = (code &- low) / scaled
            return value >= total ? total - 1 : value
        }

        mutating func decode(_ cumulative: UInt32, _ frequency: UInt32) {
            low = low &+ scaled &* cumulative
            range = scaled &* frequency
            while true {
                if (low ^ (low &+ range)) < Self.top {
                    // top byte settled
                } else if range < Self.bottom {
                    range = (0 &- low) & (Self.bottom - 1)
                } else {
                    break
                }
                code = (code << 8) | UInt32(read())
                low <<= 8
                range <<= 8
            }
        }

        private mutating func read() -> UInt8 {
            guard position < input.count else { failed = true; return 0 }
            defer { position += 1 }
            return input[position]
        }
    }
}

enum SAMRender {
    /// Translucent signal-amber fill with a bright contour, sized to the mask raster.
    static func overlay(raster: [UInt8], width: Int, height: Int) -> UIImage? {
        guard width > 0, height > 0, raster.count == width * height else { return nil }
        let fill: (UInt8, UInt8, UInt8, UInt8) = (87, 60, 11, 87)         // premultiplied amber #FFB020 @ 34%
        let edge: (UInt8, UInt8, UInt8, UInt8) = (255, 214, 120, 255)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                guard raster[i] == 1 else { continue }
                let isEdge = x == 0 || y == 0 || x == width - 1 || y == height - 1
                    || raster[i - 1] == 0 || raster[i + 1] == 0
                    || raster[i - width] == 0 || raster[i + width] == 0
                let c = isEdge ? edge : fill
                let o = i * 4
                pixels[o] = c.0
                pixels[o + 1] = c.1
                pixels[o + 2] = c.2
                pixels[o + 3] = c.3
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: width, height: height,
                bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              ) else { return nil }
        return UIImage(cgImage: image)
    }
}

enum ImageCodec {
    /// Upright, 1x-scale copy whose longest edge is at most `maxEdge` pixels, so
    /// `size` equals pixel dimensions and matches SAM's coordinate space.
    static func normalized(_ image: UIImage, maxEdge: CGFloat = 1280) -> UIImage {
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let ratio = min(1, maxEdge / max(pixels.width, pixels.height, 1))
        let target = CGSize(width: (pixels.width * ratio).rounded(), height: (pixels.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    static func jpegDataURL(_ image: UIImage, quality: CGFloat = 0.85) -> String? {
        image.jpegData(compressionQuality: quality).map { "data:image/jpeg;base64,\($0.base64EncodedString())" }
    }
}
