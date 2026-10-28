#!/bin/bash
# Renders every title bar style with the shipped drawing code into build/fidelity/ and opens
# gallery.html. See docs/fidelity/README.md.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$PWD/build/fidelity"
rm -rf "$OUT"
RETROMAC_GALLERY="$OUT" swift test --build-system native --filter TitleBarGalleryTests >/dev/null
echo "✓ $OUT/gallery.html"
open "$OUT/gallery.html"
