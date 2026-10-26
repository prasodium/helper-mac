import CoreGraphics
import Foundation

/// Builds one long, de-duplicated image from screenshots taken while the
/// user scrolls through a page that doesn't fit on one screen (for example
/// a long document or problem statement).
///
/// Overlap between consecutive frames is found by correlating a cheap 1-D
/// per-row brightness signature, so the AI receives a single coherent image
/// instead of many overlapping ones. A frame only counts once enough new
/// content has scrolled into view, so polling faster than the user scrolls
/// costs almost nothing.
public final class ScrollCaptureSession {
    public static let workWidth = 1280
    public static let minOverlap = 40
    public static let goodMatchThreshold: Float = 12
    public static let minNewContent = 50
    public static let maxHeight = 16000
    public static let maxFrames = 24

    public struct Outcome: Equatable {
        public enum Reason { case firstFrame, added, noNewContent, maxHeight }
        public var captured: Bool
        public var reason: Reason
    }

    private var slices: [CGImage] = []
    private var lastSignature: [Float] = []
    private var width = 0
    public private(set) var height = 0
    public private(set) var frameCount = 0

    public init() {}

    public var isFull: Bool { frameCount >= Self.maxFrames || height >= Self.maxHeight }

    @discardableResult
    public func consider(_ screenshot: CGImage) -> Outcome {
        if height >= Self.maxHeight { return .init(captured: false, reason: .maxHeight) }

        let frame = ImageTools.resized(screenshot, maxWidth: Self.workWidth)
        let signature = Self.rowSignature(frame)

        if slices.isEmpty {
            slices = [frame]
            lastSignature = signature
            width = frame.width
            height = frame.height
            frameCount = 1
            return .init(captured: true, reason: .firstFrame)
        }

        // A frame of a different width (display change) can't be stitched.
        guard frame.width == width else { return .init(captured: false, reason: .noNewContent) }

        let overlap = Self.findOverlap(previous: lastSignature, next: signature)
        let newHeight = frame.height - overlap
        guard newHeight >= Self.minNewContent else { return .init(captured: false, reason: .noNewContent) }

        let slice = overlap > 0
            ? frame.cropping(to: CGRect(x: 0, y: overlap, width: width, height: newHeight)) ?? frame
            : frame
        slices.append(slice)
        lastSignature = signature
        height += newHeight
        frameCount += 1
        return .init(captured: true, reason: .added)
    }

    /// The assembled composite (nil if nothing was captured).
    public func finish() -> CGImage? {
        guard !slices.isEmpty,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var top = height // CGContext origin is bottom-left; draw slices downward.
        for slice in slices {
            top -= slice.height
            ctx.draw(slice, in: CGRect(x: 0, y: top, width: width, height: slice.height))
        }
        return ctx.makeImage()
    }

    // MARK: Overlap detection

    /// Mean grayscale brightness of every pixel row.
    static func rowSignature(_ image: CGImage) -> [Float] {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return [Float](repeating: 0, count: h)
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Bitmap memory is top row first, so index 0 is the top of the image.
        var signature = [Float](repeating: 0, count: h)
        for row in 0..<h {
            var sum = 0
            let start = row * w
            for x in 0..<w { sum += Int(pixels[start + x]) }
            signature[row] = Float(sum) / Float(w)
        }
        return signature
    }

    /// How many rows at the top of `next` duplicate the bottom of `previous`
    /// (0 when there is no trustworthy match).
    public static func findOverlap(previous: [Float], next: [Float]) -> Int {
        let maxCandidate = min(previous.count, next.count)
        guard maxCandidate >= minOverlap else { return 0 }
        var bestOffset = 0
        var bestScore = Float.infinity
        for candidate in minOverlap...maxCandidate {
            var err: Float = 0
            let tailStart = previous.count - candidate
            for k in 0..<candidate {
                let d = previous[tailStart + k] - next[k]
                err += d * d
            }
            let score = err / Float(candidate)
            if score < bestScore { bestScore = score; bestOffset = candidate }
        }
        return bestScore <= goodMatchThreshold ? bestOffset : 0
    }
}
