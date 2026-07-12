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

                if !appState.hasVisibleContent {
                    ProjectEmptyView()
                } else if geometry.size.width >= 760 {
                    WideProjectLayout()
                } else {
                    ProjectCardList()
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
        .frame(minWidth: 360, minHeight: 400)
        .task { appState.startMonitoring() }
        .serverStopDialogs()
        .containerStopDialog()
        .projectStopDialog()
        .automationDialog()
        .appErrorAlert()
    }
}

private struct DashboardHeader: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @Binding var panelMode: PanelMode

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.tint.opacity(0.16))
                    Image(systemName: "server.rack")
                        .foregroundStyle(.tint)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Local Projects")
                        .font(.headline)
                    Text("\(appState.activeProjectCount) aktiv · \(appState.activeContainerCount) Container · \(appState.servers.count) Prozesse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                DockerStatusPill(state: appState.dockerState)

                Button { openSettings() } label: {
                    Image(systemName: "folder.badge.gearshape")
                }
                .buttonStyle(.borderless)
                .help("Projektordner verwalten")

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
                    Task { await appState.refresh(forceProjects: true) }
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
                .help("Projekte und Laufzeiten aktualisieren")
            }

            HStack(spacing: 8) {
                SearchField(text: $appState.searchText)
                Picker("Filter", selection: $appState.filter) {
                    ForEach(AppState.Filter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .labelsHidden()
                .frame(width: 145)
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
            TextField("Projekt, Container oder Port suchen", text: $text)
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

private struct ProjectCardList: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(appState.filteredProjects) { project in
                    ProjectCard(project: project)
                }
                if appState.showsUnassigned {
                    UnassignedCard(
                        servers: appState.filteredUnassignedServers,
                        containers: appState.filteredUnassignedContainers
                    )
                }
            }
            .padding(12)
        }
        .scrollIndicators(.visible)
    }
}

private struct ProjectCard: View {
    @EnvironmentObject private var appState: AppState
    let project: MonitoredProject

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProjectHeader(project: project, compact: true)

            if project.servers.isEmpty && project.containers.isEmpty {
                Label("Derzeit keine Laufzeit aktiv", systemImage: "moon.zzz")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 5)
            } else {
                VStack(spacing: 7) {
                    ForEach(project.servers) { server in
                        ServerRuntimeRow(server: server)
                    }
                    ForEach(project.containers) { container in
                        ContainerRuntimeRow(container: container)
                    }
                }
            }

            HStack {
                Button("Finder", systemImage: "folder") { appState.reveal(project) }
                    .controlSize(.small)
                Spacer()
                ProjectActionButtons(project: project, compact: true)
            }
        }
        .padding(13)
        .background(.background.opacity(0.48), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(.primary.opacity(0.07))
        }
        .contentShape(Rectangle())
        .onTapGesture { appState.selectedProjectID = project.id }
    }
}

