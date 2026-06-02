# Code-Review-Analyse — Verifikation der 11 Findings

Jedes Finding gegen den echten Code geprüft. Status: ACCURATE / PARTLY / WRONG.

| # | Thema | Datei:Zeile | Status | Schwere |
|---|-------|-------------|--------|---------|
| 9 | Installer ohne Integritätsprüfung | EmulatorInstaller.swift:43,109 | ACCURATE | **CRITICAL** |
| 7 | Recording-Blit + managed + synchronize() | RetroRenderer.swift:184-194 | ACCURATE | HIGH |
| 8 | killall synchron (waitUntilExit, Main-Thread) | SystemUIHelper.swift:119; DockController.swift:845 | ACCURATE | HIGH |
| 2 | Single-Window-Capture nutzt NSScreen.main-Scale | ScreenCaptureManager.swift:119 | ACCURATE | HIGH |
| 11 | Sandbox aus | RetroMac(-release).entitlements:5 | ACCURATE | HIGH |
| 10 | Lizenz-POST nicht form-encoded | LicenseManager.swift:231 | ACCURATE | MEDIUM |
| 5 | CGWindowList-Polling 33–100 ms | OverlayWindowController.swift:455,469 | ACCURATE | MEDIUM |
| 4 | enableOnLaunch/dockEnabled hart false | AppDelegate.swift:118-120 | ACCURATE (by design) | MEDIUM |
| 3 | Observer nicht gehalten | AppDelegate.swift:86,94,102,107 | PARTLY | LOW |
| 6 | bis zu 4 Render-Passes | RetroRenderer.swift:133-173 | ACCURATE (bedingt) | LOW |
| 1 | DockFix behandelt vertikal nur als „left" | DockFix.swift:87-101 | **WRONG** | — |

## Details / Korrekturen am Reviewer

**#1 WRONG:** `dockCGRect` kommt aus `DockController.currentDockFrame()` (DockFix.swift:83) und enthält den **echten** Fenster-Frame in Screen-Koordinaten — also bereits links *oder* rechts. `dockRight = dockCGRect.maxX` schiebt Fenster korrekt weg, egal welche Seite. Nur der **Kommentar** „Vertical dock on the left" (Z. 88) ist irreführend → nur Kommentar fixen.

**#3 PARTLY:** Die Observer aus `startAppLaunchObserver()`/`startSleepObserver()` werden in Properties (Z. 26-30) gehalten und in `stop()` entfernt. **Aber** die vier Inline-Observer (Z. 86/94/102/107: TV-Bookmarks, Dock-Theme, Camera-State, Viewport) speichern ihr Token nicht → nicht entfernbar. Klein (AppDelegate lebt App-Lifetime), aber unsauber.

**#4 ACCURATE, aber Absicht:** Z. 118-120 setzen bewusst `enableOnLaunch=false`, `dockEnabled=false` („App always starts deactivated"). Widerspruch: Es *gibt* ein `enableOnLaunch`-Setting, das so nie greift. Fix: gespeicherten Wert respektieren statt hart zu überschreiben.

**#2 HIGH:** `Int(NSScreen.main?.backingScaleFactor ?? 2)` (Z. 119) ignoriert das Display des Ziel-Fensters → falsche Capture-Größe auf Multi-Display mit gemischtem Scale. Fix: Screen wählen, der `freshWindow.frame` enthält (analog `captureSize(for display:)` Z. 75-102).

**#7 HIGH:** Pro Frame `blit.copy(drawable→recTex)` + `blit.synchronize(recTex)` auf `.managed`-Textur (Z. 190-191, 214) → GPU-Pipeline-Stall beim Recording. Fix: `.synchronize` raus, async per `addCompletedHandler` lesen, oder Ring-Buffer/Shared-Storage-Capture-Pfad.

**#8 HIGH:** Drei sequentielle `Process … waitUntilExit()` (killall Dock/Finder) ohne Background-Dispatch → wahrscheinlich Main-Thread-Block (Spinner) bei Dock-/Desktop-Toggles. Fix: auf `DispatchQueue.global(qos:.userInitiated)` auslagern.

**#9 CRITICAL (wichtigster Fund):** `curl -L -s -o` Download (Z. 43), nur Größencheck >500 KB (Z. 53), dann `copyItem` nach `/Applications/<Emu>.app` (Z. 109-115). **Keine** SHA256-/codesign-/Team-ID-/Notarisierungs-Prüfung. Quarantäne bleibt zwar erhalten (Gatekeeper-Warnung beim ersten Start), aber das verhindert die Installation nicht. MITM/CDN-/DNS-Kompromiss → beliebiges Binary in /Applications. Fix: vor dem Kopieren `codesign --verify -R "anchor apple generic and certificate leaf[subject.OU] = <TeamID>"` + `spctl -a -t install` prüfen, idealerweise zusätzlich gepinnte SHA256 je Emulator.

**#10 MEDIUM:** `let body = "product_id=…&license_key=\(key)"` (Z. 231) ohne Encoding → Keys mit `+ & % space` brechen/injizieren Parameter. Fix: `URLComponents`/`URLQueryItem` + `percentEncodedQuery`.

**#11 HIGH:** `app-sandbox=false` in beiden Entitlements; zusätzlich `system-extension.install=true`. Wegen ScreenCaptureKit/System-UI nachvollziehbar, aber Download-/Installer-/WebView-Pfade (#9) müssen dann besonders hart sein. Sandbox-Aktivierung ist invasiv (ScreenCaptureKit + System-Extension brauchen Ausnahmen) — realistisch eher: #9/#10 absichern + Hardened Runtime beibehalten, Sandbox separat evaluieren.

## Empfohlene Reihenfolge
1. **#9** (Signatur-/Team-ID-Prüfung im Installer) — Supply-Chain, kritisch.
2. **#10** (form-encoding) — klein, klar.
3. **#7** + **#8** (GPU-Stall, Main-Thread-Block) — spürbare Stabilität/Perf.
4. **#2** (Capture-Scale Multi-Display).
5. **#4** (Launch-Setting respektieren), **#5** (AX statt Polling), **#3**/#1 (Aufräumen/Kommentar).
6. **#11** Sandbox: separat bewerten (großer Eingriff).
