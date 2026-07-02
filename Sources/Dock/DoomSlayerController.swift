import AppKit
import QuartzCore

/// Animated "Doom Slayer" that patrols the lower edge of the dock — the DOOM-themed
/// counterpart to the Pac-Man border (theme `dock.borderStyle == "doomslayer"`).
///
/// He runs, stops to fire (the weapon cycles each lap), occasionally gets fragged
/// (gib burst → corpse → blood splatter), then loops. The DOOM logo sits in the
/// bottom-right corner. Ported from the reference web component (Doom Dock.dc.html):
/// sprite atlas is 13 cells of 68×56 (`slayer-atlas.png`, incl. Chainsaw + BFG), death is
/// 2 cells of 68×56 (`slayer-death.png`), the fall sequence is 6 cells (`slayer-die.png`),
/// plus `rocket-proj.png`, `bfg-proj.png` and `doom-logo.png`.
///
/// Like the Pac-Man border this animates exclusively via CALayers driven by a timer,
/// so the dock's backing is never re-rasterized.
final class DoomSlayerController {

    // MARK: Atlas constants (from the reference component)
    private let CW: CGFloat = 68, CH: CGFloat = 56
    private let atlasCols = 13   // 11 original + Chainsaw (cell 11) + BFG (cell 12)
    private let walkCells = [0, 1, 2, 3]
    private let baseline: CGFloat = 52
    private let cellBot: [CGFloat] = [52, 52, 52, 52, 50, 50, 43, 52, 52, 52, 43, 51, 52]

    private struct Weapon { let label: String; let cell: Int; let blink: Double; let dur: Double; let recoil: CGFloat; let glow: NSColor }
    private let weapons: [Weapon] = [
        Weapon(label: "Shotgun",  cell: 5,  blink: 0.09, dur: 0.72, recoil: 1, glow: NSColor(red: 1.0,  green: 0.71, blue: 0.16, alpha: 0.95)),
        Weapon(label: "Chaingun", cell: 6,  blink: 0.05, dur: 1.05, recoil: 1, glow: NSColor(red: 1.0,  green: 0.71, blue: 0.16, alpha: 0.95)),
        Weapon(label: "Rocket",   cell: 9,  blink: 0.13, dur: 0.66, recoil: 2, glow: NSColor(red: 1.0,  green: 0.43, blue: 0.16, alpha: 0.98)),
        Weapon(label: "Plasma",   cell: 10, blink: 0.05, dur: 0.92, recoil: 1, glow: NSColor(red: 0.37, green: 0.61, blue: 1.0,  alpha: 0.98)),
        // Chainsaw: melee — no muzzle flash (clear glow); the blink drives a small revving jitter.
        Weapon(label: "Chainsaw", cell: 11, blink: 0.05, dur: 0.95, recoil: 1, glow: NSColor.clear),
        Weapon(label: "BFG",      cell: 12, blink: 0.12, dur: 0.95, recoil: 2, glow: NSColor(red: 0.42, green: 1.0, blue: 0.35, alpha: 0.98)),
    ]

    // MARK: Sliced art (loaded once per theme)
    private var mainCells: [CGImage] = []      // 13 cells
    private var deathCells: [CGImage] = []     // 2 cells (random gib-frag)
    private var dieCells: [CGImage] = []       // 6 cells (fall sequence: hit → collapse → corpse)
    private var rocketImage: CGImage?
    private var bfgImage: CGImage?
    private var splatImage: CGImage?
    private var loadedFromURL: URL?

    // MARK: Layers
    private weak var hostLayer: CALayer?
    private weak var hostView: NSView?     // for converting the mouse location (hover-to-kill)
    private let spriteLayer = CALayer()
    private let splatLayer = CALayer()
    private let rocketLayer = CALayer()
    private let soulLayer = CALayer()
    private var layersInstalled = false

