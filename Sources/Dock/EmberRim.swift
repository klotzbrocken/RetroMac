import AppKit

/// The Halloween dock's rim: a fine line of glowing embers around the bar that wavers like lava,
/// with sparks running along it. Core Animation only — the GPU keeps it moving, the dock's own
/// drawing is never asked again. Still under Reduce Motion, and paused while the dock is hidden.
final class EmberRim {
    private var root: CALayer?
    private var glow: CAShapeLayer?
    private var halo: CAShapeLayer?
    private var lavaMask: CAShapeLayer?
    private var maskHolder: CALayer?
    private var lava: CAGradientLayer?
    private var sparks: CAShapeLayer?
    private var configured: NSRect = .zero

    func update(host: CALayer, barRect: NSRect, cornerRadius: CGFloat) {
        if root == nil { build(in: host) }
        guard let root, barRect != configured else { return }
        configured = barRect
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.frame = host.bounds
        maskHolder?.frame = root.bounds
        lavaMask?.frame = root.bounds
        let path = CGPath(roundedRect: barRect.insetBy(dx: 0.75, dy: 0.75), cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        glow?.path = path
        halo?.path = path
        lavaMask?.path = path
        sparks?.path = path
        // The gradient turns behind the mask: a square around the bar, so no corner is ever bare.
        let side = hypot(barRect.width, barRect.height) + 20
        lava?.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        lava?.position = CGPoint(x: barRect.midX, y: barRect.midY)
        CATransaction.commit()
    }

    func refreshAnimationState(visible: Bool) {
        guard let root else { return }
        if visible { root.speed = 1; root.timeOffset = 0 }
        else { root.timeOffset = root.convertTime(CACurrentMediaTime(), from: nil); root.speed = 0 }
    }

    func teardown() {
        root?.removeFromSuperlayer()
        root = nil; glow = nil; halo = nil; lavaMask = nil; maskHolder = nil; lava = nil; sparks = nil
        configured = .zero
    }

    private func build(in host: CALayer) {
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let ember = NSColor(srgbRed: 1.0, green: 0.42, blue: 0.05, alpha: 1).cgColor
        let root = CALayer()
        root.zPosition = -1   // under the icons

        // The halo: a wide, deep-red heat that swells and sinks on its own slow beat.
        let halo = CAShapeLayer()
        halo.fillColor = nil
        halo.strokeColor = NSColor(srgbRed: 0.85, green: 0.16, blue: 0.0, alpha: 0.9).cgColor
        halo.lineWidth = 3
        halo.shadowColor = NSColor(srgbRed: 1.0, green: 0.22, blue: 0.0, alpha: 1).cgColor
        halo.shadowOffset = .zero
        halo.shadowRadius = 16
        halo.shadowOpacity = 1
        root.addSublayer(halo)

        // The glow: a brighter orange close to the line, on a quicker, uneven beat.
        let glow = CAShapeLayer()
        glow.fillColor = nil
        glow.strokeColor = ember
        glow.lineWidth = 2
        glow.shadowColor = NSColor(srgbRed: 1.0, green: 0.45, blue: 0.0, alpha: 1).cgColor
        glow.shadowOffset = .zero
        glow.shadowRadius = 9
        glow.shadowOpacity = 1
        root.addSublayer(glow)

        // The lava: deep red to yellow-orange, turning slowly under a hairline mask.
        let lava = CAGradientLayer()
        lava.type = .conic
        lava.startPoint = CGPoint(x: 0.5, y: 0.5)
        lava.endPoint = CGPoint(x: 0.5, y: 0)
        lava.colors = [NSColor(srgbRed: 0.55, green: 0.06, blue: 0.0, alpha: 1), NSColor(srgbRed: 1.0, green: 0.45, blue: 0.0, alpha: 1),
                       NSColor(srgbRed: 1.0, green: 0.78, blue: 0.30, alpha: 1), NSColor(srgbRed: 0.95, green: 0.30, blue: 0.0, alpha: 1),
                       NSColor(srgbRed: 0.55, green: 0.06, blue: 0.0, alpha: 1), NSColor(srgbRed: 1.0, green: 0.55, blue: 0.08, alpha: 1),
                       NSColor(srgbRed: 0.55, green: 0.06, blue: 0.0, alpha: 1)].map(\.cgColor)
        let maskHolder = CALayer()
        let lavaMask = CAShapeLayer()
        lavaMask.fillColor = nil
        lavaMask.strokeColor = NSColor.white.cgColor
        lavaMask.lineWidth = 2
        maskHolder.addSublayer(lava)
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

        host.addSublayer(root)

        if !still {
            // Beats of different lengths that never line up, so the heat never repeats the same way.
            func waver(_ layer: CALayer, _ key: String, _ values: [CGFloat], _ duration: CFTimeInterval) {
                let a = CAKeyframeAnimation(keyPath: key)
                a.values = values; a.duration = duration; a.repeatCount = .infinity
                a.calculationMode = .cubic
                layer.add(a, forKey: key)
            }
            waver(halo, "shadowRadius", [12, 22, 15, 26, 13, 19, 12], 5.3)
            waver(halo, "opacity", [0.75, 1, 0.8, 0.95, 0.7, 1, 0.75], 3.7)
            waver(halo, "lineWidth", [2.5, 4.5, 3, 5, 2.5], 4.1)
            waver(glow, "shadowRadius", [7, 12, 8, 14, 9, 11, 7], 2.3)
            waver(glow, "shadowOpacity", [1, 0.7, 1, 0.8, 0.95, 0.65, 1], 1.7)
            waver(glow, "lineWidth", [1.6, 2.6, 1.8, 2.4, 1.6], 2.9)
            let turn = CABasicAnimation(keyPath: "transform.rotation.z")
            turn.fromValue = 0; turn.toValue = 2 * Double.pi
            turn.duration = 14; turn.repeatCount = .infinity
            lava.add(turn, forKey: "turn")
            let run = CABasicAnimation(keyPath: "lineDashPhase")
            run.fromValue = 0; run.toValue = -135
            run.duration = 4.5; run.repeatCount = .infinity
            sparks.add(run, forKey: "run")
        }
        self.root = root; self.glow = glow; self.halo = halo; self.lavaMask = lavaMask; self.maskHolder = maskHolder; self.lava = lava; self.sparks = sparks
    }
}
