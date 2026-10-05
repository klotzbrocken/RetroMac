# Theme-Steckbrief: QNX 6.2.1 — Photon

`com.retromac.qnx.qnx621-photon` · Lastenheft 3.0, Abschnitt 6 · Stand 5. Oktober 2026

## Referenz

| Punkt | Wert | Status |
|---|---|---|
| System | QNX Neutrino 6.2.1 (NC), Photon. Gelesen im Welcome-Fenster von `qnx621about2.png`: „Version 6.2.1(NC)“. Gebootet von der Non-Commercial-CD. | Original bestätigt |
| Herkunft | Zehn Screenshots aus der GUI Gallery von Toastytech, „QNX 6.2.1“ [T1], von Maik geliefert (`~/Downloads/QNX621/qnx621*.png`) | Original bestätigt |
| Auflösung | 800 × 600, verlustfreie PNG | Original bestätigt |
| Hintergrund | Toastytech hat das Standard-Hintergrundbild weggelassen, um die Dateien klein zu halten [T1]. Die einfarbige Fläche #7979A7 ist also nicht das Original-Wallpaper. | Abweichung |
| Eigene Installation | REF-03: Installationsmedium und Patches einer eigenen 6.2.1-Installation sind noch zu dokumentieren. Bis dahin gelten diese Screenshots. | Offen |

## Messwerte (Referenzpixel = Punkte)

| Komponente | Wert | Quelle |
|---|---|---|
| Panel-Rahmen | 6 pt auf der offenen Seite: #4B4B4B, weiß, 2 × #D8D8D8, #A6A6A6, #4B4B4B. Gleich bei Shelf (links) und Taskbar (oben). | `qnx621fileman.png` |
| Shelf | 135 pt breit (Rahmen 6 pt, Inhalt 129 pt), von oben bis auf die Uhr | dto. |
| Gruppenkopf | 19 pt, #DBDBDB, Kante weiß / #A9A9A9, ±-Kästchen 15 pt in #C7C7C7 mit #606060, Titel fett bei x 20 | `qnx621shelf.png` |
| Shelf-Eintrag | 25 pt, #D9D9D9, Kante weiß / #A7A7A7, Icon-Feld 28 pt in #CCCCCC, Text bei x 34 | dto. |
| System Monitor | 62 pt. Balkenkästen x 23 … 125: CPU und Speicher 16 pt, darunter zwei dünne zu 7 pt. Kasten #4B4B4B, Schatten #8D8D8D, leer #BCBCBC, Füllung #B5C4B0 mit Kanten #DDECD8 / #8D9C88. | dto. |
| Taskbar | 31 pt: Rahmen 6 pt, darunter 25 pt. Launch-Knopf 80 pt, Task-Einträge 123 pt im Abstand 126 pt ab x 83, Mulde #C0C0C0, Uhr 105 pt rechts. | `qnx621fileman.png`, `qnx621calc.png` |
| Aktiver Task-Eintrag | #F9F4E4 mit 1 pt schwarzem Rand; inaktive erhaben in #D9D9D9 | dto. |
| Uhr | „Sun-11 05:45PM“: Wochentag-Tag Stunde:Minute AM/PM | dto. |
| Titelleiste | Außen schwarz, #3F3F3F, dann 19 pt: Lichtlinie #8EBDFF, #5C8BDF, Rille #2A59AD, Verlauf #6695E9 → #4776CA, Linie #2A59AD. Titel #000065, zentriert. Inaktiv: #E3F3FF, #B1C1D9, #7F8FA7, Verlauf #B7C7DF → #A5B5CD. | File Manager, Rechner |
| Fensterknöpfe | Menükasten links; rechts Minimieren und Maximieren zusammen, Schließen abgesetzt (Quadrat im Quadrat) | File Manager, Welcome |
| Fensterrahmen | 5 pt: außen schwarz und #3F3F3F, innen weiß / #D9D9D9 oben links, #9D9D9D unten rechts | File Manager |
| Launch-Menü | Je Abschnitt ein Kasten: schwarz, #F1F1F1, 3 pt #D8D8D8. Balken 17 pt mit 2 pt Abstand, #CCCCCC. Hover #9BA9C9, Eintrag mit offener Kaskade #B3B3B3. Abschnittswechsel 7 pt. Text bei 37 pt, Icon 16 pt bei 12 pt. Kaskade bündig mit ihrem Eintrag. | `qnx621about2.png` |
| Schrift | Lucida Grande statt der Photon-Bitmapschrift: Einträge 12 pt, Gruppenköpfe fett 12 pt, Uhr 11 pt. Breiten nachgemessen („File Manager“ 72 pt, „Applications“ fett 79 pt). | Shelf |

