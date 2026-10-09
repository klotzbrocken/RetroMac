# Abnahme RetroMac 3.0

Lastenheft 3.0, Abschnitte 7.5, 8.5, 9.5, 13 und Release-Abnahme. Stand 9. Oktober 2026, Build 3.0.

So ist der Status zu lesen:

- **Bestanden:** durch einen automatischen Test oder eine Live-Prüfung belegt.
- **Im Code:** umgesetzt, aber nur durch Durchsicht belegt.
- **Offen:** fehlt, mit Grund.

## M1 Desktop retten (RET-A)

| Punkt | Status | Nachweis |
|---|---|---|
| RET-A1 Drei Einstiege, ein Ergebnis | Bestanden | Live geprüft am 9. Oktober: Kürzel ⌃⌥⌘R, Flyout und Menüleistenmenü, alle über `DesktopRescue.run()`. Der Bericht zeigt RetroMacs Icon und hat „Don't show this again“; eine Rettung mit Fehler oder fehlendem Recht zeigt ihn trotzdem. |
| RET-A2 Aufrollen + Theme-Wechsel + Rettung | Bestanden | Parken und Zurückholen laufen über eine serielle Warteschlange (`TitleBarOverlayController.axQueue`); `WindowShadeTests`. |
| RET-A3 Hängende App blockiert nichts | Im Code | Fenster-Sweep auf der AX-Warteschlange mit 0,5 s Zeitlimit; der Bericht steht unabhängig davon. |
| RET-A4 Abgezogener Monitor | Bestanden | `DesktopRescueTests.testAWindowLeftOnAnUnpluggedDisplayComesToTheNearestOne` |
| RET-A5 Ohne AX kein Vollerfolg | Bestanden | Ohne Recht meldet der Bericht „Windows were not checked: RetroMac has no Accessibility permission.“ als übersprungen. Ein Fenster, das nicht antwortet, gilt als fehlgeschlagen (`DesktopRescueTests.testTheReportLine`). |
| RET-A6 Recovery-Daten überleben | Bestanden | Ein Fenster, das sich nicht bewegen ließ, bleibt im Recovery-Datensatz (`remainingShadeRecords`); `WindowShadeTests`. |
| RET-A7 Zwei Aufrufe sind idempotent | Bestanden | Ein zweiter Aufruf zeigt den laufenden Bericht. Erreichbare Fenster bleiben stehen (`testAWindowOnScreenIsReachable`). |
| RET-A8 Nach Rettung bleibt alles aus | Im Code | `desktopRescuePending` sperrt beim Start Theme und Effekte, bis die Rettung zu Ende ist. Live geprüft im M1-Test. |

## M3 Solaris 8 — CDE

| Kriterium | Status | Nachweis |
|---|---|---|
| Referenzvergleich | Bestanden | Front Panel, Subpanel, Workspace Menu, File-Manager-Fenster und Panic-Bildschirm offscreen gerendert und neben die Toastytech-Screenshots gelegt. Messwerte im Steckbrief. |
| Dokumentierte Anpassungen | Bestanden | `docs/reference/com.retromac.sun.solaris8-cde.md`, Abschnitt „RetroMac-Anpassungen“ |
| CDE-01 … CDE-11 | Bestanden | Live geprüft: Panel, Subpanels mit Esc und Klick daneben, Workspace Menu, Fenstermenü, Icons minimierter Fenster, Application Manager, Widgets. |
| REF-01 eigene Installation | Offen | Es gibt keine Solaris-8-VM. Grundlage sind die sieben Toastytech-Screenshots. |
| Bootscreen (dtlogin), Cursor | Offen | Keine Vorlage geliefert |

## M4 QNX 6.2.1 — Photon

