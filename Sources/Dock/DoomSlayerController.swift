import AppKit
import QuartzCore

/// Animated "Doom Slayer" that patrols the lower edge of the dock — the DOOM-themed
/// counterpart to the Pac-Man border (theme `dock.borderStyle == "doomslayer"`).
///
/// He runs, stops to fire (the weapon cycles each lap), occasionally gets fragged
/// (gib burst → corpse → blood splatter), then loops. The DOOM logo sits in the
/// bottom-right corner. Ported from the reference web component (Doom Dock.dc.html):
/// sprite atlas is 19 cells of 68×56 (`slayer-atlas.png`: 6-frame run cycle, aim/fire pair
/// per weapon incl. Chainsaw + BFG), death is 2 cells of 68×56 (`slayer-death.png`), the
/// fall sequence is 6 cells (`slayer-die.png`), plus `rocket-proj.png`, `bfg-proj.png`,
/// `plasma-proj.png`, `bfg-boom.png` and `doom-logo.png`.
///
/// Like the Pac-Man border this animates exclusively via CALayers driven by a timer,
/// so the dock's backing is never re-rasterized.
final class DoomSlayerController {

    // MARK: Atlas constants (from the reference component)
    private let CW: CGFloat = 68, CH: CGFloat = 56
    // Cells: 0-3 walk cycle, 4/5 shotgun aim/fire, 15/6 chaingun, 16/9 rocket, 17/10 plasma,
    // 11 chainsaw, 12/18 BFG aim/fire. (7/8 legacy pain frames + 13/14 = unused/blank —
    // the sheet's extra "walk" frames turned out to be idle poses, not part of the cycle.)
    private let atlasCols = 19
    private let walkCells = [0, 1, 2, 3]
    private let baseline: CGFloat = 52
    private let cellBot: [CGFloat] = [52, 52, 52, 52, 52, 52, 52, 52, 52, 52, 52, 51, 52, 52, 52, 52, 52, 52, 52]

    // aimCell/cell are a matched pair from the sheet: ready pose ↔ firing frame with the
    // real muzzle flash baked in; the blink alternates them (authentic staccato).
    private struct Weapon { let label: String; let aimCell: Int; let cell: Int; let blink: Double; let dur: Double; let recoil: CGFloat; let glow: NSColor }
    private let weapons: [Weapon] = [
        Weapon(label: "Shotgun",  aimCell: 4,  cell: 5,  blink: 0.09, dur: 0.72, recoil: 1, glow: NSColor(red: 1.0,  green: 0.71, blue: 0.16, alpha: 0.95)),
        Weapon(label: "Chaingun", aimCell: 15, cell: 6,  blink: 0.05, dur: 1.05, recoil: 1, glow: NSColor(red: 1.0,  green: 0.71, blue: 0.16, alpha: 0.95)),
        Weapon(label: "Rocket",   aimCell: 16, cell: 9,  blink: 0.13, dur: 0.66, recoil: 2, glow: NSColor(red: 1.0,  green: 0.43, blue: 0.16, alpha: 0.98)),
        Weapon(label: "Plasma",   aimCell: 17, cell: 10, blink: 0.05, dur: 0.92, recoil: 1, glow: NSColor(red: 0.37, green: 0.61, blue: 1.0,  alpha: 0.98)),
        // Chainsaw: melee — no muzzle flash (clear glow); the blink drives a small revving jitter.
        Weapon(label: "Chainsaw", aimCell: 11, cell: 11, blink: 0.05, dur: 0.95, recoil: 1, glow: NSColor.clear),
        Weapon(label: "BFG",      aimCell: 12, cell: 18, blink: 0.12, dur: 0.95, recoil: 2, glow: NSColor(red: 0.42, green: 1.0, blue: 0.35, alpha: 0.98)),
    ]

    // MARK: Sliced art (loaded once per theme)
    private var mainCells: [CGImage] = []      // 13 cells
    private var deathCells: [CGImage] = []     // 2 cells (random gib-frag)
    private var dieCells: [CGImage] = []       // 6 cells (fall sequence: hit → collapse → corpse)
    private var rocketImage: CGImage?
    private var bfgImage: CGImage?
    private var plasmaImage: CGImage?
    private var bfgBoom: [CGImage] = []    // 2 cells (green blast → streak); rocket reuses soulDeath
    private var splatImage: CGImage?
    private var loadedFromURL: URL?

