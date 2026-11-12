import SwiftUI

struct ContentView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var phase
    @AppStorage("hasCompletedOnboarding") private var onboarded = false
    @AppStorage("appLanguage") private var language = "system"
    var body: some View {
        Group {
            if onboarded {
                TabView {
                    DashboardView().tabItem { Label("Today", systemImage: "house") }
                    PetsView().tabItem { Label("Pets", systemImage: "pawprint") }
                    RemindersView().tabItem { Label("Reminders", systemImage: "bell") }
                    SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
                }
                .safeAreaInset(edge: .top) {
                    if let error = services.store.readError {
                        HStack { InlineError(message: error); Button("Try again") { services.store.refresh() } }
                            .padding(12).background(.regularMaterial)
                    }
                }
            } else { OnboardingView { onboarded = true } }
        }
        .environment(\.locale, language == "system" ? Locale.current : Locale(identifier: language))
        .id(language)
        .task { await services.activate() }
        .onChange(of: phase) { _, value in if value == .active { Task { await services.activate() } } }
        .onChange(of: services.store.revision) { _, _ in Task { await services.reconcile() } }
        .onChange(of: language) { _, _ in Task { await services.reconcile() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            Task { await services.reconcile() }
        }
    }
}
