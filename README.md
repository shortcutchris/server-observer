<p align="center">
  <img src="ServerObserver/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" width="196" alt="Server Observer App Icon">
</p>

# Server Observer

Server Observer ist ein natives, widgetartiges macOS-Panel für lokale Entwicklungsprojekte. Es verbindet lauschende TCP-Prozesse, Docker- und Dev-Container mit den passenden Projektordnern und bietet direkte Start-, Stopp-, Browser- und Finder-Aktionen.

## Download

Die aktuelle notarisierten Universal-App für Apple Silicon und Intel gibt es unter [GitHub Releases](https://github.com/shortcutchris/server-observer/releases/latest). Benötigt wird macOS 14 oder neuer.

## Funktionen

- automatische Aktualisierung alle vier Sekunden
- frei konfigurierbare Projektstämme mit einstellbarer Scan-Tiefe
- Erkennung von Git, Docker Compose, Dev Containers, Dockerfiles und gängigen Sprach-Manifests
- automatische Zuordnung lokaler Prozesse über ihr Arbeitsverzeichnis
- Docker-Container inklusive Status, Healthcheck, Image, Service, Bind-Mounts und internen oder veröffentlichten Ports
- Container ohne Webserver, etwa PostgreSQL, Worker oder Dev-Container, bleiben sichtbar
- responsive Kartenansicht sowie Projektliste mit Detailspalte
- Suche und Filter für aktive Projekte, Webserver, Container und nicht zugeordnete Laufzeiten
- Browser- und Finder-Aktionen
- `SIGTERM` mit optionalem `SIGKILL`, falls ein Prozess nicht reagiert
- Docker-Container starten und kontrolliert stoppen; komplettes Projekt nach Bestätigung stoppen
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

Server Observer liest ausschließlich lokale Dateisystem-Metadaten, Prozess- und Portinformationen sowie den lokalen Docker-Status. Es verwendet weder Mikrofon noch Bildschirmaufzeichnung und überträgt keine Projekt- oder Serverdaten. Prozesse und Container werden nur nach einer ausdrücklichen Aktion beendet.
