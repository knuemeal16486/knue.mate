import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kProProductId = 'knue_mate_pro';
const String kPremiumPrefKey = 'premium_unlocked';

final ValueNotifier<bool> isPremiumNotifier = ValueNotifier(false);

class PremiumService {
  static final PremiumService _instance = PremiumService._();
  static PremiumService get instance => _instance;
  PremiumService._();

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    isPremiumNotifier.value = prefs.getBool(kPremiumPrefKey) ?? false;

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final available = await InAppPurchase.instance.isAvailable();
      if (!available) return;

      _purchaseSubscription = InAppPurchase.instance.purchaseStream.listen(
        _handlePurchaseUpdate,
        onError: (e) => debugPrint('IAP stream error: $e'),
      );
    }
  }

  void dispose() {
    _purchaseSubscription?.cancel();
  }

  Future<void> buyPro() async {
    if (isPremiumNotifier.value) return;
    final available = await InAppPurchase.instance.isAvailable();
    if (!available) return;

    final response = await InAppPurchase.instance.queryProductDetails({kProProductId});
    if (response.productDetails.isEmpty) {
      debugPrint('IAP: product not found — check Play/App Store listing');
      return;
    }

    final purchaseParam = PurchaseParam(productDetails: response.productDetails.first);
    await InAppPurchase.instance.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<void> restorePurchases() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      await InAppPurchase.instance.restorePurchases();
    }
  }

  Future<void> _handlePurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.productID == kProProductId) {
        if (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored) {
          await _setPremium(true);
        } else if (p.status == PurchaseStatus.error) {
          debugPrint('IAP purchase error: ${p.error}');
        }
        if (p.pendingCompletePurchase) {
          await InAppPurchase.instance.completePurchase(p);
        }
      }
    }
  }

  static Future<void> _setPremium(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kPremiumPrefKey, value);
    isPremiumNotifier.value = value;
  }

  // 개발/테스트 전용
  static Future<void> debugSetPremium(bool value) => _setPremium(value);
}
