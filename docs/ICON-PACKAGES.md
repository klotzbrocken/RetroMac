# Icon-Pakete liefern

Historische Icons für moderne Apps (Lastenheft 3.0, Abschnitt 9). Du lieferst die Bilder, RetroMac prüft sie beim Import und zeigt sie an (ICO-01). Importiert wird unter **Settings ▸ Dock ▸ Historic icons ▸ Import…**, jeweils für das gerade gewählte Theme.

## Aufbau

Ein Paket ist ein Ordner pro Theme mit einer `icons.json` und den PNG-Dateien:

```
Solaris-Icons/
  icons.json
  claude-32.png
  claude-32@2x.png
  word-16.png
```

```json
{
  "format": 1,
  "themeID": "com.retromac.sun.solaris8-cde",
  "source": "Maik Klotz",
  "icons": [
    {
      "appID": "claude",
      "bundleIDs": ["com.anthropic.claudefordesktop"],
      "kind": "era-adaptation",
      "referenceVersion": "Stiladaption",
      "usageStatus": "released",
      "variants": [
        { "file": "claude-32.png", "size": 32, "scale": 1 },
        { "file": "claude-32@2x.png", "size": 32, "scale": 2 }
      ]
    }
  ]
}
```

| Feld | Inhalt |
|---|---|
| `themeID` | Die Theme-ID, zum Beispiel `com.retromac.qnx.neutrino621-photon`. Sie steht in der `theme.json` des Themes. |
| `appID` | Ein kurzer, fester Name für die App. Die Namen aus `Resources/IconCatalog.json` verwenden. |
| `bundleIDs` | Genaue Bundle-IDs, keine App-Namen (ICO-08). Der Katalog nennt sie; `verified` sind die auf einem echten Mac geprüften. |
| `kind` | `historical-original` für das echte Icon aus der Epoche, `era-adaptation` für eine moderne App im alten Stil (ICO-02) |
| `referenceVersion` | Bei Originalen die Version, zum Beispiel „Mac OS 9.2“. Bei Adaptionen „Stiladaption“, sonst lehnt der Import ab. |
| `usageStatus` | `released`, `unchecked` oder `not-for-release`. Letztere werden geprüft, aber nicht verwendet. |
| `variants` | Je Datei die logische Größe in Punkt und den Maßstab 1 oder 2. Eine 32-pt-Datei mit Maßstab 2 hat 64 × 64 Pixel. |

Die Prüfsumme berechnet RetroMac selbst.

## Was der Import prüft

- Jede Datei ist ein PNG mit Alphakanal und hat genau die angegebene Pixelgröße.
- Kein Pfad verlässt den Ordner.
- Jede Bundle-ID gehört zu genau einer App im Paket.
- Eine Adaption gibt sich nicht als Original aus.

Fehlerhafte Einträge werden mit Grund gemeldet. Hatte die App schon ein funktionierendes Icon, bleibt es (ICO-A2). Gute Einträge ersetzen den alten Stand der jeweiligen App.

## Größen

Lieber mehrere native Größen liefern als eine große (ICO-06). RetroMac nimmt die passende logische Größe, sonst die nächstgrößere. Ein 48-pt-Bild wird nicht auf 16 pt verkleinert, wenn es ein 16-pt-Bild gibt.

## Reihenfolge

Für jede Stelle (Dock, Taskbar, Shelf, Front Panel, Listen, Wechsler) gilt (ICO-07):

1. dein eigenes Icon für dieses Theme
2. das Icon-Paket
3. die Zuordnung des Themes selbst
4. das echte Icon der App
5. ein allgemeines App-Icon

Eine App ohne Icon im Paket zeigt also ihr echtes Icon, nie ein fremdes Ersatzlogo (ICO-A3).

Es gilt überall, wo ein Theme Apps zeigt (ICO-09):

- Dock und Taskbars (auch laufende Apps und Fenster-Einträge)
- Win-3.1-Task-Icons, BeOS-Deskbar und NeXT-Kacheln
- CDE-Subpanels und Icons minimierter Fenster
- Photon-Taskbar und Launch-Menü
- Apple-Menü, Programm-Menü und Fenster-Titelleisten
- Application Manager, App-Ordner und Exposé

Oberflächen, die sonst nur Theme-Bilder zeigen (Win 3.1, klassische Mac-Menüs), nehmen ein Paket-Icon genauso wie eine Theme-Zuordnung.

Nicht betroffen sind die RetroMac-Einstellungen. Dort zeigen die App-Listen das echte Icon, damit du beim Zuordnen die App erkennst.
