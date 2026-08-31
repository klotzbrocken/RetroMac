import CoreAudio
import AudioToolbox
import Foundation

/// The default output device's volume and mute, for the Windows themes' tray speaker.
///
/// Reads and writes the real system volume rather than keeping a number of its own: the tray
/// icon is meant to be the system's volume control, and a slider that only agreed with the
/// menu bar until someone touched a keyboard key would be worse than no slider.
enum SystemVolume {

    private static var defaultOutputDevice: AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                             &addr, 0, nil, &size, &id)
        return err == noErr && id != 0 ? id : nil
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    /// 0...1, or nil when the device exposes no main volume (some aggregate and HDMI devices).
    static var level: Float? {
        get {
            guard let dev = defaultOutputDevice else { return nil }
            var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            guard AudioObjectHasProperty(dev, &addr) else { return nil }
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &value) == noErr else { return nil }
            return value
        }
        set {
            guard let dev = defaultOutputDevice, var v = newValue else { return }
            v = min(max(v, 0), 1)
            var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            guard AudioObjectHasProperty(dev, &addr),
                  AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr,
                  settable.boolValue else { return }
            AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        }
    }
    private static var settable: DarwinBoolean = false

    static var isMuted: Bool {
        get {
            guard let dev = defaultOutputDevice else { return false }
            var addr = address(kAudioDevicePropertyMute)
            guard AudioObjectHasProperty(dev, &addr) else { return false }
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &value) == noErr else { return false }
            return value != 0
        }
        set {
            guard let dev = defaultOutputDevice else { return }
            var addr = address(kAudioDevicePropertyMute)
            var v: UInt32 = newValue ? 1 : 0
            guard AudioObjectHasProperty(dev, &addr),
                  AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr,
                  settable.boolValue else {
                // Devices without a mute property: fall back to parking the volume at zero, which
                // is what the Sound pane does for them too.
                if newValue { mutedLevel = level; level = 0 } else { level = mutedLevel ?? 0.5; mutedLevel = nil }
                return
            }
            AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
        }
    }
    /// Remembered so a device without a mute property can be un-muted to where it was.
    private static var mutedLevel: Float?

    /// True when the machine has an output whose volume we can actually move. The tray speaker
    /// hides itself otherwise rather than offering a slider that does nothing.
    static var isAvailable: Bool { level != nil }
}
