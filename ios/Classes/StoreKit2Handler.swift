import StoreKit



class StoreKit2Handler {
    
    
    
       static func initialize()async{
           print("StoreKit2Handler initialize start")
            Task.detached {
                do {
                    for await result in Transaction.updates {
                        if case .verified(let transaction) = result {
                            print("initialize \(transaction.id)")
                            // 检查交易是否有appAccountToken (UUID)
                            if let appAccountToken = transaction.appAccountToken {
                                // 有UUID的交易，需要通过回调传回给客户端进行服务器验证
                                NotificationCenter.default.post(
                                    name: Notification.Name("NewTransactionAvailable"),
                                    object: nil,
                                    userInfo: [
                                        "transactionId": transaction.id,
                                        "productId": transaction.productID,
                                        "originalID": transaction.originalID,
                                        "appAccountToken": appAccountToken.uuidString,
                                        "json": String(data: transaction.jsonRepresentation, encoding: .utf8) ?? ""
                                    ]
                                )
                            } else {
                                // 没有UUID的交易，直接完成
                                await transaction.finish()
                                print("已自动完成无UUID的交易: \(transaction.id)")
                            }
                        }
                    }
                } catch {
                    print("StoreKit2Handler initialize error: \(error.localizedDescription)")
                    // 可以通过通知中心告知Flutter端出现了错误
                    NotificationCenter.default.post(
                        name: Notification.Name("StoreKitInitError"),
                        object: nil,
                        userInfo: [
                            "error": error.localizedDescription
                        ]
                    )
                }
            }
           print("StoreKit2Handler initialize completed")
       }
       
    
    static func fetchProducts(productIdentifiers: [String], completion: @escaping (Result<[Product], Error>) -> Void) {
        Task {
            do {
                print("StoreKit2Handler fetchProducts")
                let allProducts = try await Product.products(for: productIdentifiers)
                
                let sortedProducts = productIdentifiers.compactMap { identifier in
                    allProducts.first(where: { $0.id == identifier })
                }
                print("StoreKit2Handler fetchProducts finish")
                completion(.success(sortedProducts))
                
            } catch {
                print("StoreKit2Handler fetchProducts error")
                completion(.failure(error))
            }
        }
    }
    
    static  func hasActiveSubscription() async -> Bool {
        
        for await verificationResult in Transaction.currentEntitlements {
            switch verificationResult {
                
            case .verified(_):
                return true
                
            case .unverified(_, _): break
                
            }
        }
        return false
    }
    
    static func buyProduct(productId productID: String, uniId: String?, completion: @escaping (Bool, Error?, Transaction?) -> Void) {
        Task {
            do {
                print("StoreKit2Handler buyProduct \(productID) -- \(uniId ?? "")")
                // 获取产品
                let products = try await Product.products(for: [productID])
                guard let product = products.first else {
                    completion(false, NSError(domain: "StoreKitError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Product not found"]), nil)
                    return
                }
                
                // 准备购买选项
                var purchaseOptions: Set<Product.PurchaseOption> = []
                
                // 只有当uniId不为空时才添加appAccountToken
                if let uniId = uniId, !uniId.isEmpty {
                    if let uuid = UUID(uuidString: uniId) {
                        purchaseOptions.insert(Product.PurchaseOption.appAccountToken(uuid))
                    } else {
                        purchaseOptions.insert(Product.PurchaseOption.appAccountToken(UUID()))
                    }
                }
                print("StoreKit2Handler buyProduct start")
                // 尝试购买产品
                let result = try await product.purchase(options: purchaseOptions)
                
                switch result {
                case .success(let verification):
                    switch verification {
                    case .verified(let transaction):
                        // 不要立即调用finish，而是将交易返回给客户端
                        print("StoreKit2Handler buyProduct success")
                        completion(true, nil, transaction)
                    case .unverified:
                        completion(false, NSError(domain: "StoreKitError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Transaction unverified"]), nil)
                    }
                case .pending:
                    completion(false, NSError(domain: "StoreKitError", code: -5, userInfo: [NSLocalizedDescriptionKey: "Transaction pending"]), nil)
                case .userCancelled:
                    completion(false, NSError(domain: "StoreKitError", code: -3, userInfo: [NSLocalizedDescriptionKey: "User cancelled"]), nil)
                @unknown default:
                    completion(false, NSError(domain: "StoreKitError", code: -4, userInfo: [NSLocalizedDescriptionKey: "Unknown purchase result"]), nil)
                }
            } catch {
                print("StoreKit2Handler buyProduct error \(error)")
                completion(false, error, nil)
            }
        }
    }
    
    
    

    
    
   static func fetchPurchaseHistory() async ->   [String]  {
   
       var all : [String] = []
     
       for await verificationResult in Transaction.all {
           switch verificationResult {
               
           case .verified(let transaction):
             
               all.append(String(data:  transaction.jsonRepresentation, encoding: .utf8) ?? "")
                
           case .unverified(_, _): break
              
               
           }
       }
       return all
    }
    
    static func restorePurchases() async -> [[String: Any]] {
        var transactions: [[String: Any]] = []
        
        // 获取所有当前有效的权限
        for await verificationResult in Transaction.currentEntitlements {
            switch verificationResult {
            case .verified(let transaction):
                // 构建交易信息字典
                let transactionDetails: [String: Any] = [
                    "transactionId": transaction.id,
                    "productId": transaction.productID,
                    "appBundleID": transaction.appBundleID,
                    "originalID": transaction.originalID,
                    "appAccountToken": transaction.appAccountToken?.uuidString ?? ""
                    "purchaseDate": Int(transaction.purchaseDate.timeIntervalSince1970),
                    "json": String(data: transaction.jsonRepresentation, encoding: .utf8) ?? "",
                    "isSubscription": transaction.productType == .autoRenewable || transaction.productType == .nonRenewable
                ]
                
                transactions.append(transactionDetails)
                
            case .unverified(_, _):
                // 处理未验证的交易
                break
            }
        }
        
        return transactions
    }
    
    static func finishTransaction(transactionId: UInt64) async -> Bool {
        // 尝试获取交易
        for await verificationResult in Transaction.all {
            switch verificationResult {
            case .verified(let transaction):
                if transaction.id == transactionId {
                    // 找到匹配的交易，完成它
                    print("找到匹配的交易\(transactionId) code:\(transaction.productID)，完成它")
                    await transaction.finish()
                    return true
                }
            case .unverified:
                continue
            }
        }
        return false
    }
}
  

   
    

