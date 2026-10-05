# Theme-Steckbrief: Solaris 8 — CDE

`com.retromac.sun.solaris8-cde` · Lastenheft 3.0, Abschnitt 5 · Stand 5. Oktober 2026

## Referenz

| Punkt | Wert | Status |
|---|---|---|
| System | SunOS 5.8 „Generic February 2000“ (Solaris 8, Erstausgabe 2/00). Gelesen im Console-Fenster von `solcdeshutdown.png`. | Original bestätigt |
| Desktop | CDE mit dtwm, Standardpalette (mauve/grau), Backdrop „Solaris“ | Original bestätigt |
| Sprache | Englisch | Original bestätigt |
| Auflösung | 1024 × 768, verlustfreie PNG | Original bestätigt |
| Herkunft | Sieben Screenshots aus der GUI Gallery von Toastytech, „Solaris 8 CDE and OpenWindows“ [T1]: `solcde*.png`, von Maik geliefert. Die Seite beschreibt dazu das Verhalten von Subpanels, Fenstermenü, Icons und Workspace-Menü. | Original bestätigt |
| Handbuch | Solaris CDE User's Guide 806-1360 [S1–S3] | Dokumentiert |
| Version | SunOS 5.8 = Solaris 8, erschienen 2000, letztes Update 2/04 [W1] | Dokumentiert |

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
| Menüs | 1-pt-Kante, Titel 20 pt über Doppellinie (2 × 1 pt schwarz), Zeilen 21 pt, mit 16-pt-Icon 23 pt, Trenner 2 pt geätzt. Aktive Zeile eingesenkt, #9494A5. Kaskade 4 pt unter ihrer Zeile, 2 pt überlappend. Schrift Lucida Grande 14 (Titel 115 pt breit wie im Original). | Workspace Menu in `solcdegeneral.png` |
| File-Manager-Fenster | Rahmen 5 pt (2 pt Kante außen, 2 pt Fläche, 1 pt innen), Titelleiste 19 pt, Menüleiste 27 pt (File, Selected, View, Help), Pfadzeile 57 pt mit Ordnern im Abstand Icon + 17 pt Linie, Pfadfeld 31 pt, Ansicht eingesenkt in #9494A5 mit 2-pt-Kante, Raster 83 × 61 pt, Auswahl als 2-pt-Rahmen #B54A7B, Statuszeile 20 pt („N Items“). | `solcdefileman.png` |
| Icons minimierter Fenster | Bild-Box 60 × 59, 2-pt-Kante, geätzter Rahmen 4 pt innen, Bild 48 × 48. Label-Box 20 pt darunter, Text abgeschnitten („Calcula“). Raster 85 pt ab (2, 4) oben links. | `solcdegeneral.png`, `solcdefileman.png` |

## Assets und Herkunft

Alle Bilder stammen aus den gelieferten Screenshots, unverändert in Pixeln und Farben. Die Panelfarbe #ADB5C6 wird transparent, so wie CDE seine Icons maskiert. Der Nutzungsstatus ist „ungeprüft“ (ASSET-01): Es sind Sun-Grafiken, verwendet wie bei den übrigen historischen Themes.

