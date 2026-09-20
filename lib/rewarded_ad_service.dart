import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 보상형 광고 로딩·표시를 한 곳에서 관리한다.
/// 무지개 모드 잠금 해제와 랜덤 테마 색 뽑기가 같은 광고 단위를 쓴다.
///
/// 미리 하나를 불러와 캐싱해두고, 실제로 보여줄 때는 그 캐시를 즉시 쓴다 —
/// 사용자가 스위치를 누른 순간 로딩 스피너를 오래 보게 하지 않기 위해서다.
/// 캐시가 없으면(아직 안 불러졌거나 막 하나 써버렸으면) 그 자리에서 새로
/// 불러오되, 너무 오래 걸리면(8초) 광고 없이 실패로 처리한다.
///
class RewardedAdService {
  RewardedAdService._();

  static const String _androidRealId =
      'ca-app-pub-8400037761673359/5991705303';
  static const String _iosRealId = 'ca-app-pub-8400037761673359/4422168102';

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
    // 개발 빌드는 항상 테스트 ID. 실제 광고 단위로 개발 중에 계속 광고를
    // 띄우면 무효 트래픽으로 잡혀 AdMob 계정이 정지될 수 있다.
    return kReleaseMode ? realId : testId;
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

    // 캐시가 비었을 때만 즉석 로드. preload를 여기서 먼저 부르면 즉석
    // 로드와 겹쳐 **광고를 두 개 불러놓고 하나만 쓰게 된다** — 요청 대비
    // 노출 비율이 나빠지므로, 보여줄 것을 확보한 뒤에 다음 몫을 부른다.
    ad ??= await _loadOnDemand();
    preload();

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
          if (!completer.isCompleted) {
            completer.complete(ad);
            return;
          }
          // 8초 타임아웃으로 포기한 뒤에 도착했다. 그냥 두면 dispose되지
          // 않아 광고 객체가 샌다 — 다음 번 몫으로 넣어두고, 자리가 이미
          // 찼으면 버린다.
          if (_cached == null) {
            _cached = ad;
          } else {
            ad.dispose();
          }
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
