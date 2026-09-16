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

    func applicationWillTerminate(_ notification: Notification) {
        // Give the helper a moment to hand the device its real location back.
        MainActor.assumeIsolated {
            AppDelegate.bridge?.shutdownAndWait()
        }
    }
}
