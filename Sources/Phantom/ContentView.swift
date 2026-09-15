import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var bridge: DeviceBridge

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 290, ideal: 320, max: 400)
        } detail: {
            MapPane()
        }
        .onAppear { bridge.start() }
    }
}
