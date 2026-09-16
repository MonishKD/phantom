import AppKit
import MapKit
import SwiftUI

struct MapPane: View {
    @EnvironmentObject private var bridge: DeviceBridge
    @EnvironmentObject private var model: PhantomModel
    @AppStorage("teleportOnClick") private var teleportOnClick = true
    @AppStorage("satelliteMap") private var satellite = false

    var body: some View {
        MapReader { proxy in
            Map(position: $model.camera) {
                if let active = bridge.activeCoordinate {
                    Annotation("Simulated location", coordinate: active, anchor: .center) {
                        SpoofedLocationDot()
                    }
                }
                if let pin = model.pin, !isActive(pin) {
                    Marker(pin.name, systemImage: "mappin", coordinate: pin.coordinate)
                        .tint(Theme.accent)
                }
            }
            .mapStyle(satellite ? .hybrid(elevation: .realistic) : .standard(elevation: .realistic, emphasis: .muted))
            .mapControls {}  // replaced by MapControlBar, which matches the rest of the UI
            .onMapCameraChange(frequency: .onEnd) { context in
                model.visibleRegion = context.region
            }
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                model.choose(coordinate, teleport: teleportOnClick && bridge.canTeleport, flyTo: false)
            }
        }
        .overlay(alignment: .topTrailing) {
            MapControlBar()
                .padding(.top, 36)  // below the window's title bar strip
                .padding(.trailing, 16)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 10) {
                RestoreToast()
                ErrorBanner()
                PlaceCard()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .overlay {
            if bridge.helperState == .notInstalled {
                SetupCard()
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: bridge.lastError)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: bridge.restoreNotice)
        .onChange(of: activeKey, initial: true) { _, key in
            // Phantom opened while a location is already simulated: show where the device is.
            guard key != nil, model.pin == nil, !model.hasCenteredOnDevice, let active = bridge.activeCoordinate else { return }
            model.hasCenteredOnDevice = true
            model.fly(to: active)
        }
    }

    private var activeKey: String? {
        bridge.activeCoordinate.map { "\($0.latitude),\($0.longitude)" }
    }

    private func isActive(_ pin: SavedPlace) -> Bool {
        guard let active = bridge.activeCoordinate else { return false }
        return active.distance(to: pin.coordinate) < 1
    }
}

// MARK: - Floating controls

struct PlaceCard: View {
    @EnvironmentObject private var bridge: DeviceBridge
    @EnvironmentObject private var model: PhantomModel
    @AppStorage("teleportOnClick") private var teleportOnClick = true

    private var deviceNoun: String { bridge.selectedDevice?.noun ?? "device" }

    var body: some View {
        HStack(spacing: 12) {
            if let pin = model.pin {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pin.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(pin.coordinate.formatted)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 8)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(pin.coordinate.formatted, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(IconButtonStyle())
                .help("Copy coordinates")

                if model.isTeleporting {
                    ProgressView().controlSize(.small)
                }
                Button("Teleport Here") { model.teleportToPin() }
                    .buttonStyle(PhantomButtonStyle(kind: .primary))
                    .disabled(!bridge.canTeleport || pinIsActive(pin))
            } else {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.accent)
                Text("Click anywhere on the map to move your \(deviceNoun) there.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
            }

            Rectangle()
                .fill(Theme.border)
                .frame(width: 1, height: 22)

            Toggle("Instant", isOn: $teleportOnClick)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Theme.accent)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .help("Move the \(deviceNoun) as soon as you click the map or pick a search result")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 600, alignment: .leading)
        .floatingPanel()
    }

    private func pinIsActive(_ pin: SavedPlace) -> Bool {
        guard let active = bridge.activeCoordinate else { return false }
        return active.distance(to: pin.coordinate) < 1
    }
}

struct MapControlBar: View {
    @EnvironmentObject private var bridge: DeviceBridge
    @EnvironmentObject private var model: PhantomModel
    @AppStorage("satelliteMap") private var satellite = false

