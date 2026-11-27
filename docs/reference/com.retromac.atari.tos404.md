# Theme-Steckbrief: Atari TOS 4.04

`com.retromac.atari.tos404` · Lastenheft „Atari TOS 4.04 für RetroMac“ (26. November 2026) · Stand 26. November 2026, erste Runde (P1-Kern)

## Referenz

| Punkt | Wert | Status |
|---|---|---|
| System | TOS 4.04, Falcon030, farbiger GEM-Desktop | Original bestätigt |
| Herkunft | Maiks Aufnahmen `~/Downloads/Tos404/tos404-multilingual-08-03-1993_2.png` … `_7.png` (640 × 480, 1:1) und `TOS_4.04.png` (1280 × 950, 2 × 2 vergrößert) | Original bestätigt |
| Icons | DESKICON.RSC der Falcon030 Language Disk 1 UK Rev. G, als PNG in `RetroMac-Audit-2026-11-14/tos404-assets/falcon-language-disk` | Original, Rechte für Weitergabe offen |
| Hintergrund | #9EBEFF (Bildserie). Türkis #00AAA9 aus `TOS_4.04.png` ist eine andere Konfiguration. | Gesetzt |
| Theme-ID, Mindestversion | `com.retromac.atari.tos404`, `minAppVersion: "3.0"` | Gesetzt |

## Messwerte (Referenzpixel = Punkte)

| Komponente | Wert | Quelle |
|---|---|---|
| Menüleiste | 18 Zeilen weiß, Zeile 18 schwarz, zusammen 19 pt. Titel je mit einem Leerzeichen davor und danach ab x 16: „ Desk “ 16 … 63, Inversion 17 … 62, Zeilen 1 … 17. | `_2.png` |
| Pulldown | Linke Kante 1 pt links vom Titel, oberer Rand auf der Leistenlinie, 1 pt schwarzer Rand, kein Schatten. Zeilen 16 pt, Text 17 pt eingerückt (zwei Zeichen), Häkchen im ersten Zeichen. Breite längster Eintrag + 5 Zeichen (View: 25 Zeichen). Gewählte Zeile schwarz invertiert, Trenner eine gedimmte Strichzeile. | `_3.png` |
| Desktop-Raster | Zellen 80 × 51 ab Unterkante der Leiste. Icon 32 × 32 bei x + 20, Etikett 72 × 8 weiß darunter, Kleinschrift 6 × 6 zentriert. Ausgewählt: Etikett schwarz, Schrift weiß, Auswahlbild des Icons. | `_2.png`, `TOS_4.04.png` |
| Laufwerksbuchstabe | Kleinschrift schwarz bei Icon + (13, 19) | APPS in `_2.png` |
| Fenster | 1 pt schwarze Linien zwischen allen Elementen; Gadgets erhaben (#CFCFCF, weiß oben links, #B2B2B2 unten rechts); Infozeile weiß; Schieberbahn 50 % schwarz gerastert; inaktive Beschriftung weiß | `_3.png` |
| Dialog | Außen 1 pt #CFCFCF und 2 pt weiß oben links, 3 pt #B2B2B2 unten rechts, dann 3 pt schwarz, Fläche #CFCFCF. Standardknopf 3 pt schwarz, Knopf 74 × 26. | Desktop Info in `_2.png` |
| Schrift | PxPlus IBM VGA 8 × 16 (VileR, CC BY-SA 4.0) statt des Falcon-Systemfonts; gleiche Zelle. Kleinschrift: Buchstaben der Etiketten aus `_2.png` abgelesen, fehlende Zeichen im selben Raster ergänzt. | |

## Assets und Herkunft

| Datei | Herkunft |
|---|---|
| `icons/gem_disk*.png` | RSC-Index 11 (HARD DISK), normal und Auswahl |
| `icons/gem_trash*.png`, `gem_trash_full*.png` | RSC-Index 02 und 22 |
| `icons/gem_program*.png` | RSC-Index 03, Programmsymbol für jede App ohne eigenes Motiv |
| `icons/gem_floppy*.png`, `gem_games*.png`, `gem_tools*.png`, `gem_folder*.png`, `gem_pencil*.png`, `gem_paint*.png`, `gem_text*.png` | RSC-Index 09, 23, 24, 32, 28, 26 und 04: FLOPPY DISK A, GAMES und die Programmspalte rechts (TextEdit, Vorschau, Dokumente, Dienstprogramme, README) nach `_2.png` |
| `icons/<motiv>.png`, `<motiv>_sel.png` | 20 neu gezeichnete App-Motive (`tos404-assets/app-icons`), Zuordnung nach `Zuordnung.csv` |
| `appIcon.png` | RSC-Index 10 (TOS-Datei), vierfach ohne Glättung |
| Atari-Zeichen in Desktop Info | Bitmap aus `_2.png` abgelesen |

## Bewusst offen (spätere Runden)

Mauszeiger und Biene, Startsequenz, Titelleisten für echte Mac-Fenster, Desktop Configuration und Video-Dialoge, MultiTOS. Widgets tragen vorerst die System-6-Möblierung.
