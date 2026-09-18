import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 보상형 광고(무지개 모드 잠금 해제용) 로딩·표시를 한 곳에서 관리한다.
///
/// 미리 하나를 불러와 캐싱해두고, 실제로 보여줄 때는 그 캐시를 즉시 쓴다 —
/// 사용자가 스위치를 누른 순간 로딩 스피너를 오래 보게 하지 않기 위해서다.
/// 캐시가 없으면(아직 안 불러졌거나 막 하나 써버렸으면) 그 자리에서 새로
/// 불러오되, 너무 오래 걸리면(8초) 광고 없이 실패로 처리한다.
///
/// ⚠️ 아래 real ID는 AdMob 콘솔에서 "보상형" 광고 단위를 새로 만든 뒤
/// 넣어야 한다(네이티브 광고 단위를 만들 때와 같은 절차). 아직 안 만들어서
/// 지금은 테스트 ID로 대체돼 있다 — 실제 배포 전에 채워 넣을 것.
class RewardedAdService {
  RewardedAdService._();

  static const String _androidRealId = 'REPLACE_ME_ANDROID_REWARDED_UNIT_ID';
  static const String _iosRealId = 'REPLACE_ME_IOS_REWARDED_UNIT_ID';

  // Google 공식 테스트용 보상형 광고 단위. 출처: developers.google.com/admob/*/test-ads
  static const String _androidTestId =
      'ca-app-pub-3940256099942544/5224354917';
  static const String _iosTestId = 'ca-app-pub-3940256099942544/1712485313';

  static bool get _isSupportedPlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static String? get _adUnitId {
    if (!_isSupportedPlatform) return null;
    final realId = Platform.isAndroid ? _androidRealId : _iosRealId;
    final testId = Platform.isAndroid ? _androidTestId : _iosTestId;
    // real ID를 아직 안 채워 넣었으면(placeholder 그대로면) 릴리스에서도
    // 테스트 ID로 대체한다 — 빈 문자열이나 placeholder로 요청을 보내
    // 광고가 통째로 안 뜨는 것보다는, 테스트 광고라도 뜨는 편이 낫다.
    final useReal = kReleaseMode && !realId.startsWith('REPLACE_ME');
    return useReal ? realId : testId;
  }

  static RewardedAd? _cached;
  static bool _loading = false;

  /// 다음에 보여줄 광고를 미리 불러온다. 이미 캐싱돼 있거나 불러오는 중이면
  /// 아무 일도 안 한다 — 여러 화면에서 동시에 불러도 안전.
  static void preload() {
    if (_cached != null || _loading) return;
    final unitId = _adUnitId;
    if (unitId == null) return;
    _loading = true;
    RewardedAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _cached = ad;
          _loading = false;
        },
        onAdFailedToLoad: (error) {
          _loading = false;
          debugPrint('RewardedAdService: 로드 실패: $error');
        },
      ),
    );
  }

  /// 광고를 보여준다. [onEarned]는 끝까지 보고 보상을 받았을 때만 불린다.
  /// [onUnavailable]은 광고를 아예 못 띄웠을 때(네트워크 문제 등).
  static Future<void> show({
    required VoidCallback onEarned,
    required VoidCallback onUnavailable,
  }) async {
    var ad = _cached;
    _cached = null;
    preload(); // 다음 번을 위해 미리 하나 더 불러둔다

    ad ??= await _loadOnDemand();

    if (ad == null) {
      onUnavailable();
      return;
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) => ad.dispose(),
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        onUnavailable();
      },
    );

    await ad.show(onUserEarnedReward: (ad, reward) => onEarned());
  }

  static Future<RewardedAd?> _loadOnDemand() async {
    final unitId = _adUnitId;
    if (unitId == null) return null;

    final completer = Completer<RewardedAd?>();
    RewardedAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          if (!completer.isCompleted) completer.complete(ad);
        },
        onAdFailedToLoad: (error) {
          debugPrint('RewardedAdService: 즉석 로드 실패: $error');
          if (!completer.isCompleted) completer.complete(null);
        },
      ),
    );

    return completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => null,
    );
  }
}