| Datei | Herkunft |
|---|---|
| `icons/cde_frontpanel.png` | Panel aus `solcdeshutdown.png`. Darin ersetzt: Uhr-Globus ohne Zeiger, Kalenderblatt ohne Text, cpu-Balken entfernt. |
| `icons/cde_clock.png` | Globus, pixelweise aus den sieben Screens zusammengesetzt (Zeigerpixel verworfen) |
| `icons/cde_*.png` | Panel-Icons aus `solcdeshutdown.png` |
| `icons/sp_*.png` | Subpanel-Icons aus `solcdegeneral.png` (Links, Cards, Mail) und `solcdehelp.png` (Help) |
| `wallpaper.png` | Backdrop-Kachel aus `solcdeshutdown.png` (x 0, y 528) |
| `icons/cde_folder.png`, `icons/cde_goup.png` | Ordner und „..(go up)“ aus der Ansicht in `solcdefileman.png` |
| `icons/mi_*.png` | 16-pt-Menü-Icons aus dem Workspace Menu und seiner Kaskade „Applications“ in `solcdegeneral.png` |

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
- **Fenstermenü (CDE-08):** wie bei dtwm. Ein Klick auf den Kasten öffnet es, ein Doppelklick schließt das Fenster. Restore, Minimize, Maximize und Close wirken. Move, Size, Lower und die Workspace-Einträge bleiben grau: macOS bietet sie für fremde Fenster nicht an. Die Tastenkürzel (Alt+F4 …) fehlen, weil sie nicht wirken würden.
- **Workspace Menu (CDE-09):** Rechtsklick auf den Desktop. Die Kaskaden zeigen die Inhalte der Subpanels, wie CDE sie aus dem Front Panel baute. „Applications“ folgt der Solaris-Liste mit Mac-Gegenstücken: Image Viewer → Vorschau, Snapshot → Bildschirmfoto, Text Note → Notizzettel, Voice Note → Sprachmemos. Einträge ohne installierte App fehlen; das Icon Editor fehlt immer. „Add Item to Menu“ und „Customize Menu“ werden zu „RetroMac Settings...“. „Log out...“ heißt „Exit Theme...“ und beendet das Theme (CDE-11). „Windows“ enthält Mission Control, „Restore All Icons“ und „Minimize/Restore Front Panel“. Ein minimiertes Front Panel wird nicht zum Icon, sondern ausgeblendet.
- **Icons minimierter Fenster (CDE-10):** ein Klick öffnet das Fenstermenü, ein Doppelklick stellt das Fenster wieder her. Ohne Bedienungshilfen-Recht zeigt RetroMac ausgeblendete Apps statt Fenster (das Verhalten des Fenster-Trackers). Das Bild ist das Theme-Icon der App, sonst ihr eigenes. Der Desktop übernimmt wie bei den anderen Themes mit Desktop-Icons die Klicks auf die freie Fläche.
- **Application Manager (CDE-04):** Er zeigt die Mac-Apps in Gruppen nach Solaris-Art, die sich aus der App-Store-Kategorie der App ergeben: Desktop_Apps (auch ohne Kategorie), Desktop_Tools, Developer_Tools, Graphics, Audio_Video, Information, Games. „All_Applications“ listet alle Apps. Leere Gruppen fehlen. Das Fenster ist das File-Manager-Fenster mit Pfad als Ordnerzeile und Text. Der Pfad „/Applications/Desktop_Tools“ ist virtuell. Solaris hatte /var/dt/appconfig/appmanager. Geöffnet wird er aus dem Workspace Menu und dem Applications-Subpanel. Minimieren blendet das Fenster aus.
- **Widgets (Uhr, Rechner, Notepad, CPU-Monitor):** Sie tragen den dtwm-Rahmen mit Mauve-Titelleiste, Menükasten links, grauen Motif-Flächen und Textfeldern in #FFF7EF. Innen behalten sie ihren Aufbau aus dem Windows-98-Stil (Menüleiste, Tasten des Rechners), weil Solaris für diese RetroMac-Widgets kein Vorbild hat. Der Menükasten schließt das Widget mit einem Klick; das volle Fenstermenü haben echte Fenster und der Application Manager.
- **Subpanels:** Laut Toastytech blieben sie offen, bis man den Pfeil erneut klickte. RetroMac schließt sie zusätzlich mit Esc und mit einem Klick daneben, wie CDE-02 verlangt.
- **Bildschirmschoner:** keiner. RetroMac hat keinen der CDE-Schoner (Swarm, Worms …).

## Offen für die nächsten Runden

- WebApp-Chrome.
- Crash-Ära (Solaris), Bootscreen (dtlogin), Cursor (X11-Cursorfont).
- `minAppVersion: "3.0"` (ARC-03): wird gesetzt, wenn die App-Version auf 3.0 geht. Vorher würde das Theme im 2.8.x-Build nicht laden.

## Quellen

- [T1] Toastytech GUI Gallery, „Solaris 8 CDE and OpenWindows“, http://toastytech.com/guis/sol.html und sol2.html
- [W1] Wikipedia, „Solaris (Betriebssystem)“, https://de.wikipedia.org/wiki/Solaris_(Betriebssystem)
