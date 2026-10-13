import AppKit

/// The 3D Maze "Options…" sheet.
final class MazeOptions: NSObject {
    private(set) var sheet: OptionsSheet!
    private let ratsSlider: NSSlider
    private let ratsLabel: NSTextField
    private let flippersSlider: NSSlider
    private let flippersLabel: NSTextField

    init(settings: MazeSettings, onSave: @escaping (MazeSettings) -> Void) {
        let sizePopUp = OptionsSheet.popUp(titles: MazeSize.allCases.map(\.title), selectedIndex: MazeSize.allCases.firstIndex(of: settings.size) ?? 0)
        let speedSlider = OptionsSheet.slider(range: MazeSettings.speedRange, value: settings.speed)
        ratsSlider = Self.countSlider(range: MazeSettings.ratsRange, value: settings.rats)
        ratsLabel = NSTextField(labelWithString: "\(settings.rats)")
        flippersSlider = Self.countSlider(range: MazeSettings.flippersRange, value: settings.flippers)
        flippersLabel = NSTextField(labelWithString: "\(settings.flippers)")
        let mapBox = NSButton(checkboxWithTitle: "Show map", target: nil, action: nil)
        mapBox.state = settings.showsMap ? .on : .off
        super.init()

        for slider in [ratsSlider, flippersSlider] {
            slider.target = self
            slider.action = #selector(countChanged)
        }
        let ratsSlider = ratsSlider
        let flippersSlider = flippersSlider
        sheet = OptionsSheet(title: "Retro 3D Maze", rows: [
            ("Maze size:", sizePopUp),
            ("Speed:", speedSlider),
            ("Rats:", NSStackView(views: [ratsSlider, ratsLabel])),
            ("Flippers:", NSStackView(views: [flippersSlider, flippersLabel])),
            ("", mapBox),
        ]) {
            var newSettings = settings
            newSettings.size = MazeSize.allCases[sizePopUp.indexOfSelectedItem]
            newSettings.speed = speedSlider.doubleValue
            newSettings.rats = ratsSlider.integerValue
            newSettings.flippers = flippersSlider.integerValue
            newSettings.showsMap = mapBox.state == .on
            onSave(newSettings)
        }
    }

    private static func countSlider(range: ClosedRange<Int>, value: Int) -> NSSlider {
        OptionsSheet.slider(range: Double(range.lowerBound)...Double(range.upperBound), value: Double(value), steps: range.count)
    }

    @objc private func countChanged() {
        ratsLabel.stringValue = "\(ratsSlider.integerValue)"
        flippersLabel.stringValue = "\(flippersSlider.integerValue)"
    }
}
