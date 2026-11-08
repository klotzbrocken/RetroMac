# Theme-Steckbrief: Mac OS X 10.6 Snow Leopard

`com.retromac.apple.snow-leopard` · Stand 8. November 2026

## Referenz

| Punkt | Wert | Status |
|---|---|---|
| Referenzversion | Mac OS X 10.6.8, das letzte Update (Juli 2011). Neue App-Icons und Verhalten werden gegen diesen Stand beurteilt. | Festgelegt |
| Handbuch | Apple, „Welcome to Snow Leopard“ (2009) [A1]. Seitenzahlen unten sind die gedruckten. | Dokumentiert |
| Apple-Menü | Zeile für Zeile nach 10.6 (seit 3.0.3) | Original bestätigt |

## Belegtes Verhalten

| Bereich | Original | In RetroMac |
|---|---|---|
| Stacks: Ansichten | „When you click a stack, the items in it appear in a grid, fan, or list.“ [A1, S. 7] | Fan, Grid, List und Automatic im Rechtsklick der Ordnerkachel |
| Stacks: Automatic | Fächer oder Raster „based on the number of items in the stack“ [A1, S. 9] | Fächer, solange alles über das Dock passt, sonst Raster |
| Stacks: Anpassen | Ansicht und Sortierung per Control-Klick auf die Kachel [A1, S. 9] | Sort by (Name, Date Added, Date Modified, Date Created, Kind), Display as (Folder, Stack), View content as |
| Exposé aus dem Dock | Klicken und halten auf ein App-Icon zeigt dessen Fenster [A1, S. 10] | Vorhanden |
| Exposé: Vorschau | Fenster markieren, Leertaste: Vorschau in voller Größe [A1, S. 10] | Leertaste auf der markierten Karte, Leertaste oder Esc zurück |

## RetroMac-eigene Werte (nicht gegen das Original gemessen)

- **Fächer:** Krümmung (0,7 pt × i² nach rechts), Icongröße 44–56 pt, Beschriftung links auf dunklem Etikett, „Open in Finder“ bzw. „N more in Finder“ als oberster Eintrag.
- **Raster:** bis 7 Spalten, scrollt, sobald es nicht mehr auf den Bildschirm passt. Ein Ordner öffnet sich im Raster selbst, mit Zurück-Pfeil oben links. Pakete wie Apps gelten als Datei.
- **Standardsortierung:** Applications nach Name, Downloads nach Date Added, andere Ordner nach Date Modified.
- **Exposé:** Pfeiltasten wählen die nächste Karte in der Richtung, Return holt das Fenster nach vorn. Minimierte Fenster stehen in der App-Ansicht in einer eigenen Reihe unter einer Haarlinie. Sie brauchen die Bedienungshilfen-Freigabe, ohne sie fehlen sie wie bisher.
- **Schreibtisch:** TV, Uhr, CPU, Bildschirmschoner, Dashboard und Exposé sind RetroMac-Werkzeuge, kein 10.6-Standardschreibtisch.

## Icons

- `missioncontrol.png` zeigt das Exposé-Icon von 10.5/10.6: vier Fenster auf dunklem Grund, eines mit dem Frosch, ohne die Leiste der Schreibtische, die Mission Control ab 10.7 hat. Nur der Dateiname ist jünger.

## Offen

- Spaces-Übersicht (Raster der Arbeitsflächen). Ansehen ginge, Fenster zwischen echten Spaces verschieben nur über private Schnittstellen.
- Finder mit Cover Flow und Spotlight im Look von 10.6, wenn überhaupt, als eigene App.
- Dashboard-Widgets gegen das Original abgleichen (Gehäuse, Rückseiten, Animation).

## Quellen

- [A1] Apple: „Welcome to Snow Leopard“, 2009. https://media.512pixels.net/downloads/OS-X-docs/10-6/Welcome%20to%20Snow%20Leopard.pdf
