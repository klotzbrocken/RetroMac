import AppKit

/// The windowed errors: the Windows 9x illegal-operation dialog and the Macintosh bomb alert.
///
/// Two things separate these from the full-screen text modes. They are drawn in points, not in
/// pixels, because they were never a video mode — a Windows dialog was always the size the system
/// font made it. And they have buttons that must work: an OK button that does nothing is the one
/// detail that tells a viewer this is a picture rather than a program.
enum CrashDialogRenderer {

    /// A finished dialog: the artwork, and where its buttons are inside it.
    struct Rendered {
        let image: NSImage
        /// Button rects in the image's own coordinates, y up, and the label each belongs to.
        let buttons: [(rect: NSRect, label: String)]
    }

    /// Draw at the display's own resolution and hand back an image whose logical size is the
    /// dialog's real size. Drawing at 1x and then scaling the view up by two is what made the
    /// first version look soft.
    private static func render(size: NSSize, scale: CGFloat, _ body: (NSSize) -> Void) -> NSImage {
        let px = NSSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(px.width), pixelsHigh: Int(px.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else {
            return NSImage(size: size)
        }
        rep.size = size                        // logical size stays in points…
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        body(size)                             // …so the drawing code works in points
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    // MARK: - Windows 9x

    /// The invalid-page-fault dialog. Real ones were small: a caption bar, three or four lines of
    /// text and two buttons, in MS Sans Serif at 8pt. `expanded` adds the register dump that
    /// "Details >>" revealed, which is the only thing that button ever did.
    /// Routes to the era that owns this dialog. One entry point so the director never has to
    /// know which paint job a scenario asked for.
    static func dialog(_ dialog: ErrorDialog, expanded: Bool, scale: CGFloat) -> Rendered {
        // Content decides before style does. A dialog with a sunken report well, a status strip
        // or a column of buttons needs the painter that can draw those — the Luna one cannot,
        // and routing an antivirus notification to it silently dropped its entire contents.
        let needsClassicFurniture = !dialog.report.isEmpty
            || dialog.statusBar != nil
            || dialog.buttonLayout == .rightColumn
            || !dialog.details.isEmpty
        if needsClassicFurniture || dialog.style == .win9x {
            return classicDialog(dialog, expanded: expanded, scale: scale)
        }
        switch dialog.style {
        case .winXP: return lunaDialog(dialog, scale: scale, aero: false)
        case .win7:  return lunaDialog(dialog, scale: scale, aero: true)
        case .aqua:  return aquaDialog(dialog, scale: scale)
        case .win9x: return classicDialog(dialog, expanded: expanded, scale: scale)
        }
    }

    /// Windows XP's error-reporting dialog: a Luna caption, plain text, and the two buttons that
    /// asked whether Microsoft could have a copy of what just went wrong.
    /// `aero` swaps Luna's saturated blue caption for Windows 7's pale glass one. Same layout —
    /// the dialog did not change shape between the two, only its paint.
    static func lunaDialog(_ dialog: ErrorDialog, scale: CGFloat, aero: Bool) -> Rendered {
        let font = NSFont(name: "Tahoma", size: 11) ?? NSFont.systemFont(ofSize: 11)
        let bold = NSFont(name: "Tahoma Bold", size: 11) ?? NSFont.boldSystemFont(ofSize: 11)
        let lineH: CGFloat = 15, padX: CGFloat = 14, titleH: CGFloat = 26
        let buttonH: CGFloat = 23, buttonW: CGFloat = 112, iconSide: CGFloat = 32

        let textW = dialog.body.reduce(CGFloat(0)) { w, line in
            max(w, (line as NSString).size(withAttributes: [.font: font]).width)
        }
        let width = max(360, ceil(padX + iconSide + 12 + textW + padX))
        let height = ceil(titleH + 14 + max(iconSide, CGFloat(dialog.body.count) * lineH) + 16 + buttonH + 14)

        var buttons: [(NSRect, String)] = []
        let image = render(size: NSSize(width: width, height: height), scale: scale) { size in
            let bounds = NSRect(origin: .zero, size: size)
            // Luna's dialog face is a warm grey; Aero's is near-white.
            (aero ? NSColor(srgbRed: 0.941, green: 0.949, blue: 0.957, alpha: 1)
                  : NSColor(srgbRed: 0.925, green: 0.914, blue: 0.847, alpha: 1)).setFill()
            bounds.fill()

            // Caption: the blue gradient, rounded at the top only.
            let cap = NSRect(x: 0, y: bounds.maxY - titleH, width: size.width, height: titleH)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: cap.minX, y: cap.minY))
            path.line(to: NSPoint(x: cap.minX, y: cap.maxY - 6))
            path.appendArc(withCenter: NSPoint(x: cap.minX + 6, y: cap.maxY - 6), radius: 6,
                           startAngle: 180, endAngle: 90, clockwise: true)
            path.line(to: NSPoint(x: cap.maxX - 6, y: cap.maxY))
            path.appendArc(withCenter: NSPoint(x: cap.maxX - 6, y: cap.maxY - 6), radius: 6,
                           startAngle: 90, endAngle: 0, clockwise: true)
            path.line(to: NSPoint(x: cap.maxX, y: cap.minY))
            path.close()
            if aero {
                NSGradient(colors: [NSColor(srgbRed: 0.90, green: 0.94, blue: 0.98, alpha: 1),
                                    NSColor(srgbRed: 0.79, green: 0.86, blue: 0.93, alpha: 1)])?
                    .draw(in: path, angle: -90)
            } else {
                NSGradient(colors: [NSColor(srgbRed: 0.27, green: 0.60, blue: 0.99, alpha: 1),
                                    NSColor(srgbRed: 0.01, green: 0.31, blue: 0.78, alpha: 1)])?
                    .draw(in: path, angle: -90)
            }
            (dialog.title as NSString).draw(at: NSPoint(x: cap.minX + 8, y: cap.midY - 8),
                                            withAttributes: [.font: bold,
                                                             .foregroundColor: aero ? NSColor.black : NSColor.white])

            // The rounded red cross XP used for an application error.
            let iconRect = NSRect(x: padX, y: cap.minY - 14 - iconSide, width: iconSide, height: iconSide)
            NSColor(srgbRed: 0.80, green: 0.11, blue: 0.11, alpha: 1).setFill()
            NSBezierPath(ovalIn: iconRect).fill()
            NSColor.white.setStroke()
            let cross = NSBezierPath()
            let inset = iconSide * 0.30
            cross.move(to: NSPoint(x: iconRect.minX + inset, y: iconRect.minY + inset))
            cross.line(to: NSPoint(x: iconRect.maxX - inset, y: iconRect.maxY - inset))
            cross.move(to: NSPoint(x: iconRect.minX + inset, y: iconRect.maxY - inset))
            cross.line(to: NSPoint(x: iconRect.maxX - inset, y: iconRect.minY + inset))
            cross.lineWidth = 3; cross.stroke()

            var y = cap.minY - 14 - 12
            for line in dialog.body {
                (line as NSString).draw(at: NSPoint(x: iconRect.maxX + 12, y: y),
                                        withAttributes: [.font: font, .foregroundColor: NSColor.black])
                y -= lineH
            }

            var bx = size.width - padX - CGFloat(dialog.buttons.count) * (buttonW + 8) + 8
            for label in dialog.buttons {
                let r = NSRect(x: bx, y: 14, width: buttonW, height: buttonH)
                let p = NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3)
                NSGradient(colors: [NSColor(white: 1.0, alpha: 1), NSColor(white: 0.88, alpha: 1)])?
                    .draw(in: p, angle: -90)
                NSColor(srgbRed: 0.44, green: 0.50, blue: 0.60, alpha: 1).setStroke()
                p.lineWidth = 1; p.stroke()
                let s = (label as NSString).size(withAttributes: [.font: font])
                (label as NSString).draw(at: NSPoint(x: r.midX - s.width / 2, y: r.midY - s.height / 2),
                                         withAttributes: [.font: font, .foregroundColor: NSColor.black])
                buttons.append((r, label))
                bx += buttonW + 8
            }
        }
        return Rendered(image: image, buttons: buttons.map { (rect: $0.0, label: $0.1) })
    }

    /// Mac OS X's "has unexpectedly quit": a plain Aqua sheet, the application icon's place taken
    /// by a caution triangle, and the three buttons that arrived with crash reporting.
    static func aquaDialog(_ dialog: ErrorDialog, scale: CGFloat) -> Rendered {
        let title = NSFont.boldSystemFont(ofSize: 13)
        let font = NSFont.systemFont(ofSize: 11)
        let lineH: CGFloat = 15, pad: CGFloat = 20
        let buttonH: CGFloat = 22, buttonW: CGFloat = 84, iconSide: CGFloat = 48

        let textW = dialog.body.reduce(CGFloat(260)) { w, line in
            max(w, (line as NSString).size(withAttributes: [.font: font]).width)
        }
        let width = ceil(pad + iconSide + 16 + textW + pad)
        let height = ceil(pad + CGFloat(dialog.body.count) * lineH + 22 + buttonH + pad)

        var buttons: [(NSRect, String)] = []
        let image = render(size: NSSize(width: width, height: height), scale: scale) { size in
            let bounds = NSRect(origin: .zero, size: size)
            let body = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
            NSColor(srgbRed: 0.929, green: 0.929, blue: 0.929, alpha: 1).setFill()
            body.fill()
            NSColor(white: 0.62, alpha: 1).setStroke(); body.lineWidth = 1; body.stroke()

            let iconRect = NSRect(x: pad, y: bounds.maxY - pad - iconSide, width: iconSide, height: iconSide)
            if let caution = NSImage(named: NSImage.cautionName) {
                caution.draw(in: iconRect)
            }

            var y = bounds.maxY - pad - 14
            for (i, line) in dialog.body.enumerated() {
                let f = i == 0 ? title : font
                (line as NSString).draw(at: NSPoint(x: iconRect.maxX + 16, y: y),
                                        withAttributes: [.font: f, .foregroundColor: NSColor.black])
                y -= i == 0 ? lineH + 4 : lineH
            }

            var bx = size.width - pad - CGFloat(dialog.buttons.count) * (buttonW + 10) + 10
            for (i, label) in dialog.buttons.enumerated() {
                let r = NSRect(x: bx, y: pad - 4, width: buttonW, height: buttonH)
                let p = NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5)
                let isDefault = i == dialog.buttons.count - 1
                if isDefault {
                    NSGradient(colors: [NSColor(srgbRed: 0.42, green: 0.66, blue: 0.95, alpha: 1),
                                        NSColor(srgbRed: 0.20, green: 0.45, blue: 0.85, alpha: 1)])?
                        .draw(in: p, angle: -90)
                } else {
                    NSGradient(colors: [.white, NSColor(white: 0.90, alpha: 1)])?.draw(in: p, angle: -90)
                }
                NSColor(white: 0.55, alpha: 1).setStroke(); p.lineWidth = 1; p.stroke()
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: isDefault ? NSColor.white : NSColor.black]
                let s = (label as NSString).size(withAttributes: attrs)
                (label as NSString).draw(at: NSPoint(x: r.midX - s.width / 2, y: r.midY - s.height / 2),
                                         withAttributes: attrs)
                buttons.append((r, label))
                bx += buttonW + 10
            }
        }
        return Rendered(image: image, buttons: buttons.map { (rect: $0.0, label: $0.1) })
    }

    /// The bevelled Windows dialog, laid out the way the originals were: the badge and the
    /// message on the left, buttons either along the bottom or stacked down the right-hand side,
    /// and a sunken white well for a register dump or an antivirus report. Used for every era
    /// that needs that furniture — XP's antivirus notifications wore an XP caption on exactly
    /// this body.
    static func classicDialog(_ dialog: ErrorDialog, expanded: Bool, scale: CGFloat) -> Rendered {
        let font = NSFont(name: "Tahoma", size: 11) ?? NSFont.systemFont(ofSize: 11)
        let bold = NSFont(name: "Tahoma Bold", size: 11) ?? NSFont.boldSystemFont(ofSize: 11)
        let mono = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)

        let lineH: CGFloat = 14, padX: CGFloat = 10, titleH: CGFloat = 18
        let buttonH: CGFloat = 21, buttonW: CGFloat = 78, gap: CGFloat = 6
        let iconSide: CGFloat = 32
        let stackedRight = dialog.buttonLayout == .rightColumn

        let details = expanded ? (dialog.details.isEmpty ? registerDump(dialog) : dialog.details) : []
        let report = dialog.report

        let textW = dialog.body.reduce(CGFloat(0)) { w, line in
            max(w, (line as NSString).size(withAttributes: [.font: font]).width)
        }
        let wellLines = details + report
        let wellW = wellLines.reduce(CGFloat(0)) { w, line in
            max(w, (line as NSString).size(withAttributes: [.font: mono]).width)
        }
        let messageW = padX + iconSide + 10 + textW + padX
        let contentW = stackedRight ? messageW + buttonW + gap * 2 : messageW
        let wellNeeds = dialog.body.isEmpty && !report.isEmpty
            ? wellW + padX * 2 + iconSide + 20
            : wellW + padX * 2 + 20
        let width = max(300, ceil(max(contentW, wellNeeds)))

        // An empty body is a report-only dialog (the antivirus notifications): the badge sits
        // beside the well instead of above it, so there is no empty half at the top.
        let reportOnly = dialog.body.isEmpty && !report.isEmpty
        let messageH = reportOnly ? 0 : max(iconSide, CGFloat(dialog.body.count) * lineH)
        let buttonsH = dialog.buttons.isEmpty ? 0 : (stackedRight
            ? CGFloat(dialog.buttons.count) * (buttonH + gap)
            : buttonH + gap)
        let wellH = wellLines.isEmpty ? 0 : CGFloat(wellLines.count) * 12 + 14
        let statusH: CGFloat = dialog.statusBar == nil ? 0 : 22
        let bottomH = stackedRight || dialog.buttons.isEmpty ? 6 : buttonH + 12
        let height = ceil(titleH + 10 + max(messageH, buttonsH) + (reportOnly ? 0 : 10)
                          + wellH + statusH + bottomH)

        var buttons: [(NSRect, String)] = []
        let image = render(size: NSSize(width: width, height: height), scale: scale) { size in
            let bounds = NSRect(origin: .zero, size: size)
            Win31Chrome.face.setFill()
            bounds.fill()
            Win31Chrome.drawRaisedBevel(bounds, thickness: 2)

            // Caption bar with the close box.
            let titleRect = NSRect(x: 3, y: bounds.maxY - titleH - 3, width: size.width - 6, height: titleH)
            if dialog.style == .winXP {
                // Same body, XP's caption: which is exactly how these notifications looked when
                // the antivirus was older than the Windows it was running on.
                NSGradient(colors: [NSColor(srgbRed: 0.27, green: 0.60, blue: 0.99, alpha: 1),
                                    NSColor(srgbRed: 0.01, green: 0.31, blue: 0.78, alpha: 1)])?
                    .draw(in: titleRect, angle: -90)
            } else {
                Win31Chrome.activeTitle.setFill()
                titleRect.fill()
            }
            (dialog.title as NSString).draw(
                at: NSPoint(x: titleRect.minX + 5, y: titleRect.midY - 7),
                withAttributes: [.font: bold, .foregroundColor: NSColor.white])
            let closeBox = NSRect(x: titleRect.maxX - 18, y: titleRect.midY - 7, width: 14, height: 14)
            Win31Chrome.face.setFill(); closeBox.fill()
            Win31Chrome.drawRaisedBevel(closeBox, thickness: 1)
            NSColor.black.setStroke()
            let x1 = NSBezierPath()
            x1.move(to: NSPoint(x: closeBox.minX + 4, y: closeBox.minY + 4))
            x1.line(to: NSPoint(x: closeBox.maxX - 4, y: closeBox.maxY - 4))
            x1.move(to: NSPoint(x: closeBox.minX + 4, y: closeBox.maxY - 4))
            x1.line(to: NSPoint(x: closeBox.maxX - 4, y: closeBox.minY + 4))
            x1.lineWidth = 1; x1.stroke()
            buttons.append((closeBox, "Close"))

            let topOfBody = titleRect.minY - 10
            let iconRect = reportOnly
                ? NSRect(x: padX, y: topOfBody - iconSide - 6, width: iconSide, height: iconSide)
                : NSRect(x: padX, y: topOfBody - iconSide, width: iconSide, height: iconSide)
            CrashRenderer.badge(dialog.icon)?.draw(in: iconRect)

            var y = topOfBody - 12
            for line in dialog.body {
                (line as NSString).draw(at: NSPoint(x: iconRect.maxX + 10, y: y),
                                        withAttributes: [.font: font, .foregroundColor: NSColor.black])
                y -= lineH
            }

            // Buttons: stacked down the right in the classic error dialog, otherwise a row.
            if stackedRight {
                var by = topOfBody - buttonH
                for label in dialog.buttons {
                    let r = NSRect(x: size.width - padX - buttonW, y: by, width: buttonW, height: buttonH)
                    drawButton(r, label: label, dialog: dialog, expanded: expanded, font: font,
                               enabled: !(label == "Details >>" && expanded && !dialog.details.isEmpty))
                    buttons.append((r, label))
                    by -= buttonH + gap
                }
            } else {
                var bx = size.width - padX - CGFloat(dialog.buttons.count) * (buttonW + gap) + gap
                for label in dialog.buttons {
                    let r = NSRect(x: bx, y: 12 + wellH, width: buttonW, height: buttonH)
                    drawButton(r, label: label, dialog: dialog, expanded: expanded, font: font, enabled: true)
                    buttons.append((r, label))
                    bx += buttonW + gap
                }
            }

            // The well: the register dump behind Details, or an antivirus report.
            if !wellLines.isEmpty {
                let wellX = reportOnly ? iconRect.maxX + 10 : padX
                let well = NSRect(x: wellX, y: statusH + 8,
                                  width: size.width - wellX - padX, height: wellH - 6)
                NSColor.white.setFill(); well.fill()
                Win31Chrome.drawSunkenBevel(well, thickness: 1)
                var dy = well.maxY - 13
                for line in wellLines {
                    (line as NSString).draw(at: NSPoint(x: well.minX + 5, y: dy),
                                            withAttributes: [.font: mono, .foregroundColor: NSColor.black])
                    dy -= 12
                }
            }

            if let status = dialog.statusBar {
                let bar = NSRect(x: 3, y: 3, width: size.width - 6, height: 16)
                Win31Chrome.face.setFill(); bar.fill()
                let left = NSRect(x: bar.minX, y: bar.minY, width: bar.width * 0.55, height: bar.height)
                let right = NSRect(x: left.maxX + 2, y: bar.minY, width: bar.width - left.width - 2, height: bar.height)
                Win31Chrome.drawSunkenBevel(left, thickness: 1)
                Win31Chrome.drawSunkenBevel(right, thickness: 1)
                (status.0 as NSString).draw(at: NSPoint(x: left.minX + 4, y: left.midY - 6),
                                            withAttributes: [.font: font, .foregroundColor: NSColor.black])
                (status.1 as NSString).draw(at: NSPoint(x: right.minX + 4, y: right.midY - 6),
                                            withAttributes: [.font: font, .foregroundColor: NSColor.black])
            }
        }
        return Rendered(image: image, buttons: buttons.map { (rect: $0.0, label: $0.1) })
    }

    private static func drawButton(_ r: NSRect, label: String, dialog: ErrorDialog,
                                   expanded: Bool, font: NSFont, enabled: Bool) {
        Win31Chrome.face.setFill(); r.fill()
        Win31Chrome.drawRaisedBevel(r, thickness: 1)
        let title = (label == "Details >>" && expanded) ? "Details <<" : label
        let colour: NSColor = enabled ? .black : Win31Chrome.darkGray
        let s = (title as NSString).size(withAttributes: [.font: font])
        (title as NSString).draw(at: NSPoint(x: r.midX - s.width / 2, y: r.midY - s.height / 2),
                                 withAttributes: [.font: font, .foregroundColor: colour])
    }

    /// What "Details >>" actually showed: registers, then a stack dump nobody ever read.
    private static func registerDump(_ dialog: ErrorDialog) -> [String] {
        ["Registers:",
         "EAX=00000000 CS=0167 EIP=bff9db49 EFLGS=00010246",
         "EBX=0053f6c4 SS=016f ESP=0063fd3c EBP=0063fd54",
         "ECX=00000000 DS=016f ESI=8177c9e0 FS=4bb7",
         "EDX=bff76855 ES=016f EDI=00000000 GS=0000",
         "Bytes at CS:EIP:",
         "53 8b 15 20 00 fa bf 8b 42 04 50 e8 ac 00 00 00",
         "Stack dump:",
         "0053f6c4 00000000 bff9db49 0063fd54 00000001 00000000"]
    }

    /// The white-on-red stop sign of the 9x error dialogs, drawn rather than shipped.
    private static func drawStopIcon(_ rect: NSRect) {
        let r = rect.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath()
        let cut = r.width * 0.30
        path.move(to: NSPoint(x: r.minX + cut, y: r.minY))
        path.line(to: NSPoint(x: r.maxX - cut, y: r.minY))
        path.line(to: NSPoint(x: r.maxX, y: r.minY + cut))
        path.line(to: NSPoint(x: r.maxX, y: r.maxY - cut))
        path.line(to: NSPoint(x: r.maxX - cut, y: r.maxY))
        path.line(to: NSPoint(x: r.minX + cut, y: r.maxY))
        path.line(to: NSPoint(x: r.minX, y: r.maxY - cut))
        path.line(to: NSPoint(x: r.minX, y: r.minY + cut))
        path.close()
        NSColor(srgbRed: 0.78, green: 0.0, blue: 0.0, alpha: 1).setFill()
        path.fill()
        NSColor.white.setStroke()
        let bar = NSBezierPath()
        bar.move(to: NSPoint(x: r.minX + r.width * 0.22, y: r.midY))
        bar.line(to: NSPoint(x: r.maxX - r.width * 0.22, y: r.midY))
        bar.lineWidth = max(2, r.width * 0.13)
        bar.stroke()
    }

    // MARK: - Macintosh

    /// The caution triangle, for the alerts that were not a bomb.
    ///
    /// Drawn rather than shipped: it is three lines and a bar, and one more borrowed icon in the
    /// bundle would need one more line in the credits for no gain. Sized off the rect so it holds
    /// at any scale, with the exclamation built from rectangles so it stays crisp in the System 6
    /// alert, which is one bit deep and has no grey to fall back on.
    static func drawCaution(in rect: NSRect, isSix: Bool) {
        let w = rect.width, h = rect.height
        let lw = max(1, w / 16)
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: rect.midX, y: rect.maxY - lw))
        tri.line(to: NSPoint(x: rect.maxX - lw, y: rect.minY + lw))
        tri.line(to: NSPoint(x: rect.minX + lw, y: rect.minY + lw))
        tri.close()
        tri.lineJoinStyle = .round
        (isSix ? NSColor.white : ClassicMacChrome.face).setFill()
        tri.fill()
        NSColor.black.setStroke()
        tri.lineWidth = lw * 1.6
        tri.stroke()

        // The mark sits in the lower two thirds of the triangle, where there is room for it.
        NSColor.black.setFill()
        let barW = max(1, w * 0.11)
        let barTop = rect.minY + h * 0.62
        let barBottom = rect.minY + h * 0.30
        NSRect(x: rect.midX - barW / 2, y: barBottom, width: barW, height: barTop - barBottom).fill()
        NSRect(x: rect.midX - barW / 2, y: rect.minY + h * 0.19, width: barW, height: barW).fill()
    }

    /// The bomb alert, drawn at display resolution for the same reason as above.
    static func macAlert(_ alert: MacAlert, scale: CGFloat) -> Rendered {
        let isSix = alert.style == .system6
        let bodyFont = isSix
            ? (NSFont(name: "ChiKareGo2", size: 12) ?? NSFont(name: "Chicago", size: 12) ?? NSFont.boldSystemFont(ofSize: 12))
            : (NSFont(name: "Charcoal", size: 12) ?? NSFont.boldSystemFont(ofSize: 12))

        let lineH: CGFloat = 16
        let pad: CGFloat = 13
        let bombSide: CGFloat = 32
        let buttonH: CGFloat = 20
        let buttonW: CGFloat = 72
        let textLeft = pad + bombSide + 12

        let widest = alert.lines.reduce(CGFloat(200)) { w, line in
            max(w, (line as NSString).size(withAttributes: [.font: bodyFont]).width)
        }
        let width = ceil(textLeft + widest + pad)
        let bodyH = max(bombSide, CGFloat(alert.lines.count) * lineH)
        let height = ceil(pad + bodyH + 12 + buttonH + pad)

        var buttons: [(NSRect, String)] = []
        let image = render(size: NSSize(width: width, height: height), scale: scale) { size in
            let bounds = NSRect(origin: .zero, size: size)
            if isSix {
                NSColor.white.setFill(); bounds.fill()
                NSColor.black.setStroke()
                let outer = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)); outer.lineWidth = 1; outer.stroke()
                let inner = NSBezierPath(rect: bounds.insetBy(dx: 3.5, dy: 3.5)); inner.lineWidth = 1; inner.stroke()
            } else {
                ClassicMacChrome.face.setFill(); bounds.fill()
                NSColor(white: 0.42, alpha: 1).setStroke()
                let edge = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)); edge.lineWidth = 1; edge.stroke()
                NSColor.white.setStroke()
                let hi = NSBezierPath()
                hi.move(to: NSPoint(x: 1.5, y: 1.5))
                hi.line(to: NSPoint(x: 1.5, y: bounds.maxY - 1.5))
                hi.line(to: NSPoint(x: bounds.maxX - 1.5, y: bounds.maxY - 1.5))
                hi.lineWidth = 1; hi.stroke()
            }

            let iconRect = NSRect(x: pad, y: bounds.maxY - pad - bombSide,
                                  width: bombSide, height: bombSide)
            if alert.showsBomb {
                CrashRenderer.bomb?.draw(in: iconRect)
            } else {
                drawCaution(in: iconRect, isSix: isSix)
            }

            var y = bounds.maxY - pad - 13
            for line in alert.lines {
                (line as NSString).draw(at: NSPoint(x: textLeft, y: y),
                                        withAttributes: [.font: bodyFont, .foregroundColor: NSColor.black])
                y -= lineH
            }

            // System 6 put its buttons bottom left, Mac OS 9 bottom right.
            var bx = isSix ? pad : size.width - pad - CGFloat(alert.buttons.count) * (buttonW + 10) + 10
            for (i, label) in alert.buttons.enumerated() {
                let r = NSRect(x: bx, y: pad - 3, width: buttonW, height: buttonH)
                let enabled = alert.restartButton == nil || label == alert.restartButton || i == 0
                if isSix {
                    NSColor.white.setFill(); r.fill()
                    (enabled ? NSColor.black : System6Chrome.inactiveText).setStroke()
                    let p = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
                    p.lineWidth = 1
                    p.stroke()
                } else {
                    ClassicMacChrome.boxFace.setFill()
                    let p = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
                    p.fill()
                    NSColor(white: 0.45, alpha: 1).setStroke(); p.lineWidth = 1; p.stroke()
                }
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: bodyFont,
                    .foregroundColor: enabled ? NSColor.black : System6Chrome.inactiveText]
                let s = (label as NSString).size(withAttributes: attrs)
                (label as NSString).draw(at: NSPoint(x: r.midX - s.width / 2, y: r.midY - s.height / 2),
                                         withAttributes: attrs)
                if enabled { buttons.append((r, label)) }
                bx += buttonW + 10
            }

            if let id = alert.idCode {
                let s = (id as NSString).size(withAttributes: [.font: bodyFont])
                (id as NSString).draw(at: NSPoint(x: size.width - pad - s.width, y: pad + buttonH + 4),
                                      withAttributes: [.font: bodyFont, .foregroundColor: NSColor.black])
            }
        }
        return Rendered(image: image, buttons: buttons.map { (rect: $0.0, label: $0.1) })
    }
}