| Kriterium | Status | Nachweis |
|---|---|---|
| 6.2.1 bestätigt | Bestanden | „Version 6.2.1(NC)“ im Welcome-Fenster der Referenz |
| QNX-01 … QNX-05, QNX-07 … QNX-10 | Bestanden | Live geprüft: Shelf, Gruppen, Taskbar, Launch-Menü mit Kategorien, Desktop-Kontextmenü, World View, Maximieren, Titelleisten, Widgets. |
| QNX-06 Klick auf Task-Eintrag | Bestanden, mit Vorbehalt | Holt das Fenster nach vorn (live). Wie 6.2.1 auf einen zweiten Klick reagierte, ist nicht belegt; deshalb gibt es kein Minimieren. |
| REF-03 eigene Installation | Offen | Grundlage sind die zehn Toastytech-Screenshots. |
| Bootscreen, Crash-Ära, Cursor | Offen | Keine Vorlage geliefert |

## M5 Fensterwechsel (SW-A)

| Punkt | Status | Nachweis |
|---|---|---|
| SW-A1 Jedes Theme hat einen Eintrag | Bestanden | `WindowSwitcherTests.testEveryThemeHasAnEntry` |
| SW-A2 Kein Exposé für Cheetah, kein Alt-Tab-Panel für CDE | Bestanden | `testNothingAnEraDidNotHave` |
| SW-A3 App- und Fenstermodus | Entfällt vorerst | Erst mit den Windows-Panels |
| SW-A4 Esc ändert den Fokus nicht | Entfällt vorerst | Erst mit den Windows-Panels; der CDE-Zyklus hat kein Panel. |
| SW-A5 Geschlossenes Fenster während der Auswahl | Im Code | Der Zyklus prüft jedes Ziel beim WindowServer und lässt verschwundene aus. |
| SW-A6 Ohne Aufnahmerecht nutzbar | Bestanden | Kein Modus braucht Bildschirmaufnahme. |
| SW-A7 Keine Capture-Streams | Bestanden | Es gibt keine. |
| SW-A8 50 Fenster, zwei Displays, Skalierungen | Offen | Nicht geprüft |
| Windows 95 … XP Alt+Tab, Vista/7 Flip und Flip 3D | Offen | Abgeschaltet bis zu den Referenz-Screenshots (SW-02) |

## M2/M6 Icons (ICO-A)

| Punkt | Status | Nachweis |
|---|---|---|
| ICO-A1 Ein geliefertes Icon erscheint überall | Im Code | Alle Theme-Oberflächen fragen denselben Resolver. Maiks Lieferungen stecken jetzt in den Themes selbst (`iconMappings`), nicht in einem Paket; der Paket-Import bleibt für eigene Sammlungen. |
| ICO-A2 Kaputte Datei, funktionierende bleiben | Bestanden | `IconPackTests.testFaultsAreNamed`, `testAnImportKeepsWhatWorked`, `testImportThenDraw` |
| ICO-A3 Unbekannte App zeigt ihr Icon | Bestanden | `testImportThenDraw` |
| ICO-A4 1×/2×, kleine Icons, Transparenz | Bestanden | `testImportThenDraw` (32 und 64 Pixel in einem Bild), `testTheNearestSizeIsTaken`, Alphakanal ist Pflicht beim Import. |
| ICO-A5 Ohne Neustart, kein alter Cache | Bestanden | Paket-Revision im Cache-Schlüssel; der Import leert den Cache und zeichnet neu. |
| Bildabdeckung | Teilweise | 219 Icons aus Maiks Lieferungen in zehn Themes: 65 Originale, 121 KI-Stiladaptionen erst nach seiner Prüfseite, 3 nachgelieferte für Mac OS 9, 30 aus dem StudioTwentyEight-Set für BeOS. Herkunft je Theme in `icon-sources.json`. Lücken: `docs/ICON-GAPS.md` (Stand vor den Lieferungen, neu zu rechnen). |

## Release-Abnahme

