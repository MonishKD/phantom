import MapKit
import SwiftUI

struct Sidebar: View {
    @EnvironmentObject private var recents: RecentPlaces

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Device")
                        DevicePanel()
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Go To")
                        SearchPanel()
                    }
                    if !recents.places.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel(title: "Recent") {
                                Button("Clear") { recents.clear() }
                                    .buttonStyle(PhantomLinkStyle())
                            }
                            VStack(spacing: 1) {
                                ForEach(recents.places) { place in
                                    RecentRow(place: place)
                                }
                            }
                            .padding(.horizontal, -10)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.never)
            SidebarFooter()
        }
        .background(Theme.background)
    }
}

struct SidebarHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            PhantomLogo(size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text("PHANTOM")
                    .font(.system(size: 15, weight: .heavy))
                    .tracking(3.4)
                    .foregroundStyle(Theme.textPrimary)
                Text("Location for iPhone & iPad")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 46)  // clears the window's traffic lights
        .padding(.bottom, 22)
    }
}

// MARK: - Device

struct DevicePanel: View {
    @EnvironmentObject private var bridge: DeviceBridge

    var body: some View {
        switch bridge.helperState {
        case .stopped, .starting:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Starting device helper…")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            .phantomCard()
        case .notInstalled:
            Text("Finish the one-time setup to connect your iPhone or iPad.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
                .phantomCard()
        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.danger)
                    Text(message)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Restart Helper") { bridge.restart() }
                    .buttonStyle(PhantomButtonStyle(kind: .secondary))
            }
            .phantomCard()
        case .running:
            if bridge.devices.isEmpty {
                NoDeviceCard()
            } else {
                VStack(spacing: 8) {
                    if bridge.devices.count > 1 {
                        Picker("Device", selection: $bridge.selectedUDID) {
                            ForEach(bridge.devices) { device in
                                Text(device.displayName).tag(Optional(device.udid))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    if let device = bridge.selectedDevice {
                        DeviceCard(device: device, status: bridge.selectedStatus)
                    }
                }
            }
        }
    }
}

struct NoDeviceCard: View {
    @EnvironmentObject private var bridge: DeviceBridge

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "cable.connector")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                Text("No device connected")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("Plug your iPhone or iPad into this Mac with a cable, unlock it, and tap **Trust** if asked.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Refresh") { Task { await bridge.refreshDevices() } }
                .buttonStyle(PhantomLinkStyle())
        }
        .phantomCard()
    }
}

struct DeviceCard: View {
    @EnvironmentObject private var bridge: DeviceBridge
    let device: DeviceInfo
    let status: SessionStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: device.icon)
                    .font(.system(size: 19))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let model = device.model {
                        Text(model)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Text(device.systemAndConnection)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            StatusRow(status: status, noun: device.noun, waitingForDeveloperMode: device.paired && device.developerMode == false)

            if !device.paired {
                Callout(icon: "lock.fill", tint: Theme.warning) {
                    Text("Unlock your \(device.noun) and tap **Trust** to pair it with this Mac.")
                    Button("Pair Now") { Task { await bridge.pair() } }
                        .buttonStyle(PhantomButtonStyle(kind: .secondary))
                }
            } else if device.developerMode == false {
                DeveloperModeGuide(noun: device.noun)
            }

            if let problem = device.problem {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.warning)
            }
        }
        .phantomCard()
    }
}

/// How to switch Developer Mode on. The helper reveals the switch in Settings on its own.
struct DeveloperModeGuide: View {
    let noun: String

    var body: some View {
        Callout(icon: "hammer.fill", tint: Theme.warning) {
            Text("Turn on Developer Mode")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            VStack(alignment: .leading, spacing: 7) {
                step(1, "Open **Settings › Privacy & Security** on the \(noun).")
                step(2, "Scroll to the bottom, tap **Developer Mode**, and switch it on.")
                step(3, "Tap **Restart**. When the \(noun) is back, unlock it and tap **Turn On**.")
            }
            Text("Don't see Developer Mode? Keep the \(noun) connected to this Mac, then close and reopen Settings.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(Color.black)
                .frame(width: 16, height: 16)
                .background(Theme.warning, in: Circle())
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct Callout<Content: View>: View {
    let icon: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 9) {
                content
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.07), in: shape)
        .overlay(shape.strokeBorder(tint.opacity(0.28), lineWidth: 1))
    }
}

struct StatusRow: View {
    let status: SessionStatus?
    let noun: String
    var waitingForDeveloperMode = false

    var body: some View {
        let phase = status?.phase ?? .idle
        let waiting = waitingForDeveloperMode && phase == .idle
        let dot = waiting ? Theme.warning : phase.color
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                if phase.isWorking {
                    ProgressView().controlSize(.mini)
                } else {
                    Circle()
                        .fill(dot)
                        .frame(width: 7, height: 7)
                        .shadow(color: dot.opacity(phase == .active || waiting ? 0.9 : 0), radius: 4)
                }
            }
            .frame(width: 14)
            Text(waiting ? "Waiting for Developer Mode" : (status?.message ?? phase.defaultMessage(noun)))
                .font(.system(size: 12))
                .foregroundStyle(phase == .error ? Theme.danger : Theme.textSecondary)
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
        case .active: Theme.success
        case .error: Theme.danger
        case .reconnecting: Theme.warning
        default: Theme.textTertiary
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

// MARK: - Search

struct SearchPanel: View {
    @EnvironmentObject private var bridge: DeviceBridge
    @EnvironmentObject private var model: PhantomModel
    @EnvironmentObject private var search: LocationSearch
    @AppStorage("teleportOnClick") private var teleportOnClick = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            let field = RoundedRectangle(cornerRadius: 10, style: .continuous)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                TextField("Search a place or paste lat, lon", text: $search.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                    .onSubmit(submit)
                if !search.query.isEmpty {
                    Button {
                        search.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(Theme.surface, in: field)
            .overlay(field.strokeBorder(Theme.border, lineWidth: 1))

            VStack(spacing: 1) {
                if let coordinate = search.typedCoordinate {
                    resultRow(icon: "scope", title: coordinate.formatted, subtitle: "Coordinates") {
                        go(to: coordinate, name: nil)
                    }
                }
                ForEach(search.completions, id: \.self) { completion in
                    resultRow(icon: "mappin.circle", title: completion.title, subtitle: completion.subtitle) {
                        Task { await pick(completion) }
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private func resultRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            .modifier(HoverRow())
        }
        .buttonStyle(.plain)
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
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(place.coordinate.formatted)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .modifier(HoverRow())
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
        Button {
            Task { await bridge.restoreRealLocation() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "location.slash.fill")
                Text("Restore Real Location")
            }
            .padding(.vertical, 3)
        }
        .buttonStyle(PhantomButtonStyle(kind: .secondary, fullWidth: true))
        // Stays available whenever a device is connected: the device can still be simulating a
        // location this run never set, and the app can't know that until it asks.
        .disabled(!bridge.canTeleport || bridge.isRestoring)
        .padding(16)
        .background(Theme.background)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }
}
