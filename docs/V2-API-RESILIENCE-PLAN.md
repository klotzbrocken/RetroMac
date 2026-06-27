# v2.0 — Apple-API Resilience (Eng Plan)

**Goal:** one chokepoint for every OS-poking call, with capability detection, OS-version
gating, **graceful + visible** degradation, and crash recovery. macOS 27 (or a user with
revoked permissions) should degrade features cleanly — never break silently, never leave
the real Dock hidden. This is the foundation the iPad work (baustein #2, adds
`CGVirtualDisplay`) plugs into.

## Current OS-touching surface (grounded)
- **DockController** — `defaults write com.apple.dock …` + `killall Dock` to hide/relocate
  the system Dock (`applySystemDockPolicy` / `setSystemDockPrefs`). Riskiest surface.
- **SystemUIHelper** — menu-bar autohide (osascript System Events + `_HIHideMenuBar`),
  desktop icons (`com.apple.finder CreateDesktop` + `killall Finder`).
- **DockFix** — dock workaround toggle.
- **Accessibility (AX)** — `MinimizedWindowTracker`, `AppLauncher` (raise/minimize; needs
  `AXIsProcessTrusted`).
- **ScreenCaptureKit** — `ScreenCaptureManager`, `OverlayWindowController` (needs Screen
  Recording).
- **Gap:** only 4 `#available` checks repo-wide; no central capability probe; failures
  partly silent.
- **Future:** `CGVirtualDisplay` (private CoreGraphics) for the iPad second screen.

## Design — `SystemBridge` layer
- `enum SystemCapability` { systemDockControl, menuBarAutohide, desktopIconsToggle,
  accessibility, screenCapture, virtualDisplay }.
- `struct CapabilityStatus { available: Bool; degraded: Bool; reason: String? }`.
- `protocol SystemBridge` — `hideSystemDock(edge:) throws`, `restoreSystemDock()`,
  `setMenuBarAutohide(_:) throws`, `setDesktopIconsHidden(_:) throws`,
  `raiseAppWindow(pid:) throws`, `capability(_:) -> CapabilityStatus`.
