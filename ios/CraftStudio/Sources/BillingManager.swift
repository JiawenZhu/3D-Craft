import Combine
import Foundation
import StoreKit
import RevenueCat
import RevenueCatUI

/// RevenueCat & StoreKit unified billing manager.
/// Configured with RevenueCat purchases-ios SDK v5+ for entitlement checking,
/// paywalls, customer center, and backend token ledger synchronization.
@MainActor
final class BillingManager: ObservableObject {
    struct VerifiedPurchase: Identifiable, Equatable, Sendable {
        let productID: String
        let transactionID: UInt64
        let environment: String
        let isLocalTesting: Bool
        var id: UInt64 { transactionID }
    }

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case pendingApproval
        case awaitingCredit(UInt64)
        case completed(UInt64)
        case cancelled
        case failed
    }

    static let productIDs = [
        "craft.creator.weekly.v1",
        "craft.creator.monthly.v1",
        "craft.credits.small.v1",
        "craft.credits.medium.v1",
        "craft.credits.large.v1",
        "craft.creator.weekly300",
        "craft.starter100"
    ]
    static let revenueCatApiKey = "appl_VFwtbJPAzTWtBeGLvBVVXjKOJJI"
    static let creatorEntitlementID = "creator"

    struct PendingCredit: Codable, Equatable {
        let userID: String
        let productID: String
        let transactionID: String
        var showSuccess: Bool? = nil
    }
    private let pendingCreditKey = "craft.pendingRevenueCatCredits"
    var pendingCredits: [PendingCredit] {
        guard let data = UserDefaults.standard.data(forKey: pendingCreditKey) else { return [] }
        return (try? JSONDecoder().decode([PendingCredit].self, from: data)) ?? []
    }
    func rememberCredit(_ item: PendingCredit) {
        var items = pendingCredits.filter { $0 != item }; items.append(item)
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: pendingCreditKey) }
    }
    func acknowledgeCredit(_ item: PendingCredit) {
        if let data = try? JSONEncoder().encode(pendingCredits.filter { $0 != item }) { UserDefaults.standard.set(data, forKey: pendingCreditKey) }
    }
    @Published private(set) var walletSyncMessage: String?
    @Published private(set) var syncingWallet = false
    private var lastWalletSync: Date = .distantPast
    private var lastWalletUser: String?

    /// Reconcile only the signed-in account. Never opens an Apple purchase sheet.
    func reconcileWallet(store: CraftStore, force: Bool = false) async throws {
        guard let uid = CraftAccount.shared.uid else { throw CraftError(message: "Sign in to sync purchases.") }
        guard store.connected else {
            if force { throw CraftError(message: store.t("Check your internet connection to sync purchased Tokens.", "请检查网络连接以同步购买的 Tokens。")) }
            return
        }
        guard !syncingWallet else {
            if force { throw CraftError(message: store.t("Purchases are already syncing. Please wait a moment.", "正在同步购买记录，请稍候。")) }
            return
        }
        guard force || uid != lastWalletUser || Date().timeIntervalSince(lastWalletSync) >= 30 else { return }
        syncingWallet = true
        lastWalletSync = Date(); lastWalletUser = uid
        defer { syncingWallet = false }
        do {
            try await ensurePurchaseAccount(uid)
            guard CraftAccount.shared.uid == uid else { return }
            // One unavailable transaction must not prevent other purchases syncing.
            var deliveryError: Error?
            for item in pendingCredits where item.userID == uid {
                guard CraftAccount.shared.uid == uid else { return }
                do {
                    try await store.creditRevenueCatPurchase(productID: item.productID, transactionID: item.transactionID, presentPurchase: item.showSuccess == true)
                    acknowledgeCredit(item)
                } catch { deliveryError = error }
            }
            guard CraftAccount.shared.uid == uid else { return }
            try await store.syncRevenueCatWallet()
            guard CraftAccount.shared.uid == uid else { return }
            if let deliveryError { throw deliveryError }
            walletSyncMessage = nil
        } catch {
            if CraftAccount.shared.uid == uid, pendingCredits.contains(where: { $0.userID == uid }) {
                walletSyncMessage = store.t("Tokens awaiting sync. No need to buy again.", "Tokens 等待同步，无需再次购买。")
            }
            throw error
        }
    }

    private(set) var lastPurchaseTransactionID: String?
    private(set) var lastPurchaseProductID: String?
    @Published private(set) var customerInfo: CustomerInfo?
    @Published private(set) var currentOffering: Offering?
    @Published private(set) var isCreatorActive = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var state: PurchaseState = .idle
    @Published private(set) var pendingVerifiedTransactions: [VerifiedPurchase] = []
    @Published private(set) var hasCreatorEntitlement = false
    @Published private(set) var activePlanID: String?

    private var transactions: [UInt64: Transaction] = [:]
    private var finishedThisSession: Set<UInt64> = []
    private var updatesTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var customerInfoTask: Task<Void, Never>?

    init() {
        if !Purchases.isConfigured {
            Purchases.logLevel = .debug
            Purchases.configure(withAPIKey: Self.revenueCatApiKey)
        }

        customerInfoTask = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                guard !Task.isCancelled else { return }
                self?.handleCustomerInfo(info)
            }
        }

        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                _ = self?.accept(result)
            }
        }
        recoveryTask = Task { [weak self] in
            for await result in Transaction.unfinished {
                guard !Task.isCancelled else { return }
                _ = self?.accept(result)
            }
        }
        Task { [weak self] in
            await self?.loadOfferings()
            await self?.refreshEntitlements()
        }
    }

    deinit {
        customerInfoTask?.cancel()
        updatesTask?.cancel()
        recoveryTask?.cancel()
    }

    func handleCustomerInfo(_ info: CustomerInfo) {
        self.customerInfo = info
        let isEntitled = info.entitlements[Self.creatorEntitlementID]?.isActive == true
        self.isCreatorActive = isEntitled
        self.hasCreatorEntitlement = isEntitled
        if isEntitled, let prodId = info.entitlements[Self.creatorEntitlementID]?.productIdentifier {
            self.activePlanID = prodId
        } else {
            self.activePlanID = nil
        }
    }

    func loadOfferings() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            self.currentOffering = offerings.current
        } catch {
            print("[RevenueCat] Load offerings error: \(error.localizedDescription)")
        }
    }

    func ensurePurchaseAccount(_ userID: String) async throws {
        guard CraftAccount.shared.uid == userID else { throw CraftError(message: "Sign in to the purchasing account first.") }
        _ = try await Purchases.shared.logIn(userID)
        guard CraftAccount.shared.uid == userID, Purchases.shared.appUserID == userID else { throw CraftError(message: "Please sign in again before purchasing.") }
        if currentOffering == nil { await loadOfferings() }
    }

    func purchase(package: Package) async throws -> (CustomerInfo, Bool) {
        guard state != .purchasing else { throw CraftError(message: "A purchase is already in progress.") }
        lastPurchaseTransactionID = nil
        lastPurchaseProductID = nil
        state = .purchasing
        error = nil
        do {
            let result = try await Purchases.shared.purchase(package: package)
            lastPurchaseTransactionID = result.transaction?.transactionIdentifier
            lastPurchaseProductID = result.transaction?.productIdentifier
            handleCustomerInfo(result.customerInfo)
            if result.userCancelled {
                state = .cancelled
            } else {
                state = .idle
            }
            return (result.customerInfo, result.userCancelled)
        } catch {
            if (error as NSError).code == RevenueCat.ErrorCode.paymentPendingError.rawValue {
                state = .pendingApproval
            } else {
                state = .failed
            }
            self.error = error.localizedDescription
            throw error
        }
    }

    func restoreRevenueCatPurchases() async throws -> CustomerInfo {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let info = try await Purchases.shared.restorePurchases()
            handleCustomerInfo(info)
            return info
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    func logInRevenueCat(userId: String) async {
        do {
            let (info, _) = try await Purchases.shared.logIn(userId)
            handleCustomerInfo(info)
        } catch {
            print("[RevenueCat] logIn error: \(error.localizedDescription)")
        }
    }

    func logOutRevenueCat() async {
        walletSyncMessage = nil
        lastWalletUser = nil
        customerInfo = nil; isCreatorActive = false; hasCreatorEntitlement = false; activePlanID = nil
        do {
            let info = try await Purchases.shared.logOut()
            handleCustomerInfo(info)
        } catch {
            print("[RevenueCat] logOut error: \(error.localizedDescription)")
        }
    }

    func product(for id: String) -> Product? {
        products.first { $0.id == id }
    }

    func package(for id: String) -> Package? {
        guard let packages = currentOffering?.availablePackages else { return nil }
        return packages.first { $0.storeProduct.productIdentifier == id }
    }

    func displayPrice(for id: String) -> String? {
        if let pkg = package(for: id) {
            return pkg.localizedPriceString
        }
        if let prod = product(for: id) {
            return prod.displayPrice
        }
        return nil
    }

    func loadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            products = try await Product.products(for: Self.productIDs).sorted { $0.price < $1.price }
            await refreshEntitlements()
            await loadOfferings()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        if let info = try? await Purchases.shared.customerInfo() {
            handleCustomerInfo(info)
            if hasCreatorEntitlement { return }
        }

        var active = false
        var activeID: String?
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productType == .autoRenewable &&
                    (transaction.expirationDate.map { $0 > Date() } ?? true) &&
                    transaction.revocationDate == nil {
                    active = true
                    activeID = transaction.productID
                }
            }
        }
        hasCreatorEntitlement = active
        activePlanID = activeID
    }

    func purchase(_ product: Product) async -> VerifiedPurchase? {
        guard state != .purchasing, Self.productIDs.contains(product.id) else { return nil }
        error = nil
        state = .purchasing
        do {
            switch try await product.purchase() {
            case .success(let result):
                return accept(result)
            case .pending:
                state = .pendingApproval
            case .userCancelled:
                state = .cancelled
            @unknown default:
                state = .failed
                error = "The purchase returned an unknown status. Please try again."
            }
        } catch {
            state = .failed
            self.error = error.localizedDescription
        }
        return nil
    }

    /// Retries unfinished deliveries and reconciles current verified subscriptions.
    func restore() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let info = try await Purchases.shared.restorePurchases()
            handleCustomerInfo(info)
        } catch {
            // Fallback to StoreKit sync
            do {
                try await AppStore.sync()
            } catch {
                self.error = error.localizedDescription
            }
        }
        for await result in Transaction.unfinished {
            _ = accept(result)
        }
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productType == .autoRenewable,
                  Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil,
                  !transaction.isUpgraded,
                  transaction.expirationDate.map({ $0 > Date() }) ?? true else { continue }
            hasCreatorEntitlement = true
            activePlanID = transaction.productID
            finishedThisSession.remove(transaction.id)
            _ = accept(result)
        }
    }

    /// Check RevenueCat status for the given user ID
    func checkRevenueCatStatus(userId: String) async {
        await logInRevenueCat(userId: userId)
    }

    /// Call only after the backend confirms delivery (or already delivered).
    func finish(transactionID: UInt64) async {
        guard let transaction = transactions[transactionID] else { return }
        finishedThisSession.insert(transactionID)
        await transaction.finish()
        transactions.removeValue(forKey: transactionID)
        pendingVerifiedTransactions.removeAll { $0.transactionID == transactionID }
        state = .completed(transactionID)
    }

    @discardableResult
    private func accept(_ result: StoreKit.VerificationResult<StoreKit.Transaction>) -> VerifiedPurchase? {
        switch result {
        case .unverified(_, let verificationError):
            error = "The purchase could not be verified: \(verificationError.localizedDescription)"
            state = .failed
            return nil
        case .verified(let transaction):
            guard Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil,
                  !transaction.isUpgraded,
                  !finishedThisSession.contains(transaction.id) else { return nil }
            if transaction.productType == .autoRenewable && (transaction.expirationDate.map({ $0 > Date() }) ?? true) {
                hasCreatorEntitlement = true
                activePlanID = transaction.productID
            }
            let isTesting = transaction.environment == .xcode || transaction.environment == .sandbox
            let purchase = VerifiedPurchase(
                productID: transaction.productID,
                transactionID: transaction.id,
                environment: transaction.environment.rawValue,
                isLocalTesting: isTesting
            )
            transactions[transaction.id] = transaction
            if !pendingVerifiedTransactions.contains(where: { $0.id == transaction.id }) {
                pendingVerifiedTransactions.append(purchase)
            }
            state = .awaitingCredit(transaction.id)
            return purchase
        }
    }
}
