import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 전면(interstitial) 광고 로딩·표시를 한 곳에서 관리한다.
/// 지금은 무지개 모드 잠금 해제가 쓴다.
///
/// 예전엔 보상형(rewarded)이었다. 보상형은 30초를 끝까지 봐야 해서 테마 색을
/// 바꾸는 정도의 일에 비해 너무 길었다 — 광고 길이는 앱이 정하는 값이 아니라
/// 형식이 정하므로, 형식을 바꾸는 것 말고는 줄일 방법이 없었다.
///
/// 미리 하나를 불러와 캐싱해두고, 실제로 보여줄 때는 그 캐시를 즉시 쓴다 —
/// 사용자가 스위치를 누른 순간 로딩 스피너를 오래 보게 하지 않기 위해서다.
/// 캐시가 없으면(아직 안 불러졌거나 막 하나 써버렸으면) 그 자리에서 새로
/// 불러오되, 너무 오래 걸리면(8초) 광고 없이 실패로 처리한다.
class InterstitialAdService {
  InterstitialAdService._();

  /// ⚠️ **아직 비어 있다.** AdMob 콘솔에서 «전면 광고» 단위를 만들고 그 ID를
  /// 여기 넣어야 실제 광고가 나간다. 비어 있는 동안 릴리스 빌드는 광고를
  /// 띄우지 않고 [show]가 곧바로 `onUnavailable`로 간다 — 호출부는 그때
  /// 기능을 그냥 열어주므로(아래 주석 참고) 사용자가 막히지는 않는다.
  static const String _androidRealId = '';
  static const String _iosRealId = '';

  // Google 공식 테스트용 전면 광고 단위. 출처: developers.google.com/admob/*/test-ads
  static const String _androidTestId = 'ca-app-pub-3940256099942544/1033173712';
  static const String _iosTestId = 'ca-app-pub-3940256099942544/4411468910';

  static bool get _isSupportedPlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static String? get _adUnitId {
    if (!_isSupportedPlatform) return null;
    // 개발 빌드는 항상 테스트 ID. 실제 광고 단위로 개발 중에 계속 광고를
    // 띄우면 무효 트래픽으로 잡혀 AdMob 계정이 정지될 수 있다.
    if (!kReleaseMode) {
      return Platform.isAndroid ? _androidTestId : _iosTestId;
    }
    final realId = Platform.isAndroid ? _androidRealId : _iosRealId;
    return realId.isEmpty ? null : realId;
  }

  /// 광고 단위가 준비돼 있는지. 화면이 "광고를 본다"고 미리 안내할지 정할 때 쓴다.
  static bool get isConfigured => _adUnitId != null;

  static InterstitialAd? _cached;
  static bool _loading = false;

  /// 다음에 보여줄 광고를 미리 불러온다. 이미 캐싱돼 있거나 불러오는 중이면
  /// 아무 일도 안 한다 — 여러 화면에서 동시에 불러도 안전.
  static void preload() {
    if (_cached != null || _loading) return;
    final unitId = _adUnitId;
    if (unitId == null) return;
    _loading = true;
    InterstitialAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _cached = ad;
          _loading = false;
        },
        onAdFailedToLoad: (error) {
          _loading = false;
          debugPrint('InterstitialAdService: 로드 실패: $error');
        },
      ),
    );
  }

  /// 광고를 보여준다.
  ///
  /// [onClosed]는 광고를 닫고 돌아왔을 때 불린다. 전면 광고에는 보상형 같은
  /// "끝까지 봤다" 신호가 없다 — 몇 초 뒤 X로 닫아도 정상이다.
  /// [onUnavailable]은 광고를 아예 못 띄웠을 때(단위 미설정·네트워크 문제 등).
  static Future<void> show({
    required VoidCallback onClosed,
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

    // 닫힘 콜백은 반드시 한 번만 불러야 한다 — 닫힘과 실패가 겹쳐 들어오면
    // 무지개 모드가 두 번 켜지며 토스트도 두 번 뜬다.
    var done = false;
    void finish(VoidCallback callback) {
      if (done) return;
      done = true;
      callback();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        finish(onClosed);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('InterstitialAdService: 표시 실패: $error');
        ad.dispose();
        finish(onUnavailable);
      },
    );

    await ad.show();
  }

  static Future<InterstitialAd?> _loadOnDemand() async {
    final unitId = _adUnitId;
    if (unitId == null) return null;

    final completer = Completer<InterstitialAd?>();
    InterstitialAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
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
          debugPrint('InterstitialAdService: 즉석 로드 실패: $error');
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
