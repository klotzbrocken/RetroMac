# Visual fidelity passes

How a look is checked against the real system, after macOS 7 Ultimate SP1's fidelity pass
(github.com/kaganisildak/macOS-7-Ultimate-SP1, `docs/fidelity`).

## The gallery

```sh
Scripts/render-gallery.sh
```

draws every title bar style, front and behind, with the code RetroMac ships
(`TitleBarOverlayView`, no live window needed) into `build/fidelity/` and opens `gallery.html`.
`TitleBarGalleryTests` does the same drawing in every `swift test` run and fails when a style
draws nothing, so a broken bar shows up before anyone opens a window.

## References

Screenshots of the real system are a visual reference only: they stay outside the repository
(for example in `docs/copland-theme-reference/`, which is never committed), are never shipped,
and no pixels are copied from them. Name the source of each one in the findings table.

Read reference colours by decoding the PNG into an sRGB bitmap. `NSBitmapImageRep.colorAt` with
`usingColorSpace(.sRGB)` shifts untagged images (#F0F0F0 reads as #F3F3F3); tag the image as sRGB
first, or read the bytes.

## Findings

One row per property that was compared. "Status" is changed, matches, or gap (with the reason).

| Theme | Component | Property | Before | After / target | Source | Status |
|---|---|---|---|---|---|---|
| Mac OS 8/9 (Platinum) | title bar, inactive | stripes and boxes | pinstripes and close, zoom and collapse boxes | flat #DADADA bar, grey title, no boxes; a click only brings the window forward (native bars and RetroMac's own windows) | Mac OS 8/9 Appearance Manager, inactive window | changed |
| Windows XP (Luna) | caption buttons in the gallery | — | none drawn | the buttons follow the real lights' positions, which an offscreen render has none of | — | gap (gallery only) |