    // MARK: Geometry (recomputed when the bar rect / scale changes)
    private var configuredRect: NSRect = .zero
    private var configuredScale: CGFloat = 0
    private var deckLeft: CGFloat = 0
    private var trackWidth: CGFloat = 880
    private var feetBottomY: CGFloat = 0   // y (y-up) where the slayer's feet rest
    private var artScale: CGFloat = 0.75

    // MARK: Animation state (ported from the reference tick())
    private enum Mode { case walk, shoot, death, killed }
    private var mode: Mode = .walk
    private var x: CGFloat = -60
    private var walkPhase = 0
    private var walkT: Double = 0
    private var modeT: Double = 0
    private var blinkT: Double = 0
    private var blink = false
    private var deathPhase = 0
    private var weaponIdx = 0
    private var shootWeapon: Weapon
    private var untilEvent: Double = 1.4
    private var splatX: CGFloat = -300
    // rocket
    private var rocketLive = false
    private var rocketX: CGFloat = -400
    private var rocketDir: CGFloat = 1
    private var rocketFired = false
    private var projIsBFG = false   // in-flight projectile is the green BFG orb

    // Lost Soul: a flying skull spawns ahead of the slayer, he fires, it explodes.
    private enum SoulMode { case gone, flying, dying }
    private var soulMode: SoulMode = .gone
    private var soulX: CGFloat = 0          // deck-space x (like the slayer's x)
    private var soulYOff: CGFloat = 0       // height above the feet baseline
    private var soulLife: Double = 0
    private var soulFlyT: Double = 0
    private var soulFrame = 0
    private var soulShot = false
    private var soulDeathPhase = 0
    private var soulDeathT: Double = 0
    private var soulCooldown: Double = 4.0
    private var soulFly: [CGImage] = []     // 2 flicker frames
    private var soulDeath: [CGImage] = []   // 3 explosion frames
    private var killFrame: Int = -1         // >=0 → drawing a hover-kill frame (slayer-die.png)
    private var killT: Double = 0

    private var timer: Timer?
    private var lastTime: CFTimeInterval = 0
    private var rng = SystemRandomNumberGenerator()

    init() { shootWeapon = weapons[0] }

    deinit { timer?.invalidate() }

    // MARK: - Public API (called from DockView)

    /// (Re)configure for the current bar rect, ensuring layers + timer. Geometry is only
    /// rebuilt when the rect or scale changed; otherwise the timer keeps animating.
    func update(host: CALayer, view: NSView, barRect: NSRect, scale: CGFloat) {
        loadArtIfNeeded()
        guard !mainCells.isEmpty else { return }
        hostView = view
        if hostLayer !== host { installLayers(in: host) }
        if !barRect.equalTo(configuredRect) || scale != configuredScale {
            configureGeometry(barRect: barRect, scale: scale)
        }
        startTimerIfVisible()
    }

    /// Remove everything (theme switched away from doomslayer).
    func teardown() {
        timer?.invalidate(); timer = nil
        spriteLayer.removeFromSuperlayer()
        splatLayer.removeFromSuperlayer()
        rocketLayer.removeFromSuperlayer()
        soulLayer.removeFromSuperlayer()
        layersInstalled = false
        hostLayer = nil
        configuredRect = .zero
    }

    /// Pause/resume from the window-occlusion observer.
    func refreshAnimationState(visible: Bool) {
        if visible { startTimerIfVisible() }
        else { timer?.invalidate(); timer = nil }
    }

    // MARK: - Settings (read live, like the reference props)
    private var optScale: CGFloat { CGFloat(AppSettings.shared.slayerScale) }
    private var optSpeed: CGFloat { CGFloat(AppSettings.shared.slayerRunSpeed) }
    private var optDir: CGFloat { AppSettings.shared.slayerDirection == "Left" ? -1 : 1 }
    private var optCombat: String { AppSettings.shared.slayerCombat }
    private var optWeapon: String { AppSettings.shared.slayerWeapon }