| Punkt | Status |
|---|---|
| Neue Themes bedienbar, keine unmarkierten Platzhalter | Bestanden. Alle Grafiken stammen aus den Referenzen. Fehlendes (Bootscreen, Cursor) ist in den Steckbriefen benannt. |
| Detailwerte belegt oder als Anpassung benannt | Bestanden. Die Steckbriefe unter `docs/reference` stehen statt `deviations.md` (Entscheidung vom 5. Oktober). |
| Desktop retten über drei Einstiege | Bestanden (RET-A1, live) |
| Recovery-Daten gehen nicht verloren | Bestanden (RET-A6) |
| Nicht freigegebene Switcher sind aus | Bestanden (SW-02) |
| Icon-Lieferungen integriert, Fallback und Status | Bestanden: Infrastruktur und 219 Icons in zehn Themes |
| Migration von Themes, Kürzeln, Zuordnungen | Bestanden: `MigrationTests` (Einstellungen und Kürzel aus 2.8.8). Eigene Icons und Themes behalten ihre IDs. |
| Tests, Referenzvergleiche, Leistungsprotokoll | Bestanden: 286 Tests, Steckbriefe, `docs/PERFORMANCE-3.0.md` (Vergleichsmessung und M1-Kontrolllauf offen) |
| Release Notes nach neu, angepasst, Grenzen | Bestanden: CHANGELOG, Abschnitt 3.0 |

## Seit dem 6. Oktober dazugekommen

| Punkt | Status | Nachweis |
|---|---|---|
| Theme nur auf gewählten Spaces | Bestanden | Live geprüft am 9. Oktober auf zwei Spaces, ein Display: Theme-Fenster bleiben auf ihrem Space, auf dem anderen macOS-Dock, eigenes Bild, kein Flackern. `ThemeSpacesTests`. Zwei Displays nicht geprüft. |
| Hintergrundbild pro Space | Bestanden | Live geprüft: jeder Space bekommt sein Original zurück. `WallpaperSpacesTests`. |
| BeOS-Titelleisten | Bestanden | Live geprüft; Lasche danach etwas breiter. `TitleBarOverlayTests`. |
| Dock-Spiegelungen (Snow Leopard, Mountain Lion) | Bestanden | Live geprüft in Snow Leopard. `DockReflectionTests`. |
| Pac-Man | Bestanden | Live gestartet. Der Build bündelt SDL3 neben sdl2-compat; ein Release-Build bricht ab, wenn das Spiel fehlt oder Homebrew braucht. 2.8.8 hatte ein leeres Spiel ausgeliefert. |
| Amiga und IRIX ohne Mac-Menüleiste | Im Code | `hideMenuBarDefault` wie bei Windows |
| Settings: Reihenfolge, Shader-Tabs, „Favourite“, kleinerer Setup-Assistent | Im Code | Offscreen gerendert |
| Kein Neustart von Dock und Finder ohne Änderung | Bestanden | Live über die Spaces-Zeitleiste belegt; `SystemTweakHoldsTests` |
| Kein Log mehr auf dem Schreibtisch | Im Code | Nur mit About ▸ Diagnostics ▸ Debug logging, in das Diagnose-Log |

## Vor dem Release noch zu tun

1. SW-A8: Solaris-Zyklus mit vielen Fenstern auf zwei Displays; dabei Spaces mit zwei Displays.
2. Entscheiden, ob 3.0 ohne die Windows-Wechsler (Alt+Tab, Flip, Flip 3D), ohne Bootscreens, Crash-Szenen und Cursor von Solaris und QNX und ohne eigene Installationen (REF-01, REF-03) erscheint. Die Release Notes nennen das unter „Known limits“.
3. `./build.sh release` mit den neuen Pac-Man-Prüfungen, Notarisierung, `./appcast.sh --dry-run`.
4. Leistungsprotokoll: Vergleichsmessung PERF-02, Kontrolllauf auf einem M1.
5. Pushen (48 lokale Commits, Stand 9. Oktober).
