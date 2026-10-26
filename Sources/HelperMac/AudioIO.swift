import AVFoundation
import CoreMedia
import HelperCore
import ScreenCaptureKit

enum AudioError: LocalizedError {
    case micDenied
    case recordingFailed
    case emptyRecording

    var errorDescription: String? {
        switch self {
        case .micDenied: "Helper needs Microphone permission. Open System Settings > Privacy & Security > Microphone and turn Helper on."
        case .recordingFailed: "Couldn't start recording."
        case .emptyRecording: "Didn't catch anything. Try again."
        }
    }
}

func requestMicrophoneAccess() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: return true
    case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
    default: return false
    }
}

/// Records the microphone to an AAC .m4a file for transcription.
final class VoiceRecorder: NSObject {
    private var recorder: AVAudioRecorder?
    private var url: URL?

    var isRecording: Bool { recorder?.isRecording ?? false }

    func start() async throws {
        guard await requestMicrophoneAccess() else { throw AudioError.micDenied }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("helper-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32000,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        guard recorder.record() else { throw AudioError.recordingFailed }
        self.recorder = recorder
        self.url = url
    }

    func stop() throws -> Data {
        recorder?.stop()
        recorder = nil
        defer { if let url { try? FileManager.default.removeItem(at: url) }; url = nil }
        guard let url, let data = try? Data(contentsOf: url), data.count > 1000 else { throw AudioError.emptyRecording }
        return data
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        if let url { try? FileManager.default.removeItem(at: url) }
        url = nil
    }
}

/// Plays text-to-speech replies.
final class SpeechPlayer {
    private var player: AVAudioPlayer?
    var isPlaying: Bool { player?.isPlaying ?? false }

    func play(_ mp3: Data) throws {
        player = try AVAudioPlayer(data: mp3)
        player?.play()
    }

    func stop() { player?.stop(); player = nil }
}

/// Anything that feeds 24 kHz mono PCM16 to the live translator.
protocol TranslationAudioSource: AnyObject {
    var onPCM: ((Data) -> Void)? { get set }
    func start() async throws
    func stop()
}

/// Captures everything the Mac is playing (a meeting, a video) through
/// ScreenCaptureKit. Helper's own audio is excluded.
final class SystemAudioCapture: NSObject, TranslationAudioSource, SCStreamOutput, SCStreamDelegate {
    var onPCM: ((Data) -> Void)?
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "helper.system-audio")

    func start() async throws {
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            throw ScreenCaptureError.permissionDenied
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw ScreenCaptureError.noDisplay }
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 24000
        config.channelCount = 1
        // Audio only matters; keep the (required) video side as cheap as possible.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() {
        let s = stream
        stream = nil
        Task { try? await s?.stopCapture() }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        try? sampleBuffer.withAudioBufferList { list, _ in
            guard let buffer = list.first, let raw = buffer.mData else { return }
            guard let desc = sampleBuffer.formatDescription?.audioStreamBasicDescription else { return }
            let isFloat = desc.mFormatFlags & kAudioFormatFlagIsFloat != 0
            if isFloat {
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                let samples = UnsafeBufferPointer(start: raw.assumingMemoryBound(to: Float.self), count: count)
                onPCM?(PCM.int16Data(fromFloat: samples))
            } else {
                onPCM?(Data(bytes: raw, count: Int(buffer.mDataByteSize)))
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { self.stream = nil }
}

/// Captures the microphone (useful when translating a conversation in the room).
final class MicrophoneCapture: TranslationAudioSource {
    var onPCM: ((Data) -> Void)?
    private let engine = AVAudioEngine()

    func start() async throws {
        guard await requestMicrophoneAccess() else { throw AudioError.micDenied }
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: target) else { throw AudioError.recordingFailed }
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            let ratio = target.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, let channel = out.int16ChannelData else { return }
            self?.onPCM?(Data(bytes: channel[0], count: Int(out.frameLength) * MemoryLayout<Int16>.size))
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
