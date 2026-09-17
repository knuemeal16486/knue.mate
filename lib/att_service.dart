import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOS 앱 추적 투명성(ATT) 권한 요청.
///
/// AdMob이 맞춤 광고를 위해 광고 식별자(IDFA)를 쓰려면 이 권한이 필요하다.
/// Info.plist의 NSUserTrackingUsageDescription과 짝이며, ios/Runner/AppDelegate.swift가
/// "com.knue.knuemate/att" 채널로 ATTrackingManager.requestTrackingAuthorization을
/// 대신 호출해준다. Android/웹에서는 ATT 자체가 없는 개념이라 아무 일도 하지 않는다.
class AttService {
  AttService._();

  static const _channel = MethodChannel('com.knue.knuemate/att');

  /// 이미 사용자가 이전에 허용/거부해서 상태가 결정돼 있으면 시스템이 팝업을
  /// 다시 띄우지 않고 곧장 그 상태를 돌려준다 — 여러 번 불러도 안전하다.
  static Future<void> requestIfNeeded() async {
    if (kIsWeb || !Platform.isIOS) return;
    try {
      await _channel.invokeMethod('requestTrackingAuthorization');
    } catch (e) {
      debugPrint('AttService: 요청 실패: $e');
    }
  }
}
