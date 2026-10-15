import Foundation
import StoreKit

// MARK: - Products

/// App Store Connect product ids — mirrored by `backend/src/services/plusCatalog.ts`.
/// Never rename one: shipped builds keep buying the old id.
enum PlusProducts {
    static let monthly = "mad.plus.monthly"
    static let yearly = "mad.plus.yearly"
    static let lifetime = "mad.plus.lifetime"
    static let giftYear = "mad.plus.gift.year"

    /// What the paywall sells, in display order (the default pick first).
    static let plans = [yearly, monthly, lifetime]
    static let all = plans + [giftYear]
}

// MARK: - Server DTOs

/// `GET /plus/status`. Timestamps stay Strings (parse with `BuddyDate`).
struct PlusStatus: Codable, Equatable {
    let is_plus: Bool
    /// lifetime | subscription | gift | founding — nil when not Plus.
    let source: String?
    let expires_at: String?
    let will_renew: Bool?
    let in_trial: Bool?
    let family_shared: Bool?
    let founding_runner: Bool?
    let founding_ends_at: String?
    let ever_subscribed: Bool?
    let perks: Perks?

    struct Perks: Codable, Equatable {
        let double_down_target: Int
        let streak_save_target: Int
    }

    var expiresDate: Date? { BuddyDate.parse(expires_at) }
    var foundingEndsDate: Date? { BuddyDate.parse(founding_ends_at) }
    var isFoundingRunner: Bool { founding_runner == true }
}

/// One gift a user bought (`GET /plus/gifts`, or fresh from a purchase).
struct PlusGift: Codable, Identifiable, Equatable {
    let code: String
    let display_code: String
    let months: Int
    let created_at: String?
    let redeemed: Bool
    let redeemed_at: String?
    let redeemed_by_username: String?
    let voided: Bool

    var id: String { code }
}

private struct PlusTransactionsBody: Encodable {
    let signed_transactions: [String]
}

private struct PlusTransactionsResponse: Decodable {
    struct Result: Decodable {
        let ok: Bool
        let error: String?
        let retryable: Bool?
    }
    let status: PlusStatus?
    let results: [Result]
    let gifts: [PlusGift]?
}

private struct PlusGiftList: Decodable { let gifts: [PlusGift] }
private struct PlusRedeemResponse: Decodable {
    let starts_at: String
    let ends_at: String
    let status: PlusStatus?
}

// MARK: - Store

/// Mile A Day+ — StoreKit 2 purchases, verified and recorded by OUR server.
///
/// The App Store signs every transaction; this class never decides on its
/// own that someone is Plus. It posts Apple's signed JWS to
/// `POST /plus/transactions`, the server verifies the signature and keeps the
/// ledger, and `status` is whatever the server answers. A transaction is
/// FINISHED only once the server has it on file (or has said it never
/// will), so a purchase made offline or signed-out is retried on the next
/// launch instead of being lost.
@MainActor
final class PlusStore: ObservableObject {
    static let shared = PlusStore()

    enum PurchaseOutcome: Equatable {
        case purchased
        /// Ask to Buy / SCA: Apple will deliver it later via `Transaction.updates`.
        case pending
        case cancelled
        /// Paid, but our server hasn't confirmed it yet; it retries on its own.
        case awaitingServer
        case failed(String)
    }

    @Published private(set) var status: PlusStatus?
    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var productsLoaded = false
    @Published private(set) var trialEligible = true
    @Published private(set) var isBusy = false

    var isPlus: Bool { status?.is_plus ?? false }

    private var updatesTask: Task<Void, Never>?
    private let statusCachePrefix = "plusStatusV1|"

    private init() {
        status = cachedStatus()
    }

    private var userId: String? {
        guard let id = SessionIdentity.cachedUserId, !id.isEmpty else { return nil }
        return id
    }

