import AppKit

/// The Pipes "Options…" sheet.
final class PipesOptions: NSObject {
    private(set) var sheet: OptionsSheet!
    private let countSlider: NSSlider
    private let countLabel: NSTextField

    init(settings: PipesSettings, onSave: @escaping (PipesSettings) -> Void) {
        let jointPopUp = OptionsSheet.popUp(
            titles: JointStyle.allCases.map(\.title),
            selectedIndex: JointStyle.allCases.firstIndex(of: settings.jointStyle) ?? 0
        )
        let surfacePopUp = OptionsSheet.popUp(
            titles: Surface.allCases.map(\.title),
            selectedIndex: Surface.allCases.firstIndex(of: settings.surface) ?? 0
        )
        let countRange = PipesSettings.pipeCountRange
        countSlider = OptionsSheet.slider(
            range: Double(countRange.lowerBound)...Double(countRange.upperBound),
            value: Double(settings.pipeCount),
            steps: countRange.count
        )
        countLabel = NSTextField(labelWithString: "\(settings.pipeCount)")
        let speedSlider = OptionsSheet.slider(range: PipesSettings.speedRange, value: settings.speed)
        super.init()

        countSlider.target = self
        countSlider.action = #selector(countChanged)
        let countSlider = countSlider
        sheet = OptionsSheet(title: "Retro Pipes", rows: [
            ("Joints:", jointPopUp),
            ("Surface:", surfacePopUp),
            ("Pipes at once:", NSStackView(views: [countSlider, countLabel])),
            ("Speed:", speedSlider),
        ]) {
            var newSettings = settings
            newSettings.jointStyle = JointStyle.allCases[jointPopUp.indexOfSelectedItem]
            newSettings.surface = Surface.allCases[surfacePopUp.indexOfSelectedItem]
            newSettings.pipeCount = countSlider.integerValue
            newSettings.speed = speedSlider.doubleValue
            onSave(newSettings)
        }
    }

    @objc private func countChanged() {
        countLabel.stringValue = "\(countSlider.integerValue)"
    }
}