## Assets und Herkunft

| Datei | Herkunft |
|---|---|
| `icons/qnx_<eintrag>.png` | Icon-Felder der Shelf (28 × 23), #CCCCCC transparent. Applications und Configure aus `qnx621shelf.png`, Utilities aus `qnx621calc.png`. |
| `icons/qnx_mon_*.png` | System-Monitor-Icons aus `qnx621shelf.png` |
| `icons/qnx_launch.png` | Launch-Knopf aus `qnx621fileman.png` |
| `icons/qnx_cdplayer.png`, `icons/qnx_worldview.png` | Inhalt der Gruppen CD Player und World View aus `qnx621exit.png` |
| `appIcon.png` | Die beiden Münzen aus dem Welcome-Fenster (`qnx621about2.png`) |
| `preview.jpg` | `qnx621fileman.png`, verkleinert |

## RetroMac-Anpassungen

- **Shelf (QNX-03, QNX-07):** Jeder Starter öffnet ein echtes Mac-Ziel: Voyager den Standardbrowser, Editor TextEdit, File Manager den Home-Ordner, Installer den App Store, Help die Tipps-App, Welcome die Theme-Readme. Configure öffnet die passenden Systemeinstellungen, „Shelf“ die RetroMac-Einstellungen. Utilities: Find... öffnet vorerst den Home-Ordner, Report Bug die RetroMac-Issues, Connect... die Netzwerkeinstellungen. Der Dialer fehlt, weil kein Modem zu wählen ist.
- **Auf- und Zuklappen (QNX-03):** Der Zustand der Gruppen wird gespeichert. Anfangs sind Utilities, CD Player und World View zu, wie beim ersten Start von 6.2.1.
- **Platz (QNX-04):** Das Original schnitt die Shelf unten ab. In RetroMac lässt sie sich mit dem Mausrad scrollen, damit jeder Eintrag erreichbar bleibt.
- **System Monitor (QNX-08):** CPU und Speicher echt, die zwei dünnen Balken zeigen Swap und zugesagten Speicher. Erfasst wird einmal pro Sekunde und nur, solange die Shelf sichtbar und die Gruppe offen ist.
- **CD Player:** zeigt das Original-Bedienfeld. Ein Klick öffnet die Musik-App, denn RetroMac steuert keine CD.
- **World View (QNX-09):** öffnet Mission Control. Neun Arbeitsflächen werden nicht nachgebaut (TH-12).
- **Taskbar (QNX-02, QNX-06):** ein Eintrag pro Fenster, wie bei Photon. Ein Klick holt das Fenster nach vorn oder aus dem Dock zurück. Die Uhr öffnet die Datums- und Uhrzeiteinstellungen.
- **Launch-Menü (QNX-05):** MultiMedia, Editors, Utilities, Internet und Development enthalten die installierten Apps nach ihrer App-Store-Kategorie. Apps, die Webseiten oder Mail öffnen, zählen zu Internet. Configure ist dieselbe Liste wie in der Shelf. „End Photon session“, die erste Wahl aus Photons Shutdown-Dialog, schaltet das Theme ab.
- **Fenstermenü-Kasten:** schließt mit einem Klick, wie bei den übrigen Fenster-Themes.
- **Maximieren:** Fenster bleiben links der Shelf und über der Taskbar.

## Offen für die nächsten Runden

- Desktop-Kontextmenü mit denselben Zielen wie Launch (QNX-05).
- Kategorien des Launch-Menüs einstellbar machen (QNX-05).
- Widget-Stile (Uhr, Rechner, Notepad, CPU-Monitor), Application-Menü-Fenster, Crash-Ära, Bootscreen, Cursor.
- Klickverhalten auf den aktiven Task-Eintrag (QNX-06) an einer eigenen 6.2.1-Installation prüfen.
- Alt+Tab (SW): erst mit 6.2.1-Nachweis.

## Quellen

- [T1] Toastytech GUI Gallery, „QNX 6.2.1“, http://toastytech.com/guis/qnx621.html
