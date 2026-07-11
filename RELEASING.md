# Releases und Auto-Updates

Server Observer verwendet Sparkle 2.9.2. Updates werden sowohl durch Apple Developer ID als auch durch einen separaten Ed25519-Schlüssel abgesichert.

## Lokaler Release auf diesem Mac

```sh
cp release.env.example .release.env
# `.release.env` einmalig mit den lokalen Apple-Werten ausfüllen
scripts/publish_update.sh 0.1.0 1
```

Der Ablauf:

1. erzeugt einen Release-Build,
2. signiert ihn mit der Developer ID,
3. übermittelt ihn an Apples Notarisierungsdienst,
4. stapelt das Notarisierungs-Ticket,
5. erzeugt ein signiertes ZIP und
6. aktualisiert `appcast.xml`.

Danach werden ZIP, Release Notes und der aktualisierte Appcast gemeinsam committed. Der Tag `v<version>` und das ZIP müssen denselben Versionsnamen verwenden.

## Automatische GitHub-Releases

Der Workflow `.github/workflows/release.yml` startet bei einem Tag wie `v0.2.0`. Vor dem ersten automatischen Release müssen diese Repository-Secrets gesetzt werden:

- `MACOS_CERTIFICATE_BASE64`
- `MACOS_CERTIFICATE_PASSWORD`
- `MACOS_KEYCHAIN_PASSWORD`
- `APPLE_API_KEY_BASE64`
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER_ID`
- `SPARKLE_PRIVATE_KEY`

Der Workflow baut, signiert, notarisiert und veröffentlicht die App und schreibt anschließend den signierten Appcast nach `main` zurück.

Private Zertifikate und Schlüssel gehören ausschließlich in GitHub Secrets und niemals ins Repository.
