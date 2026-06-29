import Foundation

/// A named webcam "look" for the virtual camera — the core of the Creator/Streamer wedge.
/// Bundles the shader + intensity + lower-third toggle/style so a creator can switch the
/// whole look with one click (your name/title stay put, independent of the scene).
struct CameraScene: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var shader: String            // PresetRegistry id, e.g. "late-night-crt"
    var intensity: Double         // 0...1
    var lowerThird: Bool          // show the name/title lower-third (needs an LT-capable shader)
    var lowerThirdStyle: String   // "latenight" | "newsroom"

    /// Lower-third only renders on these shaders (see VirtualCameraManager).
    static let lowerThirdShaders: Set<String> = ["late-night-crt", "newsroom-1987"]
    var supportsLowerThird: Bool { CameraScene.lowerThirdShaders.contains(shader) }

    /// Curated starting looks. Custom user scenes live in AppSettings.cameraScenes.
    static let builtIns: [CameraScene] = [
        CameraScene(id: "builtin.latenight", name: "Late Night Talk",
                    shader: "late-night-crt", intensity: 0.85, lowerThird: true, lowerThirdStyle: "latenight"),
        CameraScene(id: "builtin.newsroom", name: "Newsroom 1987",
                    shader: "newsroom-1987", intensity: 0.85, lowerThird: true, lowerThirdStyle: "newsroom"),
        CameraScene(id: "builtin.vhs", name: "VHS Tape",
                    shader: "vhs", intensity: 0.9, lowerThird: false, lowerThirdStyle: "latenight"),
        CameraScene(id: "builtin.trinitron", name: "Trinitron TV",
                    shader: "trinitron-tv", intensity: 0.8, lowerThird: false, lowerThirdStyle: "latenight"),
        CameraScene(id: "builtin.softcrt", name: "Soft CRT",
                    shader: "newpixie-crt", intensity: 0.7, lowerThird: false, lowerThirdStyle: "latenight"),
    ]

    /// Built-in + user scenes, in display order.
    static var all: [CameraScene] { builtIns + AppSettings.shared.cameraScenes }

    /// Apply this look to the virtual camera (live if running) and remember it as active.
    func apply() {
        let vcam = VirtualCameraManager.shared
        let s = AppSettings.shared
        vcam.changeShader(shader)
        vcam.updateIntensity(Float(intensity))
        s.lowerThirdEnabled = lowerThird
        s.lowerThirdStyle = lowerThirdStyle
        s.activeCameraSceneID = id
        NotificationCenter.default.post(name: .cameraSceneChanged, object: nil)
    }

    /// Cycle to the next scene (wraps). Used by the Quick-Switch pill arrows + hotkey.
    static func cycle(by delta: Int) {
        let scenes = all
        guard !scenes.isEmpty else { return }
        let current = scenes.firstIndex { $0.id == AppSettings.shared.activeCameraSceneID } ?? -1
        let next = ((current + delta) % scenes.count + scenes.count) % scenes.count
        scenes[next].apply()
    }

    /// Capture the current camera + lower-third settings as a new (unsaved) scene.
    static func fromCurrent(name: String) -> CameraScene {
        let vcam = VirtualCameraManager.shared
        let s = AppSettings.shared
        return CameraScene(id: "user.\(UUID().uuidString)", name: name,
                           shader: vcam.selectedShader, intensity: Double(vcam.shaderIntensity),
                           lowerThird: s.lowerThirdEnabled, lowerThirdStyle: s.lowerThirdStyle)
    }
}
