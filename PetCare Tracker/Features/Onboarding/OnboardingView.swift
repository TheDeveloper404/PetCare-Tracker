import SwiftUI

struct OnboardingView: View {
    let finish: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Image(systemName: "pawprint.circle.fill").font(.system(size: 64)).foregroundStyle(CareTheme.tint).accessibilityHidden(true)
                Text("Good care starts with a little clarity.").font(.largeTitle.bold())
                Text("A private home for your pet's health history and everyday care.").font(.title3).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 24) {
                    Label("Keep health records together", systemImage: "heart.text.square")
                    Label("Remember upcoming care", systemImage: "bell.badge")
                    Label("Your data stays on your device", systemImage: "lock.shield")
                }.font(.headline)
                Text("No account needed. Start with one pet for free.").foregroundStyle(.secondary)
                Button("Get started", action: finish).buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("getStarted")
            }.padding(24).frame(maxWidth: 600, alignment: .leading).frame(maxWidth: .infinity)
        }
    }
}
