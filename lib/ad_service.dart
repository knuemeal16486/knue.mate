import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'premium_service.dart';

// 테스트 배너 ID — 배포 전 실제 AdMob ID로 교체할 것
String get _bannerMealId {
  if (kDebugMode) {
    return Platform.isAndroid
        ? 'ca-app-pub-3940256099942544/6300978111'
        : 'ca-app-pub-3940256099942544/2934735716';
  }
  // TODO: 실제 AdMob 배너 ID 입력 (식단)
  return Platform.isAndroid
      ? 'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX'
      : 'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX';
}

String get _bannerBusId {
  if (kDebugMode) {
    return Platform.isAndroid
        ? 'ca-app-pub-3940256099942544/6300978111'
        : 'ca-app-pub-3940256099942544/2934735716';
  }
  // TODO: 실제 AdMob 배너 ID 입력 (버스)
  return Platform.isAndroid
      ? 'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX'
      : 'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX';
}

class AdService {
  static final AdService _instance = AdService._();
  static AdService get instance => _instance;
  AdService._();

  Future<void> init() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await MobileAds.instance.initialize();
  }

  static String get mealBannerId => _bannerMealId;
  static String get busBannerId => _bannerBusId;
}

/// 광고 배너 위젯 — 프리미엄 사용자에게는 빈 SizedBox 반환
class AdBannerWidget extends StatefulWidget {
  final String adUnitId;
  const AdBannerWidget({super.key, required this.adUnitId});

  @override
  State<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<AdBannerWidget> {
  BannerAd? _bannerAd;
  bool _adLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    if (isPremiumNotifier.value) return;

    _bannerAd = BannerAd(
      adUnitId: widget.adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _adLoaded = true),
        onAdFailedToLoad: (_, error) {
          debugPrint('BannerAd load failed: $error');
          _bannerAd?.dispose();
          _bannerAd = null;
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isPremiumNotifier,
      builder: (_, isPremium, __) {
        if (isPremium) return const SizedBox.shrink();
        if (!_adLoaded || _bannerAd == null) return const SizedBox(height: 50);
        return SizedBox(
          height: _bannerAd!.size.height.toDouble(),
          child: AdWidget(ad: _bannerAd!),
        );
      },
    );
  }
}
