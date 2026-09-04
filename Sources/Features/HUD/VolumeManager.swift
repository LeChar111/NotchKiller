import CoreAudio
import Foundation

@MainActor
@Observable
final class VolumeManager {
    static let shared = VolumeManager()

    var volume: Float = 0
    var isMuted: Bool = false
    var lastChangeAt: Date = .distantPast
    var isVisible: Bool { Date().timeIntervalSince(lastChangeAt) < 1.5 }

    private var listenerBlock: AudioObjectPropertyListenerBlock?

    private init() {
        fetchCurrent()
        setupListener()
    }

    func increase() {
        setVolume(min(1, volume + 1.0 / 16.0))
    }

    func decrease() {
        setVolume(max(0, volume - 1.0 / 16.0))
    }

    func toggleMute() {
        let deviceID = defaultOutputDevice()
        guard deviceID != kAudioObjectUnknown else { return }

        var muted: UInt32 = isMuted ? 0 : 1
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &muted)
        fetchCurrent()
        lastChangeAt = Date()
    }

    func setVolume(_ value: Float) {
        let clamped = max(0, min(1, value))
        let deviceID = defaultOutputDevice()
        guard deviceID != kAudioObjectUnknown else { return }

        var vol = Float32(clamped)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &vol)
        volume = clamped
        lastChangeAt = Date()
    }

    private func fetchCurrent() {
        let deviceID = defaultOutputDevice()
        guard deviceID != kAudioObjectUnknown else { return }

        // Volume
        var vol: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &vol)
        volume = vol

        // Mute
        var muted: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(deviceID, &muteAddress, 0, nil, &muteSize, &muted)
        isMuted = muted != 0
    }

    private func setupListener() {
        let deviceID = defaultOutputDevice()
        guard deviceID != kAudioObjectUnknown else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.fetchCurrent()
                self?.lastChangeAt = Date()
            }
        }
        listenerBlock = block

        AudioObjectAddPropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
    }

    private nonisolated func defaultOutputDevice() -> AudioObjectID {
        var deviceID: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceID
    }
}