    private func combatCfg() -> (gap: ClosedRange<Double>, pShoot: Double, pHit: Double, pFrag: Double) {
        switch optCombat {
        case "Calm":    return (3.0...3.6, 0.46, 0.07, 0.05)
        case "Intense": return (0.7...1.1, 0.58, 0.16, 0.18)
        default:        return (1.4...1.7, 0.54, 0.12, 0.10)
        }
    }

    private func selectWeapon() -> Weapon {
        if optWeapon == "Auto-cycle" {
            let w = weapons[weaponIdx % weapons.count]
            weaponIdx += 1            // advance per shot so Auto-cycle visibly rotates weapons
            return w
        }
        return weapons.first { $0.label == optWeapon } ?? weapons[0]
    }
    private func nextLap() { /* weapon rotation now driven per-shot in selectWeapon() */ }
    private func newGap() { let c = combatCfg(); untilEvent = Double.random(in: c.gap, using: &rng) }

    // MARK: - Lost Soul (flies in, slayer shoots it, it explodes)

    private func soulNextCooldown() -> Double {
        switch optCombat {
        case "Calm":    return Double.random(in: 4.5...7, using: &rng)
        case "Intense": return Double.random(in: 1.2...2.5, using: &rng)
        default:        return Double.random(in: 2.5...4.5, using: &rng)
        }
    }

    private func tickSoul(dt: Double, faceRight: Bool, spriteW: CGFloat) {
        guard !soulFly.isEmpty, !soulDeath.isEmpty else { return }
        switch soulMode {
        case .gone:
            soulCooldown -= dt
            // Spawn mid-track while walking, with room ahead in the facing direction.
            if soulCooldown <= 0, mode == .walk, x > trackWidth * 0.12, x < trackWidth * 0.88 {
                let dir: CGFloat = faceRight ? 1 : -1
                soulX = x + spriteW / 2 + dir * spriteW * 1.4
                soulYOff = 34 * artScale          // up near the slayer's head
                soulLife = 0; soulFlyT = 0; soulFrame = 0; soulShot = false
                soulMode = .flying
            }
        case .flying:
            soulLife += dt; soulFlyT += dt
            if soulFlyT > 0.1 { soulFlyT = 0; soulFrame = (soulFrame + 1) % soulFly.count }
            // The slayer opens fire shortly after the soul appears.
            if !soulShot, soulLife > 0.45, mode == .walk {
                mode = .shoot; shootWeapon = selectWeapon()
                modeT = max(0.5, shootWeapon.dur); blinkT = 0; blink = true; rocketFired = false
                soulShot = true
            }
            // Muzzle flash connects → the soul bursts.
            if soulShot, mode == .shoot, blink, soulLife > 0.5 {
                soulMode = .dying; soulDeathPhase = 0; soulDeathT = 0
            }
            // Safety: slayer knocked out of the shot (pain/death) → drop the soul.
            if soulLife > 3.0, mode != .shoot, soulShot {
                soulMode = .gone; soulCooldown = soulNextCooldown()
            }
        case .dying:
            soulDeathT += dt
            if soulDeathPhase == 0, soulDeathT > 0.12 { soulDeathPhase = 1; soulDeathT = 0 }
            else if soulDeathPhase == 1, soulDeathT > 0.14 { soulDeathPhase = 2; soulDeathT = 0 }
            else if soulDeathPhase == 2, soulDeathT > 0.20 {
                soulMode = .gone; soulCooldown = soulNextCooldown()
            }
        }
    }

