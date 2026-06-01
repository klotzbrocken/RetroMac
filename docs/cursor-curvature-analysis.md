# Cursor-Offset Correction for CRT Barrel Distortion — Feasibility Analysis

**Status:** Analysis only. No behavior changed. Recommendation: do **not** implement an event-tap cursor remap.

## 1. The problem

The CRT shaders apply barrel/pincushion curvature to the captured desktop image. The
ScreenCaptureKit overlay window is **purely visual and click-through**
(`OverlayWindowController.swift:134` → `window.ignoresMouseEvents = true`; comment at
line 436 confirms clicks pass straight through to the real desktop). So:

- A control at real screen point **P** is *displayed*, through the shader, at a displaced
  point **P′ = inv(P)**.
- The hardware mouse cursor is drawn by the OS on top of everything; it is **not** part of
  the captured source texture, so it is **not** warped. It appears at its true coord **C**.
- Clicks land at **C** (true coords). Near edges/corners, where the user sees a control at
  **P′** but must put the cursor at **P** to hit it, the visual mismatch **P − P′** makes
  edge controls hard to aim at.

## 2. The distortion formula(s)

Shaders are Metal source strings in `Sources/Presets/BuiltinShaders.swift`. Curvature is
**not uniform** — it varies per shader and many shaders have none.

**Type A — radial barrel** (newpixie L1102, lncrt L1971, tgrn L2216):
```metal
uv = uv * 2.0 - 1.0;
uv = uv + uv * offset * offset;   // offset = uv  → uv_c * (1 + uv_c²) component-wise
uv = uv * 0.5 + 0.5;
```
amount = `0.5/0.3/0.4 * intensity` respectively.

**Type B — per-axis curve** (GDV L1317, CurvatureX L1381):
```metal
uv = uv * 2.0 - 1.0;
uv *= 1.0 + float2(amount * uv.y*uv.y, amount * uv.x*uv.x);
uv = uv * 0.5 + 0.5;
```
amount: CurvatureX `0.01`, GDV `cx=0.03, cy=0.04`, all `* intensity`.

Several shaders (zfast, crt-geom) have **no curvature** at all; others (Lottes, sony-pvm,
trinitron) only darken edges, no UV warp. All strengths are multiplied by
`AppSettings.defaultIntensity` (default 1.0, user-adjustable, hotkey-bumpable).

This forward map is what samples the source; the *inverse* (P → P′, screen→visual) is what a
cursor correction would need. At full intensity the Type-A map samples far outside the unit
square (sampled magnitude reaches ~2.0 at the edge), i.e. heavy edge compression — the
correction near corners would be large (hundreds of px).

## 3. Feasibility per option

### (a) CGEventTap that remaps cursor / click coordinates — NOT RECOMMENDED
- **Correctness:** Achievable in principle. App is **not** sandboxed and already uses
  Accessibility (`AXIsProcessTrusted()` in HealthCheckTab/OverviewTab/WelcomeFlowWindow), so
  an event tap is permitted. To make a click *land* on the warped control while the cursor
  *looks* aligned, the tap must apply the **forward** distortion to the event location
  (`delivered = forward(C)`), reversing the visual offset. The math is the exact inverse of
  the shader's per-shader formula.
- **Why it fails in practice:**
  1. **Fights the OS cursor.** Moving/rewriting `kCGEventMouseMoved` locations to reposition
     the visible cursor creates a feedback loop with the OS's own cursor drawing — jitter,
     acceleration conflicts, and a cursor that no longer tracks the trackpad 1:1. The user
     would perceive the pointer "sliding" near edges.
  2. **Per-shader + per-intensity coupling.** The correct transform depends on which of ~15
     shaders is active and the live `defaultIntensity` (and the intensity hotkey). The tap
     would need to mirror every shader's formula and update on every change. High maintenance,
     easy to desync from the visual.
  3. **Multi-display / coordinate-space hazards.** Overlay windows are per-`NSScreen`; the
     distortion is per-window-rect. A global event tap sees global coords and must map to the
     right display rect and re-normalize — error-prone, and wrong near display seams.
  4. **Breaks edge access entirely.** Forward-warping the click pushes the *delivered*
     coordinate toward the extreme edge; near corners the target compresses to a sliver, so
     hitting the Apple menu or a corner Hot Corner becomes harder, not easier, and can push
     coordinates off-screen.
  5. **Latency/IPI cost** on every mouse event, plus a permission the feature would now hard-require.
- **Verdict:** Correct in theory, but invasive, fragile, high-risk, and degrades UX. Not low-risk.

### (b) Synthetic cursor drawn in-shader at the warped position, hide real cursor — NOT RECOMMENDED
- **Correctness:** The cursor could be drawn *inside* the source/shader at `inv(realC)` so it
  visually sits on the warped control. But the real (now hidden) cursor still defines where
  clicks land, so the user aims with the synthetic cursor while clicks land at the *true* `C`
  — exactly the original mismatch, just relocated. To fix targeting you'd *also* need option
  (a)'s event remap. Hiding the system cursor app-wide is itself disruptive (text fields,
  drags, other apps). Highest complexity, breaks click targeting.
- **Verdict:** Worse than (a). Reject.

### (c) Reduce / clamp curvature where precise input matters — RECOMMENDED (pragmatic)
- **Correctness:** Eliminates the *cause*. If the visual offset is small, see-vs-click
  mismatch is negligible. CurvatureX (`0.01`) and GDV (`0.03/0.04`) are already nearly
  imperceptible; the painful cases are the Type-A shaders at high intensity.
- **Options, lowest-risk first:**
  - Lower `defaultIntensity`, or use a low-curvature shader (CurvatureX / a no-curvature
    preset) — **already possible today, zero code.**
  - Optionally cap Type-A curvature amounts (e.g. clamp the `* intensity` term) so edges never
    displace more than a few px. Small, self-contained shader-string tweak; no new permission,
    no event tap, clicks always land correctly because nothing touches input.
- **Verdict:** Clicks always land correctly; pointer behaves normally; no Accessibility
  dependency. Best correctness-to-risk ratio.

## 4. Recommendation

Do **not** add an event-tap cursor remap. The "offset the mouse to match the curve" idea is
mathematically sound but practically a net-negative: it fights the OS cursor, must track
per-shader/intensity state, is multi-display fragile, and makes corner controls *harder* to
reach — for a cosmetic curve. The right answer is **(c)**: treat strong edge curvature as the
problem and reduce it. Today that needs no code (lower intensity / pick a flatter shader);
if desired, a future low-risk change is clamping the Type-A curvature terms in
`BuiltinShaders.swift` so the maximum edge displacement stays within a few pixels.

## 5. Key file references
- `Sources/Presets/BuiltinShaders.swift` — shader source strings; curvature helpers
  `curveUV_np` (L1102), `curveUV_gdv` (L1317), `curveUV_cx` (L1381), `curveUV_lncrt` (L1971),
  `curveUV_tgrn` (L2216).
- `Sources/Overlay/OverlayWindowController.swift:134` — `ignoresMouseEvents = true`
  (overlay is purely visual / click-through).
- `Sources/App/Settings.swift:77` — `defaultIntensity` (scales all curvature amounts).
- `Sources/App/HealthCheckTab.swift:72`, `OverviewTab.swift:265` — existing
  `AXIsProcessTrusted()` Accessibility usage (the only infra that would have enabled an event tap).
