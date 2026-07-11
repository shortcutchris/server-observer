# Server Observer – Produktspezifikation

## Ziel

Server Observer ist eine native macOS-Desktop-App, die lokale Entwicklungsprojekte, TCP-Server sowie Docker- und Dev-Container automatisch erkennt, verständlich zuordnet und kontrolliert bedienen kann. Die App arbeitet ausschließlich lokal; Mikrofon-, Bildschirm- oder Inhaltsüberwachung findet nicht statt.

## Oberfläche

- Frei skalierbares, widgetartiges Desktop-Panel mit einer Mindestgröße von 340 × 360 Punkten.
- Drei Fensterverhalten: **Desktop**, **Schwebend** und **Normales Fenster**.
- Kompakte Projektkarten bei schmalem Fenster, Projektliste plus Detailspalte bei breitem Fenster.
- Scrollbare Laufzeitlisten, Suche und Filter für aktive Projekte, alle Projekte, Webserver, Container und nicht zugeordnete Einträge.
- Light/Dark Mode, systemnahe Materialien, SF Symbols und zugängliche Statusbeschriftungen.
- Menüleisteneintrag zum Öffnen des Panels und für einen schnellen Überblick.

## Erkennung

- Mehrere persistente Projektstammordner mit Aktiv-Schalter und Scan-Tiefe von eins bis acht Ebenen.
- Projektmarker: `.git`, Compose-Dateien, `.devcontainer/devcontainer.json`, `Dockerfile` sowie Node-, Python-, Swift-, Go-, Rust- und Java-Manifeste.
- Abhängigkeiten und Build-Verzeichnisse wie `node_modules`, `.build`, `target`, `vendor` oder `.venv` werden übersprungen.
- Regelmäßige Ermittlung lokaler TCP-Listener über das macOS-Systemwerkzeug `lsof`.
- Standardmäßig werden Prozesse des angemeldeten Benutzers berücksichtigt.
- Erfassung von PID, Port, Bind-Adresse, Prozessname, Startbefehl und Arbeitsverzeichnis.
- Erkennung typischer Runtimes und Dienste wie Node.js, Next.js, Vite, Python, Ruby, Java, PHP, PostgreSQL und Redis.
- Vorsichtiger HTTP-Test über Loopback, um Webserver von anderen TCP-Diensten zu unterscheiden.
- Zusammenfassung mehrerer Ports desselben Prozesses als einzelne Einträge.
- Zuordnung lokaler Prozesse zum spezifischsten überwachten Projekt anhand des Arbeitsverzeichnisses.
- Ermittlung aller Docker-Container über die lokale Docker CLI und Zuordnung über Compose-/Dev-Container-Labels oder Bind-Mounts.
- Darstellung laufender und gestoppter Container, Healthchecks, Images, Services sowie interner und veröffentlichter Ports.
- Kategorisierung von Web-, Datenbank- und sonstigen Containern; ein veröffentlichter Webport ist keine Voraussetzung für die Sichtbarkeit.

## Aktionen

- Webadresse im Standardbrowser öffnen.
- Projektordner im Finder anzeigen.
- Prozessdetails einsehen.
- Prozess nach Bestätigung mit `SIGTERM` sauber beenden.
- Wenn der Prozess nicht reagiert, optionales Erzwingen mit `SIGKILL`.
- Systemfremde oder nicht berechtigte Prozesse werden nicht ohne Weiteres beendet.
- Docker-Container nach Bestätigung stoppen und gestoppte Container starten.
- Alle lokalen Prozesse und laufenden Container eines Projekts gesammelt stoppen.

## Nicht Teil der aktuellen Version

- Neustart anhand des ursprünglichen Shell-Kontexts.
- Persistenter Verlauf und Ressourcenmetriken.
- VM-spezifische Steuerung außerhalb von Docker.
- Auswertung von Logs oder Inhalten der überwachten Anwendungen.

## Technische Basis

- Swift 6, SwiftUI und AppKit-Brücke für das Fensterverhalten.
- Native macOS-App ohne Electron oder Hintergrundserver.
- Deployment Target macOS 14 oder neuer.
