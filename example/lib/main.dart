import 'package:flutter/material.dart';
import 'dart:async';
import 'package:storekit2Utils/storekit2helper.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _hasActiveSubscription = false;
  List<ProductDetail> _products = [];
  List<TransactionData> _restoredTransactions = [];
  bool _isLoading = true;
  String _statusMessage = "正在加载...";

  // 模拟远程服务器API服务
  final MockApiService _apiService = MockApiService();

  @override
  void initState() {
    super.initState();
    _initializeStoreKit();
  }

  Future<void> _initializeStoreKit() async {
    try {
      // 初始化StoreKit并设置未完成交易处理器
      await Storekit2Helper.initialize(
        unfinishedTransactionHandler: _handleUnfinishedTransaction,
      );

      // 加载产品信息
      await _loadProducts();

      // 检查是否有活跃订阅
      await _checkSubscription();

      setState(() {
        _isLoading = false;
        _statusMessage = _hasActiveSubscription ? "您已订阅" : "您尚未订阅";
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = "初始化失败: $e";
      });
    }
  }

  Future<void> _loadProducts() async {
    try {
      // 这里使用您的实际产品ID
      final productIDs = [
        "purchase_0_99",
        "purchase_5_99",
        "purchase_9_99",
        "purchase_19_99",
        "purchase_29_99",
        "purchase_49_99",
        "purchase_99_99"
      ];
      final products = await Storekit2Helper.fetchProducts(productIDs);

      setState(() {
        _products = products;
      });
    } catch (e) {
      print("加载产品失败: $e");
    }
  }

  Future<void> _checkSubscription() async {
    try {
      final hasSubscription = await Storekit2Helper.hasActiveSubscription();

      setState(() {
        _hasActiveSubscription = hasSubscription;
      });
    } catch (e) {
      print("检查订阅状态失败: $e");
    }
  }

  // 处理未完成的交易
  void _handleUnfinishedTransaction(TransactionData transaction) async {
    print("收到未完成交易: ${transaction.productId}");

    // 显示交易信息
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("发现未完成交易: ${transaction.productId}")),
      );
    }

    // 在这里，您应该向您的服务器发送验证请求
    try {
      // 向服务器验证交易
      final verifyResult = await _apiService.verifyPurchase(
        productId: transaction.productId ?? "",
        transactionId: transaction.transactionId ?? "",
        receiptData: transaction.json ?? "",
        appAccountToken: transaction.appAccountToken ?? "",
      );

      if (verifyResult.success) {
        // 服务器验证成功，完成交易
        final finishSuccess = await Storekit2Helper.finishTransaction(
          int.parse(transaction.productId ?? "0"),
        );

        if (finishSuccess) {
          // 更新订阅状态
          await _checkSubscription();

          if (mounted) {
            setState(() {
              _statusMessage = _hasActiveSubscription ? "验证成功，您已订阅" : "验证成功，但未找到有效订阅";
            });
          }
        } else {
          print("完成交易失败");
        }
      } else {
        print("服务器验证失败: ${verifyResult.message}");
      }
    } catch (e) {
      print("处理未完成交易时出错: $e");
    }
  }

  // 购买产品
  void _buyProduct(ProductDetail product) async {
    setState(() {
      _statusMessage = "正在购买...";
      _isLoading = true;
    });

    try {
      // 生成唯一标识符用于跟踪此次交易
      final uuid = _generateUUID();

      Storekit2Helper.buyProduct(
        product.productId,
        (success, transaction, errorMessage) async {
          if (success && transaction != null) {
            setState(() {
              _statusMessage = "购买成功，正在验证...";
            });

            try {
              // 向服务器发送验证请求
              final verifyResult = await _apiService.verifyPurchase(
                productId: transaction.productId ?? "",
                transactionId: transaction.transactionId ?? "",
                receiptData: transaction.json ?? "",
                appAccountToken: transaction.appAccountToken ?? "",
              );

              if (verifyResult.success) {
                // 验证成功后，完成交易
                await Storekit2Helper.finishTransaction(
                    int.parse(transaction.transactionId ?? "0"));

                // 更新订阅状态
                await _checkSubscription();

                setState(() {
                  _isLoading = false;
                  _statusMessage = _hasActiveSubscription ? "购买并验证成功，您已订阅" : "购买成功，但未找到有效订阅";
                });
              } else {
                setState(() {
                  _isLoading = false;
                  _statusMessage = "服务器验证失败: ${verifyResult.message}";
                });
              }
            } catch (e) {
              setState(() {
                _isLoading = false;
                _statusMessage = "验证失败: $e";
              });
            }
          } else {
            setState(() {
              _isLoading = false;
              _statusMessage = "购买失败: $errorMessage";
            });
          }
        },
        uuid: uuid,
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = "购买过程中出错: $e";
      });
    }
  }

  // 恢复购买
  Future<void> _restorePurchases() async {
    setState(() {
      _statusMessage = "正在恢复购买...";
      _isLoading = true;
    });

    try {
      final transactions = await Storekit2Helper.restorePurchases();

      setState(() {
        _restoredTransactions = transactions;
      });

      if (transactions.isEmpty) {
        setState(() {
          _statusMessage = "没有找到可恢复的购买";
          _isLoading = false;
        });
        return;
      }

      // 验证恢复的交易
      for (final transaction in transactions) {
        // 向服务器发送验证请求
        final verifyResult = await _apiService.verifyPurchase(
          productId: transaction.productId ?? "",
          transactionId: transaction.transactionId ?? "",
          receiptData: transaction.json ?? "",
          appAccountToken: null, // 恢复的交易可能没有appAccountToken
        );

        if (verifyResult.success) {
          print("交易 ${transaction.transactionId} 验证成功");
        } else {
          print("交易 ${transaction.transactionId} 验证失败: ${verifyResult.message}");
        }
      }

      // 更新订阅状态
      await _checkSubscription();

      setState(() {
        _isLoading = false;
        _statusMessage = _hasActiveSubscription ? "恢复成功，您已订阅" : "恢复成功，但未找到有效订阅";
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = "恢复购买失败: $e";
      });
    }
  }

  // 生成UUID
  String _generateUUID() {
    return DateTime.now().millisecondsSinceEpoch.toString() +
        "-" +
        (1000 + DateTime.now().microsecond % 9000).toString();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('StoreKit2 示例应用'),
          actions: [
            IconButton(
              icon: Icon(Icons.refresh),
              onPressed: _restorePurchases,
              tooltip: '恢复购买',
            )
          ],
        ),
        body: _isLoading
            ? Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: EdgeInsets.all(16.0),
                      color: Colors.white,
                      child: Column(
                        children: [
                          Text(
                            _statusMessage,
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 8),
                          Text(
                            "订阅状态: ${_hasActiveSubscription ? '已订阅' : '未订阅'}",
                            style: TextStyle(
                              fontSize: 16,
                              color: _hasActiveSubscription ? Colors.green : Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        "可用产品",
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (_products.isEmpty)
                      Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(child: Text("没有可用的产品")),
                      )
                    else
                      ..._products.map((product) => _buildProductCard(product)).toList(),
                    if (_restoredTransactions.isNotEmpty) ...[
                      Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          "恢复的交易",
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ..._restoredTransactions
                          .map((transaction) => _buildTransactionCard(transaction))
                          .toList(),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildProductCard(ProductDetail product) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    product.title,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  product.localizedPrice,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(product.description),
            if (product.type.contains("autoRenewable"))
              Text(
                "订阅周期: ${product.periodTitle}",
                style: TextStyle(color: Colors.blue),
              ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _buyProduct(product),
              child: Text('购买'),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 40),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionCard(TransactionData transaction) {
    final date = DateTime.fromMillisecondsSinceEpoch(int.parse(transaction.transactionDate ?? "0") * 1000);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "产品: ${transaction.productId}",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text("交易ID: ${transaction.transactionId}"),
            Text("购买日期: ${date.toLocal()}"),
            // if (transaction['isSubscription'] == true)
            //   Text(
            //     "类型: 订阅",
            //     style: TextStyle(color: Colors.blue),
            //   ),
          ],
        ),
      ),
    );
  }
}

// 模拟API服务
class MockApiService {
  Future<VerifyResult> verifyPurchase({
    required String productId,
    required String transactionId,
    required String receiptData,
    String? appAccountToken,
  }) async {
    // 模拟网络延迟
    await Future.delayed(Duration(seconds: 1));

    // 在实际应用中，这里应该向您的服务器发送请求
    // 服务器会将收据发送到苹果的服务器进行验证

    // 模拟成功响应
    return VerifyResult(
      success: true,
      message: "验证成功",
      data: {
        "productId": productId,
        "transactionId": transactionId,
        "purchaseDate": DateTime.now().millisecondsSinceEpoch ~/ 1000,
        "expiresDate": DateTime.now().add(Duration(days: 30)).millisecondsSinceEpoch ~/ 1000,
      },
    );
  }
}

// 验证结果类
class VerifyResult {
  final bool success;
  final String message;
  final Map<String, dynamic>? data;

  VerifyResult({
    required this.success,
    required this.message,
    this.data,
  });
}
