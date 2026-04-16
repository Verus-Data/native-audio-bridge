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
    case deviceNotFound(String)

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
        case .deviceNotFound(let identifier):
            return "Audio device not found: \(identifier). Use --list-devices to see available devices."
        }
    }
}

public struct AudioDevice: Identifiable {
    public let id: AudioDeviceID
    public let name: String
    public let isDefault: Bool

    public init(id: AudioDeviceID, name: String, isDefault: Bool) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
    }
}

#if os(macOS)
private enum AudioCheckResult {
    case available
    case noInputDevice
    case audioSubsystemError(String)
}

private func checkAudioInputAvailability() -> AudioCheckResult {
    print("[DEBUG] Querying CoreAudio for input devices...")
    
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

    print("[DEBUG] CoreAudio check returned status: \(status)")

    if status != noErr {
        return .audioSubsystemError("Failed to get default input device, error: \(status)")
    }

    if inputDevice == kAudioObjectUnknown || inputDevice == 0 {
        print("[DEBUG] No audio input devices found")
        return .noInputDevice
    }
    
    print("[DEBUG] Found \(inputDevice) as default input device")

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

private func getDefaultInputDeviceID() -> AudioDeviceID? {
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

    guard status == noErr, inputDevice != kAudioObjectUnknown, inputDevice != 0 else {
        return nil
    }
    return inputDevice
}

private func getAllInputDeviceIDs() -> [AudioDeviceID] {
    var propertySize = UInt32(0)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var status = AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &propertySize
    )
    guard status == noErr else { return [] }

    let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
    var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

    status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &propertySize,
        &deviceIDs
    )
    guard status == noErr else { return [] }

    var inputDevices: [AudioDeviceID] = []
    for deviceID in deviceIDs {
        var hasInputStreams = false
        var inputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var inputPropertySize = UInt32(0)
        let inputStatus = AudioObjectGetPropertyDataSize(
            deviceID,
            &inputAddress,
            0,
            nil,
            &inputPropertySize
        )
        if inputStatus == noErr && inputPropertySize > 0 {
            hasInputStreams = true
        }
        if hasInputStreams {
            inputDevices.append(deviceID)
        }
    }
    return inputDevices
}

private func getDeviceName(deviceID: AudioDeviceID) -> String {
    var propertySize = UInt32(0)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceNameCFString,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var status = AudioObjectGetPropertyDataSize(
        deviceID,
        &address,
        0,
        nil,
        &propertySize
    )
    guard status == noErr else { return "Unknown Device" }

    var name: CFString = "" as CFString
    status = AudioObjectGetPropertyData(
        deviceID,
        &address,
        0,
        nil,
        &propertySize,
        &name
    )
    guard status == noErr else { return "Unknown Device" }
    return name as String
}
#endif

public final class AudioEngine {
    #if os(macOS)
    public var engine: AVAudioEngine?
    private var isAudioSafe: Bool = false
    private var selectedInputDeviceID: AudioDeviceID?
    #else
    public let engine = AVAudioEngine()
    #endif

    public init() {
        #if os(macOS)
        print("[DEBUG] Initializing AudioEngine...")
        print("[DEBUG] Checking audio safety...")
        checkAudioSafety()
        print("[DEBUG] Audio safety check complete: isAudioSafe = \(isAudioSafe)")
        if isAudioSafe {
            print("[DEBUG] Creating AVAudioEngine...")
            engine = AVAudioEngine()
            print("[DEBUG] Engine created: \(engine != nil)")
        }
        #endif
    }

    #if os(macOS)
    private func checkAudioSafety() {
        print("[DEBUG] Starting CoreAudio device check...")
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
    public static func listAudioDevices() -> [AudioDevice] {
        let defaultDeviceID = getDefaultInputDeviceID()
        let deviceIDs = getAllInputDeviceIDs()

        return deviceIDs.map { deviceID in
            AudioDevice(
                id: deviceID,
                name: getDeviceName(deviceID: deviceID),
                isDefault: deviceID == defaultDeviceID
            )
        }
    }

    public static func getDeviceName(deviceID: AudioDeviceID) -> String {
        return getDeviceName(deviceID: deviceID)
    }

    public func setInputDevice(identifier: String) throws {
        let devices = AudioEngine.listAudioDevices()

        if let deviceID = UInt32(identifier), let device = devices.first(where: { $0.id == deviceID }) {
            selectedInputDeviceID = device.id
            return
        }

        let matchingDevice = devices.first { device in
            device.name.lowercased() == identifier.lowercased() ||
            device.name.lowercased().contains(identifier.lowercased())
        }

        if let device = matchingDevice {
            selectedInputDeviceID = device.id
            return
        }

        throw AudioError.deviceNotFound(identifier)
    }

    public func setInputDevice(id: AudioDeviceID) {
        selectedInputDeviceID = id
    }

    public func getSelectedDeviceName() -> String? {
        guard let deviceID = selectedInputDeviceID else { return nil }
        return AudioEngine.getDeviceName(deviceID: deviceID)
    }
    #endif

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
