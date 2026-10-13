import AppKit

/// The Flower Box "Options…" sheet.
final class FlowerBoxOptions {
    let sheet: OptionsSheet

    init(settings: FlowerBoxSettings, onSave: @escaping (FlowerBoxSettings) -> Void) {
        let shapePopUp = OptionsSheet.popUp(
            titles: FlowerBoxShape.allCases.map(\.title),
            selectedIndex: FlowerBoxShape.allCases.firstIndex(of: settings.shape) ?? 0
        )
        let sizeSlider = OptionsSheet.slider(range: FlowerBoxSettings.sizeRange, value: settings.size)
        let speedSlider = OptionsSheet.slider(range: FlowerBoxSettings.speedRange, value: settings.speed)
        let spinBox = Self.checkbox("Spin", isOn: settings.spins)
        let bloomBox = Self.checkbox("Bloom", isOn: settings.blooms)
        let colorBox = Self.checkbox("Cycle colors", isOn: settings.cyclesColors)
        let animation = NSStackView(views: [spinBox, bloomBox, colorBox])
        animation.orientation = .vertical
        animation.alignment = .leading
        animation.spacing = 6

        sheet = OptionsSheet(title: "Retro Flower Box", rows: [
            ("Shape:", shapePopUp),
            ("Size:", sizeSlider),
            ("Speed:", speedSlider),
            ("Animation:", animation),
        ]) {
            var newSettings = settings
            newSettings.shape = FlowerBoxShape.allCases[shapePopUp.indexOfSelectedItem]
            newSettings.size = sizeSlider.doubleValue
            newSettings.speed = speedSlider.doubleValue
            newSettings.spins = spinBox.state == .on
            newSettings.blooms = bloomBox.state == .on
            newSettings.cyclesColors = colorBox.state == .on
            onSave(newSettings)
        }
    }

    private static func checkbox(_ title: String, isOn: Bool) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        checkbox.state = isOn ? .on : .off
        return checkbox
    }
}