private struct ProjectHeader: View {
    let project: MonitoredProject
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill((project.isActive ? Color.green : Color.secondary).opacity(0.13))
                Image(systemName: project.descriptor.hasDevContainer ? "shippingbox.fill" : "folder.fill")
                    .foregroundStyle(project.isActive ? .green : .secondary)
            }
            .frame(width: compact ? 36 : 44, height: compact ? 36 : 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(project.isActive ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 7, height: 7)
                    Text(project.descriptor.name)
                        .font(compact ? .headline : .title2.bold())
                        .lineLimit(1)
                }
                Text(project.descriptor.displayPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 5) {
                    ForEach(Array(project.descriptor.markers).sorted { $0.rawValue < $1.rawValue }.prefix(compact ? 3 : 6), id: \.self) {
                        MarkerPill(marker: $0)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(project.isActive ? "Läuft" : "Gestoppt")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(project.isActive ? .green : .secondary)
                Text("\(project.servers.count) lokal · \(project.containers.count) Docker")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct MarkerPill: View {
    let marker: ProjectMarker
    var body: some View {
        Text(marker.label)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.primary.opacity(0.055), in: Capsule())
    }
}

private struct ServerRuntimeRow: View {
    @EnvironmentObject private var appState: AppState
    let server: LocalServer

    var body: some View {
        HStack(spacing: 9) {
            RuntimeIcon(symbol: server.kind.symbol, color: serverColor)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(server.displayName).font(.callout.weight(.medium)).lineLimit(1)
                    RuntimePill(text: "Lokal", color: .blue)
                }
                Text("\(server.runtime) · \(server.addressLabel) · PID \(server.pid)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let metrics = server.metrics {
                    RuntimeMetricsLine(metrics: metrics)
                }
            }
            Spacer()
            if server.browserURL != nil {
                Button { appState.open(server) } label: { Image(systemName: "safari") }
                    .buttonStyle(.borderless)
                    .help("Im Browser öffnen")
            }
            Button { appState.requestStop(server) } label: { Image(systemName: "stop.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Prozess stoppen")
        }
        .padding(.horizontal, 9)
        .frame(minHeight: 46)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    private var serverColor: Color {
        switch server.kind {
        case .web: .green
        case .database: .blue
        case .service: .orange
        case .unknown: .secondary
        }
    }
}

private struct ContainerRuntimeRow: View {
    @EnvironmentObject private var appState: AppState
    let container: DockerContainer

    var body: some View {
        HStack(spacing: 9) {
            RuntimeIcon(symbol: container.kind == .database ? "cylinder.fill" : "shippingbox.fill", color: containerColor)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(container.displayName).font(.callout.weight(.medium)).lineLimit(1)
                    RuntimePill(text: "Docker", color: .cyan)
                    if container.health != .none {
                        RuntimePill(text: container.health.label, color: healthColor)
                    }
                }
                Text("\(container.image) · \(container.portsLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let metrics = container.metrics {
                    RuntimeMetricsLine(metrics: metrics)
                }
            }
            Spacer()
            if appState.busyContainerIDs.contains(container.id) {
                ProgressView().controlSize(.small)
            } else {
                if container.browserURL != nil {
                    Button { appState.open(container) } label: { Image(systemName: "safari") }
                        .buttonStyle(.borderless)
                        .help("Im Browser öffnen")
                }
                if container.isRunning {
                    Button { appState.requestStop(container) } label: { Image(systemName: "stop.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Container stoppen")
                } else {
                    Button { appState.start(container) } label: { Image(systemName: "play.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.green)
                        .help("Container starten")
                }
            }
        }
        .padding(.horizontal, 9)
        .frame(minHeight: 48)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    private var containerColor: Color {
        if !container.isActive { return .secondary }
        if container.health == .unhealthy { return .red }
        switch container.kind {
        case .web: return .green
        case .database: return .blue
        case .worker: return .cyan
        }
    }

    private var healthColor: Color {
        switch container.health {
        case .healthy: .green
        case .unhealthy: .red
        case .starting: .orange
        case .none: .secondary
        }
    }
}

private struct RuntimeIcon: View {
    let symbol: String
    let color: Color
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color.opacity(0.13))
            Image(systemName: symbol).foregroundStyle(color).font(.caption)
        }
        .frame(width: 29, height: 29)
    }
}

private struct RuntimePill: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.1), in: Capsule())
    }
}

private struct RuntimeMetricsLine: View {
    let metrics: RuntimeMetrics

    var body: some View {
        HStack(spacing: 7) {
            Label(metrics.cpuLabel, systemImage: "cpu")
            Label(metrics.memoryLabel, systemImage: "memorychip")
            if let uptime = metrics.uptimeLabel { Label(uptime, systemImage: "clock") }
            if let network = metrics.networkLabel { Text(network) }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .lineLimit(1)
    }
}

private struct ProjectActionButtons: View {
    @EnvironmentObject private var appState: AppState
    let project: MonitoredProject
    var compact = false

    private var state: ProjectActionState { appState.actionStates[project.id] ?? .idle }

