# Leistungsprotokoll RetroMac 3.0

Lastenheft 3.0, Abschnitt 12. Stand 6. Oktober 2026, Build 3.0 (Debug, `RetroMac Dev`).

## Referenz-Mac (PERF-01)

| Punkt | Wert |
|---|---|
| Rechner | MacBook Air (Mac17,3), Apple M5, 10 Kerne, 24 GB |
| System | macOS 27.2 (26B5091g) |
| Anzeige | eingebautes Liquid-Retina-Display 2560 × 1664 (Retina). Ein externer 1920 × 1080 war zeitweise angeschlossen. |
| Fenster | 21 auf dem Bildschirm (Ebene 0) während der Leerlaufmessung |
| Konfiguration | Theme QNX 6.2.1 — Photon aktiv, Titelleisten an, Shader aus, Bedienungshilfen erteilt. Nebenher normale Arbeit (Browser, Office, Claude). |

## Messungen

| Ziel | Messung | Ergebnis | Bewertung |
|---|---|---|---|
| PERF-02 Leerlauf | Arbeit eines Sekundentakts (Werte holen, ganze Fläche neu zeichnen), Mittel aus 30 Läufen, `PerformanceTests.testIdleCostOfTheNewSurfaces` | QNX-Shelf 1,06 ms je Sekunde = 0,11 % eines Kerns. CDE Front Panel 0,66 ms = 0,07 %. | Bestanden (Grenze 1 Prozentpunkt) |
| PERF-02 Gesamtprozess | `ps` alle 5 s über 5 min, ganzer RetroMac-Prozess mit QNX, bei laufender Arbeit | CPU im Mittel 1,95 %, Median 1,8 %, Spitze 4,8 % eines Kerns. Speicher 73 … 83 MB, ohne Anstieg. | Obergrenze; enthält Titelleisten, Fenster-Tracker und Dock |
| PERF-04 Menüs | p95 aus 30 warmen Läufen: Liste bauen und ersten Rahmen zeichnen, `testMenusOpenWithin100ms` | Photon-Launch-Menü 2,7 … 4,0 ms, CDE-Workspace-Menü 3,1 … 3,8 ms, CDE-Subpanel 0,9 … 1,0 ms | Bestanden (Grenze 100 ms) |
| PERF-06 Zyklen | 100 × Menü öffnen und schließen, abwechselnd CDE und Photon, `testOpenAndCloseLeaveNothingBehind` | danach 0 Fenster, kein gehaltenes Esc, kein Mausmonitor | Bestanden |

## Prüfung im Code

- **PERF-03 (keine Aufnahme, keine 60-Hz-Neuzeichnung):** Die neuen Oberflächen nehmen nichts auf. Ihre Takte:
  - CDE Front Panel: 1 Hz, zeichnet nur Uhr, Kalender und Anzeige neu.
  - QNX-Shelf: 1 Hz, nur wenn sichtbar und der System Monitor offen ist.
  - QNX-Taskbar: alle 15 s für die Uhr.
  - Fensterwechsler: 20 Hz nur, solange ein Zyklus läuft (Modifier gedrückt).
  - Desktop-Ebenen und Menüs haben keine Takte.
- **PERF-05 (nichts Langsames im UI-Thread):** In dieser Runde korrigiert:
  - Fokuszyklus und Icon-Menü fragen Accessibility jetzt auf der AX-Warteschlange ab. Ob ein Fenster noch da ist, sagt der WindowServer sofort.
  - Das Launch-Menü liest die App-Ordner im Hintergrund und baut beim Öffnen nur noch aus dem fertigen Ergebnis.
  - Icon-Pakete werden beim Zeichnen nur aus dem Speicher gelesen. `icons.json` und die Bilder werden im Hintergrund gelesen und dekodiert.
- **PERF-06 (Speicher):** Die Icon-Pakete halten nur die Bilder des aktiven Themes; ein neues Paket verwirft die alten. Der Fenster-Tracker hält keine Bilder.

## Offen

- **PERF-02 im Vergleich:** Eine Leerlaufmessung derselben Sitzung ohne die neue Oberfläche, einmal mit Solaris, einmal mit QNX, je 5 min, ohne Bedienung. Dafür muss das Theme 20 Minuten lang wechseln; das stört während der Arbeit.
- **PERF-04 Wechsler:** Der erste sichtbare Rahmen eines Wechsler-Panels wird gemessen, sobald es Panels gibt (Windows-Wechsler, warten auf Referenzen).
- Das Lastenheft verlangt den Referenz-Mac mit mindestens M1 und 8 GB. Das Protokoll ist auf dem schnelleren M5 entstanden; die Zahlen liegen so weit unter den Grenzen, dass ein M1 sie ebenfalls einhält. Ein Kontrolllauf auf einem M1 steht aus.
