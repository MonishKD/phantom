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
                        .tint(.orange)
                }
            }
            .mapStyle(satellite ? .hybrid(elevation: .realistic) : .standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapScaleView()
                MapZoomStepper()
            }
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                model.choose(coordinate, teleport: teleportOnClick && bridge.canTeleport, flyTo: false)
            }
        }
        .overlay(alignment: .top) {
            PlaceCard().padding(12)
        }
        .overlay(alignment: .bottom) {
            ErrorBanner()
        }
        .overlay {
            if bridge.helperState == .notInstalled {
                SetupCard()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: bridge.lastError)
        .toolbar {
            ToolbarItemGroup {
                Picker("Map Style", selection: $satellite) {
                    Text("Map").tag(false)
                    Text("Satellite").tag(true)
                }
                .pickerStyle(.segmented)
                .help("Map style")

                Button {
                    if let active = bridge.activeCoordinate { model.fly(to: active) }
                } label: {
                    Label("Show Device Location", systemImage: "location.fill")
                }
                .disabled(bridge.activeCoordinate == nil)
                .help("Center the map on the simulated location")

                Button {
                    model.showActivity.toggle()
                } label: {
                    Label("Activity", systemImage: "list.bullet.rectangle")
                }
                .help("Helper activity log")
                .popover(isPresented: $model.showActivity, arrowEdge: .bottom) {
                    ActivityLog()
                }
            }
        }
    }

    private func isActive(_ pin: SavedPlace) -> Bool {
        guard let active = bridge.activeCoordinate else { return false }
        return active.distance(to: pin.coordinate) < 1
    }
}

struct PlaceCard: View {
    @EnvironmentObject private var bridge: DeviceBridge
    @EnvironmentObject private var model: PhantomModel
    @AppStorage("teleportOnClick") private var teleportOnClick = true

    private var deviceNoun: String { bridge.selectedDevice?.noun ?? "device" }

    var body: some View {
        HStack(spacing: 12) {
            if let pin = model.pin {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pin.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(pin.coordinate.formatted)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 8)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(pin.coordinate.formatted, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy coordinates")

                if model.isTeleporting {
                    ProgressView().controlSize(.small)
                }
                Button("Teleport Here") { model.teleportToPin() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!bridge.canTeleport || pinIsActive(pin))
            } else {
                Label("Click anywhere on the map to move your \(deviceNoun) there.", systemImage: "hand.tap")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
            }

            Divider().frame(height: 22)

            Toggle("Instant", isOn: $teleportOnClick)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Move the \(deviceNoun) as soon as you click the map or pick a search result")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 640)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }

    private func pinIsActive(_ pin: SavedPlace) -> Bool {
        guard let active = bridge.activeCoordinate else { return false }
        return active.distance(to: pin.coordinate) < 1
    }
}

struct ErrorBanner: View {
    @EnvironmentObject private var bridge: DeviceBridge

    var body: some View {
        if let error = bridge.lastError {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(error.title).font(.headline)
                    Text(error.message)
                        .font(.callout)
                        .textSelection(.enabled)
                    if let hint = error.hint(bridge.selectedDevice?.noun ?? "device") {
                        Text(hint)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    bridge.lastError = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }
            .padding(12)
            .frame(maxWidth: 560)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .padding(16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct SetupCard: View {
    @EnvironmentObject private var installer: Installer
    @EnvironmentObject private var bridge: DeviceBridge

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("One-time setup", systemImage: "shippingbox")
                .font(.title2.bold())
            Text("Phantom talks to your iPhone or iPad through the open-source pymobiledevice3 toolkit. It installs into ~/Library/Application Support/Phantom and takes about a minute online.")
                .fixedSize(horizontal: false, vertical: true)

            if !installer.output.isEmpty {
                ScrollView {
                    Text(installer.output)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 160)
                .padding(8)
                .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }

            if installer.didFail {
                Text("Setup failed. See the output above.")
                    .foregroundStyle(.red)
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
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(installer.isRunning)
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 4)
    }
}

struct ActivityLog: View {
    @EnvironmentObject private var bridge: DeviceBridge

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Activity").font(.headline)
                Spacer()
                Button("Copy All") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(bridge.log.joined(separator: "\n"), forType: .string)
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(bridge.log.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                }
                .onAppear { proxy.scrollTo(bridge.log.count - 1, anchor: .bottom) }
                .onChange(of: bridge.log.count) { _, count in
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
        }
        .padding(12)
        .frame(width: 600, height: 380)
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
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(width: 56, height: 56)
                    .scaleEffect(0.3 + 0.7 * progress)
                    .opacity(1 - progress)
                Circle()
                    .fill(.white)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 15, height: 15)
            }
        }
    }
}
