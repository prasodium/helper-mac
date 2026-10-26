import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageTools {
    /// OpenAI downsizes images itself; sending 1536 px wide keeps all the
    /// detail the model will see while uploading several times faster.
    public static let visionMaxWidth = 1536

    public static func resized(_ image: CGImage, maxWidth: Int) -> CGImage {
        guard image.width > maxWidth else { return image }
        let scale = Double(maxWidth) / Double(image.width)
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let ctx = CGContext(data: nil, width: maxWidth, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: maxWidth, height: height))
        return ctx.makeImage() ?? image
    }

    public static func encode(_ image: CGImage, as type: UTType, quality: Double? = nil) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        var options: [CFString: Any] = [:]
        if let quality { options[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    public static func pngData(_ image: CGImage) -> Data? { encode(image, as: .png) }
    public static func jpegData(_ image: CGImage, quality: Double = 0.82) -> Data? { encode(image, as: .jpeg, quality: quality) }

    public static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// PNG bytes scaled for a vision request.
    public static func visionPNG(_ image: CGImage) -> Data? {
        pngData(resized(image, maxWidth: visionMaxWidth))
    }
}
