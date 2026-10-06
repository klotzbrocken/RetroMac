#!/bin/bash
# Puts a release into appcast.xml — the step that was done by hand.
#
# Run it after ./package.sh, once the DMG is uploaded to the GitHub release v<version>:
#
#   ./appcast.sh            # the release in RetroMac.dmg
#   ./appcast.sh --beta     # RetroMac-<version>-beta.dmg, only for Macs that opted into betas
#   ./appcast.sh --phased   # automatic updates spread over a week (manual checks get it at once)
#   ./appcast.sh --dry-run  # print the item from CHANGELOG.md, check and sign nothing
#
# Before writing it checks that the DMG is notarized, that the app inside is this version and
# carries the binary just built (2.8.4 once shipped an old one), and that the release asset can
# be downloaded, so no Mac is offered an update that is not there. It signs with Sparkle's
# sign_update (the key in the keychain), takes the notes from the CHANGELOG section of the
# version, and keeps the five newest releases in the feed. It commits and pushes nothing.
set -e
cd "$(dirname "$0")"

BETA=false; PHASED=false; DRY=false
for arg in "$@"; do
    case "$arg" in
        --beta) BETA=true ;;
        --phased) PHASED=true ;;
        --dry-run) DRY=true ;;
        *) echo "Unknown option $arg"; exit 1 ;;
    esac
done

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
if [ "$BETA" = true ]; then DMG="RetroMac-${VERSION}-beta.dmg"; else DMG="RetroMac.dmg"; fi
URL="https://github.com/klotzbrocken/RetroMac/releases/download/v${VERSION}/${DMG}"
SIGN_UPDATE=".build/artifacts/sparkle/Sparkle/bin/sign_update"

if grep -q "<sparkle:version>${VERSION}</sparkle:version>" appcast.xml && [ "$DRY" = false ]; then
    echo "❌ appcast.xml already has ${VERSION}."; exit 1
fi

if [ "$DRY" = true ]; then
    SIGNATURE='sparkle:edSignature="DRY-RUN" length="0"'
else
    [ -f "$DMG" ] || { echo "❌ ${DMG} is missing. Run ./package.sh first."; exit 1; }

    echo "=== Notarization ticket"
    xcrun stapler validate "$DMG" >/dev/null || { echo "❌ ${DMG} is not stapled."; exit 1; }

    echo "=== The app inside the DMG"
    MNT="$(mktemp -d)"
    hdiutil attach -nobrowse -readonly -quiet -mountpoint "$MNT" "$DMG"
    INSIDE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MNT/RetroMac.app/Contents/Info.plist")"
    SHA_DMG="$(shasum -a 256 "$MNT/RetroMac.app/Contents/MacOS/RetroMac" | cut -d' ' -f1)"
    hdiutil detach -quiet "$MNT"
    [ "$INSIDE" = "$VERSION" ] || { echo "❌ The DMG holds ${INSIDE}, Info.plist says ${VERSION}."; exit 1; }
    SHA_BUILD="$(shasum -a 256 .build/RetroMac.app/Contents/MacOS/RetroMac | cut -d' ' -f1)"
    [ "$SHA_DMG" = "$SHA_BUILD" ] || { echo "❌ The DMG's binary is not the one in .build/RetroMac.app."; exit 1; }

    echo "=== The release asset"
    curl -sfIL "$URL" >/dev/null || { echo "❌ ${URL} cannot be downloaded. Upload it to release v${VERSION} first."; exit 1; }

    echo "=== Signing"
    SIGNATURE="$("$SIGN_UPDATE" "$DMG")"
    echo "$SIGNATURE" | grep -q 'sparkle:edSignature=' || { echo "❌ sign_update gave no signature."; exit 1; }
fi

VERSION="$VERSION" URL="$URL" SIGNATURE="$SIGNATURE" BETA="$BETA" PHASED="$PHASED" DRY="$DRY" python3 - <<'PY'
import os, re, html, datetime
v, url, sig = os.environ["VERSION"], os.environ["URL"], os.environ["SIGNATURE"]
beta, phased, dry = os.environ["BETA"] == "true", os.environ["PHASED"] == "true", os.environ["DRY"] == "true"

# The notes: the version's CHANGELOG section, its "New", "Known limits" and "Fixes" as lists.
log = open("CHANGELOG.md", encoding="utf-8").read()
m = re.search(r"^## " + re.escape(v) + r"\s*\n(.*?)(?=^## )", log, re.S | re.M)
if not m:
    raise SystemExit(f"❌ CHANGELOG.md has no section ## {v}.")
def inline(t):
    t = html.escape(t, quote=False)
    t = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", t)
    return re.sub(r"`(.+?)`", r"<code>\1</code>", t)
def bullets(block):
    items, cur = [], None
    for line in block.splitlines():
        if line.startswith("- "):
            cur = [line[2:].strip()]; items.append(cur)
        elif cur is not None and line.startswith("  ") and not line.strip().startswith("- "):
            cur.append(line.strip())
    return "".join(f"<li>{inline(' '.join(i))}</li>" for i in items)
body = m.group(1)
sections = re.split(r"^### (.+)$", body, flags=re.M)
parts = []
if len(sections) == 1:
    parts.append(f"<ul>{bullets(body)}</ul>")
else:
    for title, block in zip(sections[1::2], sections[2::2]):
        if title.strip() in ("New", "Known limits", "Fixes"):
            parts.append(f"<h3>{inline(title.strip())}</h3><ul>{bullets(block)}</ul>")
notes = f"<h2>RetroMac {v}</h2>" + "".join(parts)

date = datetime.datetime.now(datetime.timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
extra = ""
if beta: extra += "\n      <sparkle:channel>beta</sparkle:channel>"
if phased: extra += "\n      <sparkle:phasedRolloutInterval>86400</sparkle:phasedRolloutInterval>"
item = f"""    <item>
      <title>Version {v}{' beta' if beta else ''}</title>
      <pubDate>{date}</pubDate>
      <sparkle:version>{v}</sparkle:version>
      <sparkle:shortVersionString>{v}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>{extra}
      <description><![CDATA[
        {notes}
      ]]></description>
      <enclosure
        url="{url}"
        type="application/octet-stream"
        {sig}
      />
    </item>
"""
if dry:
    print(item)
    raise SystemExit(0)

feed = open("appcast.xml", encoding="utf-8").read()
first = feed.index("    <item>")
feed = feed[:first] + item + feed[first:]
# The five newest downloadable releases stay; informational items (no enclosure) always stay.
items = re.findall(r"    <item>.*?</item>\n", feed, re.S)
keep, kept = [], 0
for it in items:
    if "<enclosure" in it:
        kept += 1
        if kept > 5:
            continue
    keep.append(it)
start, end = feed.index("    <item>"), feed.rindex("</item>\n") + len("</item>\n")
feed = feed[:start] + "".join(keep) + feed[end:]
open("appcast.xml", "w", encoding="utf-8").write(feed)
print(f"✅ appcast.xml: {v}{' (beta)' if beta else ''}{' (phased over 7 days)' if phased else ''} added, {len(keep)} items in the feed.")
PY

if [ "$DRY" = false ]; then
    echo ""
    echo "Next: git add appcast.xml && git commit -m \"Appcast: publish ${VERSION}\" && git push"
    echo "Pushing main publishes it: the feed is read from raw.githubusercontent.com."
fi
