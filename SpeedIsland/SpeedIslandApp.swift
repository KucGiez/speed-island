import SwiftUI

@main
struct SpeedIslandApp: App {
    @State private var monitor = SpeedMonitor()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(monitor)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            monitor.scenePhaseChanged(phase)
        }
    }
}
