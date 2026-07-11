# Server Observer – MVP-Spezifikation

## Ziel

Server Observer ist eine native macOS-Desktop-App, die lokale Entwicklungsserver automatisch erkennt, verständlich einem Projekt zuordnet und kontrolliert beenden kann. Die App arbeitet ausschließlich mit lokalen Prozess- und Portinformationen; Mikrofon- oder Inhaltsüberwachung findet nicht statt.

## Oberfläche

- Frei skalierbares, widgetartiges Desktop-Panel mit einer Mindestgröße von 340 × 360 Punkten.
- Drei Fensterverhalten: **Desktop**, **Schwebend** und **Normales Fenster**.
- Kompakte Kartenansicht bei schmalem Fenster, Tabelle plus Detailspalte bei breitem Fenster.
- Scrollbare Serverliste, Suche und Filter für Webserver bzw. alle lokalen Dienste.
- Light/Dark Mode, systemnahe Materialien, SF Symbols und zugängliche Statusbeschriftungen.
- Menüleisteneintrag zum Öffnen des Panels und für einen schnellen Überblick.

## Erkennung

- Regelmäßige Ermittlung lokaler TCP-Listener über das macOS-Systemwerkzeug `lsof`.
- Standardmäßig werden Prozesse des angemeldeten Benutzers berücksichtigt.
- Erfassung von PID, Port, Bind-Adresse, Prozessname, Startbefehl und Arbeitsverzeichnis.
- Erkennung typischer Runtimes und Dienste wie Node.js, Next.js, Vite, Python, Ruby, Java, PHP, PostgreSQL und Redis.
- Vorsichtiger HTTP-Test über Loopback, um Webserver von anderen TCP-Diensten zu unterscheiden.
- Zusammenfassung mehrerer Ports desselben Prozesses als einzelne Einträge.

## Aktionen

- Webadresse im Standardbrowser öffnen.
- Projektordner im Finder anzeigen.
- Prozessdetails einsehen.
- Prozess nach Bestätigung mit `SIGTERM` sauber beenden.
- Wenn der Prozess nicht reagiert, optionales Erzwingen mit `SIGKILL`.
- Systemfremde oder nicht berechtigte Prozesse werden nicht ohne Weiteres beendet.

## Nicht Teil des ersten MVP

- Docker- und VM-spezifische Steuerung.
- Neustart anhand des ursprünglichen Shell-Kontexts.
- Persistenter Verlauf und Ressourcenmetriken.
- Vollständige Gruppierung mehrerer unabhängiger Prozesse zu einem Projekt.

## Technische Basis

- Swift 6, SwiftUI und AppKit-Brücke für das Fensterverhalten.
- Native macOS-App ohne Electron oder Hintergrundserver.
- Deployment Target macOS 14 oder neuer.