    var body: some View {
        HStack(spacing: 7) {
            if state.isBusy {
                ProgressView().controlSize(.small)
            } else {
                if project.descriptor.recipe.canStart {
                    if project.descriptor.recipe.profiles.isEmpty {
                        Button(project.isActive ? "Neustart" : "Starten", systemImage: project.isActive ? "arrow.clockwise" : "play.fill") {
                            project.isActive ? appState.restart(project) : appState.start(project)
                        }
                    } else {
                        Menu {
                            if project.isActive {
                                Button("Aktuelles Setup neu starten") { appState.restart(project) }
                            } else {
                                Button("Standard") { appState.start(project) }
                            }
                            Divider()
                            ForEach(project.descriptor.recipe.profiles) { profile in
                                Button("Profil: \(profile.name)") { appState.start(project, profile: profile) }
                            }
                        } label: {
                            Label(project.isActive ? "Neustart" : "Starten", systemImage: project.isActive ? "arrow.clockwise" : "play.fill")
                        }
                    }
                }
                if project.isActive {
                    Button("Stoppen", systemImage: "stop.fill", role: .destructive) {
                        appState.requestStop(project)
                    }
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(compact ? .small : .regular)
    }
}

private struct UnassignedCard: View {
    let servers: [LocalServer]
    let containers: [DockerContainer]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Nicht zugeordnet", systemImage: "questionmark.folder")
                .font(.headline)
            Text("Diese Laufzeiten liegen außerhalb der überwachten Projektordner oder enthalten keine eindeutigen Projektmetadaten.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(servers) { ServerRuntimeRow(server: $0) }
            ForEach(containers) { ContainerRuntimeRow(container: $0) }
        }
        .padding(13)
        .background(.orange.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.orange.opacity(0.14)))
    }
}

private struct WideProjectLayout: View {
    @EnvironmentObject private var appState: AppState
    private let unassignedID = "__unassigned__"

    var body: some View {
        HSplitView {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(appState.filteredProjects) { project in
                        ProjectSidebarRow(
                            project: project,
                            selected: selectedProject?.id == project.id && appState.selectedProjectID != unassignedID
                        )
                        .onTapGesture { appState.selectedProjectID = project.id }
                    }
                    if appState.showsUnassigned {
                        HStack(spacing: 9) {
                            Image(systemName: "questionmark.folder").foregroundStyle(.orange)
                            VStack(alignment: .leading) {
                                Text("Nicht zugeordnet").fontWeight(.medium)
                                Text("\(appState.filteredUnassignedServers.count) lokal · \(appState.filteredUnassignedContainers.count) Docker")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(appState.selectedProjectID == unassignedID ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                        .onTapGesture { appState.selectedProjectID = unassignedID }
                    }
                }
                .padding(10)
            }
            .frame(minWidth: 300, idealWidth: 390)

            if appState.selectedProjectID == unassignedID, appState.showsUnassigned {
                UnassignedDetailView()
                    .frame(minWidth: 340)
            } else if let selectedProject {
                ProjectDetailView(project: selectedProject)
                    .frame(minWidth: 340)
            }
        }
    }

    private var selectedProject: MonitoredProject? {
        appState.selectedProject ?? appState.filteredProjects.first
    }
}

private struct ProjectSidebarRow: View {
    let project: MonitoredProject
    let selected: Bool

