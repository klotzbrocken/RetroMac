import AppKit

/// The Halloween dock's rim: a smouldering fire. A charred edge with embers glowing up and
/// dying down in it, a flickering red heat round it, and now and then a small flame licking up
/// from the top, sparks and a wisp of smoke rising. Core Animation only — the GPU keeps it moving, the dock's own
/// drawing is never asked again. Still under Reduce Motion, and paused while the dock is hidden.
final class EmberRim {
    private var root: CALayer?
    private var glow: CAShapeLayer?
    private var halo: CAShapeLayer?
    private var farHalo: CAShapeLayer?
    private var lavaMask: CAShapeLayer?
    private var maskHolder: CALayer?
    private var lava: CAGradientLayer?
    private var undertow: CAGradientLayer?
    private var sparks: CAShapeLayer?
    private var flames: CAEmitterLayer?
    private var configuredPath: CGPath?

    /// `path`: the bar's outline in the host's coordinates — a rounded rect, or the rubber band;
    /// `restBar`: the bar itself, whose top edge the flames rise from.
    func update(host: CALayer, path barPath: CGPath, restBar: NSRect) {
        if root == nil { build(in: host) }
        guard let root, barPath != configuredPath else { return }
        configuredPath = barPath
        let bar = barPath.boundingBox
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.frame = host.bounds
        maskHolder?.frame = root.bounds
        lavaMask?.frame = root.bounds
        for layer in [glow, halo, farHalo] { layer?.frame = root.bounds; layer?.rasterizationScale = host.contentsScale }
        glow?.path = barPath
        halo?.path = barPath
        farHalo?.path = barPath
        lavaMask?.path = barPath
        sparks?.path = barPath
        // Shadows with a given shape: without one, Core Animation renders each shadowed layer
        // off screen to find its outline, again at every new path — every step of the rubber
        // band — and the dock stuttered.
        let outline = barPath.copy(strokingWithWidth: 6, lineCap: .round, lineJoin: .round, miterLimit: 2)
        halo?.shadowPath = outline
        farHalo?.shadowPath = outline
        glow?.shadowPath = outline
        lavaMask?.shadowPath = outline
        // The gradients turn behind the mask: squares round the bar, so no corner is ever bare.
        let side = hypot(bar.width, bar.height) + 20
        for g in [lava, undertow] {
            g?.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            g?.position = CGPoint(x: bar.midX, y: bar.midY)
        }
        flames?.frame = root.bounds
        flames?.emitterPosition = CGPoint(x: restBar.midX, y: restBar.maxY - 1)
        flames?.emitterSize = CGSize(width: max(0, restBar.width - 30), height: 0)
        CATransaction.commit()
    }

    func refreshAnimationState(visible: Bool) {
        guard let root else { return }
        if visible { root.speed = 1; root.timeOffset = 0 }
        else { root.timeOffset = root.convertTime(CACurrentMediaTime(), from: nil); root.speed = 0 }
    }

    func teardown() {
        root?.removeFromSuperlayer()
        root = nil; glow = nil; halo = nil; farHalo = nil; lavaMask = nil; maskHolder = nil; lava = nil; undertow = nil; sparks = nil; flames = nil
        configuredPath = nil
    }

