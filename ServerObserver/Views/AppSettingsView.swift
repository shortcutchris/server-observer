import AppKit
import SwiftUI

struct AppSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var updateController: UpdateController

    var body: some View {
        TabView {
            ProjectFoldersSettingsView()
                .environmentObject(appState)
                .tabItem { Label("Projekte", systemImage: "folder") }

            UpdateSettingsView()
                .environmentObject(updateController)
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 640, height: 450)
    }
}

private struct ProjectFoldersSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Projektordner")
                    .font(.title2.bold())
                Text("Server Observer durchsucht diese Ordner nach Git-Repositories, Compose-Dateien, Dev Containern und bekannten Projektdateien.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GroupBox {
                if appState.roots.isEmpty {
                    ContentUnavailableView(
                        "Noch keine Projektordner",
                        systemImage: "folder.badge.plus",
                        description: Text("Füge einen oder mehrere übergeordnete Ordner hinzu. Unterordner werden automatisch erkannt.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 170)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(appState.roots) { root in
                                ProjectRootSettingsRow(root: root)
                                if root.id != appState.roots.last?.id {
                                    Divider().padding(.leading, 36)
                                }
                            }
                        }
                    }
                    .frame(minHeight: 170)
                }
            }

            HStack {
                Button {
                    chooseProjectFolders()
                } label: {
                    Label("Ordner hinzufügen …", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await appState.refresh(forceProjects: true) }
                } label: {
                    Label("Neu scannen", systemImage: "arrow.clockwise")
                }
                .disabled(appState.isScanning || appState.roots.isEmpty)

                Spacer()

                if appState.isScanning {
                    ProgressView().controlSize(.small)
                    Text("Scan läuft …").foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: appState.dockerState.isReady ? "shippingbox.fill" : "shippingbox")
                    .font(.title2)
                    .foregroundStyle(appState.dockerState.isReady ? .blue : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Docker-Integration").font(.headline)
                    Text(appState.dockerState.label)
                        .foregroundStyle(.secondary)
                    Text("Container werden ausschließlich lokal über die Docker CLI gelesen. Server Observer verändert nichts, bis du ausdrücklich Starten oder Stoppen auswählst.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(24)
    }

    private func chooseProjectFolders() {
        let panel = NSOpenPanel()
        panel.title = "Projektordner auswählen"
        panel.prompt = "Hinzufügen"
        panel.message = "Wähle einen oder mehrere Ordner, unter denen deine Projekte liegen."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK else { return }
        appState.addProjectRoots(panel.urls)
    }
}

private struct ProjectRootSettingsRow: View {
    @EnvironmentObject private var appState: AppState
    let root: ProjectRoot

    var body: some View {
        HStack(spacing: 10) {
            Toggle(
                "",
                isOn: Binding(
                    get: { root.isEnabled },
                    set: { appState.setProjectRoot(root, enabled: $0) }
                )
            )
            .labelsHidden()

            Image(systemName: "folder.fill")
                .foregroundStyle(root.isEnabled ? .blue : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(root.displayPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(appState.projectCount(for: root)) Projekte erkannt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Stepper(
                "Tiefe \(root.scanDepth)",
                value: Binding(
                    get: { root.scanDepth },
                    set: { appState.setProjectRoot(root, scanDepth: $0) }
                ),
                in: 1...8
            )
            .fixedSize()
            .help("Maximale Unterordner-Tiefe")

            Button(role: .destructive) {
                appState.removeProjectRoot(root)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Ordner entfernen")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .opacity(root.isEnabled ? 1 : 0.58)
    }
}

private struct UpdateSettingsView: View {
    @EnvironmentObject private var updateController: UpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Server Observer")
                        .font(.title2.bold())
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")")
                        .foregroundStyle(.secondary)
                }
            }

            Text("Server Observer prüft automatisch den signierten Release-Feed auf neue Versionen.")
                .foregroundStyle(.secondary)

            Button("Nach Updates suchen …") {
                updateController.checkForUpdates()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!updateController.canCheckForUpdates)

            Spacer()
        }
        .padding(24)
    }
}
