import XCTest
import StoreKitTest
import StoreKit
@testable import PetCare_Tracker

@MainActor final class StoreKitIntegrationTests: XCTestCase {
    // "Premium purchases and restoration work in StoreKit testing."
    func testVerifiedLocalPurchaseAutomaticRestorationAndRefund() async throws {
        let configuration = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PetCareTesting", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: configuration)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        let provider = StoreKitProvider(productID: "petcaretracker.test.premium.lifetime")
        let offered = try await Product.products(for: ["petcaretracker.test.premium.lifetime"])
        XCTAssertEqual(offered.map(\.id), ["petcaretracker.test.premium.lifetime"], "Local StoreKit configuration must publish the test product.")
        let product = try await provider.product()
        XCTAssertNotNil(product)
        let before = try await provider.hasEntitlement()
        XCTAssertFalse(before)
        _ = try await session.buyProduct(identifier: "petcaretracker.test.premium.lifetime")
        // The test server's receipt can reach currentEntitlements after buyProduct
        // returns. Wait for the actual entitlement rather than an unrelated UI delay.
        var after = false
        for _ in 0..<30 {
            after = try await provider.hasEntitlement()
            if after { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(after)
        var verifiedTransaction: Transaction?
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == "petcaretracker.test.premium.lifetime" {
                verifiedTransaction = transaction
            }
        }
        let localTransaction = try XCTUnwrap(verifiedTransaction)
        XCTAssertEqual(localTransaction.environment, .xcode)
        // A newly created provider represents a fresh launch, not an in-memory boolean.
        let reopened = StoreKitProvider(productID: "petcaretracker.test.premium.lifetime")
        let restoredStore = PremiumStore(provider: reopened)
        await restoredStore.refresh()
        XCTAssertTrue(restoredStore.isPremium)
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.refundTransaction(identifier: transaction.identifier)
        var entitled = true
        for _ in 0..<30 {
            entitled = try await reopened.hasEntitlement()
            if !entitled { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(entitled)
    }
}
