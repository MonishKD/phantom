import AppKit
import SwiftUI

@main
struct PhantomApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var bridge: DeviceBridge
    @StateObject private var recents: RecentPlaces
    @StateObject private var model: PhantomModel
    @StateObject private var search = LocationSearch()
    @StateObject private var installer = Installer()

    init() {
        // Writing to the helper after it dies must surface as an error, not kill the app.
        signal(SIGPIPE, SIG_IGN)

        let bridge = DeviceBridge()
        let recents = RecentPlaces()
        _bridge = StateObject(wrappedValue: bridge)
        _recents = StateObject(wrappedValue: recents)
        _model = StateObject(wrappedValue: PhantomModel(bridge: bridge, recents: recents))
        AppDelegate.bridge = bridge
    }

    var body: some Scene {
        WindowGroup("Phantom") {
            ContentView()
                .environmentObject(bridge)
                .environmentObject(recents)
                .environmentObject(model)
                .environmentObject(search)
                .environmentObject(installer)
                .frame(minWidth: 960, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            LocationCommands(bridge: bridge, model: model)
        }
    }
}

/// Every action in the window, reachable from the menu bar and the keyboard.
struct LocationCommands: Commands {
    @ObservedObject var bridge: DeviceBridge
    @ObservedObject var model: PhantomModel
    @AppStorage("satelliteMap") private var satellite = false

    var body: some Commands {
        CommandMenu("Location") {
            Button("Teleport to Pin") { model.teleportToPin() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!bridge.canTeleport || model.pin == nil)
            Button("Restore Real Location") { Task { await bridge.restoreRealLocation() } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!bridge.canTeleport || bridge.isRestoring)
            Divider()
            Button("Center on Device") {
                if let active = bridge.activeCoordinate { model.fly(to: active) }
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(bridge.activeCoordinate == nil)
        }
        CommandGroup(after: .toolbar) {
            Picker("Map Style", selection: $satellite) {
                Text("Map").tag(false)
                Text("Satellite").tag(true)
            }
            .pickerStyle(.inline)
            Divider()
            Button("Zoom In") { model.zoom(by: 0.5) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Zoom Out") { model.zoom(by: 2) }
                .keyboardShortcut("-", modifiers: .command)
            Divider()
            Button("Show Activity") { model.showActivity.toggle() }
                .keyboardShortcut("a", modifiers: [.command, .option])
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var bridge: DeviceBridge?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Jet black throughout: system controls, menus and popovers follow the dark appearance.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private var terminationAnswered = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            // A proper restore takes several seconds, longer than applicationWillTerminate can wait, so
            // quitting holds off until the device has its real location back (at most 20 seconds).
            guard let bridge = AppDelegate.bridge, bridge.isRestoring || bridge.activeCoordinate != nil else {
                return .terminateNow
            }
            Task { @MainActor in
                if bridge.isRestoring {
                    while bridge.isRestoring { try? await Task.sleep(for: .milliseconds(200)) }
                } else {
                    await bridge.restoreRealLocation()
                }
                self.answerTermination()
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(20))
                self.answerTermination()
            }
            return .terminateLater
        }
    }

    @MainActor private func answerTermination() {
        guard !terminationAnswered else { return }
        terminationAnswered = true
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Give the helper a moment to hand the device its real location back.
        MainActor.assumeIsolated {
            AppDelegate.bridge?.shutdownAndWait()
        }
    }
}