    private func renderSoul(scale: CGFloat) {
        switch soulMode {
        case .gone:
            soulLayer.opacity = 0
        case .flying:
            let img = soulFly[min(soulFrame, soulFly.count - 1)]
            let h = 22 * scale
            let w = h * CGFloat(img.width) / CGFloat(max(1, img.height))
            soulLayer.contents = img
            soulLayer.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            let bob = CGFloat(sin(soulLife * 7)) * 2 * scale
            soulLayer.position = CGPoint(x: deckLeft + soulX, y: feetBottomY + soulYOff + bob)
            soulLayer.opacity = 1
        case .dying:
            let img = soulDeath[min(soulDeathPhase, soulDeath.count - 1)]
            let h = (24 + CGFloat(soulDeathPhase) * 7) * scale   // explosion grows
            let w = h * CGFloat(img.width) / CGFloat(max(1, img.height))
            soulLayer.contents = img
            soulLayer.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            soulLayer.position = CGPoint(x: deckLeft + soulX, y: feetBottomY + soulYOff)
            soulLayer.opacity = soulDeathPhase == 2 ? 0.85 : 1
        }
    }

    // MARK: - Layer setup

    private func installLayers(in host: CALayer) {
        hostLayer = host
        for (l, z) in [(splatLayer, 3.0), (soulLayer, 4.2), (rocketLayer, 4.5), (spriteLayer, 5.0)] {
            l.removeFromSuperlayer()
            l.actions = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull(),
                         "transform": NSNull(), "opacity": NSNull(), "hidden": NSNull(),
                         "shadowOpacity": NSNull(), "shadowOffset": NSNull(), "shadowColor": NSNull()]
            l.zPosition = z
            l.magnificationFilter = .nearest
            l.minificationFilter = .nearest
            l.contentsScale = host.contentsScale
            host.addSublayer(l)
        }
        spriteLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        soulLayer.opacity = 0
        splatLayer.contents = splatImage
        splatLayer.opacity = 0
        rocketLayer.contents = rocketImage
        rocketLayer.opacity = 0
        layersInstalled = true
    }

    private func configureGeometry(barRect: NSRect, scale: CGFloat) {
        configuredRect = barRect
        configuredScale = scale
        artScale = optScale * scale
        let margin: CGFloat = 8 * scale
        deckLeft = barRect.minX + margin
        trackWidth = max(120, barRect.width - margin * 2)
        feetBottomY = barRect.minY + 12 * scale   // raised so the slayer band sits a bit higher
        // (DOOM logo is placed every tick in render() at a FIXED size.)

        // Reset the run so a fresh configure starts clean.
        mode = .walk; x = -CW * artScale - 30 * scale; walkPhase = 0; walkT = 0
        modeT = 0; blinkT = 0; blink = false; deathPhase = 0
        rocketLive = false; rocketFired = false
        soulMode = .gone; soulShot = false; soulCooldown = soulNextCooldown()
        newGap()
    }

    // MARK: - Timer / tick

    private func startTimerIfVisible() {
        guard timer == nil, layersInstalled, !mainCells.isEmpty else { return }
        lastTime = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.05, now - lastTime)
        lastTime = now

        artScale = optScale * configuredScale   // live: slayer "Size" setting takes effect at once
        let scale = artScale
        let dir = optDir
        let faceRight = dir > 0
        let spriteW = CW * scale
        let track = trackWidth

        var cell = 0
        var flip = false
        var dy: CGFloat = 0
        var glow = false
        var opacity: CGFloat = 1
        var useDeath = false
        var deathCell = 0

        let dscale = configuredScale          // position-space scale (dock)
        let m: CGFloat = 30 * dscale          // off-edge margin

        pollMouseForKill()                    // mouse over the slayer → frag him

        switch mode {
        case .walk:
            x += dir * optSpeed * dscale * CGFloat(dt)   // runSpeed is px/s in the dock space
            walkT += dt
            if walkT > 0.12 { walkT = 0; walkPhase = (walkPhase + 1) % 4 }
            cell = walkCells[walkPhase]
            flip = faceRight
            if dir > 0 && x > track + m { x = -spriteW - m; nextLap() }
            else if dir < 0 && x < -spriteW - m { x = track + m; nextLap() }
            untilEvent -= dt
            if untilEvent <= 0 {
                let c = combatCfg(); let r = Double.random(in: 0...1, using: &rng)
                let allowFrag = (x > track * 0.2 && x < track * 0.78)
                if r < c.pShoot {
                    mode = .shoot; shootWeapon = selectWeapon()
                    modeT = shootWeapon.dur; blinkT = 0; blink = true; rocketFired = false
                } else if r < c.pShoot + c.pHit {
                    // Hit: the full DOOM fall sequence (same as hover-frag) — no tinted flinch.
                    mode = .killed; killFrame = 0; killT = 0
                } else if r < c.pShoot + c.pHit + c.pFrag && allowFrag {
                    mode = .death; deathPhase = 0; modeT = 0.5; blinkT = 0; blink = true; splatX = x
                } else { newGap() }
            }

        case .shoot:
            let wpn = shootWeapon
            flip = faceRight
            modeT -= dt; blinkT += dt
            if blinkT > wpn.blink { blinkT = 0; blink.toggle() }
            cell = wpn.cell
            dy = blink ? wpn.recoil * scale : 0
            glow = blink
            if (wpn.label == "Rocket" || wpn.label == "BFG") && !rocketFired && modeT < wpn.dur - 0.12 {
                rocketFired = true; rocketLive = true; rocketDir = dir
                projIsBFG = wpn.label == "BFG"
                rocketX = faceRight ? (x + spriteW * 0.90) : (x + spriteW * 0.10)
            }
            if modeT <= 0 { mode = .walk; newGap() }

        case .death:
            useDeath = true; flip = false
            modeT -= dt
            if deathPhase == 0 {
                deathCell = 0
                blinkT += dt; if blinkT > 0.04 { blinkT = 0; blink.toggle() }
                dy = blink ? -1 * scale : 0
                if modeT <= 0 { deathPhase = 1; modeT = 3.0 }
            } else {
                deathCell = 1
                if modeT < 0.6 { opacity = max(0, CGFloat(modeT / 0.6)) }
                if modeT <= 0 {
                    mode = .walk
                    x = dir > 0 ? (-spriteW - m) : (track + m)
                    walkPhase = 0; nextLap(); newGap()
                }
            }

        case .killed:
            // The full DOOM fall sequence (hit → bend → kneel → collapse → corpse), then respawn.
            // Used for both the hover-frag and the random "hit" event; faces the travel direction.
            flip = faceRight
            let lastFrame = dieCells.count - 1
            if dieCells.count >= 2 {
                if killFrame < lastFrame {
                    killT += dt
                    killFrame = min(lastFrame, Int(killT / 0.11))   // step through the fall frames
                    if killFrame >= lastFrame { modeT = 1.8 }       // corpse landed → start the hold
                } else {
                    modeT -= dt                              // corpse holds, then fades out
                    if modeT < 0.6 { opacity = max(0, CGFloat(modeT / 0.6)) }
                    if modeT <= 0 {
                        mode = .walk; killFrame = -1
                        x = dir > 0 ? (-spriteW - m) : (track + m)
                        walkPhase = 0; nextLap(); newGap()
                    }
                }
            } else {
                mode = .walk; killFrame = -1               // no die atlas → just respawn
            }
        }

        // Projectile (rocket / BFG orb) travels independently; the orb flies heavier & slower.
        if rocketLive {
            rocketX += rocketDir * (projIsBFG ? 220 : 360) * dscale * CGFloat(dt)
            if rocketX > track + 50 * dscale || rocketX < -50 * dscale { rocketLive = false }
        }

        // Lost Soul (may command the slayer to shoot — run after the slayer's own state).
        tickSoul(dt: dt, faceRight: faceRight, spriteW: spriteW)

        render(cell: cell, useDeath: useDeath, deathCell: deathCell, flip: flip,
               dy: dy, glow: glow, opacity: opacity, scale: scale, spriteW: spriteW)
    }

    // MARK: - Hover-to-kill

    /// If the mouse is currently over the (alive) slayer, frag him: a short hit, then a corpse.
    private func pollMouseForKill() {
        guard mode == .walk || mode == .shoot,
              let v = hostView, let win = v.window else { return }
        let screenPt = NSEvent.mouseLocation
        let winPt = win.convertPoint(fromScreen: screenPt)
        let viewPt = v.convert(winPt, from: nil)
        // sprite frame is in host-layer == view coordinates; a little padding for easier hits.
        guard spriteLayer.frame.insetBy(dx: -3, dy: -3).contains(viewPt) else { return }
        mode = .killed; killFrame = 0; killT = 0
        soulMode = .gone; soulCooldown = soulNextCooldown()   // cancel any in-flight soul
    }

    // MARK: - Render

    private func render(cell: Int, useDeath: Bool, deathCell: Int, flip: Bool,
                        dy: CGFloat, glow: Bool, opacity: CGFloat,
                        scale: CGFloat, spriteW: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let spriteH = CH * scale
        // Pick the frame image.
        let img: CGImage?
        let bottomAligned = useDeath || killFrame >= 0
        if killFrame >= 0 {
            img = dieCells.indices.contains(killFrame) ? dieCells[killFrame] : nil
        } else if useDeath {
            img = deathCells.indices.contains(deathCell) ? deathCells[deathCell] : nil
        } else {
            img = mainCells.indices.contains(cell) ? mainCells[cell] : nil
        }
        spriteLayer.contents = img

        // Ground each frame on its own feet (web `fa`); +dy/+fa move DOWN → subtract in y-up.
        let fa = bottomAligned ? 0 : (baseline - (cellBot.indices.contains(cell) ? cellBot[cell] : baseline)) * scale
        let originX = deckLeft + x
        let originY = feetBottomY - (dy + fa)
        spriteLayer.bounds = CGRect(x: 0, y: 0, width: spriteW, height: spriteH)
        spriteLayer.position = CGPoint(x: originX + spriteW / 2, y: originY + spriteH / 2)
        spriteLayer.transform = CATransform3DMakeScale(flip ? -1 : 1, 1, 1)
        spriteLayer.opacity = Float(opacity)

        // Muzzle glow / drop shadow.
        if glow {
            spriteLayer.shadowColor = shootWeapon.glow.cgColor
            spriteLayer.shadowOpacity = 0.95
            spriteLayer.shadowRadius = 5
            spriteLayer.shadowOffset = CGSize(width: flip ? 3 : -3, height: 7)   // toward the muzzle (y-up)
        } else {
            spriteLayer.shadowColor = NSColor.black.cgColor
            spriteLayer.shadowOpacity = 0.55
            spriteLayer.shadowRadius = 2
            spriteLayer.shadowOffset = CGSize(width: 0, height: -2)
        }

        // Blood splatter decal.
        if useDeath {
            let k = scale / 0.75
            if let s = splatImage {
                let w = CGFloat(s.width) * k, h = CGFloat(s.height) * k
                splatLayer.bounds = CGRect(x: 0, y: 0, width: w, height: h)
                let left = (deckLeft + splatX) + (spriteW / 2) - 27 * k
                splatLayer.position = CGPoint(x: left + w / 2, y: feetBottomY + h / 2)
            }
            splatLayer.opacity = Float(deathPhase == 0 ? 1 : opacity)
        } else {
            splatLayer.opacity = 0
        }

        // Projectile (rocket or BFG orb).
        if rocketLive, let r = (projIsBFG ? (bfgImage ?? rocketImage) : rocketImage) {
            let pk: CGFloat = projIsBFG ? 0.72 : 1   // the orb art is chunky — trim it a bit
            let pw = CGFloat(r.width) * scale * pk, ph = CGFloat(r.height) * scale * pk
            rocketLayer.contents = r
            rocketLayer.bounds = CGRect(x: 0, y: 0, width: pw, height: ph)
            let by = feetBottomY + (25 * scale + 1)
            rocketLayer.position = CGPoint(x: deckLeft + rocketX + pw / 2, y: by + ph / 2)
            rocketLayer.transform = CATransform3DMakeScale(rocketDir > 0 ? -1 : 1, 1, 1)
            rocketLayer.opacity = 1
        } else {
            rocketLayer.opacity = 0
        }

        // (The DOOM logo is a clickable dock tile now — see DockView.addDoomLauncherItem.)

        renderSoul(scale: scale)

        CATransaction.commit()
    }

    // MARK: - Art loading

    private func loadArtIfNeeded() {
        guard let url = ThemeManager.shared.activeTheme?.url else { return }
        if loadedFromURL == url, !mainCells.isEmpty { return }
        loadedFromURL = url
        mainCells = []; deathCells = []
        rocketImage = nil; bfgImage = nil; splatImage = nil

        func cg(_ name: String) -> CGImage? {
            guard let img = NSImage(contentsOf: url.appendingPathComponent(name)) else { return nil }
            var rect = CGRect(origin: .zero, size: img.size)
            return img.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }

        if let atlas = cg("slayer-atlas.png") {
            let cellW = atlas.width / atlasCols, cellH = atlas.height
            for i in 0..<atlasCols {
                if let c = atlas.cropping(to: CGRect(x: i * cellW, y: 0, width: cellW, height: cellH)) {
                    mainCells.append(c)
                }
            }
        }
        if let death = cg("slayer-death.png") {
            let cellW = death.width / 2, cellH = death.height
            for i in 0..<2 {
                if let c = death.cropping(to: CGRect(x: i * cellW, y: 0, width: cellW, height: cellH)) {
                    deathCells.append(c)
                }
            }
        }
        dieCells = []
        if let die = cg("slayer-die.png") {
            let cols = max(1, Int((CGFloat(die.width) / CW).rounded()))
            let cellW = die.width / cols, cellH = die.height
            for i in 0..<cols {
                if let c = die.cropping(to: CGRect(x: i * cellW, y: 0, width: cellW, height: cellH)) {
                    dieCells.append(c)
                }
            }
        }
        rocketImage = cg("rocket-proj.png")
        bfgImage = cg("bfg-proj.png")
        splatImage = makeSplatImage()
        soulFly = ["lostsoul-fly0.png", "lostsoul-fly1.png"].compactMap(cg)
        soulDeath = ["lostsoul-death0.png", "lostsoul-death1.png", "lostsoul-death2.png"].compactMap(cg)
    }

    /// Blood splatter drawn from concentric red dots (matches the reference radial-gradient decal).
    private func makeSplatImage() -> CGImage? {
        let w = 54, h = 22
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        func dot(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ c: NSColor) {
            ctx.setFillColor(c.cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        }
        let W = CGFloat(w), H = CGFloat(h)
        dot(W * 0.50, H * 0.06, 9, NSColor(red: 0.48, green: 0.05, blue: 0.05, alpha: 1))
        dot(W * 0.27, H * 0.20, 3, NSColor(red: 0.60, green: 0.07, blue: 0.07, alpha: 1))
        dot(W * 0.73, H * 0.22, 3, NSColor(red: 0.60, green: 0.07, blue: 0.07, alpha: 1))
        dot(W * 0.13, H * 0.34, 2, NSColor(red: 0.77, green: 0.09, blue: 0.09, alpha: 1))
        dot(W * 0.89, H * 0.38, 2, NSColor(red: 0.77, green: 0.09, blue: 0.09, alpha: 1))
        dot(W * 0.62, H * 0.44, 2, NSColor(red: 0.72, green: 0.08, blue: 0.08, alpha: 1))
        dot(W * 0.38, H * 0.50, 2, NSColor(red: 0.72, green: 0.08, blue: 0.08, alpha: 1))
        return ctx.makeImage()
    }
}
