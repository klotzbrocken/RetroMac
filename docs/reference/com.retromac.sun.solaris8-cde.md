# Theme-Steckbrief: Solaris 8 — CDE

`com.retromac.sun.solaris8-cde` · Lastenheft 3.0, Abschnitt 5 · Stand 5. Oktober 2026

## Referenz

| Punkt | Wert | Status |
|---|---|---|
| System | SunOS 5.8 „Generic February 2000“ (Solaris 8, Erstausgabe 2/00). Gelesen im Console-Fenster von `solcdeshutdown.png`. | Original bestätigt |
| Desktop | CDE mit dtwm, Standardpalette (mauve/grau), Backdrop „Solaris“ | Original bestätigt |
| Sprache | Englisch | Original bestätigt |
| Auflösung | 1024 × 768, verlustfreie PNG | Original bestätigt |
| Herkunft | Sieben Screenshots, von Maik geliefert (`~/Downloads/Solaris/solcde*.png`). Ihre ursprüngliche Quelle ist noch nachzutragen. | Offen |
| Handbuch | Solaris CDE User's Guide 806-1360 [S1–S3] | Dokumentiert |

Eine eigene VM-Installation (REF-01) steht noch aus. Bis dahin gelten diese Screenshots als optische Referenz.

## Messwerte (Referenzpixel = Punkte)

| Komponente | Wert | Quelle |
|---|---|---|
| Front Panel | 956 × 86, unten bündig, x 28–983 bei 1024 Breite | `solcdeshutdown.png` |
| Panel-Zellen | Pfeilleiste y 4–18, Icons y 20–80. Zellen links x 26–84, 86–142, 144–200, 202–258, 260–313. Rechts x 642–697, 699–753, 755–813, 815–871, 873–929. | dto. |
| Arbeitsflächen-Feld | x 314–641 (Schloss, One–Four, Busy-Globus, EXIT) | dto. |
| Uhr | Live, Nabe bei (55, 50). Zeiger #FF1042, 4 pt breit, mit weißer Mittellinie, Länge 13 bzw. 20. | Vier Screens mit verschiedenen Uhrzeiten |
| Kalender | Blatt bei (95, 27), 36 × 45. Monat und Tag live, zentriert auf x 113. | `solcdeshutdown.png` |
| cpu/disk | Balken #5252FF, 3 pt hoch, y 60. cpu x 760 (max. 17), disk x 785 (max. 23). | dto. |
| Farben | Desktop #524A8C, Panel #ADB5C6, Kanten hell #DEDEE7 / dunkel #5A636B, Textfelder #FFF7EF | dto. |
| Fenster aktiv | Fläche #B54A7B, hell #DEADC6, dunkel #522139, Titel weiß | Console-Fenster |
| Fenster inaktiv | Fläche #ADB5C6, hell #DEDEE7, dunkel #5A636B, Titel schwarz | Style-Manager-Fenster |
| Titelleiste | 1 pt Kante plus 19 pt Leiste. Menü-, Minimier- und Maximierknopf je 19 × 19. Rahmen 5 pt. | Console-Fenster |
| Subpanel | Breite 208. Titel 15 pt plus 2 pt Kante, Install-Icon-Zeile 50 pt mit eingeprägter Linie, Einträge 45 pt flach. Schrift weiß mit dunklem Schatten. | Help-Subpanel `solcdehelp.png` |
| Backdrop | Kachel 113 × 88, Ursprung am Bildschirmrand oben links | Autokorrelation über `solcdeshutdown.png` |

## Assets und Herkunft

Alle Bilder stammen aus den gelieferten Screenshots, unverändert in Pixeln und Farben. Die Panelfarbe #ADB5C6 wird transparent, so wie CDE seine Icons maskiert. Der Nutzungsstatus ist „ungeprüft“ (ASSET-01): Es sind Sun-Grafiken, verwendet wie bei den übrigen historischen Themes.

| Datei | Herkunft |
|---|---|
| `icons/cde_frontpanel.png` | Panel aus `solcdeshutdown.png`. Darin ersetzt: Uhr-Globus ohne Zeiger, Kalenderblatt ohne Text, cpu-Balken entfernt. |
| `icons/cde_clock.png` | Globus, pixelweise aus den sieben Screens zusammengesetzt (Zeigerpixel verworfen) |
| `icons/cde_*.png` | Panel-Icons aus `solcdeshutdown.png` |
| `icons/sp_*.png` | Subpanel-Icons aus `solcdegeneral.png` (Links, Cards, Mail) und `solcdehelp.png` (Help) |
| `wallpaper.png` | Backdrop-Kachel aus `solcdeshutdown.png` (x 0, y 528) |

## RetroMac-Anpassungen

- **Arbeitsflächen (TH-12):** Das Feld One–Four ist eine einzige Schaltfläche und öffnet Mission Control. Die vier Namen bleiben sichtbar, sind aber keine einzelnen Ziele.
- **EXIT (CDE-11):** schaltet das Theme ab, nicht die Sitzung.
- **Schloss:** startet den Bildschirmschoner. macOS hat keinen öffentlichen Aufruf zum Sofortsperren.
- **Uhr:** öffnet die Clock-App bzw. RetroMacs Uhr-Widget.
- **Kalender:** öffnet Kalender.
- **Dateien:** öffnet den Home-Ordner im Finder.
- **Text Editor:** öffnet TextEdit.
- **Mail:** öffnet das Standard-Mailprogramm.
- **Drucker:** öffnet „Drucker & Scanner“.
- **Style Manager:** öffnet die Einstellungen zum Erscheinungsbild.
- **Performance Meter:** öffnet die Aktivitätsanzeige.
- **Hilfe:** zeigt die Theme-Readme.
- **Papierkorb:** öffnet den Papierkorb.
- **disk-Balken:** zeigt die Belegung des Startvolumes. Solaris zeigte Plattenaktivität.
- **Drop-Zonen (CDE-06):** nur zwei. Der Papierkorb legt Dateien in den macOS-Papierkorb, „Install Icon“ nimmt Apps auf. Andere Ziele nehmen nichts an.
- **Schrift:** Lucida Grande statt der Sun-Bitmap-Lucida. Sie rendert etwas kräftiger, weil macOS glättet.
- **Fensterrahmen:** Der 5-pt-Rahmen kennt das aktive Fenster nicht und trägt immer die inaktiven Farben. Die Titelleiste zeigt den aktiven Zustand.
- **Fenstermenü-Knopf:** schließt mit einem Klick. dtwm öffnete beim Klick das Fenstermenü und schloss erst beim Doppelklick.
- **Bildschirmschoner:** keiner. RetroMac hat keinen der CDE-Schoner (Swarm, Worms …).

## Offen für die nächsten Runden

- **CDE-04:** Anwendungen-Fenster (Application Manager) im CDE-Stil. Bis dahin öffnet es den Programme-Ordner.
- **CDE-09:** Desktop-Kontextmenü als Workspace Menu.
- **CDE-10:** minimierte Fenster als Desktop-Icons.
- Fenstermenü statt Ein-Klick-Schließen.
- Widget-Stile `cde` für Uhr, Rechner, Notepad, CPU-Monitor und AppFolder; WebApp-Chrome.
- Crash-Ära (Solaris), Bootscreen (dtlogin), Cursor (X11-Cursorfont).
- `minAppVersion: "3.0"` (ARC-03): wird gesetzt, wenn die App-Version auf 3.0 geht. Vorher würde das Theme im 2.8.x-Build nicht laden.
