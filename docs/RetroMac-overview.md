# RetroMac — Überblick (aktueller Stand)

## Was ist RetroMac?
RetroMac ist eine **macOS-Menüleisten-App**, die deinen Mac in einen Retro-Computer
verwandelt. Zwei Kernideen:

1. **Echtzeit-CRT/Retro-Shader über den ganzen Bildschirm** (oder ein einzelnes Fenster):
   Über ScreenCaptureKit + Metal legt RetroMac einen klick-durchlässigen Overlay über den
   Desktop und rendert ihn mit Shadern (CRT-Krümmung, Scanlines, NTSC-Dot-Crawl, VHS,
   Bloom, Vignette …). Es gibt viele Presets (z. B. „CRT GDV Mini Ultra", „Joel GDV NTSC v4",
   LCD-/PVM-/Trinitron-Looks) mit Reglern für Intensität, Vignette und Bloom.

2. **Retro-Desktop-Themes** über `.retromactheme`-Bundles: ein schwebendes Dock + Wallpaper
   + Icon-Set + optional ein eigener Desktop (Programm-Manager, Toolchest) je Ära —
   Snow Leopard, Mountain Lion, Mac OS 9 (Classic/Platinum), Mac OS X Aqua, Windows 3.1/98/XP,
   BeOS, OS/2 Warp, SGI IRIX, AmigaOS Workbench, Sleek Retro und „Maiks Favourite".

## Funktionsbausteine
- **Retro-Dock:** schwebt über dem System-Dock; Position unten/links/rechts; Magnifier oder
  Hover-Zoom; themen-eigene Icons (`iconMappings`), Papierkorb, Running-Indikatoren.
- **Virtuelle Kamera (CMIO-System-Extension):** legt den Shader auf dein Webcam-Bild für
  Video-Calls (eigenes Gerät „RetroMac Cam").
- **Television:** Web-/Stream-Inhalte in einem retro-geshaderten Fenster, jetzt mit Vollbild.
- **Retro-Games:** eingebaute Quake-/Doom-Engines, Emulator-Auto-Installer + ROM-Bibliothek.
- **Screenshot mit Shader** per globalem Hotkey.
- **Welcome-Flow, Lizenzierung (Gumroad), „Buy me a coffee".**

## Neu im aktuellen Stand
**Virtuelle Kamera repariert:** Die Surface-ID wird jetzt über eine CMIO-Custom-Property
benutzerübergreifend an die (notarisierte) Extension übergeben → echtes Webcam-Bild statt
schwarz.

**Welcome-Flow überarbeitet:** What's New → Freigaben (mit Willkommen) → „Keep RetroMac free"
(3 Vorteile: No Tracking / Ad-Free / 100 % Optional) + Support-Optionen (Kaffee → Ko-fi,
Pizza → Gumroad-Unlock, „None" → App starten) + „Ich hab schon"-Checkbox.

**Menü aufgeräumt:** „Shader Options"-Untermenü (Intensity/Vignette/Bloom); Themes in
Kategorien (Apple · Windows · Unix & Amiga · Other); **Quit** als Power-Symbol oben;
**Reset Permissions** in die Settings verschoben.

**Retro Mode (One-Click, ✨ im Menü-Header):** versteckt Dock/Menüleiste/Desktop-Icons,
setzt das Lieblings-Theme + Shader und stellt beim Verlassen/Beenden/nach Crash alles
wieder her. Voll konfigurierbar unter **Settings → Retro Mode**.

**Timer (Settings → Timer):** „aktiv von Uhrzeit bis Uhrzeit" (Tagesfenster) und
„Countdown: aktiv für X Minuten" — jeweils mit Ziel Shader-Overlay **oder** Retro Mode.

**Theme „Maiks Favourite":** Pac-Man-Wallpaper, linksbündiges Pixel-Dock, hi-res Icons,
Hover-Zoom (gerade nach oben). **Animierter Pac-Man-Rahmen:** ein gelber Pac-Man läuft
einmal rund ums Dock und frisst die Punkte (an/aus in Settings → Dock; aus = ruhiger
statischer Pac-Man, gedimmte Punkte).

**Weitere Politur & Härtung:**
- Mountain-Lion-Dock auf reale Default-Größe (48 px), dezenterer Hintergrund.
- „Joel GDV NTSC v4": Randkrümmung halbiert → Cursor passt am Rand besser.
- Logs nach `~/Library/Logs/RetroMac/` (owner-only, Rotation) statt world-readable `/tmp`.
- Sicherheit/Performance: Emulator-Installer prüft Signatur + Notarisierung vor
  `/Applications`-Kopie; Lizenz-Request form-encoded; Recording ohne GPU-Stall;
  `killall` blockiert die UI nicht mehr; Window-Capture nutzt das richtige Display.

## Verteilung
Universal (arm64 + x86_64), Developer-ID-signiert **und notarisiert** (App, Camera-Extension,
DMG). Hinweis: App läuft unsandboxed (zwingend für Dock-/Menüleisten-/System-Steuerung),
mit Hardened Runtime + Notarisierung als Absicherung.
