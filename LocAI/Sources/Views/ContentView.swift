import SwiftUI

struct ContentView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ZStack {
            LiquidBackdrop()

            TabView {
                Tab(Loc.t("tab_chat", lang: settings.languageCode), systemImage: "bubble.left.and.bubble.right.fill") {
                    ChatView()
                }
                Tab(Loc.t("tab_models", lang: settings.languageCode), systemImage: "shippingbox.fill") {
                    ModelsView()
                }
                Tab(Loc.t("tab_settings", lang: settings.languageCode), systemImage: "slider.horizontal.3") {
                    SettingsView()
                }
                Tab(Loc.t("tab_tuning", lang: settings.languageCode), systemImage: "wand.and.stars") {
                    TuningView()
                }
            }
            // The system TabView already renders its bar as Liquid Glass
            // on macOS 26 / iOS 26 - no manual styling needed here.
        }
    }
}

#Preview {
    ContentView()
        .environment(AppSettings())
        .environment(AppState())
        .environment(ModelManager.shared)
}