    // MARK: Layers
    private weak var hostLayer: CALayer?
    private weak var hostView: NSView?     // for converting the mouse location (hover-to-kill)
    private let spriteLayer = CALayer()
    private let splatLayer = CALayer()
    private let rocketLayer = CALayer()
    private let soulLayer = CALayer()
    private let boomLayer = CALayer()
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
    private enum Projectile { case rocket, bfg, plasma }
    private var projKind: Projectile = .rocket
    private var projStartX: CGFloat = 0   // plasma bolts fizzle after a fixed range
    // Impact explosion when a rocket/BFG orb reaches the track edge.
    private var boomLive = false
    private var boomT: Double = 0
    private var boomX: CGFloat = 0
    private var boomBFG = false

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
    private var soulSeenThisLap = false     // → nextLap forces a spawn if a lap stayed quiet
    private var diedThisLap = false         // every lap ends with one death (lethal soul)
    private var lethalSoul = false          // this soul gets him: the slayer holds his fire
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
        boomLayer.removeFromSuperlayer()
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

    // Deaths are never random anymore — only the Lost Soul catching him or the mouse
    // hover-frag kill the slayer. Random events are just "stop and shoot".
    private func combatCfg() -> (gap: ClosedRange<Double>, pShoot: Double) {
        switch optCombat {
        case "Calm":    return (3.0...3.6, 0.46)
        case "Intense": return (0.7...1.1, 0.58)
        default:        return (1.4...1.7, 0.54)
        }
    }

    private func selectWeapon() -> Weapon {
        if optWeapon == "Auto-cycle" {
            return weapons[weaponIdx % weapons.count]   // rotates per LAP (nextLap), not per shot
        }
        return weapons.first { $0.label == optWeapon } ?? weapons[0]
    }
    private func nextLap() {
        weaponIdx += 1   // Auto-cycle: a fresh weapon each lap
        // Guarantee at least one demon encounter per lap: if none spawned last lap,
        // send one in right away.
        if !soulSeenThisLap, soulMode == .gone { soulCooldown = min(soulCooldown, 0.3) }
        soulSeenThisLap = false
        diedThisLap = false
    }
    private func newGap() { let c = combatCfg(); untilEvent = Double.random(in: c.gap, using: &rng) }

    // MARK: - Lost Soul (flies in, slayer shoots it, it explodes)

    private func soulNextCooldown() -> Double {
        // Demons ARE the action now (the slayer only fires at them), so the combat
        // setting directly scales how often they come.
        switch optCombat {
        case "Calm":    return Double.random(in: 2.2...4.0, using: &rng)
        case "Intense": return Double.random(in: 0.5...1.2, using: &rng)
        default:        return Double.random(in: 1.2...2.2, using: &rng)
        }
    }