    var body: some View {
        HStack(spacing: 9) {
            Circle().fill(project.isActive ? Color.green : Color.secondary.opacity(0.45)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.descriptor.name).fontWeight(.medium).lineLimit(1)
                Text("\(project.servers.count) lokal · \(project.containers.count) Docker")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !project.portConflicts.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
            if project.serviceHealth.contains(where: { $0.state == .unreachable || $0.state == .degraded }) {
                Image(systemName: "heart.slash.fill").font(.caption).foregroundStyle(.red)
            }
            if project.webCount > 0 {
                Image(systemName: "globe").font(.caption).foregroundStyle(.green)
                Text(String(project.webCount)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(selected ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}

private struct ProjectDetailView: View {
    @EnvironmentObject private var appState: AppState
    let project: MonitoredProject
    @State private var tab: DetailTab = .overview

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                ProjectHeader(project: project)

                HStack {
                    Button("Im Finder", systemImage: "folder") { appState.reveal(project) }
                    Spacer()
                    ProjectActionButtons(project: project)
                }

                Picker("Ansicht", selection: $tab) {
                    ForEach(DetailTab.allCases) { value in
                        Label(value.title, systemImage: value.symbol).tag(value)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(18)
            Divider()

            Group {
                switch tab {
                case .overview: ProjectOverviewView(project: project)
                case .logs: ProjectLogsView(project: project)
                case .history: ProjectHistoryView(project: project)
                }
            }
        }
        .background(.background.opacity(0.28))
        .onChange(of: tab) { _, value in
            if value == .logs { appState.loadLogs(for: project) }
        }
    }
}

private enum DetailTab: String, CaseIterable, Identifiable {
    case overview
    case logs
    case history
    var id: Self { self }
    var title: String {
        switch self { case .overview: "Übersicht"; case .logs: "Logs"; case .history: "Verlauf" }
    }
    var symbol: String {
        switch self { case .overview: "gauge.with.dots.needle.33percent"; case .logs: "text.alignleft"; case .history: "clock.arrow.circlepath" }
    }
}

private struct ProjectOverviewView: View {
    let project: MonitoredProject

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 8)], spacing: 8) {
                    StatusTile(title: "CPU", value: aggregate.cpuLabel, symbol: "cpu", color: .blue)
                    StatusTile(title: "Speicher", value: aggregate.memoryLabel, symbol: "memorychip", color: .purple)
                    StatusTile(title: "Laufzeiten", value: String(project.activeRuntimeCount), symbol: "waveform.path.ecg", color: .green)
                    StatusTile(title: "Health", value: healthSummary, symbol: "heart.text.square", color: healthColor)
                }

                if let git = project.gitStatus {
                    RuntimeSection(title: "Git", count: git.changedFileCount) {
                        VStack(alignment: .leading, spacing: 5) {
                            Label(git.summary, systemImage: "arrow.triangle.branch")
                                .font(.callout.weight(.medium))
                            if let commit = git.latestCommit {
                                Text(commit).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(11)
                        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                if !project.serviceHealth.isEmpty {
                    RuntimeSection(title: "Services & Healthchecks", count: project.serviceHealth.count) {
                        ForEach(project.serviceHealth) { health in HealthRow(health: health) }
                    }
                }

                if !project.portConflicts.isEmpty {
                    RuntimeSection(title: "Portkonflikte", count: project.portConflicts.count) {
                        ForEach(project.portConflicts) { conflict in
                            Label(
                                "Port \(conflict.port) ist durch \(conflict.occupiedBy) belegt",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                RuntimeSection(title: "Lokale Prozesse", count: project.servers.count) {
                    if project.servers.isEmpty { SectionEmptyText(text: "Keine lokalen Prozesse zugeordnet") }
                    else { ForEach(project.servers) { ServerRuntimeRow(server: $0) } }
                }

                RuntimeSection(title: "Docker & Dev Containers", count: project.containers.count) {
                    if project.containers.isEmpty { SectionEmptyText(text: "Keine Container zugeordnet") }
                    else { ForEach(project.containers) { ContainerRuntimeRow(container: $0) } }
                }

                RecipeSummaryView(recipe: project.descriptor.recipe)
            }
            .padding(18)
        }
    }

    private var aggregate: RuntimeMetrics {
        let metrics = project.servers.compactMap(\.metrics) + project.containers.compactMap(\.metrics)
        return RuntimeMetrics(
            cpuPercent: metrics.reduce(0) { $0 + $1.cpuPercent },
            memoryBytes: metrics.reduce(0) { $0 + $1.memoryBytes },
            uptimeSeconds: metrics.compactMap(\.uptimeSeconds).max(),
            networkInputBytes: metrics.compactMap(\.networkInputBytes).reduce(0, +),
            networkOutputBytes: metrics.compactMap(\.networkOutputBytes).reduce(0, +),
            processCount: metrics.compactMap(\.processCount).reduce(0, +)
        )
    }

    private var unhealthy: Int { project.serviceHealth.filter { $0.state != .healthy }.count }
    private var healthSummary: String { project.serviceHealth.isEmpty ? "–" : (unhealthy == 0 ? "OK" : "\(unhealthy) Fehler") }
    private var healthColor: Color { unhealthy == 0 ? .green : .red }
}

private struct StatusTile: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 23)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.headline).lineLimit(1)
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(color.opacity(0.075), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct HealthRow: View {
    let health: ServiceHealth
    var body: some View {
        HStack(spacing: 9) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(health.name).font(.callout.weight(.medium))
                Text(health.url).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(detail).font(.caption).foregroundStyle(color)
        }
        .padding(10)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
    private var detail: String {
        var value = health.statusCode.map(String.init) ?? health.state.label
        if let latency = health.latencyMilliseconds { value += " · \(latency) ms" }
        return value
    }
    private var color: Color {
        switch health.state { case .healthy: .green; case .degraded: .orange; case .unreachable: .red; case .unknown: .secondary }
    }
}

private struct RecipeSummaryView: View {
    let recipe: ProjectRecipe
    var body: some View {
        RuntimeSection(title: "Projektsteuerung", count: recipe.profiles.count) {
            VStack(alignment: .leading, spacing: 6) {
                Label(recipe.source == .configuration ? ".server-observer.yml" : "Automatisch erkannt", systemImage: "terminal")
                    .font(.callout.weight(.medium))
                if let command = recipe.startCommand { Text("$ \(command)").font(.caption.monospaced()).textSelection(.enabled) }
                if !recipe.allExpectedPorts.isEmpty { Text("Erwartete Ports: \(recipe.allExpectedPorts.map(String.init).joined(separator: ", "))").font(.caption).foregroundStyle(.secondary) }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct ProjectLogsView: View {
    @EnvironmentObject private var appState: AppState
    let project: MonitoredProject
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let snapshot = appState.projectLogs[project.id] {
                    Text(snapshot.sourceLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else { Text("Logs werden geladen …").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Aktualisieren", systemImage: "arrow.clockwise") { appState.loadLogs(for: project) }
                    .buttonStyle(.borderless)
            }
            .padding(12)
            Divider()
            ScrollView([.horizontal, .vertical]) {
                Text(appState.projectLogs[project.id]?.text ?? "")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(14)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
        }
        .task { appState.loadLogs(for: project) }
    }
}

private struct ProjectHistoryView: View {
    @EnvironmentObject private var appState: AppState
    let project: MonitoredProject
    private var events: [ActivityEvent] { appState.activity.filter { $0.projectPath == project.id } }
    var body: some View {
        ScrollView {
            if events.isEmpty {
                ContentUnavailableView("Noch kein Verlauf", systemImage: "clock", description: Text("Starts, Stops, Fehler und Health-Änderungen erscheinen hier."))
                    .padding(.top, 50)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(events) { event in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: symbol(event.kind)).foregroundStyle(color(event.kind)).frame(width: 18)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.message).font(.callout)
                                Text(event.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        Divider()
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }
    private func symbol(_ kind: ActivityEvent.Kind) -> String {
        switch kind { case .started: "play.fill"; case .stopped: "stop.fill"; case .restarted: "arrow.clockwise"; case .unhealthy: "heart.slash"; case .recovered: "heart.fill"; case .portConflict: "exclamationmark.triangle"; case .error: "xmark.octagon"; case .info: "info.circle" }
    }
    private func color(_ kind: ActivityEvent.Kind) -> Color {
        switch kind { case .started, .recovered: .green; case .unhealthy, .error: .red; case .portConflict: .orange; default: .secondary }
    }
}

private struct UnassignedDetailView: View {
    @EnvironmentObject private var appState: AppState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Nicht zugeordnete Laufzeiten", systemImage: "questionmark.folder.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.orange)
                Text("Füge den zugehörigen Projektordner hinzu oder erhöhe dessen Scan-Tiefe, um diese Einträge automatisch zu gruppieren.")
                    .foregroundStyle(.secondary)
                RuntimeSection(title: "Lokale Prozesse", count: appState.filteredUnassignedServers.count) {
                    ForEach(appState.filteredUnassignedServers) { ServerRuntimeRow(server: $0) }
                }
                RuntimeSection(title: "Container", count: appState.filteredUnassignedContainers.count) {
                    ForEach(appState.filteredUnassignedContainers) { ContainerRuntimeRow(container: $0) }
                }
            }
            .padding(18)
        }
        .background(.background.opacity(0.28))
    }
}

private struct RuntimeSection<Content: View>: View {
    let title: String
    let count: Int
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(String(count)).font(.caption2).foregroundStyle(.tertiary)
            }
            content
        }
    }
}

private struct SectionEmptyText: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProjectEmptyView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ContentUnavailableView {
            Label(
                appState.roots.isEmpty ? "Noch keine Projektordner" : "Keine passenden Projekte",
                systemImage: appState.roots.isEmpty ? "folder.badge.plus" : "magnifyingglass"
            )
        } description: {
            Text(appState.roots.isEmpty
                 ? "Füge einen oder mehrere Ordner hinzu. Server Observer erkennt darin Projekte, lokale Prozesse und Container."
                 : "Passe Suche oder Filter an. Gestoppte Projekte findest du unter „Alle Projekte“.")
        } actions: {
            if appState.roots.isEmpty {
                Button("Projektordner hinzufügen") { openSettings() }
            } else {
                Button("Filter zurücksetzen") {
                    appState.searchText = ""
                    appState.filter = .active
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DockerStatusPill: View {
    let state: DockerEngineState
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(state.isReady ? Color.cyan : Color.secondary).frame(width: 6, height: 6)
            Text(state.isReady ? "Docker" : "Docker aus").font(.caption2.weight(.medium))
        }
        .foregroundStyle(state.isReady ? Color.cyan : Color.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.primary.opacity(0.05), in: Capsule())
        .help(state.label)
    }
}

private struct DashboardFooter: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(appState.isScanning ? Color.orange : Color.green)
                .frame(width: 6, height: 6)
            Text(appState.isScanning ? "Projekte, Ports und Container werden geprüft …" : updateText)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(appState.dockerState.label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
    }

    private var updateText: String {
        guard let date = appState.lastUpdated else { return "Bereit" }
        return "Aktualisiert " + date.formatted(.relative(presentation: .named))
    }
}

private extension View {
    func serverStopDialogs() -> some View {
        modifier(ServerStopDialogsModifier())
    }
    func containerStopDialog() -> some View {
        modifier(ContainerStopDialogModifier())
    }
    func projectStopDialog() -> some View {
        modifier(ProjectStopDialogModifier())
    }
    func automationDialog() -> some View {
        modifier(AutomationDialogModifier())
    }
    func appErrorAlert() -> some View {
        modifier(AppErrorAlertModifier())
    }
}

private struct AutomationDialogModifier: ViewModifier {
    @EnvironmentObject private var appState: AppState
    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Externe Projektaktion bestätigen",
            isPresented: Binding(
                get: { appState.automationRequest != nil },
                set: { if !$0 { appState.automationRequest = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let request = appState.automationRequest {
                Button("„\(request.projectName)“ \(request.action.title)") { appState.confirmAutomation() }
                Button("Abbrechen", role: .cancel) { appState.automationRequest = nil }
            }
        } message: {
            Text("Diese Anfrage kam über URL, CLI oder Apple Kurzbefehle. Der konfigurierte Projektbefehl wird erst nach deiner Bestätigung ausgeführt.")
        }
    }
}

private struct ServerStopDialogsModifier: ViewModifier {
    @EnvironmentObject private var appState: AppState
    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "\(appState.serverPendingTermination?.displayName ?? "Server") beenden?",
                isPresented: Binding(
                    get: { appState.serverPendingTermination != nil },
                    set: { if !$0 { appState.serverPendingTermination = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Prozess beenden", role: .destructive) { appState.confirmStop() }
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
    }
}

private struct ContainerStopDialogModifier: ViewModifier {
    @EnvironmentObject private var appState: AppState
    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Container stoppen?",
            isPresented: Binding(
                get: { appState.containerPendingStop != nil },
                set: { if !$0 { appState.containerPendingStop = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Container stoppen", role: .destructive) { appState.confirmContainerStop() }
            Button("Abbrechen", role: .cancel) { appState.containerPendingStop = nil }
        } message: {
            if let container = appState.containerPendingStop {
                Text("„\(container.displayName)“ wird mit docker stop sauber beendet. Volumes und Netzwerke bleiben erhalten.")
            }
        }
    }
}

private struct ProjectStopDialogModifier: ViewModifier {
    @EnvironmentObject private var appState: AppState
    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Alle Laufzeiten dieses Projekts stoppen?",
            isPresented: Binding(
                get: { appState.projectPendingStop != nil },
                set: { if !$0 { appState.projectPendingStop = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Alles stoppen", role: .destructive) { appState.confirmProjectStop() }
            Button("Abbrechen", role: .cancel) { appState.projectPendingStop = nil }
        } message: {
            if let project = appState.projectPendingStop {
                Text("\(project.servers.count) lokale Prozesse und \(project.containers.filter(\.isRunning).count) laufende Container werden sauber gestoppt. Docker-Ressourcen werden nicht gelöscht.")
            }
        }
    }
}

private struct AppErrorAlertModifier: ViewModifier {
    @EnvironmentObject private var appState: AppState
    func body(content: Content) -> some View {
        content.alert("Fehler", isPresented: Binding(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )) {
            Button("OK") { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "Unbekannter Fehler")
        }
    }
}
