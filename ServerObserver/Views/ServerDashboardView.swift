import SwiftUI

struct ServerDashboardView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("panelMode") private var storedPanelMode = PanelMode.normal.rawValue

    private var panelMode: Binding<PanelMode> {
        Binding(
            get: { PanelMode(rawValue: storedPanelMode) ?? .normal },
            set: { storedPanelMode = $0.rawValue }
        )
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                DashboardHeader(panelMode: panelMode)
                Divider().opacity(0.55)

                if appState.filteredServers.isEmpty {
                    EmptyServerView(hasSearch: !appState.searchText.isEmpty || appState.filter != .web)
                } else if geometry.size.width >= 760 {
                    WideServerLayout()
                } else {
                    ServerCardList()
                }

                Divider().opacity(0.55)
                DashboardFooter()
            }
            .background(.ultraThinMaterial)
            .overlay(alignment: .topLeading) {
                WindowModeController(mode: panelMode.wrappedValue)
                    .frame(width: 0, height: 0)
            }
        }
        .frame(minWidth: 340, minHeight: 360)
        .task { appState.startMonitoring() }
        .confirmationDialog(
            "\(appState.serverPendingTermination?.displayName ?? "Server") beenden?",
            isPresented: Binding(
                get: { appState.serverPendingTermination != nil },
                set: { if !$0 { appState.serverPendingTermination = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Server beenden", role: .destructive) { appState.confirmStop() }
            Button("Abbrechen", role: .cancel) { appState.serverPendingTermination = nil }
        } message: {
            if let server = appState.serverPendingTermination {
                Text("PID \(server.pid) wird zunächst sauber mit SIGTERM beendet.")
            }
        }
        .alert(
            "Server reagiert nicht",
            isPresented: Binding(
                get: { appState.forceStopCandidate != nil },
                set: { if !$0 { appState.forceStopCandidate = nil } }
            )
        ) {
            Button("Sofort beenden", role: .destructive) {
                if let server = appState.forceStopCandidate { appState.forceStop(server) }
            }
            Button("Abbrechen", role: .cancel) { appState.forceStopCandidate = nil }
        } message: {
            Text("Der Prozess läuft weiterhin. Beim sofortigen Beenden kann er keine Aufräumarbeiten mehr durchführen.")
        }
        .alert("Fehler", isPresented: Binding(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )) {
            Button("OK") { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "Unbekannter Fehler")
        }
    }
}

private struct DashboardHeader: View {
    @EnvironmentObject private var appState: AppState
    @Binding var panelMode: PanelMode

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.tint.opacity(0.16))
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(.tint)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Local Servers")
                        .font(.headline)
                    Text("\(appState.webServerCount) Webserver · \(appState.servers.count) Prozesse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    Picker("Fensterverhalten", selection: $panelMode) {
                        ForEach(PanelMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.symbol).tag(mode)
                        }
                    }
                } label: {
                    Image(systemName: panelMode.symbol)
                }
                .menuStyle(.borderlessButton)
                .help(panelMode.title)

                Button {
                    Task { await appState.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(appState.isScanning ? 360 : 0))
                        .animation(
                            appState.isScanning
                                ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                                : .default,
                            value: appState.isScanning
                        )
                }
                .buttonStyle(.borderless)
                .disabled(appState.isScanning)
                .help("Jetzt aktualisieren")
            }

            HStack(spacing: 8) {
                SearchField(text: $appState.searchText)
                Picker("Filter", selection: $appState.filter) {
                    ForEach(AppState.Filter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
            TextField("Server suchen", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.primary.opacity(0.08)))
    }
}

private struct ServerCardList: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(appState.filteredServers) { server in
                    ServerCard(server: server)
                }
            }
            .padding(12)
        }
        .scrollIndicators(.visible)
    }
}