- Typed errors: `SystemBridgeError.unsupported | .permissionDenied | .commandFailed`.
  **No silent failure** (ties to the audit's "zero silent failures").
- Version-gated impls chosen by a factory: `SonomaSystemBridge` (current behaviour,
  macOS 14–15) and `FallbackSystemBridge` (no-ops unsupported ops, reports `degraded`).
  macOS 27 impl is filled when betas land — the layer is the insurance.

## Capability probing (run once, cache)
- systemDockControl: write+read-back a harmless dock key + confirm `killall Dock` allowed;
  read-back mismatch (schema changed in 27) → unavailable.
- menuBarAutohide: reuse `SystemUIHelper.testAutomation()` + `_HIHideMenuBar` write probe.
- desktopIconsToggle: read `CreateDesktop`.
- accessibility: `AXIsProcessTrusted()`. screenCapture: `CGPreflightScreenCaptureAccess()`.
- virtualDisplay: `dlsym` for `CGVirtualDisplay` (for the iPad phase).

## Graceful + visible degradation
- New **Settings → System → "System status"** pane: per-capability green/amber/red + reason
  ("Dock control unavailable on macOS 27 — themes apply without hiding the real Dock").
- Unavailable capability → the dependent feature **self-disables and says why**, instead of
  half-applying (e.g. dock control gone → still skin the floating dock, don't hide the
  system Dock, and surface that in the UI).

## Crash recovery (folds in P1 audit + docky watchdog)
- Single recovery state file: `{ ownerPID, sessionID, dockSnapshot, didHideDock, hidePosition }`.
- On launch `recoverStaleSnapshotIfNeeded()`: snapshot from a dead PID + Dock looks hidden →
  restore it.
- **Phase 2:** tiny watchdog helper (separate signed executable) given RetroMac's PID + the
  state file; restores the system Dock if RetroMac dies while the Dock is hidden.

## Migration (incremental, low-risk)
1. Add `SystemBridge` + capability probe; move `SystemUIHelper` (menu bar + desktop icons)
   behind it — already isolated, safest first move.
2. Move `DockController` dock-pref / `killall` behind it.
3. Gate AX (`AppLauncher`, `MinimizedWindowTracker`) on the `accessibility` probe.
4. Add the System-status pane.
5. Recovery state file + stale recovery.
6. Stub `virtualDisplay` so baustein #2 plugs in.

## Tests / verification
- Unit: probe returns `degraded` when a pref read-back mismatches (point at a bogus key).
- Manual: revoke Screen Recording + Accessibility → visible degradation, no crash, Dock not
  silently hidden.
- `kill -9` with Dock hidden → relaunch → Dock restored by stale recovery.

## Out of scope / risk
- Not migrating to public APIs (none exist for dock hiding) — this **contains** the private
  surface, doesn't remove it.
- Exact macOS 27 behaviour unknown until betas; this layer is the insurance.
- Watchdog helper = separate target + code-signing → phase 2.

**Effort (phase 1, minus watchdog):** human ~1 week / CC ~1 day.

---

# Eng Review — locked decisions (2026-06-26)

**Scope locked: SLIM.** Build one `SystemBridge` + capability probe + typed errors +
visible degradation, and **consolidate** the existing dock recovery. The version-gated
impls (`SonomaSystemBridge`/`FallbackSystemBridge` + factory) and the watchdog helper are
**DEFERRED** until macOS 27 betas actually break something. Effort: human ~3-4 days / CC ~½ day.

**[EUREKA] Why the version-fork isn't needed yet:** capability *probing* already gives
macOS-27 resilience for the failure case — if 27 changes the dock-pref schema, the
write+read-back probe mismatches → capability marked unavailable → the dependent feature
self-disables with a reason. You only need version-specific impls if 27 offers a *different
working mechanism you must switch to*, not to fail gracefully. Probe-and-degrade > version-dispatch.

## Architecture (slim)
- `final class SystemBridge { static let shared }` (matches `SystemUIHelper`/controller
  style). Holds only a cached `[SystemCapability: CapabilityStatus]` snapshot.
- All OS pokes return `Result<Void, SystemBridgeError>` (or `throws`); callers degrade the
  dependent feature on `.unsupported`/`.permissionDenied`/`.commandFailed`. **No `try?`
  silent failures** — that's the "zero silent failures" win from the audit.
- **Do NOT add a parallel recovery file.** Extend `DockController`'s existing recovery
  state (`didHideSystemDock`, `lastAppliedHidePosition`, `persistDockRecoveryState`) with
  `ownerPID` + `sessionID`, plus `recoverStaleSnapshotIfNeeded()` at launch. One source of truth.

## Code quality
- Centralize the duplicated `Process` boilerplate (`SystemUIHelper.readFinderShowsIcons` /
  `writeFinderShowsIcons` / `restartFinder`, plus DockController's `defaults`/`killall`
  shell-outs) into one `SystemBridge.runDefaults(...)` / `shell(...)` returning a typed
  `Result`. DRY + typed errors in one move.
- Migration is **refactor-first, behavior-identical** (Beck: make the change easy, then make
  the easy change). Never combine structural + behavioral changes. Build + smoke after each:
  1. `SystemUIHelper` (menu bar + desktop icons) behind `SystemBridge` — safest, most isolated.
  2. `DockController` dock-pref/`killall` behind it (most fragile — the P1 recovery area; smoke hard).
  3. AX gating (`AppLauncher`, `MinimizedWindowTracker`) on the `accessibility` probe.
  4. Settings → System "System status" pane.
  5. Consolidate dock recovery (ownerPID/sessionID + stale recovery).
  6. Stub `virtualDisplay` capability for the iPad phase.

## Tests
- **Make probes dependency-injectable** (pass in the pref-reader / AX-trust closure) so the
  logic is unit-testable WITHOUT shelling out to real `defaults`/AX. This is the key
  testability decision — otherwise nothing here is unit-testable.
- ⚠️ Confirm a test target exists. If RetroMac has no XCTest target, standing one up is part
  of this work (small but real — flag, don't skip).
- Matrix: probe→`degraded` on pref read-back mismatch (inject fake reader); each op→
  `.permissionDenied` when AX/Screen-Recording ungranted (inject capability); recovery: stale
  snapshot from dead PID + dock-hidden → restore, fresh snapshot from live PID → no-op.
- Manual/integration: revoke Screen Recording + Accessibility → visible degradation, no crash,
  Dock not silently hidden; `kill -9` with Dock hidden → relaunch → Dock restored.

## Performance
- Probe shells out (`defaults read`, `killall` test) — ~10-50ms per `Process` spawn. **Never
  on the theme-switch or dock hot path.** Probe once at launch + manual refresh + after a
  failed op; cache the snapshot.
- Probe **async, off-main**; default capabilities to "assume available" until the probe
  completes, then reconcile. The dock-poke path already runs on `DockController.dockPrefsQueue`
  off-main — keep `SystemBridge` shell-outs off-main, hop to main only for UI/state.

## Biggest risk
Step 2 (DockController) touches the recovery-critical dock-hide path (the P1 area). Treat it
as the high-blast-radius step: behavior-identical refactor, smoke each sub-change (theme on/off,
quit-with-dock-hidden, `kill -9`-with-dock-hidden), and keep the existing generation-token guard.

## GSTACK REVIEW REPORT
| Run | Status | Findings |
|-----|--------|----------|
| Step 0 scope | RESOLVED | Plan was overbuilt (version-fork/watchdog speculative). Locked to SLIM; deferred version-dispatch + watchdog. |
| Architecture | RESOLVED | One `SystemBridge.shared`; typed `Result`; consolidate existing DockController recovery (no parallel file). |
| Code quality | RESOLVED | Centralize Process boilerplate; refactor-first 6-step migration, behavior-identical. |
| Tests | OPEN (impl) | Probes must be DI-testable; verify/stand-up XCTest target; matrix defined. |
| Performance | RESOLVED | Async off-main probe, cache snapshot, never on hot path. |

VERDICT: Plan is sound at SLIM scope. One open item carried to implementation: dependency-inject the probes and confirm/stand-up a test target.

NO UNRESOLVED DECISIONS
