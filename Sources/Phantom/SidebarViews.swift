import MapKit
import SwiftUI

struct Sidebar: View {
    @EnvironmentObject private var recents: RecentPlaces

    var body: some View {
        List {
            Section("Device") {
                DevicePanel()
            }
            Section("Go To") {
                SearchPanel()
            }
            if !recents.places.isEmpty {
                Section {
                    ForEach(recents.places) { place in
                        RecentRow(place: place)
                    }
                } header: {
                    HStack {
                        Text("Recent")
                        Spacer()
                        Button("Clear") { recents.clear() }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { SidebarFooter() }
    }
}

// MARK: - Device

struct DevicePanel: View {
    @EnvironmentObject private var bridge: DeviceBridge

    var body: some View {
        switch bridge.helperState {
        case .stopped, .starting:
            Label {
                Text("Starting device helper…")
            } icon: {
                ProgressView().controlSize(.small)
            }
        case .notInstalled:
            Label("Finish the one-time setup to connect your iPhone or iPad.", systemImage: "shippingbox")
                .foregroundStyle(.secondary)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Button("Restart Helper") { bridge.restart() }
            }
        case .running:
            if bridge.devices.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("No device connected", systemImage: "cable.connector")
                        .font(.headline)
                    Text("Plug your iPhone or iPad into this Mac with a cable, unlock it, and tap **Trust** if asked.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Refresh") { Task { await bridge.refreshDevices() } }
                        .buttonStyle(.link)
                }
                .padding(.vertical, 4)
            } else {
                if bridge.devices.count > 1 {
                    Picker("Device", selection: $bridge.selectedUDID) {
                        ForEach(bridge.devices) { device in
                            Text(device.displayName).tag(Optional(device.udid))
                        }
                    }
                    .labelsHidden()
                }
                if let device = bridge.selectedDevice {
                    DeviceCard(device: device, status: bridge.selectedStatus)
                }
            }
        }
    }
}

struct DeviceCard: View {
    @EnvironmentObject private var bridge: DeviceBridge
    let device: DeviceInfo
    let status: SessionStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: device.icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(device.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            StatusRow(status: status, noun: device.noun)

            if !device.paired {
                Notice(systemImage: "lock", text: "Unlock your \(device.noun) and tap **Trust** to pair it with this Mac.") {
                    Button("Pair Now") { Task { await bridge.pair() } }
                }
            } else if device.developerMode == false {
                Notice(
                    systemImage: "hammer",
                    text: "Turn on **Developer Mode** in Settings › Privacy & Security, let the \(device.noun) restart, then confirm."
                ) {
                    Button("Show the Developer Mode Switch") { Task { await bridge.revealDeveloperMode() } }
                }
            }

            if let problem = device.problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

struct StatusRow: View {
    let status: SessionStatus?
    let noun: String

    var body: some View {
        let phase = status?.phase ?? .idle
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if phase.isWorking {
                ProgressView().controlSize(.mini)
            } else {
                Circle()
                    .fill(phase.color)
                    .frame(width: 8, height: 8)
            }
            Text(status?.message ?? phase.defaultMessage(noun))
                .font(.callout)
                .foregroundStyle(phase == .error ? Color.red : Color.primary)
                .lineLimit(4)
        }
    }
}

extension SessionPhase {
    var isWorking: Bool {
        switch self {
        case .connecting, .mounting, .tunneling, .reconnecting: true
        default: false
        }
    }

    var color: Color {
        switch self {
        case .active: .green
        case .error: .red
        case .reconnecting: .orange
        default: .secondary
        }
    }

    func defaultMessage(_ noun: String) -> String {
        switch self {
        case .idle: "Ready. Click the map to move your \(noun)."
        case .connecting: "Connecting to \(noun)…"
        case .mounting: "Mounting developer disk image…"
        case .tunneling: "Opening a secure tunnel…"
        case .active: "Location simulated"
        case .reconnecting: "Connection lost, reconnecting…"
        case .error: "Error"
        }
    }
}

struct Notice<Actions: View>: View {
    let systemImage: String
    let text: LocalizedStringKey
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(text).font(.callout)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(.orange)
            }
            actions.controlSize(.small)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Search

struct SearchPanel: View {
    @EnvironmentObject private var bridge: DeviceBridge
    @EnvironmentObject private var model: PhantomModel
    @EnvironmentObject private var search: LocationSearch
    @AppStorage("teleportOnClick") private var teleportOnClick = true

    var body: some View {
        TextField("Search a place or paste “lat, lon”", text: $search.query)
            .textFieldStyle(.roundedBorder)
            .onSubmit(submit)

        if let coordinate = search.typedCoordinate {
            Button {
                go(to: coordinate, name: nil)
            } label: {
                Label(coordinate.formatted, systemImage: "scope")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        ForEach(search.completions, id: \.self) { completion in
            Button {
                Task { await pick(completion) }
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(completion.title).lineLimit(1)
                    if !completion.subtitle.isEmpty {
                        Text(completion.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func submit() {
        if let coordinate = search.typedCoordinate {
            go(to: coordinate, name: nil)
        } else if let first = search.completions.first {
            Task { await pick(first) }
        }
    }

    private func pick(_ completion: MKLocalSearchCompletion) async {
        guard let result = await search.resolve(completion) else {
            bridge.lastError = HelperFailure(code: "SEARCH", message: "Couldn't find “\(completion.title)” on the map.")
            return
        }
        go(to: result.coordinate, name: result.name)
    }

    private func go(to coordinate: CLLocationCoordinate2D, name: String?) {
        model.choose(coordinate, name: name, teleport: teleportOnClick && bridge.canTeleport, flyTo: true)
        search.clear()
    }
}

struct RecentRow: View {
    @EnvironmentObject private var bridge: DeviceBridge
    @EnvironmentObject private var model: PhantomModel
    @EnvironmentObject private var recents: RecentPlaces
    @AppStorage("teleportOnClick") private var teleportOnClick = true
    let place: SavedPlace

    var body: some View {
        Button {
            model.choose(place.coordinate, name: place.name, teleport: teleportOnClick && bridge.canTeleport, flyTo: true)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(place.name).lineLimit(1)
                Text(place.coordinate.formatted)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove from Recents") { recents.remove(place) }
        }
    }
}

struct SidebarFooter: View {
    @EnvironmentObject private var bridge: DeviceBridge

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                Task { await bridge.restoreRealLocation() }
            } label: {
                HStack(spacing: 6) {
                    if bridge.isRestoring {
                        ProgressView().controlSize(.small)
                    }
                    Label("Restore Real Location", systemImage: "location.slash")
                }
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            // Stays available whenever a device is connected: the device can still be simulating a
            // location this run never set, and the app can't know that until it asks.
            .disabled(!bridge.canTeleport || bridge.isRestoring)
            .padding(12)
        }
        .background(.bar)
    }
}
