import Foundation
import Observation
#if canImport(StoreKit)
import StoreKit
#endif
import DeckProgression

/// The things DECK sells.
///
/// Premium widens the library and lifts the daily attempt limit. It does not
/// gate Pass & Play, the core games, the tutorials, statistics or achievements —
/// the app has to be good before it is worth paying for.
public enum StoreProduct: String, CaseIterable, Sendable {
    case monthly = "com.deck.premium.monthly"
    case yearly = "com.deck.premium.yearly"
    case lifetime = "com.deck.premium.lifetime"

    public var isSubscription: Bool { self != .lifetime }
}

/// What the store screen shows for one product. Prices always come from
/// StoreKit, formatted for the customer's own storefront — never hard-coded.
public struct StoreOffer: Identifiable, Sendable {
    public var id: String
    public var product: StoreProduct
    public var displayName: String
    public var displayPrice: String
    /// "per month", "per year", or nil for the one-off purchase.
    public var periodDescription: String?
    /// Set when this offer is better value than the monthly one.
    public var savingDescription: String?
    public var isPurchased: Bool

    public init(id: String,
                product: StoreProduct,
                displayName: String,
                displayPrice: String,
                periodDescription: String?,
                savingDescription: String?,
                isPurchased: Bool) {
        self.id = id
        self.product = product
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.periodDescription = periodDescription
        self.savingDescription = savingDescription
        self.isPurchased = isPurchased
    }
}

public enum StoreState: Equatable, Sendable {
    case idle
    case loading
    case ready
    case purchasing(String)
    /// The store could not be reached. The app carries on working offline.
    case unavailable(String)
}

/// Talks to StoreKit.
///
/// Entitlements are derived from verified transactions only: a purchase is
/// never granted on the strength of a purchase call returning, and a revoked or
/// expired one drops the player back to free immediately. Nothing here fakes a
/// purchase, and there is no debug switch that does either — the debug menu sets
/// a *local* entitlement flag, which is clearly labelled as such.
@MainActor
@Observable
public final class StoreService {
    public private(set) var state: StoreState = .idle
    public private(set) var offers: [StoreOffer] = []
    public private(set) var entitlements: Entitlements

    private let progress: ProgressStore
    #if canImport(StoreKit)
    private var products: [String: Product] = [:]
    private var updatesTask: Task<Void, Never>?
    #endif

    public init(progress: ProgressStore) {
        self.progress = progress
        self.entitlements = progress.entitlements
    }

    deinit {
        #if canImport(StoreKit)
        updatesTask?.cancel()
        #endif
    }

