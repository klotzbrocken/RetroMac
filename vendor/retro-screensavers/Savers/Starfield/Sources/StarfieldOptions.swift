import AppKit

/// The Starfield "Options…" sheet: the original's two settings.
final class StarfieldOptions {
    let sheet: OptionsSheet

    init(settings: StarfieldSettings, onSave: @escaping (StarfieldSettings) -> Void) {
        let speedSlider = OptionsSheet.slider(range: StarfieldSettings.warpSpeedRange, value: settings.warpSpeed)
        let densityRange = StarfieldSettings.densityRange
        let densitySlider = OptionsSheet.slider(
            range: Double(densityRange.lowerBound)...Double(densityRange.upperBound),
            value: Double(settings.density)
        )

        sheet = OptionsSheet(title: "Retro Starfield", rows: [
            ("Warp speed:", speedSlider),
            ("Star density:", densitySlider),
        ]) {
            var newSettings = settings
            newSettings.warpSpeed = speedSlider.doubleValue
            newSettings.density = Int(densitySlider.doubleValue.rounded())
            onSave(newSettings)
        }
    }
}
