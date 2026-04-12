import AVFoundation
import Foundation

final class AudioEngine {
    private let engine = AVAudioEngine()
    private let sampleRate: Double = 16000
    private let bufferSize: AVAudioFrameCount = 1024
    private var audioBuffers: [Data] = []
    private let bufferQueue = DispatchQueue(label: "com.nativeaudiobridge.audiobuffer", attributes: .concurrent)
    private var isCapturing = false
    private let maxBufferMemoryMB: Int = 80
    private var onAudioBuffer: ((Data) -> Void)?

    var sampleRateValue: Double { sampleRate }

    func setOnAudioBuffer(_ handler: @escaping (Data) -> Void) {
        onAudioBuffer = handler
    }

    func start() throws {
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        let desiredFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!

        let converter = AVAudioConverter(from: format, to: desiredFormat)!

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, time in
            guard let self else { return }
            self.processAudioBuffer(buffer, converter: converter, fromFormat: format, toFormat: desiredFormat)
        }

        try engine.start()
        isCapturing = true
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
        clearBuffers()
    }

    func getBuffers() -> [Data] {
        bufferQueue.sync { self.audioBuffers }
    }

    func clearBuffers() {
        bufferQueue.async(flags: .barrier) { [weak self] in
            self?.audioBuffers.removeAll()
        }
    }

    var currentBufferMemoryMB: Int {
        let totalBytes = bufferQueue.sync { self.audioBuffers.reduce(0) { $0 + $1.count } }
        return totalBytes / (1024 * 1024)
    }

    var isRunning: Bool { engine.isRunning }

    private func processAudioBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        fromFormat: AVAudioFormat,
        toFormat: AVAudioFormat
    ) {
        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * sampleRate / fromFormat.sampleRate)
        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: toFormat,
            frameCapacity: frameCount > 0 ? frameCount : 1024
        ) else { return }

        var error: NSError?
        let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil else { return }

        guard let channelData = convertedBuffer.floatChannelData?[0] else { return }
        let data = Data(bytes: channelData, count: Int(convertedBuffer.frameLength) * MemoryLayout<Float>.size)

        bufferQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            if self.currentBufferMemoryMB < self.maxBufferMemoryMB {
                self.audioBuffers.append(data)
            } else {
                self.audioBuffers.removeFirst()
                self.audioBuffers.append(data)
            }
        }

        onAudioBuffer?(data)
    }
}