    /// Loads products and starts listening for transactions.
    public func start() {
        #if canImport(StoreKit)
        guard updatesTask == nil else { return }
        // Transactions can arrive at any time — an interrupted purchase, a
        // renewal, a refund, a family-sharing change — so the listener starts
        // before anything else and never stops.
        updatesTask = Task.detached { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task { await load() }
        #else
        state = .unavailable("StoreKit is not available on this platform.")
        #endif
    }

    public func load() async {
        #if canImport(StoreKit)
        state = .loading
        do {
            let fetched = try await Product.products(for: StoreProduct.allCases.map(\.rawValue))
            products = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            await refreshEntitlements()
            rebuildOffers()
            state = .ready
        } catch {
            // Being offline is not an error the player needs to fix: everything
            // except buying still works.
            state = .unavailable(String(localized: "store.offline",
                                        defaultValue: "The store is not reachable right now."))
        }
        #endif
    }

    public func purchase(_ product: StoreProduct) async {
        #if canImport(StoreKit)
        guard let storeProduct = products[product.rawValue] else { return }
        state = .purchasing(product.rawValue)
        do {
            let result = try await storeProduct.purchase()
            switch result {
            case let .success(verification):
                await handle(verification)
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
            state = .ready
        } catch {
            state = .unavailable(String(localized: "store.purchaseFailed",
                                        defaultValue: "That purchase did not go through."))
        }
        #endif
    }

    /// Restores purchases. Required by the App Store, and genuinely needed when
    /// somebody changes device.
    public func restore() async {
        #if canImport(StoreKit)
        state = .loading
        try? await AppStore.sync()
        await refreshEntitlements()
        rebuildOffers()
        state = .ready
        #endif
    }

    #if canImport(StoreKit)
    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case let .verified(transaction) = result else {
            // An unverified transaction is not a purchase. Nothing is granted.
            return
        }
        await transaction.finish()
        await refreshEntitlements()
        rebuildOffers()
    }

    /// Rebuilds the entitlement from the transactions Apple currently vouches for.
    private func refreshEntitlements() async {
        var level = Entitlements.Level.free
        var expiry: Date?
        var revoked = false

        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result else { continue }
            if transaction.revocationDate != nil {
                revoked = true
                continue
            }
            guard let product = StoreProduct(rawValue: transaction.productID) else { continue }
            if product == .lifetime {
                level = .lifetime
                expiry = nil
            } else if level != .lifetime {
                level = .subscribed
                if let date = transaction.expirationDate {
                    expiry = max(expiry ?? date, date)
                }
            }
        }

        let updated = Entitlements(level: level,
                                   expiresAt: expiry,
                                   isRevoked: revoked && level == .free,
                                   verifiedAt: Date())
        entitlements = updated
        progress.update(entitlements: updated)
    }

    private func rebuildOffers() {
        var built: [StoreOffer] = []
        let monthlyPrice = products[StoreProduct.monthly.rawValue]?.price

        for product in StoreProduct.allCases {
            guard let storeProduct = products[product.rawValue] else { continue }
            var period: String?
            var saving: String?

            if let subscription = storeProduct.subscription {
                let unit = subscription.subscriptionPeriod.unit
                let value = subscription.subscriptionPeriod.value
                period = Self.periodDescription(unit: unit, value: value)
                if product == .yearly, let monthlyPrice, monthlyPrice > 0 {
                    let yearlyAsMonthly = storeProduct.price / 12
                    let ratio = 1 - (yearlyAsMonthly / monthlyPrice)
                    if ratio > 0.05 {
                        saving = String(format: String(localized: "store.save",
                                                       defaultValue: "Save %d%%"),
                                        Int((ratio * 100).rounded()))
                    }
                }
            }

            built.append(StoreOffer(id: product.rawValue,
                                    product: product,
                                    displayName: storeProduct.displayName,
                                    displayPrice: storeProduct.displayPrice,
                                    periodDescription: period,
                                    savingDescription: saving,
                                    isPurchased: entitlements.isPremium()))
        }
        offers = built.sorted { lhs, rhs in
            StoreProduct.allCases.firstIndex(of: lhs.product) ?? 0
                < StoreProduct.allCases.firstIndex(of: rhs.product) ?? 0
        }
    }

    private static func periodDescription(unit: Product.SubscriptionPeriod.Unit, value: Int) -> String {
        switch unit {
        case .month:
            return value == 1
                ? String(localized: "store.perMonth", defaultValue: "per month")
                : String(format: String(localized: "store.perMonths", defaultValue: "every %d months"), value)
        case .year:
            return String(localized: "store.perYear", defaultValue: "per year")
        case .week:
            return String(localized: "store.perWeek", defaultValue: "per week")
        case .day:
            return String(localized: "store.perDay", defaultValue: "per day")
        @unknown default:
            return ""
        }
    }
    #endif

    /// What premium actually gets you, in plain words.
    public static let benefits: [(titleKey: String, detailKey: String)] = [
        ("premium.benefit.attempts", "premium.benefit.attempts.detail"),
        ("premium.benefit.variants", "premium.benefit.variants.detail"),
        ("premium.benefit.cosmetics", "premium.benefit.cosmetics.detail"),
        ("premium.benefit.stats", "premium.benefit.stats.detail")
    ]
}
