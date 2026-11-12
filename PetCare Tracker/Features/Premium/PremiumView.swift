import SwiftUI

struct PremiumView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        Image(systemName: "pawprint.circle").font(.largeTitle).foregroundStyle(CareTheme.tint).accessibilityHidden(true)
                        Text("More companions. One home.").font(.title.bold())
                        Text("Lifetime premium adds unlimited pet profiles, weight charts, custom reminder intervals, veterinarian contacts and offline PDF health exports.")
                    }.padding(.vertical, 16)
                }
                Section("Included with premium") {
                    Label("Unlimited pet profiles", systemImage: "pawprint")
                    Label("PDF health exports", systemImage: "doc.richtext")
                    Label("Weight chart", systemImage: "chart.xyaxis.line")
                    Label("Custom reminder intervals", systemImage: "repeat")
                    Label("Veterinarian contact", systemImage: "cross.case")
                    Label("One-time purchase. No subscription.", systemImage: "checkmark.seal")
                }
                Section {
                    if services.premium.isPremium {
                        Label("Premium is active", systemImage: "checkmark.circle.fill").foregroundStyle(CareTheme.tint)
                    } else if let product = services.premium.product {
                        Button {
                            Task { await services.premium.purchase() }
                        } label: {
                            HStack {
                                Text("Unlock lifetime premium")
                                Spacer()
                                Text(product.displayPrice)
                            }
                        }.disabled(services.premium.isBusy || services.premium.isRefreshing)
                    } else {
                        Text("Premium is not available for purchase right now. Your free features remain available.")
                            .foregroundStyle(.secondary)
                        Button("Try again") { Task { await services.premium.loadProduct() } }
                    }
                    Button("Restore purchases") { Task { await services.premium.restore() } }.disabled(services.premium.isBusy)
                    if services.premium.isBusy { ProgressView("Contacting the App Store") }
                    if let message = services.premium.message { Text(message).font(.callout).accessibilityIdentifier("purchaseMessage") }
                }
                Section {
                    Text("Your existing pets and records stay on your device if premium access changes.")
                    Text("Core records and essential reminders are included with one free pet profile.")
                }.font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Premium").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await services.premium.loadProduct() }
        }
    }
}
