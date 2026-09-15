import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdMob 초기화와 광고 단위 ID를 한 곳에서 관리한다.
///
/// 스폰서(Firestore `sponsors` 컬렉션)가 없을 때 KnueNativeAdCard의 마지막
/// 대체 수단으로 쓴다 — 직접 제휴가 있으면 그게 우선이고, 없을 때만 빈 자리를
/// 채운다.
///
/// ⚠️ 개발/디버그 빌드는 항상 구글 공식 테스트 ID를 쓴다. 실제 광고 단위 ID로
/// 개발 중에 계속 광고를 띄우면 "무효 트래픽(invalid traffic)"으로 잡혀
/// AdMob 계정이 정지될 수 있다 — Google이 명시적으로 금지하는 행위다.
class AdService {
  AdService._();

  /// 네이티브 광고 팩토리 ID. android/.../MainActivity.kt와
  /// ios/Runner/AppDelegate.swift가 이 이름으로 등록해 둔 레이아웃과 짝이다.
  static const String nativeAdFactoryId = 'listTile';

  static const String _androidRealNativeId =
      'ca-app-pub-8400037761673359/6109981845';
  static const String _iosRealNativeId =
      'ca-app-pub-8400037761673359/9857655167';

  // Google 공식 테스트용 네이티브 고급형 광고 단위 (개발자 계정을 지키기 위해
  // 릴리스 빌드가 아니면 항상 이걸 쓴다). 출처: developers.google.com/admob/*/test-ads
  static const String _androidTestNativeId =
      'ca-app-pub-3940256099942544/2247696110';
  static const String _iosTestNativeId =
      'ca-app-pub-3940256099942544/3986624511';

  static bool get _isSupportedPlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// 지금 상황(플랫폼 + 릴리스 여부)에 맞는 네이티브 광고 단위 ID.
  /// 지원 안 하는 플랫폼(웹·데스크톱)에서 부르면 null.
  static String? get nativeAdUnitId {
    if (!_isSupportedPlatform) return null;
    final useTest = !kReleaseMode;
    if (Platform.isAndroid) {
      return useTest ? _androidTestNativeId : _androidRealNativeId;
    }
    return useTest ? _iosTestNativeId : _iosRealNativeId;
  }

  static bool _initialized = false;

  /// 앱 시작 시 한 번 호출. 광고를 요청하기 전에 반드시 끝나 있어야 한다.
  static Future<void> initialize() async {
    if (_initialized || !_isSupportedPlatform) return;
    _initialized = true;
    try {
      await MobileAds.instance.initialize();
    } catch (e) {
      debugPrint('AdService: 초기화 실패: $e');
    }
  }
}
