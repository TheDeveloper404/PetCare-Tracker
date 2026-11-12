import SwiftUI
import UIKit

@main struct MyApp: App {
    @State private var services: AppServices?
    @State private var startupFailed = false
    var body: some Scene {
        WindowGroup {
            Group {
                if let services { ContentView().environment(services) }
                else if startupFailed {
                    ContentUnavailableView {
                        Label("Your data could not be opened", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text("Your stored data has not been deleted. Restart the app or try again. Do not reinstall the app without a backup.")
                    } actions: { Button("Try again") { openStore() }.buttonStyle(.borderedProminent) }
                } else { ProgressView("Opening your care journal").task { openStore() } }
            }.tint(CareTheme.tint)
        }
    }
    private func openStore() {
        do { services = try AppServices.live(); startupFailed = false }
        catch { startupFailed = true }
    }
}
