import Foundation
import StoreKit
import Observation
import UIKit

struct PremiumProduct: Equatable {
    let id: String
    let displayPrice: String
}
enum PurchaseOutcome { case purchased, pending, cancelled }

@MainActor protocol PurchaseProvider {
    var changes: AsyncStream<Void> { get }
    func product() async throws -> PremiumProduct?
    func purchase() async throws -> PurchaseOutcome
    func restore() async throws
    func hasEntitlement() async throws -> Bool
}

enum EntitlementPolicy {
    static func grants(productID: String, expectedID: String, verified: Bool, nonConsumable: Bool, revoked: Bool) -> Bool {
        !expectedID.isEmpty && productID == expectedID && verified && nonConsumable && !revoked
    }
}

@MainActor final class StoreKitProvider: PurchaseProvider {
    let productID: String
    let changes: AsyncStream<Void>
    private var updatesTask: Task<Void, Never>?
    private var loadedProduct: Product?

    init(productID: String) {
        self.productID = productID.trimmingCharacters(in: .whitespacesAndNewlines)
        var continuation: AsyncStream<Void>.Continuation!
        changes = AsyncStream { continuation = $0 }
        let identifier = self.productID
        if identifier.isEmpty { continuation.finish(); return }
        updatesTask = Task {
            for await update in Transaction.updates {
                guard !Task.isCancelled else { break }
                if case .verified(let transaction) = update, transaction.productID == identifier {
                    continuation.yield(())
                    await transaction.finish()
                }
            }
            continuation.finish()
        }
    }
    deinit { updatesTask?.cancel() }
    func product() async throws -> PremiumProduct? {
        guard !productID.isEmpty else { return nil }
        loadedProduct = try await Product.products(for: [productID]).first { $0.id == productID && $0.type == .nonConsumable }
        return loadedProduct.map { PremiumProduct(id: $0.id, displayPrice: $0.displayPrice) }
    }
    func hasEntitlement() async throws -> Bool {
        guard !productID.isEmpty else { return false }
        // StoreKit provides signed, locally available entitlements while offline.
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               EntitlementPolicy.grants(productID: transaction.productID, expectedID: productID, verified: true,
                                        nonConsumable: transaction.productType == .nonConsumable,
                                        revoked: transaction.revocationDate != nil) {
                return true
            }
        }
        return false
    }
    func purchase() async throws -> PurchaseOutcome {
        if loadedProduct == nil { _ = try await product() }
        guard let loadedProduct else { throw CareError.purchaseUnavailable }
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) else {
            throw CareError.purchaseUnavailable
        }
        switch try await loadedProduct.purchase(confirmIn: scene) {
        case .success(let result):
            guard case .verified(let transaction) = result,
                  EntitlementPolicy.grants(productID: transaction.productID, expectedID: productID, verified: true,
                                           nonConsumable: transaction.productType == .nonConsumable,
                                           revoked: transaction.revocationDate != nil) else { throw CareError.verification }
            await transaction.finish()
            return .purchased
        case .pending: return .pending
        case .userCancelled: return .cancelled
        @unknown default: throw CareError.purchaseUnavailable
        }
    }
    func restore() async throws { try await AppStore.sync() }
}

@MainActor @Observable final class PremiumStore {
    private let provider: any PurchaseProvider
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private(set) var isPremium = false
    private(set) var isRefreshing = true
    private(set) var isBusy = false
    private(set) var product: PremiumProduct?
    var message: String?
    init(provider: any PurchaseProvider) {
        self.provider = provider
        let changes = provider.changes
        updatesTask = Task { [weak self] in
            for await _ in changes {
                guard !Task.isCancelled else { break }
                await self?.refresh()
            }
        }
    }
    deinit { updatesTask?.cancel() }
    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        isRefreshing = true
        do {
            let entitled = try await provider.hasEntitlement()
            guard generation == refreshGeneration else { return }
            isPremium = entitled
        } catch {
            guard generation == refreshGeneration else { return }
            isPremium = false; message = CareError.verification.localizedDescription
        }
        isRefreshing = false
    }
    func loadProduct() async {
        do { product = try await provider.product() }
        catch { message = CareError.purchaseUnavailable.localizedDescription }
    }
    func purchase() async {
        guard !isBusy else { return }
        isBusy = true; message = nil
        defer { isBusy = false }
        do {
            switch try await provider.purchase() {
            case .purchased: await refresh()
            case .pending: message = L10n.text("Your purchase is pending approval.")
            case .cancelled: break
            }
        } catch { message = (error as? CareError ?? .purchaseUnavailable).localizedDescription }
    }
    func restore() async {
        guard !isBusy else { return }
        isBusy = true; message = nil
        defer { isBusy = false }
        do {
            try await provider.restore()
            await refresh()
            message = L10n.text(isPremium ? "Premium purchases restored." : "No verified premium purchase was found.")
        } catch { message = L10n.text("Purchases could not be restored. Check your connection and try again.") }
    }
}
