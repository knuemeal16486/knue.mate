import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

// ── 강제 업데이트 ──────────────────────────────────────────────────────
//
// 새 버전이 스토어에 풀리면 Firebase 콘솔에서 `app_settings/app_version`의
// 빌드 번호를 올린다. 앱은 켜질 때(그리고 앱으로 돌아올 때 한 시간에 한 번)
// 그 문서를 읽어, 내 빌드 번호가 더 낮으면 닫을 수 없는 창을 띄우고 스토어로
// 보낸다(사용자 결정, 2026-10-15 — 업데이트는 강제).
//
// 버전 이름(1.6.4)이 아니라 **빌드 번호(103)**로 비교한다. App Store에 보이는
// 버전(1.8)은 App Store Connect에서 정한 표시 번호라 앱 안의 버전과 다르다.
// 빌드 번호는 두 스토어에서 같고 늘 커지기만 한다.
//
//   app_settings/app_version
//     androidBuild: 104   ← Android 앱이 이보다 낮으면 업데이트
//     iosBuild:     104   ← iOS 앱이 이보다 낮으면 업데이트
//
// **스토어에서 실제로 받을 수 있게 된 뒤에 올린다.** 심사 중이거나 단계적
// 출시 중에 올리면, 스토어에 아직 새 버전이 없는 사람이 창에 갇힌다.

/// Google Play 앱 페이지.
const String kPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=com.knue.knuemate';

/// App Store 앱 페이지(번들 com.knue.knuemate의 앱 번호 6757637319).
const String kAppStoreUrl = 'https://apps.apple.com/app/id6757637319';

/// 이 플랫폼이 받아야 할 최소 빌드 번호. 순수 함수 — 테스트 대상.
///
/// 문서가 없거나 값이 이상하면 null(묻지 않는다). 업데이트를 막는 쪽은
/// 언제나 명시적이어야 한다 — 잘못된 값 하나로 모든 사용자가 창에 갇히면 안 된다.
int? requiredBuildFor(Map<String, dynamic>? data, {required bool isIOS}) {
  final v = data?[isIOS ? 'iosBuild' : 'androidBuild'];
  if (v is int && v > 0) return v;
  if (v is num && v > 0) return v.toInt();
  return null;
}

/// 업데이트가 필요한지. 순수 함수 — 테스트 대상.
///
/// 내 빌드 번호를 못 읽으면(디버그·테스트 등) 묻지 않는다.
bool needsAppUpdate({required String currentBuild, required int? requiredBuild}) {
  if (requiredBuild == null) return false;
  final current = int.tryParse(currentBuild.trim());
  if (current == null) return false;
  return current < requiredBuild;
}

class AppUpdateGate {
  AppUpdateGate._();

  static bool _showing = false;
  static DateTime? _lastCheck;

  /// 앱으로 돌아올 때 다시 확인하는 최소 간격(읽기 한도 — 앱을 켤 때마다 1건).
  static const Duration recheckGap = Duration(hours: 1);

  /// 확인하고, 필요하면 창을 띄운다. 실패하면 조용히 넘어간다 — 확인이 안 된다고
  /// 앱을 막으면 안 된다.
  static Future<void> check(BuildContext context, {bool force = false}) async {
    if (kIsWeb || _showing) return;
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    final last = _lastCheck;
    if (!force && last != null && DateTime.now().difference(last) < recheckGap) {
      return;
    }
    // Firebase가 아직 안 떴으면(앱 시작 직후) 잠깐 기다린다.
    for (var i = 0; i < 10 && Firebase.apps.isEmpty; i++) {
      await Future.delayed(const Duration(seconds: 1));
    }
    if (Firebase.apps.isEmpty) return;
    _lastCheck = DateTime.now();
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('app_settings')
            .doc('app_version')
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 6)),
        PackageInfo.fromPlatform().timeout(const Duration(seconds: 3)),
      ]);
      final snap = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final info = results[1] as PackageInfo;
      final required = requiredBuildFor(snap.data(), isIOS: Platform.isIOS);
      if (!needsAppUpdate(currentBuild: info.buildNumber, requiredBuild: required)) {
        return;
      }
      if (!context.mounted) return;
      await _show(context);
    } catch (e) {
      debugPrint('AppUpdateGate: 확인 실패: $e');
    }
  }

  static Future<void> _show(BuildContext context) async {
    _showing = true;
    final storeUrl = Platform.isIOS ? kAppStoreUrl : kPlayStoreUrl;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          // 뒤로가기로도 닫히지 않는다(강제 업데이트).
          canPop: false,
          child: AlertDialog(
            title: const Text('업데이트가 필요해요'),
            content: const Text(
              '새 버전이 나왔어요. 최신 버전으로 업데이트해야 계속 쓸 수 있어요.',
            ),
            actions: [
              FilledButton(
                onPressed: () async {
                  try {
                    await launchUrl(
                      Uri.parse(storeUrl),
                      mode: LaunchMode.externalApplication,
                    );
                  } catch (e) {
                    debugPrint('AppUpdateGate: 스토어 열기 실패: $e');
                  }
                },
                child: const Text('업데이트'),
              ),
            ],
          ),
        ),
      );
    } finally {
      _showing = false;
    }
  }
}