private struct ServerCard: View {
    @EnvironmentObject private var appState: AppState
    let server: LocalServer

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 11) {
                StatusIcon(server: server)
                VStack(alignment: .leading, spacing: 3) {
                    Text(server.displayName)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                    Text("\(server.runtime) · PID \(server.pid)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                KindBadge(kind: server.kind)
            }

            VStack(alignment: .leading, spacing: 5) {
                Label(server.addressLabel, systemImage: "network")
                    .font(.system(.callout, design: .monospaced))
                if let path = server.projectPathLabel {
                    Label(path, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            HStack {
                if server.browserURL != nil {
                    Button("Öffnen", systemImage: "safari") { appState.open(server) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                if server.workingDirectory != nil {
                    Button("Finder", systemImage: "folder") { appState.reveal(server) }
                        .controlSize(.small)
                }
                Spacer()
                Button("Stoppen", systemImage: "stop.fill", role: .destructive) {
                    appState.requestStop(server)
                }
                .controlSize(.small)
            }
        }
        .padding(13)
        .background(.background.opacity(0.48), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(.primary.opacity(0.07))
        }
        .contentShape(Rectangle())
        .onTapGesture { appState.selectedServerID = server.id }
    }
}

private struct WideServerLayout: View {
    @EnvironmentObject private var appState: AppState

    private var selectedServer: LocalServer? {
        appState.filteredServers.first { $0.id == appState.selectedServerID }
            ?? appState.filteredServers.first
    }

    var body: some View {
        HSplitView {
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(appState.filteredServers) { server in
                        ServerTableRow(
                            server: server,
                            isSelected: selectedServer?.id == server.id
                        )
                    }
                }
                .padding(10)
            }
            .frame(minWidth: 440)

            if let selectedServer {
                ServerDetailView(server: selectedServer)
                    .frame(minWidth: 260, idealWidth: 310)
            }
        }
    }
}

private struct ServerTableRow: View {
    @EnvironmentObject private var appState: AppState
    let server: LocalServer
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            StatusIcon(server: server, compact: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(server.displayName).fontWeight(.medium).lineLimit(1)
                Text(server.runtime).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(server.addressLabel)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 120, alignment: .leading)
            KindBadge(kind: server.kind)
                .frame(width: 84, alignment: .leading)
            if server.browserURL != nil {
                Button { appState.open(server) } label: { Image(systemName: "safari") }
                    .buttonStyle(.borderless)
                    .help("Im Browser öffnen")
            }
            Button { appState.requestStop(server) } label: { Image(systemName: "stop.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Server stoppen")
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background(isSelected ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { appState.selectedServerID = server.id }
    }
}

private struct ServerDetailView: View {
    @EnvironmentObject private var appState: AppState
    let server: LocalServer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    StatusIcon(server: server)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.displayName).font(.title3.bold())
                        Text(server.kind.label).foregroundStyle(.secondary)
                    }
                }

                DetailSection(title: "Verbindung") {
                    DetailValue(label: "Adresse", value: server.addressLabel)
                    DetailValue(label: "Bindung", value: server.hosts.joined(separator: ", "))
                }
                DetailSection(title: "Prozess") {
                    DetailValue(label: "PID", value: String(server.pid))
                    DetailValue(label: "Runtime", value: server.runtime)
                    DetailValue(label: "Befehl", value: server.command)
                    if let path = server.projectPathLabel {
                        DetailValue(label: "Ordner", value: path)
                    }
                }

                VStack(spacing: 8) {
                    if server.browserURL != nil {
                        Button("Im Browser öffnen", systemImage: "safari") { appState.open(server) }
                            .buttonStyle(.borderedProminent)
                    }
                    if server.workingDirectory != nil {
                        Button("Im Finder anzeigen", systemImage: "folder") { appState.reveal(server) }
                    }
                    Button("Server beenden", systemImage: "stop.fill", role: .destructive) {
                        appState.requestStop(server)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
            .padding(18)
        }
        .background(.background.opacity(0.28))
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct DetailValue: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.tertiary)
            Text(value)
                .font(label == "Befehl" || label == "Adresse" ? .system(.caption, design: .monospaced) : .callout)
                .textSelection(.enabled)
        }
    }
}

private struct StatusIcon: View {
    let server: LocalServer
    var compact = false

    var color: Color {
        switch server.kind {
        case .web: .green
        case .database: .blue
        case .service: .orange
        case .unknown: .secondary
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: compact ? 7 : 10, style: .continuous)
                .fill(color.opacity(0.14))
            Image(systemName: server.kind.symbol)
                .foregroundStyle(color)
                .font(compact ? .caption : .body)
        }
        .frame(width: compact ? 28 : 38, height: compact ? 28 : 38)
        .accessibilityLabel(server.kind.label)
    }
}

private struct KindBadge: View {
    let kind: LocalServer.Kind
    var body: some View {
        Text(kind.label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.primary.opacity(0.055), in: Capsule())
    }
}

private struct EmptyServerView: View {
    @EnvironmentObject private var appState: AppState
    let hasSearch: Bool

    var body: some View {
        ContentUnavailableView {
            Label(
                hasSearch ? "Keine Treffer" : "Keine lokalen Server",
                systemImage: hasSearch ? "magnifyingglass" : "dot.radiowaves.left.and.right"
            )
        } description: {
            Text(hasSearch
                 ? "Passe Suche oder Filter an."
                 : "Sobald ein lokaler TCP-Server startet, erscheint er automatisch hier.")
        } actions: {
            if hasSearch {
                Button("Filter zurücksetzen") {
                    appState.searchText = ""
                    appState.filter = .web
                }
            } else {
                Button("Jetzt prüfen") { Task { await appState.refresh() } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DashboardFooter: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(appState.isScanning ? Color.orange : Color.green)
                .frame(width: 6, height: 6)
            Text(appState.isScanning ? "Lokale Ports werden geprüft …" : updateText)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Nur lokale Prozesse")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
    }

    private var updateText: String {
        guard let date = appState.lastUpdated else { return "Bereit" }
        return "Aktualisiert " + date.formatted(.relative(presentation: .named))
    }
}