    private func tickSoul(dt: Double, faceRight: Bool, spriteW: CGFloat) {
        guard !soulFly.isEmpty, !soulDeath.isEmpty else { return }
        switch soulMode {
        case .gone:
            soulCooldown -= dt
            // Every lap ends with one death: past ~60% of the lap without dying,
            // force a spawn — and that soul is lethal (he won't fire at it).
            let pastLapMiddle = faceRight ? x > trackWidth * 0.6 : x < trackWidth * 0.4
            if !diedThisLap, pastLapMiddle { soulCooldown = min(soulCooldown, 0.05) }
            // Spawn mid-track while walking — from the front OR from behind (50/50).
            if soulCooldown <= 0, mode == .walk, x > trackWidth * 0.12, x < trackWidth * 0.88 {
                lethalSoul = !diedThisLap && pastLapMiddle
                let ahead: CGFloat = faceRight ? 1 : -1
                // The lethal soul always comes head-on (he can't outwalk it); others 50/50.
                let side = lethalSoul ? ahead : (Bool.random() ? ahead : -ahead)
                soulX = min(max(x + spriteW / 2 + side * spriteW * 1.4, 20), trackWidth - 20)
                soulYOff = 34 * artScale          // up near the slayer's head
                soulLife = 0; soulFlyT = 0; soulFrame = 0; soulShot = false
                soulMode = .flying
                soulSeenThisLap = true
            }
        case .flying:
            soulLife += dt; soulFlyT += dt
            if soulFlyT > 0.1 { soulFlyT = 0; soulFrame = (soulFrame + 1) % soulFly.count }
            // Lost Souls charge: it darts toward the slayer. If the shot comes too late
            // (slayer busy with another animation), it reaches him and frags him.
            let slayerMid = x + spriteW / 2
            let dx = slayerMid - soulX
            soulX += (dx > 0 ? 1 : -1) * 65 * artScale * CGFloat(dt)
            if abs(dx) < 14 * artScale, mode == .walk || mode == .shoot {
                mode = .killed; killFrame = 0; killT = 0
                diedThisLap = true; lethalSoul = false
                soulMode = .gone; soulCooldown = soulNextCooldown()
                return
            }
            // The slayer opens fire shortly after the soul appears — unless this is the
            // lap's lethal soul (he holds his fire and it gets him).
            if !soulShot, !lethalSoul, soulLife > 0.45, mode == .walk {
                mode = .shoot; shootWeapon = selectWeapon()
                modeT = max(0.5, shootWeapon.dur); rocketFired = false
                // Demon behind him: he turns first, THEN opens fire a beat later.
                let behind = (soulX > slayerMid) != faceRight
                blink = false
                blinkT = behind ? -0.22 : 0
                if !behind { blink = true }
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
        for (l, z) in [(splatLayer, 3.0), (soulLayer, 4.2), (rocketLayer, 4.5), (boomLayer, 4.6), (spriteLayer, 5.0)] {
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
        boomLayer.opacity = 0
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
        killFrame = -1; killT = 0   // a reconfigure mid-fall must not leave the corpse frame stuck
        rocketLive = false; rocketFired = false; boomLive = false
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
            if walkT > 0.12 { walkT = 0; walkPhase = (walkPhase + 1) % walkCells.count }
            cell = walkCells[walkPhase]
            flip = faceRight
            if dir > 0 && x > track + m { x = -spriteW - m; nextLap() }
            else if dir < 0 && x < -spriteW - m { x = track + m; nextLap() }
            // He only ever fires at an incoming Lost Soul (tickSoul triggers the shot) —
            // no random shooting into the void. The combat setting scales demon frequency.

        case .shoot:
            let wpn = shootWeapon
            flip = faceRight
            // Face the demon — souls can come from behind now.
            if soulMode != .gone { flip = soulX > x + spriteW / 2 }
            modeT -= dt; blinkT += dt
            if blinkT > wpn.blink { blinkT = 0; blink.toggle() }
            cell = blink ? wpn.cell : wpn.aimCell   // fire frame (real muzzle flash) ↔ aim pose
            dy = blink ? wpn.recoil * scale : 0
            glow = blink
            // Projectile weapons. Rocket/BFG fire once; Plasma re-fires a fresh bolt as soon
            // as the previous one fizzles (short range), giving the signature rapid stream.
            if modeT < wpn.dur - 0.12 {
                let firstShot = !rocketFired
                let plasmaRefire = wpn.label == "Plasma" && !rocketLive && modeT > 0.15
                if (firstShot || plasmaRefire),
                   let kind: Projectile = (wpn.label == "Rocket" ? .rocket
                                          : wpn.label == "BFG" ? .bfg
                                          : wpn.label == "Plasma" ? .plasma : nil) {
                    rocketFired = true; rocketLive = true
                    rocketDir = flip ? 1 : -1          // projectile follows the facing (may aim backwards at a soul)
                    projKind = kind
                    rocketX = flip ? (x + spriteW * 0.90) : (x + spriteW * 0.10)
                    projStartX = rocketX
                }
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

        // Projectile travels independently. Speeds: plasma is a fast short bolt, the
        // rocket cruises, the BFG orb flies heavy & slow. Rocket/BFG detonate at the
        // track edge; plasma bolts just fizzle after a short range.
        if rocketLive {
            let speed: CGFloat = projKind == .plasma ? 540 : projKind == .bfg ? 220 : 360
            rocketX += rocketDir * speed * dscale * CGFloat(dt)
            let edgeHit = rocketDir > 0 ? rocketX >= track - 6 * dscale : rocketX <= 6 * dscale
            if projKind == .plasma {
                if edgeHit || abs(rocketX - projStartX) > 300 * dscale { rocketLive = false }
            } else if edgeHit {
                rocketLive = false
                boomLive = true; boomT = 0; boomBFG = projKind == .bfg
                boomX = min(max(rocketX, 0), track)
            }
        }
        if boomLive {
            boomT += dt
            if boomT > (boomBFG ? 0.34 : 0.3) { boomLive = false }
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
        // Mostly the fall sequence; occasionally the gib burst for variety (its only
        // remaining trigger now that random deaths are gone).
        if Double.random(in: 0...1, using: &rng) < 0.35 {
            mode = .death; deathPhase = 0; modeT = 0.5; blinkT = 0; blink = true; splatX = x
        } else {
            mode = .killed; killFrame = 0; killT = 0
        }
        soulMode = .gone; soulCooldown = soulNextCooldown()   // cancel any in-flight soul
    }

    // MARK: - Render

    private func render(cell: Int, useDeath: Bool, deathCell: Int, flip: Bool,
                        dy: CGFloat, glow: Bool, opacity: CGFloat,
                        scale: CGFloat, spriteW: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let spriteH = CH * scale
        // Pick the frame image. The fall frames are gated on mode == .killed so a stale
        // killFrame can never paint a corpse over a walking/shooting slayer.
        let img: CGImage?
        let showFall = mode == .killed && killFrame >= 0
        let bottomAligned = useDeath || showFall
        if showFall {
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

        // Projectile (rocket, BFG orb or plasma bolt).
        let projImg: CGImage? = projKind == .bfg ? (bfgImage ?? rocketImage)
                              : projKind == .plasma ? (plasmaImage ?? rocketImage)
                              : rocketImage
        if rocketLive, let r = projImg {
            let pk: CGFloat = projKind == .bfg ? 0.85 : 1   // the orb art is chunky — trim it a bit
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

        // Impact explosion: BFG uses its own green 2-frame blast, the rocket reuses the
        // red fireball frames from the Lost-Soul explosion (same 8-bit fireball look).
        let boomFrames = boomBFG ? bfgBoom : soulDeath
        if boomLive, !boomFrames.isEmpty {
            let stepDur = boomBFG ? 0.17 : 0.10
            let idx = min(boomFrames.count - 1, Int(boomT / stepDur))
            let img = boomFrames[idx]
            let h: CGFloat = boomBFG ? (idx == 0 ? 34 : 16) * scale : (20 + CGFloat(idx) * 8) * scale
            let w = h * CGFloat(img.width) / CGFloat(max(1, img.height))
            boomLayer.contents = img
            boomLayer.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            boomLayer.position = CGPoint(x: deckLeft + boomX, y: feetBottomY + 25 * scale)
            boomLayer.opacity = idx == boomFrames.count - 1 ? 0.85 : 1
        } else {
            boomLayer.opacity = 0
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
        rocketImage = nil; bfgImage = nil; plasmaImage = nil; splatImage = nil

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
        plasmaImage = cg("plasma-proj.png")
        bfgBoom = []
        if let boom = cg("bfg-boom.png") {
            let cellW = boom.width / 2, cellH = boom.height
            for i in 0..<2 {
                if let c = boom.cropping(to: CGRect(x: i * cellW, y: 0, width: cellW, height: cellH)) {
                    bfgBoom.append(c)
                }
            }
        }
        splatImage = makeSplatImage()
        soulFly = ["lostsoul-fly0.png", "lostsoul-fly1.png"].compactMap(cg)
        soulDeath = ["lostsoul-death0.png", "lostsoul-death1.png", "lostsoul-death2.png"].compactMap(cg)
    }

    /// Blood splatter as chunky 2px-raster pixel art (matches the 8-bit sprite look —
    /// the old version used smooth anti-aliased ellipses that clashed with the sprites).
    private func makeSplatImage() -> CGImage? {
        let w = 54, h = 22
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setShouldAntialias(false)
        let dark  = NSColor(red: 0.42, green: 0.03, blue: 0.03, alpha: 1)
        let mid   = NSColor(red: 0.60, green: 0.06, blue: 0.06, alpha: 1)
        let light = NSColor(red: 0.78, green: 0.10, blue: 0.10, alpha: 1)
        func px(_ gx: Int, _ gy: Int, _ c: NSColor) {   // one 2×2 "fat pixel" on the grid
            ctx.setFillColor(c.cgColor)
            ctx.fill(CGRect(x: gx * 2, y: gy * 2, width: 2, height: 2))
        }
        // Main pool (bottom rows, y-up: row 0 is the bottom) with a ragged top edge.
        for gx in 4...22 { px(gx, 0, dark) }
        for gx in 6...20 { px(gx, 1, dark) }
        for gx in [7, 9, 10, 12, 14, 15, 17, 19] { px(gx, 2, mid) }
        for gx in [9, 12, 15] { px(gx, 3, mid) }
        // Scattered droplets.
        px(2, 1, mid); px(24, 1, mid); px(5, 3, light); px(21, 3, light)
        px(3, 5, light); px(23, 4, light); px(12, 5, light); px(17, 6, mid)
        px(8, 6, mid); px(20, 7, light); px(13, 8, light)
        return ctx.makeImage()
    }
}
