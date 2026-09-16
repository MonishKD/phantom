import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var bridge: DeviceBridge

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 320)
            Rectangle()
                .fill(Theme.border)
                .frame(width: 1)
            MapPane()
        }
        .background(Theme.background)
        .background(WindowChrome())
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear { bridge.start() }
    }
}

/// Paints the window itself black, so resizing and the title bar area never show the default grey.
private struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.backgroundColor = .black
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
