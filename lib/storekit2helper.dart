import 'package:flutter/services.dart';

typedef TransactionHandler = void Function(TransactionData transaction);

class Storekit2Helper {
  static const MethodChannel _channel = MethodChannel('storekit2helper');
  static TransactionHandler? _unfinishedTransactionHandler;

  // 初始化和设置未完成交易处理器
  static Future<void> initialize(
      {TransactionHandler? unfinishedTransactionHandler}) async {
    _unfinishedTransactionHandler = unfinishedTransactionHandler;

    // 设置方法调用处理器来接收来自iOS端的未完成交易通知
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onUnfinishedTransaction' &&
          _unfinishedTransactionHandler != null) {
        final transaction = Map<String, dynamic>.from(call.arguments);
        _unfinishedTransactionHandler!(TransactionData.fromMap(transaction));
        return true;
      }
      return null;
    });

    await _channel.invokeMethod('initialize');
  }

  // 获取购买历史
  static Future<List<String>> fetchPurchaseHistory() async {
    List<dynamic> history = await _channel.invokeMethod('fetchPurchaseHistory');
    return history.cast<String>();
  }

  // 获取产品信息
  static Future<List<ProductDetail>> fetchProducts(
      List<String> productIDs) async {
    final List<dynamic> productList = await _channel
        .invokeMethod('fetchProducts', {"productIDs": productIDs});

    List<ProductDetail> products = [];
    for (var product in productList) {
      products.add(ProductDetail(
        description: product['description'],
        productId: product['productId'],
        title: product['title'],
        price: product['price'],
        localizedPrice: product['localizedPrice'],
        type: product['type'],
        json: product['json'],
        periodUnit: product['periodUnit'],
        periodValue: product['periodValue'],
        periodTitle: product['periodTitle'],
        introductoryOffer: product['introductoryOffer'],
        introductoryOfferPeriod: product['introductoryOfferPeriod'],
        isTrial: product['isTrial'],
      ));
    }
    return products;
  }

  // 购买产品
  static Future<void> buyProduct(
    String productId,
    void Function(bool success, TransactionData? transaction,
            String? errorMessage)
        onResult, {
    String? uuid,
  }) async {
    try {
      final Map<String, dynamic> params = {'productId': productId};

      // 只有当uuid非空时才添加到参数中
      if (uuid != null && uuid.isNotEmpty) {
        params['uuid'] = uuid;
      }

      final dynamic result = await _channel.invokeMethod('buyProduct', params);

      // 明确将结果转换为Map<String, dynamic>
      final Map<String, dynamic> resultMap = Map<String, dynamic>.from(result);

      // 成功，调用回调函数，传入success=true、转换后的结果和null作为错误消息
      onResult(true, TransactionData.fromMap(resultMap), null);
    } on PlatformException catch (e) {
      // 如果有平台异常，则调用回调函数，传入success=false、null作为交易和错误消息
      onResult(false, null, e.message);
    } catch (e) {
      // 对于任何其他类型的错误，调用回调函数，传入success=false、null作为交易和通用错误消息
      onResult(false, null, '发生意外错误: $e');
    }
  }

  // 检查是否有活跃订阅
  static Future<bool> hasActiveSubscription() async {
    final bool hasSubscription =
        await _channel.invokeMethod('hasActiveSubscription');
    return hasSubscription;
  }

  // 恢复购买
  static Future<List<TransactionData>> restorePurchases() async {
    try {
      final List<dynamic> restoredTransactions =
          await _channel.invokeMethod('restorePurchases');

      // 将动态列表转换为强类型列表
      return restoredTransactions
          .map((transaction) => TransactionData.fromMap(Map<String, dynamic>.from(transaction)))
          .toList();
    } on PlatformException catch (e) {
      print('恢复购买失败: ${e.message}');
      return [];
    } catch (e) {
      print('恢复购买出现意外错误: $e');
      return [];
    }
  }

  // 完成交易
  static Future<bool> finishTransaction(int transactionId) async {
    try {
      final bool success = await _channel
          .invokeMethod('finishTransaction', {'transactionId': transactionId});
      return success;
    } catch (e) {
      print('完成交易失败: $e');
      return false;
    }
  }
}

/*
*
*
  "transactionId": transaction!.id,
  "productId": transaction!.productID,
  "appBundleID": transaction!.appBundleID,
  "originalID": transaction!.originalID,
  "purchaseDate": Int(transaction!.purchaseDate.timeIntervalSince1970),
  "json": String(data: transaction!.jsonRepresentation, encoding: .utf8) ?? "",
  "appAccountToken": transaction!.appAccountToken?.uuidString ?? ""
* */
class TransactionData {

  final String? transactionId;
  final String? productId;
  final String? transactionDate;
  final String? originalTransactionId;
  final String? status;
  final String? json;
  final String? appAccountToken;

  TransactionData({
     this.transactionId,
     this.productId,
     this.transactionDate,
     this.originalTransactionId,
     this.status,
     this.json,
    this.appAccountToken
  });
  // 定义一个Map to Model 的方法
  factory TransactionData.fromMap(Map<String, dynamic> map) {
    return TransactionData(
      transactionId: "${map['transactionId']}",
      productId: "${map['productId']}",
      transactionDate: "${map['transactionDate']}",
      originalTransactionId: "${map['originalID']}",
      appAccountToken: map['appAccountToken'] as String?,
      status: "${map['status']}",
      json: map['json'] as String?,
    );
  }
}

// 产品详情类
class ProductDetail {
  final String productId;
  final String title;
  final String description;
  final double price;
  final String localizedPrice;
  final String type;
  final String json;
  final String periodUnit;
  final int periodValue;
  final String periodTitle;
  final String introductoryOffer;
  final String introductoryOfferPeriod;
  final bool isTrial;

  ProductDetail({
    required this.productId,
    required this.title,
    required this.description,
    required this.price,
    required this.localizedPrice,
    required this.type,
    required this.json,
    required this.periodUnit,
    required this.periodValue,
    required this.periodTitle,
    required this.introductoryOffer,
    required this.introductoryOfferPeriod,
    required this.isTrial,
  });
}
