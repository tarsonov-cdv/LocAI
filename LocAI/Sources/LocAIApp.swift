import SwiftUI

@main
struct LocAIApp: App {
    @State private var settings = AppSettings()
    @State private var appState = AppState()
    @State private var modelManager = ModelManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(appState)
                .environment(modelManager)
                .preferredColorScheme(.dark) // liquid glass reads best over a dark canvas
                .onAppear {
                    modelManager.ensureDirectories(base: settings.modelsBaseDir)
                    modelManager.refresh(base: settings.modelsBaseDir)
                }
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 720)
        #endif
    }
}
