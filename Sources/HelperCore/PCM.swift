import Foundation

public enum PCM {
    /// Float samples (-1...1) to little-endian PCM16 bytes.
    public static func int16Data(fromFloat samples: UnsafeBufferPointer<Float>) -> Data {
        var out = [Int16](repeating: 0, count: samples.count)
        for i in 0..<samples.count {
            let clamped = max(-1, min(1, samples[i]))
            out[i] = Int16((clamped * 32767).rounded())
        }
        return out.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
