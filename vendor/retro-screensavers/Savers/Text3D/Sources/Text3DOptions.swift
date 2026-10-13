import AppKit

/// The 3D Text "Options…" sheet.
final class Text3DOptions: NSObject, NSTextFieldDelegate {
    private(set) var sheet: OptionsSheet!
    private let contentPopUp: NSPopUpButton
    private let textField: NSTextField
    private let surfacePopUp: NSPopUpButton
    private let colorPopUp: NSPopUpButton

    init(settings: Text3DSettings, onSave: @escaping (Text3DSettings) -> Void) {
        contentPopUp = OptionsSheet.popUp(titles: TextContent.allCases.map(\.title), selectedIndex: TextContent.allCases.firstIndex(of: settings.content) ?? 0)
        textField = NSTextField(string: settings.text)
        textField.placeholderString = "Your text"
        textField.widthAnchor.constraint(equalToConstant: 200).isActive = true
        let fontPopUp = OptionsSheet.popUp(titles: TextFont.all.map(\.title), selectedIndex: settings.fontIndex)
        let rotationPopUp = OptionsSheet.popUp(titles: RotationStyle.allCases.map(\.title), selectedIndex: RotationStyle.allCases.firstIndex(of: settings.rotation) ?? 0)
        let speedSlider = OptionsSheet.slider(range: Text3DSettings.speedRange, value: settings.speed)
        let sizeSlider = OptionsSheet.slider(range: Text3DSettings.sizeRange, value: settings.size)
        surfacePopUp = OptionsSheet.popUp(titles: TextSurface.allCases.map(\.title), selectedIndex: TextSurface.allCases.firstIndex(of: settings.surface) ?? 0)
        colorPopUp = OptionsSheet.popUp(titles: TextColor.all.map(\.title), selectedIndex: settings.colorIndex)
        let highlightsBox = NSButton(checkboxWithTitle: "Specular highlights", target: nil, action: nil)
        highlightsBox.state = settings.showsHighlights ? .on : .off
        super.init()

        contentPopUp.target = self
        contentPopUp.action = #selector(updateEnabledControls)
        surfacePopUp.target = self
        surfacePopUp.action = #selector(updateEnabledControls)
        textField.delegate = self
        updateEnabledControls()

        let contentPopUp = contentPopUp
        let textField = textField
        let surfacePopUp = surfacePopUp
        let colorPopUp = colorPopUp
        sheet = OptionsSheet(title: "Retro 3D Text", rows: [
            ("Display:", contentPopUp),
            ("Text:", textField),
            ("Font:", fontPopUp),
            ("Rotation:", rotationPopUp),
            ("Speed:", speedSlider),
            ("Size:", sizeSlider),
            ("Surface:", surfacePopUp),
            ("Color:", colorPopUp),
            ("", highlightsBox),
        ]) {
            var newSettings = settings
            newSettings.content = TextContent.allCases[contentPopUp.indexOfSelectedItem]
            let text = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            newSettings.text = text.isEmpty ? settings.text : String(text.prefix(Text3DSettings.maximumTextLength))
            newSettings.fontIndex = fontPopUp.indexOfSelectedItem
            newSettings.rotation = RotationStyle.allCases[rotationPopUp.indexOfSelectedItem]
            newSettings.speed = speedSlider.doubleValue
            newSettings.size = sizeSlider.doubleValue
            newSettings.surface = TextSurface.allCases[surfacePopUp.indexOfSelectedItem]
            newSettings.colorIndex = colorPopUp.indexOfSelectedItem
            newSettings.showsHighlights = highlightsBox.state == .on
            onSave(newSettings)
        }
    }

    /// The text only matters when showing text, the colour only for solid colour.
    @objc private func updateEnabledControls() {
        textField.isEnabled = TextContent.allCases[contentPopUp.indexOfSelectedItem] == .text
        colorPopUp.isEnabled = TextSurface.allCases[surfacePopUp.indexOfSelectedItem] == .solid
    }

    func controlTextDidChange(_ notification: Notification) {
        if textField.stringValue.count > Text3DSettings.maximumTextLength {
            textField.stringValue = String(textField.stringValue.prefix(Text3DSettings.maximumTextLength))
        }
    }
}