    /// A soft round blob, white, for the particles to tint: drawn, not a picture of anything.
    private static let blob: CGImage = {
        let n = 32
        let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 16, y: 16), startRadius: 0, endCenter: CGPoint(x: 16, y: 16), endRadius: 16, options: [])
        return ctx.makeImage()!
    }()

    private static func flameCell() -> CAEmitterCell {
        let c = CAEmitterCell()
        c.contents = blob
        c.birthRate = 9; c.lifetime = 0.9; c.lifetimeRange = 0.35
        c.velocity = 14; c.velocityRange = 6
        c.emissionLongitude = .pi / 2; c.emissionRange = 0.35   // up
        c.yAcceleration = 20
        c.scale = 0.42; c.scaleRange = 0.15; c.scaleSpeed = -0.35
        c.color = NSColor(srgbRed: 1.0, green: 0.42, blue: 0.06, alpha: 0.75).cgColor
        c.greenSpeed = -0.35; c.alphaSpeed = -0.8
        return c
    }

    private static func sparkCell() -> CAEmitterCell {
        let c = CAEmitterCell()
        c.contents = blob
        c.birthRate = 2.5; c.lifetime = 2.2; c.lifetimeRange = 0.8
        c.velocity = 26; c.velocityRange = 12
        c.emissionLongitude = .pi / 2; c.emissionRange = 0.6
        c.yAcceleration = 6; c.xAcceleration = 3
        c.scale = 0.09; c.scaleRange = 0.04
        c.color = NSColor(srgbRed: 1.0, green: 0.78, blue: 0.35, alpha: 1).cgColor
        c.alphaSpeed = -0.45
        return c
    }

    private static func smokeCell() -> CAEmitterCell {
        let c = CAEmitterCell()
        c.contents = blob
        c.birthRate = 1.2; c.lifetime = 3.5; c.lifetimeRange = 1
        c.velocity = 9; c.velocityRange = 4
        c.emissionLongitude = .pi / 2; c.emissionRange = 0.4
        c.xAcceleration = 2
        c.scale = 0.9; c.scaleRange = 0.3; c.scaleSpeed = 0.35
        c.color = NSColor(white: 0.55, alpha: 0.10).cgColor
        c.alphaSpeed = -0.03
        return c
    }

    private func build(in host: CALayer) {
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let ember = NSColor(srgbRed: 1.0, green: 0.42, blue: 0.05, alpha: 1).cgColor
        let root = CALayer()
        root.zPosition = -1   // under the icons

        // The heat: two deep-red halos, a near and a far one, fading against each other, so it
        // seems to swell and sink. Only their opacity moves: each is drawn once and kept as a
        // picture (shouldRasterize), where a changing blur radius was blurred again every frame
        // and kept the WindowServer at half a core.
        func heat(radius: CGFloat, width: CGFloat) -> CAShapeLayer {
            let l = CAShapeLayer()
            l.fillColor = nil
            l.strokeColor = NSColor(srgbRed: 0.55, green: 0.08, blue: 0.0, alpha: 0.85).cgColor
            l.lineWidth = width
            l.shadowColor = NSColor(srgbRed: 0.95, green: 0.18, blue: 0.0, alpha: 1).cgColor
            l.shadowOffset = .zero
            l.shadowRadius = radius
            l.shadowOpacity = 1
            l.shouldRasterize = true
            root.addSublayer(l)
            return l
        }
        let farHalo = heat(radius: 36, width: 9)
        let halo = heat(radius: 20, width: 6)

        // The glow: a brighter orange close to the line, on a quicker, uneven beat.
        let glow = CAShapeLayer()
        glow.fillColor = nil
        glow.strokeColor = ember
        glow.lineWidth = 3
        glow.shadowColor = NSColor(srgbRed: 1.0, green: 0.45, blue: 0.0, alpha: 1).cgColor
        glow.shadowOffset = .zero
        glow.shadowRadius = 12
        glow.shadowOpacity = 1
        glow.shouldRasterize = true
        root.addSublayer(glow)

        // The lava: a molten band with soft edges, two flows of crust and glow turning against
        // each other inside it, so it churns like something liquid.
        let lava = CAGradientLayer()
        lava.type = .conic
        lava.startPoint = CGPoint(x: 0.5, y: 0.5)
        lava.endPoint = CGPoint(x: 0.5, y: 0)
        // Charred, with embers in it: mostly dark, a few stretches glowing red and orange.
        let char = NSColor(srgbRed: 0.16, green: 0.04, blue: 0.02, alpha: 1), coal = NSColor(srgbRed: 0.62, green: 0.10, blue: 0.02, alpha: 1)
        lava.colors = [char, coal, char, char, NSColor(srgbRed: 0.95, green: 0.32, blue: 0.04, alpha: 1), coal, char,
                       char, coal, char, NSColor(srgbRed: 0.85, green: 0.22, blue: 0.03, alpha: 1), char, char].map(\.cgColor)
        let undertow = CAGradientLayer()
        undertow.type = .conic
        undertow.startPoint = CGPoint(x: 0.5, y: 0.5)
        undertow.endPoint = CGPoint(x: 0.5, y: 0)
        // The embers that flare: a few bright spots wandering the other way, breathing.
        let none = NSColor(srgbRed: 0.3, green: 0.02, blue: 0, alpha: 0)
        undertow.colors = [none, NSColor(srgbRed: 1.0, green: 0.62, blue: 0.15, alpha: 0.9), none, none, none,
                           NSColor(srgbRed: 1.0, green: 0.48, blue: 0.08, alpha: 0.8), none, none,
                           NSColor(srgbRed: 1.0, green: 0.75, blue: 0.30, alpha: 0.85), none, none, none, none].map(\.cgColor)
        let maskHolder = CALayer()
        let lavaMask = CAShapeLayer()
        lavaMask.fillColor = nil
        lavaMask.strokeColor = NSColor.white.cgColor
        lavaMask.lineWidth = 5.5
        lavaMask.shadowColor = NSColor.white.cgColor   // feathered edges: molten, not drawn
        lavaMask.shadowOffset = .zero
        lavaMask.shadowRadius = 2.5
        lavaMask.shadowOpacity = 1
        maskHolder.addSublayer(lava)
        maskHolder.addSublayer(undertow)
        maskHolder.mask = lavaMask
        root.addSublayer(maskHolder)

        // Sparks: short bright dashes running round the rim.
        let sparks = CAShapeLayer()
        sparks.fillColor = nil
        sparks.strokeColor = NSColor(srgbRed: 1.0, green: 0.86, blue: 0.45, alpha: 0.9).cgColor
        sparks.lineWidth = 1
        sparks.lineCap = .round
        sparks.lineDashPattern = [1.5, 23, 0.8, 41, 2.5, 67]
        root.addSublayer(sparks)

        // Flames, sparks and smoke rising from the top edge: few, as a fire that smoulders.
        if !still {
            let flames = CAEmitterLayer()
            flames.emitterShape = .line
            flames.emitterMode = .outline
            flames.renderMode = .additive
            flames.emitterCells = [Self.flameCell(), Self.sparkCell(), Self.smokeCell()]
            root.addSublayer(flames)
            self.flames = flames
        }

        host.addSublayer(root)

        if !still {
            // Beats of different lengths that never line up, so the heat never repeats the same way.
            // Slow things at about 15 frames a second: nobody sees the difference in a glow, the
            // WindowServer does.
            let slow = CAFrameRateRange(minimum: 10, maximum: 20, preferred: 15)
            func waver(_ layer: CALayer, _ key: String, _ values: [CGFloat], _ duration: CFTimeInterval) {
                let a = CAKeyframeAnimation(keyPath: key)
                a.values = values; a.duration = duration; a.repeatCount = .infinity
                a.calculationMode = .cubic
                a.preferredFrameRateRange = slow
                layer.add(a, forKey: key)
            }
            // Fire flickers: quick, uneven, never quite the same.
            waver(farHalo, "opacity", [0.25, 0.7, 0.35, 0.9, 0.3, 0.55, 0.8, 0.25], 2.9)
            waver(halo, "opacity", [0.8, 0.45, 0.95, 0.5, 0.7, 0.4, 1, 0.8], 1.6)
            waver(glow, "opacity", [0.7, 0.4, 0.85, 0.55, 0.9, 0.35, 0.7], 1.1)
            waver(undertow, "opacity", [0.4, 1, 0.55, 0.85, 0.3, 0.9, 0.4], 2.3)
            let against = CABasicAnimation(keyPath: "transform.rotation.z")
            against.fromValue = 0; against.toValue = -2 * Double.pi
            against.duration = 9; against.repeatCount = .infinity
            against.preferredFrameRateRange = slow
            undertow.add(against, forKey: "turn")
            let turn = CABasicAnimation(keyPath: "transform.rotation.z")
            turn.fromValue = 0; turn.toValue = 2 * Double.pi
            turn.duration = 14; turn.repeatCount = .infinity
            turn.preferredFrameRateRange = slow
            lava.add(turn, forKey: "turn")
            let run = CABasicAnimation(keyPath: "lineDashPhase")
            run.fromValue = 0; run.toValue = -135
            run.duration = 4.5; run.repeatCount = .infinity
            run.preferredFrameRateRange = slow
            sparks.add(run, forKey: "run")
        }
        self.root = root; self.glow = glow; self.halo = halo; self.farHalo = farHalo; self.lavaMask = lavaMask; self.maskHolder = maskHolder; self.lava = lava; self.undertow = undertow; self.sparks = sparks
    }
}