    var body: some View {
        HStack(spacing: 2) {
            segment("Map", selected: !satellite) { satellite = false }
            segment("Satellite", selected: satellite) { satellite = true }
            divider
            Button { model.zoom(by: 0.5) } label: { Image(systemName: "plus") }
                .buttonStyle(IconButtonStyle())
                .help("Zoom in")
            Button { model.zoom(by: 2) } label: { Image(systemName: "minus") }
                .buttonStyle(IconButtonStyle())
                .help("Zoom out")
            divider
            Button {
                if let active = bridge.activeCoordinate { model.fly(to: active) }
            } label: {
                Image(systemName: "location.fill")
            }
            .buttonStyle(IconButtonStyle())
            .disabled(bridge.activeCoordinate == nil)
            .help("Center on the simulated location")
            Button { model.showActivity.toggle() } label: { Image(systemName: "list.bullet.rectangle") }
                .buttonStyle(IconButtonStyle())
                .help("Helper activity log")
                .popover(isPresented: $model.showActivity, arrowEdge: .bottom) {
                    ActivityLog()
                }
        }
        .padding(4)
        .floatingPanel(cornerRadius: 12)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(width: 1, height: 18)
            .padding(.horizontal, 4)
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(selected ? Color.black : Theme.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(selected ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Notices

struct RestoreToast: View {
    @EnvironmentObject private var bridge: DeviceBridge

    var body: some View {
        if let notice = bridge.restoreNotice {
            HStack(spacing: 12) {
                switch notice {
                case .restoring:
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Restoring your real location")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Give it a few seconds.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                case .restored:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.success)
                    Text("Real location restored")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .floatingPanel()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct ErrorBanner: View {
    @EnvironmentObject private var bridge: DeviceBridge

    var body: some View {
        if let error = bridge.lastError {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.danger)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(error.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(error.message)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                    if let hint = error.hint(bridge.selectedDevice?.noun ?? "device") {
                        Text(hint)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    bridge.lastError = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(IconButtonStyle())
            }
            .padding(14)
            .frame(maxWidth: 560)
            .floatingPanel()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct SetupCard: View {
    @EnvironmentObject private var installer: Installer
    @EnvironmentObject private var bridge: DeviceBridge

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                PhantomLogo(size: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text("One-time setup")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("About a minute, with an internet connection")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Text("Phantom talks to your iPhone or iPad through the open-source pymobiledevice3 toolkit. It installs into ~/Library/Application Support/Phantom.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !installer.output.isEmpty {
                ScrollView {
                    Text(installer.output)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 160)
                .padding(10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if installer.didFail {
                Text("Setup failed. See the output above.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.danger)
            }

            HStack {
                Spacer()
                if installer.isRunning {
                    ProgressView().controlSize(.small)
                }
                Button(installer.isRunning ? "Installing…" : "Install") {
                    Task {
                        if await installer.install() { bridge.start() }
                    }
                }
                .buttonStyle(PhantomButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(installer.isRunning)
            }
        }
        .padding(22)
        .frame(width: 480)
        .floatingPanel(cornerRadius: 16)
    }
}

struct ActivityLog: View {
    @EnvironmentObject private var bridge: DeviceBridge

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Activity")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Copy All") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(bridge.log.joined(separator: "\n"), forType: .string)
                }
                .buttonStyle(PhantomLinkStyle())
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(bridge.log.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(10)
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onAppear { proxy.scrollTo(bridge.log.count - 1, anchor: .bottom) }
                .onChange(of: bridge.log.count) { _, count in
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
        }
        .padding(14)
        .frame(width: 620, height: 400)
        .background(Theme.background)
    }
}

/// Pulsing dot marking where the device currently thinks it is.
/// Driven by TimelineView because the Command Line Tools SDK ships without the @State macro plugin.
struct SpoofedLocationDot: View {
    private let period = 1.8

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let progress = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.35))
                    .frame(width: 60, height: 60)
                    .scaleEffect(0.3 + 0.7 * progress)
                    .opacity(1 - progress)
                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.5), radius: 3)
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 15, height: 15)
            }
        }
    }
}