    /// The MAD account as Apple's appAccountToken, so a server notification
    /// for a purchase the app never posted still lands on the right account.
    private var appAccountToken: UUID? {
        guard let hex = userId?.lowercased(), hex.count == 32,
              hex.allSatisfy({ $0.isHexDigit }) else { return nil }
        let c = Array(hex)
        let dashed = "\(String(c[0..<8]))-\(String(c[8..<12]))-\(String(c[12..<16]))-\(String(c[16..<20]))-\(String(c[20..<32]))"
        return UUID(uuidString: dashed)
    }

    // MARK: Lifecycle

    /// Launch: listen for transactions arriving outside a purchase call
    /// (renewals, Ask to Buy approvals, refunds, purchases on another device).
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task(priority: .background) {
            for await update in Transaction.updates {
                await PlusStore.shared.process([update])
            }
        }
        Task { await refresh() }
    }

    /// Re-read the server's status and hand it anything still unfinished on
    /// this device. Cheap; safe on every foreground.
    func refresh() async {
        guard userId != nil, TokenStore.hasTokens else { return }
        var pending: [VerificationResult<Transaction>] = []
        for await result in Transaction.unfinished { pending.append(result) }
        if !pending.isEmpty { await process(pending) }
        await fetchStatus()
    }

    /// Sign-out: the cached status belongs to the account we're leaving.
    func reset() {
        status = nil
        trialEligible = true
    }

    func fetchStatus() async {
        guard let userId, TokenStore.hasTokens else { return }
        guard let fresh = try? await APIClient.fancyFetch(endpoint: "/plus/status", responseType: PlusStatus.self)
        else { return }
        apply(fresh, for: userId)
    }

    private func apply(_ fresh: PlusStatus, for userId: String) {
        let changed = fresh.is_plus != status?.is_plus
        status = fresh
        if let data = try? JSONEncoder().encode(fresh) {
            UserDefaults.standard.set(data, forKey: statusCachePrefix + userId)
        }
        if changed {
            // Plus-only Flamey items and faster token meters both read the
            // server's entitlement — pick the new state up now, not next launch.
            Task { await FlameyClosetSync.refreshOwnedItems() }
        }
    }

    private func cachedStatus() -> PlusStatus? {
        guard let userId, let data = UserDefaults.standard.data(forKey: statusCachePrefix + userId) else { return nil }
        return try? JSONDecoder().decode(PlusStatus.self, from: data)
    }

    // MARK: Products

    func loadProducts() async {
        guard !productsLoaded else { return }
        do {
            let loaded = try await Product.products(for: PlusProducts.all)
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            productsLoaded = true
            if let yearly = products[PlusProducts.yearly], let sub = yearly.subscription {
                trialEligible = await sub.isEligibleForIntroOffer
            }
        } catch {
            print("[Plus] product load failed: \(error)")
        }
    }

    func product(_ id: String) -> Product? { products[id] }

    // MARK: Purchasing

    func purchase(_ product: Product) async -> PurchaseOutcome {
        guard userId != nil else { return .failed("Sign in to subscribe.") }
        isBusy = true
        defer { isBusy = false }
        var options: Set<Product.PurchaseOption> = []
        if let token = appAccountToken { options.insert(.appAccountToken(token)) }
        do {
            switch try await product.purchase(options: options) {
            case .success(let verification):
                let response = await process([verification])
                return response?.results.first?.ok == true ? .purchased : .awaitingServer
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .cancelled
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Buy a year of Plus for someone else. Returns the new code, or nil
    /// when the purchase didn't complete (cancelled, pending, server down —
    /// in the last case it arrives in `gifts()` once the retry lands).
    func buyGift() async -> (PurchaseOutcome, PlusGift?) {
        guard let product = products[PlusProducts.giftYear] else {
            return (.failed("Gifts aren't available right now."), nil)
        }
        guard userId != nil else { return (.failed("Sign in to buy a gift."), nil) }
        isBusy = true
        defer { isBusy = false }
        var options: Set<Product.PurchaseOption> = []
        if let token = appAccountToken { options.insert(.appAccountToken(token)) }
        do {
            switch try await product.purchase(options: options) {
            case .success(let verification):
                let response = await process([verification])
                if let gift = response?.gifts?.first { return (.purchased, gift) }
                return (.awaitingServer, nil)
            case .pending:
                return (.pending, nil)
            case .userCancelled:
                return (.cancelled, nil)
            @unknown default:
                return (.cancelled, nil)
            }
        } catch {
            return (.failed(error.localizedDescription), nil)
        }
    }

    /// "Restore Purchases": sync with the App Store, then hand the server
    /// everything this Apple ID is currently entitled to.
    func restore() async -> Bool {
        guard userId != nil else { return false }
        isBusy = true
        defer { isBusy = false }
        try? await AppStore.sync()
        var current: [VerificationResult<Transaction>] = []
        for await result in Transaction.currentEntitlements { current.append(result) }
        if !current.isEmpty { await process(current) }
        await fetchStatus()
        return isPlus
    }

    // MARK: Gifts

    func gifts() async -> [PlusGift] {
        guard TokenStore.hasTokens else { return [] }
        return (try? await APIClient.fancyFetch(endpoint: "/plus/gifts", responseType: PlusGiftList.self))?.gifts ?? []
    }

    enum RedeemError: Error {
        case invalidCode, alreadyRedeemed, voided, other(String)

        var message: String {
            switch self {
            case .invalidCode: return "That code doesn't match a gift. Check it and try again."
            case .alreadyRedeemed: return "That gift has already been redeemed."
            case .voided: return "That gift was refunded and can't be redeemed."
            case .other(let m): return m
            }
        }
    }

    /// Redeem a gift code; returns when the gifted year ends.
    func redeem(code: String) async -> Result<Date?, RedeemError> {
        guard let userId else { return .failure(.other("Sign in to redeem a gift.")) }
        isBusy = true
        defer { isBusy = false }
        do {
            let body = try JSONEncoder().encode(["code": code])
            let response = try await APIClient.fancyFetch(endpoint: "/plus/gifts/redeem", method: .POST,
                                                          body: body, responseType: PlusRedeemResponse.self)
            if let fresh = response.status { apply(fresh, for: userId) }
            return .success(BuddyDate.parse(response.ends_at))
        } catch APIError.notFound {
            return .failure(.invalidCode)
        } catch APIError.conflict(let message) {
            return .failure(message == "gift_voided" ? .voided : .alreadyRedeemed)
        } catch APIError.rateLimited(let message) {
            return .failure(.other(message))
        } catch {
            return .failure(.other("Couldn't redeem right now. Try again in a moment."))
        }
    }

    // MARK: Posting to the server

    /// Post signed transactions; finish each one the server has on file (or
    /// has said it never will). Anything else stays unfinished and is posted
    /// again on the next launch or `refresh()`.
    @discardableResult
    private func process(_ results: [VerificationResult<Transaction>]) async -> PlusTransactionsResponse? {
        guard let userId, TokenStore.hasTokens else { return nil }
        var response: PlusTransactionsResponse?
        for batch in stride(from: 0, to: results.count, by: 25).map({ Array(results[$0..<min($0 + 25, results.count)]) }) {
            let body = PlusTransactionsBody(signed_transactions: batch.map(\.jwsRepresentation))
            guard let data = try? JSONEncoder().encode(body),
                  let answer = try? await APIClient.fancyFetch(endpoint: "/plus/transactions", method: .POST,
                                                               body: data, responseType: PlusTransactionsResponse.self)
            else { continue }
            for (index, result) in batch.enumerated() {
                guard index < answer.results.count else { break }
                let verdict = answer.results[index]
                guard verdict.ok || verdict.retryable == false else { continue }
                // Only a transaction StoreKit itself could verify is finished;
                // an unverified one isn't ours to acknowledge.
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
            }
            if let fresh = answer.status { apply(fresh, for: userId) }
            response = answer
        }
        return response
    }
}
