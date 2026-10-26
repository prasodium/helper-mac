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

    /// Wraps mono little-endian PCM16 samples in a WAV container so they can be sent for transcription.
    public static func wavData(pcm16: Data, sampleRate: Int) -> Data {
        var wav = Data()
        func tag(_ s: String) { wav.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        tag("RIFF"); u32(UInt32(36 + pcm16.count)); tag("WAVE")
        tag("fmt "); u32(16); u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        tag("data"); u32(UInt32(pcm16.count))
        wav.append(pcm16)
        return wav
    }

    /// Loudest sample in a PCM16 buffer (0...32768).
    public static func peak(pcm16: Data) -> Int {
        pcm16.withUnsafeBytes { raw in
            var loudest = 0
            var offset = 0
            while offset + 1 < raw.count {
                loudest = max(loudest, abs(Int(raw.loadUnaligned(fromByteOffset: offset, as: Int16.self))))
                offset += 2
            }
            return loudest
        }
    }

    /// True when a buffer is (almost) silence. Transcribing silence tends to produce invented text.
    public static func isSilent(pcm16: Data, threshold: Int = 200) -> Bool {
        peak(pcm16: pcm16) < threshold
    }
}
