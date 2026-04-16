import AVFoundation
import Foundation

#if os(macOS)
import CoreAudio
#endif

public enum AudioError: Error, LocalizedError {
    case microphoneNotAvailable
    case microphonePermissionDenied
    case engineStartFailed(String)
    case audioSubsystemUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .microphoneNotAvailable:
            return "No microphone available. Connect a microphone or check System Settings > Sound > Input"
        case .microphonePermissionDenied:
            return "Microphone permission denied. Please enable in System Settings > Privacy & Security > Microphone."
        case .engineStartFailed(let message):
            return "Failed to start audio engine: \(message)"
        case .audioSubsystemUnavailable(let message):
            return "Audio subsystem unavailable: \(message)"
        }
    }
}

#if os(macOS)
private enum AudioCheckResult {
    case available
    case noInputDevice
    case audioSubsystemError(String)
}

private func checkAudioInputAvailability() -> AudioCheckResult {
    var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
    var inputDevice = AudioDeviceID()
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &propertySize,
        &inputDevice
    )

    if status != noErr {
        return .audioSubsystemError("Failed to get default input device, error: \(status)")
    }

    if inputDevice == kAudioObjectUnknown || inputDevice == 0 {
        return .noInputDevice
    }

    address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamFormat,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )

    var format = AudioStreamBasicDescription()
    propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

    let formatStatus = AudioObjectGetPropertyData(
        inputDevice,
        &address,
        0,
        nil,
        &propertySize,
        &format
    )

    if formatStatus != noErr {
        return .noInputDevice
    }

    return .available
}
#endif

public final class AudioEngine {
    #if os(macOS)
    private var engine: AVAudioEngine?
    private var isAudioSafe: Bool = false
    #else
    private let engine = AVAudioEngine()
    #endif

    public init() {
        #if os(macOS)
        checkAudioSafety()
        if isAudioSafe {
            engine = AVAudioEngine()
        }
        #endif
    }

    #if os(macOS)
    private func checkAudioSafety() {
        let result = checkAudioInputAvailability()
        switch result {
        case .available:
            isAudioSafe = true
        case .noInputDevice, .audioSubsystemError:
            isAudioSafe = false
        }
    }
    #endif

    private let sampleRate: Double = 16000
    private let bufferSize: AVAudioFrameCount = 1024
    private var audioBuffers: [Data] = []
    private let bufferQueue = DispatchQueue(label: "com.nativeaudiobridge.audiobuffer", attributes: .concurrent)
    private var isCapturing = false
    private let maxBufferMemoryMB: Int = 80
    private var onAudioBuffer: (@Sendable (Data) -> Void)?
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    public var sampleRateValue: Double { sampleRate }

    public func setOnAudioBuffer(_ handler: @escaping (Data) -> Void) {
        onAudioBuffer = handler
    }

    #if os(macOS)
    public static func checkAudioAvailable() throws {
        let result = checkAudioInputAvailability()
        switch result {
        case .available:
            return
        case .noInputDevice:
            throw AudioError.microphoneNotAvailable
        case .audioSubsystemError(let message):
            throw AudioError.audioSubsystemUnavailable(message)
        }
    }
    #endif

    public func start() throws {
        #if os(macOS)
        guard isAudioSafe, let engine = engine else {
            throw AudioError.microphoneNotAvailable
        }
        #endif
        
        #if os(macOS)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var inputDevice = AudioDeviceID()
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let result = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &inputDevice
        )
        guard result == noErr && inputDevice != kAudioObjectUnknown && inputDevice != 0 else {
            throw AudioError.microphoneNotAvailable
        }
        #else
        let audioDevices = AVCaptureDevice.devices(for: .audio)
        guard !audioDevices.isEmpty else {
            throw AudioError.microphoneNotAvailable
        }
        #endif
        
        #if os(macOS)
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputFormat = format
        #else
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputFormat = format
        #endif

        let desiredFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!

        guard let conv = AVAudioConverter(from: format, to: desiredFormat) else {
            throw AudioError.engineStartFailed("Failed to create audio converter")
        }
        converter = conv

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            guard let self, let conv = self.converter, let fromFormat = self.inputFormat else { return }
            self.processAudioBuffer(buffer, converter: conv, fromFormat: fromFormat, toFormat: desiredFormat)
        }

        #if os(macOS)
        do {
            try engine.start()
        } catch {
            throw AudioError.engineStartFailed(error.localizedDescription)
        }
        #else
        try engine.start()
        #endif
        isCapturing = true
    }

    public func stop() {
        #if os(macOS)
        guard let engine = engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        #else
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        #endif
        isCapturing = false
        converter = nil
        inputFormat = nil
        clearBuffers()
    }

    public func getBuffers() -> [Data] {
        bufferQueue.sync { self.audioBuffers }
    }

    public func clearBuffers() {
        bufferQueue.async(flags: .barrier) { [weak self] in
            self?.audioBuffers.removeAll()
        }
    }

    public var currentBufferMemoryMB: Int {
        let totalBytes = bufferQueue.sync { self.audioBuffers.reduce(0) { $0 + $1.count } }
        return totalBytes / (1024 * 1024)
    }

    #if os(macOS)
    public var isRunning: Bool { engine?.isRunning ?? false }
    #else
    public var isRunning: Bool { engine.isRunning }
    #endif

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

        let onBuffer = self.onAudioBuffer
        bufferQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            if self.currentBufferMemoryMB < self.maxBufferMemoryMB {
                self.audioBuffers.append(data)
            } else {
                self.audioBuffers.removeFirst()
                self.audioBuffers.append(data)
            }
            onBuffer?(data)
        }
    }
}
