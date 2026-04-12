import AVFoundation
import Foundation

public final class CommandBuffer {
    private var buffers: [Data] = []
    private let bufferQueue = DispatchQueue(label: "com.nativeaudiobridge.cmdbuffer", attributes: .concurrent)
    private var isCapturing = false
    private let maxBufferMemoryMB: Int = 80
    private let silenceTimeoutMs: Int
    private let silenceThreshold: Float
    private var silenceStartTime: Date?
    private var lastAudioLevel: Float = 0
    private var silenceTimer: DispatchSourceTimer?

    public var onSilenceDetected: (() -> Void)?
    public var onAudioLevel: ((Float) -> Void)?

    public init(silenceTimeoutMs: Int = 1500, silenceThreshold: Float = 0.01) {
        self.silenceTimeoutMs = silenceTimeoutMs
        self.silenceThreshold = silenceThreshold
    }

    public func startCapture() {
        bufferQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            self.buffers.removeAll()
            self.isCapturing = true
            self.silenceStartTime = nil
            self.lastAudioLevel = 0
        }
        startSilenceTimer()
        print("[CommandBuffer] Capture started")
    }

    public func stopCapture() {
        stopSilenceTimer()
        bufferQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            self.isCapturing = false
            self.silenceStartTime = nil
        }
        print("[CommandBuffer] Capture stopped")
    }

    public func append(_ data: Data) {
        let shouldProcess = bufferQueue.sync { isCapturing }

        bufferQueue.async(flags: .barrier) { [weak self] in
            guard let self, self.isCapturing else { return }
            if self.currentBufferMemoryMB < self.maxBufferMemoryMB {
                self.buffers.append(data)
            } else {
                self.buffers.removeFirst()
                self.buffers.append(data)
            }
        }

        let rms = calculateRMS(from: data)
        lastAudioLevel = rms
        onAudioLevel?(rms)

        if shouldProcess {
            processSilenceDetection(audioLevel: rms)
        }
    }

    public func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        let data = Data(bytes: channelData, count: frameLength * MemoryLayout<Float>.size)
        append(data)
    }

    public func getBuffers() -> [Data] {
        bufferQueue.sync { buffers }
    }

    public func clearBuffers() {
        bufferQueue.async(flags: .barrier) { [weak self] in
            self?.buffers.removeAll()
        }
    }

    public var currentBufferMemoryMB: Int {
        let totalBytes = bufferQueue.sync { buffers.reduce(0) { $0 + $1.count } }
        return totalBytes / (1024 * 1024)
    }

    public var capturing: Bool {
        bufferQueue.sync { isCapturing }
    }

    public var audioLevel: Float {
        lastAudioLevel
    }

    public func calculateRMS(from data: Data) -> Float {
        guard data.count >= MemoryLayout<Float>.size else { return 0 }
        let floatCount = data.count / MemoryLayout<Float>.size
        var sum: Float = 0
        data.withUnsafeBytes { rawBuffer in
            let floatPtr = rawBuffer.bindMemory(to: Float.self)
            for i in 0..<min(floatCount, floatPtr.count) {
                sum += floatPtr[i] * floatPtr[i]
            }
        }
        let mean = sum / Float(floatCount > 0 ? floatCount : 1)
        return sqrt(mean)
    }

    public func processSilenceDetection(audioLevel: Float) {
        bufferQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            if audioLevel < self.silenceThreshold {
                if self.silenceStartTime == nil {
                    self.silenceStartTime = Date()
                }
            } else {
                self.silenceStartTime = nil
            }
        }
    }

    private func startSilenceTimer() {
        stopSilenceTimer()
        let timer = DispatchSource.makeTimerSource(queue: bufferQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.bufferQueue.async(flags: .barrier) { [weak self] in
                guard let self, self.isCapturing else { return }
                guard let startTime = self.silenceStartTime else { return }
                let elapsed = Date().timeIntervalSince(startTime)
                let timeoutInterval = Double(self.silenceTimeoutMs) / 1000.0
                if elapsed >= timeoutInterval {
                    self.isCapturing = false
                    self.silenceStartTime = nil
                    self.silenceTimer?.cancel()
                    self.silenceTimer = nil
                    self.onSilenceDetected?()
                }
            }
        }
        timer.resume()
        silenceTimer = timer
    }

    private func stopSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = nil
    }
}