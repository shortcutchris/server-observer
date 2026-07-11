<p align="center">
  <img src="ServerObserver/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" width="196" alt="Server Observer App Icon">
</p>

# Server Observer

Server Observer ist ein natives, widgetartiges macOS-Panel für lokale Entwicklungsserver. Es erkennt lauschende TCP-Prozesse, hebt echte HTTP-Entwicklungsserver hervor und kann eigene Prozesse kontrolliert beenden.

## Download

Die aktuelle notarisierten Universal-App für Apple Silicon und Intel gibt es unter [GitHub Releases](https://github.com/shortcutchris/server-observer/releases/latest). Benötigt wird macOS 14 oder neuer.

## Aktueller MVP

- automatische Aktualisierung alle vier Sekunden
- Projektname, Runtime, PID, Port, Befehl und Arbeitsverzeichnis
- responsive Kartenansicht sowie Tabelle mit Detailspalte
- Filter für Webserver, alle Prozesse und sonstige Dienste
- Browser- und Finder-Aktionen
- `SIGTERM` mit optionalem `SIGKILL`, falls ein Prozess nicht reagiert
- Fensterverhalten: Desktop, schwebend oder normal
- Menüleistensteuerung
- automatisches, kryptografisch signiertes Update-System mit Sparkle 2
- Apple Developer ID, Hardened Runtime und Notarisierung für öffentliche Builds

## Entwickeln

Voraussetzungen: macOS 14+, Xcode und XcodeGen.

```sh
xcodegen generate
open ServerObserver.xcodeproj
```

Alternativ lässt sich der MVP direkt im Terminal bauen und testen:

```sh
xcodebuild \
  -project ServerObserver.xcodeproj \
  -scheme ServerObserver \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Die gebaute Debug-App liegt anschließend unter:

```text
.build/DerivedData/Build/Products/Debug/ServerObserver.app
```

Die Produkt- und Sicherheitsentscheidungen des MVP stehen in [SPEC.md](SPEC.md). Der Veröffentlichungsprozess ist in [RELEASING.md](RELEASING.md) dokumentiert.

## Sicherheit

Server Observer überwacht ausschließlich lokale Prozess- und Portinformationen. Es verwendet weder Mikrofon noch Bildschirmaufzeichnung und überträgt keine Serverdaten. Prozesse werden zunächst mit `SIGTERM` beendet; ein erzwungenes `SIGKILL` wird nur nach einer weiteren Bestätigung angeboten.

