#!/usr/bin/env python3
"""Asset-Diät für Resources/Themes — verkleinert überdimensionierte Bilder in place.

Regeln (Formate und Dateinamen bleiben IMMER erhalten, kein Code-Touch nötig):
  1. */icons/*.png  > 256 px           → auf 256 px (LANCZOS). Paletten-PNGs (Pixel-Art) bleiben.
  2. *.icns         Reps > 256 px      → gestrippt (iconutil); 16/32/128/256 (+128@2x) bleiben.
  3. preview.png/jpg > 1470 px Breite  → auf 1470 px, Format bleibt.
  4. wallpaper*.png/jpg > 3840 px      → auf 3840 px; JPEGs > 2 MB werden q82 re-encodiert.
     Ausnahme-Themes (Pixel-/Pattern-Walls): Windows31, Windows98, SGI-IRIX.

Originale liegen in der git-History. Aufruf: python3 scripts/slim-theme-assets.py
"""
import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Resources", "Themes")
WALL_EXCEPT = {"Windows31.retromactheme", "Windows98.retromactheme", "SGI-IRIX.retromactheme"}
# iconset-Reps, die entfernt werden (Payload > 256 px)
ICNS_DROP = {"icon_256x256@2x.png", "icon_512x512.png", "icon_512x512@2x.png"}

changed = []  # (path, before, after)


def note(path, before):
    after = os.path.getsize(path)
    if after < before:
        changed.append((path, before, after))


def resize_png(path, max_px):
    im = Image.open(path)
    if im.format != "PNG" or im.mode == "P":      # Pixel-Art (Palette) nie anfassen
        return
    if im.width <= max_px and im.height <= max_px:
        return
    before = os.path.getsize(path)
    scale = max_px / max(im.width, im.height)
    im = im.convert("RGBA").resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
    im.save(path, optimize=True)
    note(path, before)


def slim_wide_image(path, max_w, jpeg_q=82, jpeg_floor=2_000_000):
    im = Image.open(path)
    fmt = im.format
    before = os.path.getsize(path)
    needs_resize = im.width > max_w
    if fmt == "JPEG":
        if not needs_resize and before <= jpeg_floor:
            return
        if needs_resize:
            s = max_w / im.width
            im = im.resize((max_w, round(im.height * s)), Image.LANCZOS)
        im.convert("RGB").save(path, "JPEG", quality=jpeg_q, optimize=True, progressive=True)
        note(path, before)
    elif fmt == "PNG":
        if im.mode == "P" or not needs_resize:
            return
        s = max_w / im.width
        im = im.convert("RGBA").resize((max_w, round(im.height * s)), Image.LANCZOS)
        im.save(path, optimize=True)
        note(path, before)


def strip_icns(path):
    before = os.path.getsize(path)
    if before < 400_000:                            # schon schlank
        return
    tmp = tempfile.mkdtemp()
    iconset = os.path.join(tmp, "x.iconset")
    try:
        if subprocess.run(["iconutil", "-c", "iconset", path, "-o", iconset],
                          capture_output=True).returncode != 0:
            return
        dropped = False
        for f in os.listdir(iconset):
            if f in ICNS_DROP:
                os.remove(os.path.join(iconset, f)); dropped = True
        if not dropped:
            return
        out = os.path.join(tmp, "x.icns")
        if subprocess.run(["iconutil", "-c", "icns", iconset, "-o", out],
                          capture_output=True).returncode == 0 and os.path.getsize(out) > 0:
            shutil.copyfile(out, path)
            note(path, before)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    total_before = sum(os.path.getsize(os.path.join(dp, f))
                       for dp, _, fs in os.walk(ROOT) for f in fs)
    for theme in sorted(os.listdir(ROOT)):
        tdir = os.path.join(ROOT, theme)
        if not os.path.isdir(tdir):
            continue
        for dp, _, fs in os.walk(tdir):
            for f in fs:
                p = os.path.join(dp, f)
                base = os.path.basename(dp)
                try:
                    if f.endswith(".icns"):
                        strip_icns(p)
                    elif base == "icons" and f.lower().endswith(".png"):
                        resize_png(p, 256)
                    elif f.lower().startswith("preview") and f.lower().endswith((".png", ".jpg", ".jpeg")):
                        slim_wide_image(p, 1470)
                    elif (f.lower().startswith("wallpaper")
                          and f.lower().endswith((".png", ".jpg", ".jpeg"))
                          and theme not in WALL_EXCEPT):
                        slim_wide_image(p, 3840)
                except Exception as e:              # eine kaputte Datei bricht nicht den Lauf ab
                    print(f"SKIP {p}: {e}", file=sys.stderr)

    total_after = sum(os.path.getsize(os.path.join(dp, f))
                      for dp, _, fs in os.walk(ROOT) for f in fs)
    print(f"{'vorher':>10} {'nachher':>10}  Datei")
    for p, b, a in sorted(changed, key=lambda c: c[1] - c[2], reverse=True):
        print(f"{b/1e6:8.1f}MB {a/1e6:8.1f}MB  {os.path.relpath(p, ROOT)}")
    print(f"\nThemes gesamt: {total_before/1e6:.0f} MB → {total_after/1e6:.0f} MB "
          f"(−{(total_before-total_after)/1e6:.0f} MB, {len(changed)} Dateien)")


if __name__ == "__main__":
    main()
