import Flutter
import UIKit
import StoreKit

public class Storekit2Plugin: NSObject, FlutterPlugin {
    
    let periodTitles = [
        "Day": "每日",
        "Week": "每周",
        "Month": "每月",
        "Year": "每年"
    ]
    
    private var transactionChannel: FlutterMethodChannel?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "storekit2helper", binaryMessenger: registrar.messenger())
        let instance = Storekit2Plugin()
        instance.transactionChannel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
        
        // 添加通知观察者
        NotificationCenter.default.addObserver(
            instance,
            selector: #selector(handleNewTransaction(_:)),
            name: Notification.Name("NewTransactionAvailable"),
            object: nil
        )
        
        // 添加初始化错误监听
        NotificationCenter.default.addObserver(
            instance,
            selector: #selector(handleInitError(_:)),
            name: Notification.Name("StoreKitInitError"),
            object: nil
        )
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            Task {
                print("initialize")
                await StoreKit2Handler.initialize()
                print("initialize finish")
                result(nil)
            }
            
        case "fetchPurchaseHistory":
            Task {
                await result(StoreKit2Handler.fetchPurchaseHistory())
            }
            
        case "hasActiveSubscription":
            Task {
                let hasSubscription = await StoreKit2Handler.hasActiveSubscription()
                result(hasSubscription)
            }
            
        case "restorePurchases":
            Task {
                let transactions = await StoreKit2Handler.restorePurchases()
                result(transactions)
            }
            
        case "finishTransaction":
            if let args = call.arguments as? [String: Any], let transactionId = args["transactionId"] as? UInt64 {
                Task {
                    let success = await StoreKit2Handler.finishTransaction(transactionId: transactionId)
                    result(success)
                }
            } else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "缺少交易ID", details: nil))
            }
            
        case "fetchProducts":
            if let args = call.arguments as? [String: Any], let productIDs = args["productIDs"] as? [String] {
                StoreKit2Handler.fetchProducts(productIdentifiers: productIDs) { fetchResult in
                    switch fetchResult {
                    case .success(let products):
                        // 将产品转换为可以发送回Flutter的格式
                        let productDetails = products.map { product -> [String: Any] in
                            var data = [
                                "productId": product.id,
                                "title": product.displayName ?? "",
                                "description": product.description,
                                "price": product.price,
                                "periodUnit": String(describing: product.subscription?.subscriptionPeriod.unit ?? Product.SubscriptionPeriod.Unit.day),
                                "periodValue": product.subscription?.subscriptionPeriod.value ?? 0,
                                "periodTitle": "",
                                "json": String(data: product.jsonRepresentation, encoding: .utf8) ?? "",
                                "localizedPrice": product.displayPrice,
                                "type": String(describing: product.type.rawValue),
                                "introductoryOffer": String(describing: product.subscription?.introductoryOffer?.paymentMode.rawValue ?? ""),
                                "introductoryOfferPeriod": String(describing: product.subscription?.introductoryOffer?.period.debugDescription ?? ""),
                                "isTrial": false
                            ]
                            
                            if let periodTitle = self.periodTitles[data["periodUnit"] as! String] {
                                data["periodTitle"] = periodTitle
                            }
                            
                            if (data["introductoryOffer"] as! String != "") {
                                data["isTrial"] = true
                            }
                            
                            return data
                        }
                        
                        result(productDetails)
                    case .failure(let error):
                        result(FlutterError(code: "PRODUCT_FETCH_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            } else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "缺少产品ID列表", details: nil))
            }
            
        case "buyProduct":
            if let args = call.arguments as? [String: Any], let productId = args["productId"] as? String {
                // 获取可选的UUID参数
                let uuid = args["uuid"] as? String
                
                StoreKit2Handler.buyProduct(productId: productId, uniId: uuid) { success, error, transaction in
                    if success {
                        // 交易成功，返回交易详情
                        let transactionDetails: [String: Any] = [
                            "transactionId": transaction!.id,
                            "productId": transaction!.productID,
                            "appBundleID": transaction!.appBundleID,
                            "originalID": transaction!.originalID,
                            "purchaseDate": Int(transaction!.purchaseDate.timeIntervalSince1970),
                            "json": String(data: transaction!.jsonRepresentation, encoding: .utf8) ?? "",
                            "appAccountToken": transaction!.appAccountToken?.uuidString ?? ""
                        ]
                        
                        result(transactionDetails)
                    } else {
                        let errorCode = "PURCHASE_ERROR"
                        let errorMessage = error?.localizedDescription ?? "购买失败"
                        
                        result(FlutterError(code: errorCode, message: errorMessage, details: nil))
                    }
                }
            } else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "缺少产品ID", details: nil))
            }
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    @objc private func handleNewTransaction(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let transactionId = userInfo["transactionId"] as? UInt64,
           let productId = userInfo["productId"] as? String,
           let appAccountToken = userInfo["appAccountToken"] as? String,
           let originalID = userInfo["originalID"] as? String,
           let json = userInfo["json"] as? String {
            
            // 构建交易信息
            let transactionInfo: [String: Any] = [
                "transactionId": transactionId,
                "productId": productId,
                "appAccountToken": appAccountToken,
                "originalID": originalID,
                "json": json,
                "type": "unfinishedTransaction"
            ]
            
            // 通过channel发送给Dart端
            transactionChannel?.invokeMethod("onUnfinishedTransaction", arguments: transactionInfo)
        }
    }
    
    @objc private func handleInitError(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let errorMessage = userInfo["error"] as? String {
            
            // 发送初始化错误到Flutter
            transactionChannel?.invokeMethod("onStoreKitInitError", arguments: [
                "error": errorMessage
            ])
        }
    }
}
