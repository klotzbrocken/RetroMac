import AppKit

/// A screen saver's "Options…" sheet: a title, a column of labelled controls, and Cancel/OK.
/// A saver builds its controls, passes them in as rows, and reads them back in `onConfirm`.
final class OptionsSheet: NSObject {
    let window: NSWindow
    private let onConfirm: () -> Void

    init(title: String, rows: [(label: String, control: NSView)], onConfirm: @escaping () -> Void) {
        self.onConfirm = onConfirm
        window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        super.init()

        let grid = NSGridView(views: rows.map { [NSTextField(labelWithString: $0.label), $0.control] })
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 12
        grid.columnSpacing = 8

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 2)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        let okButton = NSButton(title: "OK", target: self, action: #selector(confirm))
        okButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [cancelButton, okButton])

        let content = NSView()
        for view in [titleLabel, grid, buttons] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            buttons.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 20),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])

        window.contentView = content
        window.setContentSize(content.fittingSize)
    }

    static func popUp(titles: [String], selectedIndex: Int) -> NSPopUpButton {
        let popUp = NSPopUpButton()
        popUp.addItems(withTitles: titles)
        popUp.selectItem(at: selectedIndex)
        return popUp
    }

    /// A 200pt slider; with `steps`, it snaps to that many evenly spaced values.
    static func slider(range: ClosedRange<Double>, value: Double, steps: Int? = nil) -> NSSlider {
        let slider = NSSlider()
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        if let steps {
            slider.numberOfTickMarks = steps
            slider.allowsTickMarkValuesOnly = true
        }
        slider.doubleValue = value
        slider.widthAnchor.constraint(equalToConstant: 200).isActive = true
        return slider
    }

    @objc private func confirm() {
        onConfirm()
        close()
    }

    @objc private func cancel() {
        close()
    }

    private func close() {
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.close()
        }
    }
}
