import StoreKit

final class StoreKit2Handler {

    // MARK: - Internal State

    private static var updateTask: Task<Void, Never>?
    private static let transactionQueue = DispatchQueue(label: "storekit2.transaction.queue")

    // MARK: - Initialize (Transaction Listener)

    static func initialize() async {
        transactionQueue.sync {
            guard updateTask == nil else {
                print("StoreKit2Handler already initialized")
                return
            }

            print("StoreKit2Handler initialize start")

            updateTask = Task {
                for await result in Transaction.updates {
                    await handleTransactionUpdate(result)
                }
            }

            print("StoreKit2Handler initialize completed")
        }
    }

    private static func handleTransactionUpdate(
    _ result: VerificationResult<Transaction>
    ) async {
        guard case .verified(let transaction) = result else {
            return
        }

        print("Transaction update received: \(transaction.id)")

        // 有 appAccountToken → 交给 Flutter / 服务端处理
        if let token = transaction.appAccountToken {
            NotificationCenter.default.post(
                name: Notification.Name("NewTransactionAvailable"),
                object: nil,
                userInfo: [
                    "transactionId": transaction.id,
                    "productId": transaction.productID,
                    "originalID": transaction.originalID,
                    "appAccountToken": token.uuidString,
                    "json": String(
                        data: transaction.jsonRepresentation,
                        encoding: .utf8
                    ) ?? ""
                ]
            )
        } else {
            // 没有 token 的交易，直接 finish（避免卡队列）
            await transaction.finish()
            print("Auto finished transaction without appAccountToken: \(transaction.id)")
        }
    }

    // MARK: - Products

    static func fetchProducts(
    productIdentifiers: [String],
    completion: @escaping (Result<[Product], Error>) -> Void
    ) {
        Task {
            do {
                print("StoreKit2Handler fetchProducts start")

                let products = try await Product.products(for: productIdentifiers)

                let sorted = productIdentifiers.compactMap { id in
                    products.first(where: { $0.id == id })
                }

                print("StoreKit2Handler fetchProducts completed")
                completion(.success(sorted))

            } catch {
                print("StoreKit2Handler fetchProducts error: \(error)")
                completion(.failure(error))
            }
        }
    }

    // MARK: - Subscription Check

    static func hasActiveSubscription() async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }

            if transaction.productType == .autoRenewable,
            let expiration = transaction.expirationDate,
            expiration > Date() {
                return true
            }
        }
        return false
    }

    // MARK: - Purchase

    static func buyProduct(
    productId productID: String,
    uniId: String?,
    completion: @escaping (Bool, Error?, Transaction?) -> Void
    ) {
        Task {
            do {
                print("StoreKit2Handler buyProduct \(productID)")

                let products = try await Product.products(for: [productID])
                guard let product = products.first else {
                    completion(
                        false,
                        NSError(
                            domain: "StoreKitError",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Product not found"]
                        ),
                        nil
                    )
                    return
                }

                var options: Set<Product.PurchaseOption> = []

                if let uniId = uniId,
                let uuid = UUID(uuidString: uniId) {
                    options.insert(.appAccountToken(uuid))
                }

                let result = try await product.purchase(options: options)

                switch result {

                case .success(let verification):
                    guard case .verified(let transaction) = verification else {
                        completion(
                            false,
                            NSError(
                                domain: "StoreKitError",
                                code: -2,
                                userInfo: [NSLocalizedDescriptionKey: "Transaction unverified"]
                            ),
                            nil
                        )
                        return
                    }

                    print("Purchase success: \(transaction.id)")
                    completion(true, nil, transaction)

                case .pending:
                    completion(
                        false,
                        NSError(
                            domain: "StoreKitError",
                            code: -5,
                            userInfo: [NSLocalizedDescriptionKey: "Transaction pending"]
                        ),
                        nil
                    )

                case .userCancelled:
                    completion(
                        false,
                        NSError(
                            domain: "StoreKitError",
                            code: -3,
                            userInfo: [NSLocalizedDescriptionKey: "User cancelled"]
                        ),
                        nil
                    )

                @unknown default:
                    completion(
                        false,
                        NSError(
                            domain: "StoreKitError",
                            code: -4,
                            userInfo: [NSLocalizedDescriptionKey: "Unknown purchase result"]
                        ),
                        nil
                    )
                }

            } catch {
                print("StoreKit2Handler buyProduct error: \(error)")
                completion(false, error, nil)
            }
        }
    }

    // MARK: - Purchase History (Debug / Export Only)

    static func fetchPurchaseHistory() async -> [String] {
        var result: [String] = []

        for await verification in Transaction.all {
            guard case .verified(let transaction) = verification else { continue }
            result.append(
                String(
                    data: transaction.jsonRepresentation,
                    encoding: .utf8
                ) ?? ""
            )
        }

        return result
    }

    // MARK: - Restore

    static func restorePurchases() async -> [[String: Any]] {
        var transactions: [[String: Any]] = []

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }

            transactions.append([
                "transactionId": transaction.id,
                "productId": transaction.productID,
                "appBundleID": transaction.appBundleID,
                "originalID": transaction.originalID,
                "appAccountToken": transaction.appAccountToken?.uuidString ?? "",
                "purchaseDate": Int(transaction.purchaseDate.timeIntervalSince1970),
                "json": String(
                    data: transaction.jsonRepresentation,
                    encoding: .utf8
                ) ?? "",
                "isSubscription":
                transaction.productType == .autoRenewable ||
                transaction.productType == .nonRenewable
            ])
        }

        return transactions
    }

    // MARK: - Finish Transaction (Called After Server Validation)

    static func finishTransaction(transactionId: UInt64) async -> Bool {
        for await result in Transaction.all {
            guard case .verified(let transaction) = result else { continue }

            if transaction.id == transactionId {
                await transaction.finish()
                print("Finished transaction: \(transactionId)")
                return true
            }
        }
        return false
    }
}
