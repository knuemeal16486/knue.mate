import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ui_utils.dart';

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

/// 이 플랫폼이 받아야 할 최소 빌드 번호(강제). 순수 함수 — 테스트 대상.
///
/// 문서가 없거나 값이 이상하면 null(묻지 않는다). 업데이트를 막는 쪽은
/// 언제나 명시적이어야 한다 — 잘못된 값 하나로 모든 사용자가 창에 갇히면 안 된다.
int? requiredBuildFor(Map<String, dynamic>? data, {required bool isIOS}) {
  final v = data?[isIOS ? 'iosBuild' : 'androidBuild'];
  if (v is int && v > 0) return v;
  if (v is num && v > 0) return v.toInt();
  return null;
}

/// 이 플랫폼에 권장되는 최신 빌드 번호(선택 업데이트, 닫기 가능). 순수 함수.
///
/// Firestore `app_settings/app_version`:
/// - `recommendedAndroidBuild`: 115
/// - `recommendedIosBuild`: 115
int? recommendedBuildFor(Map<String, dynamic>? data, {required bool isIOS}) {
  final v = data?[isIOS ? 'recommendedIosBuild' : 'recommendedAndroidBuild'];
  if (v is int && v > 0) return v;
  if (v is num && v > 0) return v.toInt();
  return null;
}

/// 업데이트 안내 문구(`releaseNotes`). 비어 있거나 문자열이 아니면 null.
String? releaseNotesFor(Map<String, dynamic>? data) {
  final v = data?['releaseNotes'];
  if (v is! String) return null;
  final trimmed = v.trim();
  return trimmed.isEmpty ? null : trimmed;
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

/// 현재 빌드에 대한 업데이트 판정 결과.
enum AppUpdateKind { none, optional, forced }

AppUpdateKind resolveUpdateKind({
  required String currentBuild,
  required Map<String, dynamic>? data,
  required bool isIOS,
}) {
  final required = requiredBuildFor(data, isIOS: isIOS);
  if (needsAppUpdate(currentBuild: currentBuild, requiredBuild: required)) {
    return AppUpdateKind.forced;
  }
  final recommended = recommendedBuildFor(data, isIOS: isIOS);
  if (needsAppUpdate(currentBuild: currentBuild, requiredBuild: recommended)) {
    return AppUpdateKind.optional;
  }
  return AppUpdateKind.none;
}

class AppUpdateGate {
  AppUpdateGate._();

  static bool _showing = false;
  static DateTime? _lastCheck;
  static const String _optionalDismissedKey = 'app_update_optional_dismissed_v1';

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
      final data = snap.data();
      final kind = resolveUpdateKind(
        currentBuild: info.buildNumber,
        data: data,
        isIOS: Platform.isIOS,
      );
      if (kind == AppUpdateKind.none) return;

      // 선택 업데이트는 사용자가 "나중에"를 누른 빌드+날짜엔 하루 동안 다시 묻지 않는다.
      final recBuild = recommendedBuildFor(data, isIOS: Platform.isIOS);
      final todayKey = _todayStamp(recBuild ?? 0);
      if (kind == AppUpdateKind.optional) {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getString(_optionalDismissedKey) == todayKey) return;
      }

      if (!context.mounted) return;
      await _show(
        context,
        forced: kind == AppUpdateKind.forced,
        releaseNotes: releaseNotesFor(data),
        optionalDismissStamp: kind == AppUpdateKind.optional ? todayKey : null,
      );
    } catch (e) {
      debugPrint('AppUpdateGate: 확인 실패: $e');
    }
  }

  static String _todayStamp(int build) {
    final now = DateTime.now();
    return '$build-${now.year}-${now.month}-${now.day}';
  }

  static Future<void> _show(
    BuildContext context, {
    required bool forced,
    String? releaseNotes,
    String? optionalDismissStamp,
  }) async {
    _showing = true;
    final storeUrl = Platform.isIOS ? kAppStoreUrl : kPlayStoreUrl;
    final primary = Theme.of(context).primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: !forced,
        builder: (dialogContext) => PopScope(
          // 강제 업데이트일 때만 뒤로가기 차단.
          canPop: !forced,
          child: AlertDialog(
            title: Text(forced ? '업데이트가 필요해요' : '새 버전이 나왔어요'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  forced
                      ? '최신 버전으로 업데이트해야 계속 이용할 수 있어요.'
                      : '더 편리해진 최신 버전으로 업데이트해 보세요.',
                ),
                if (releaseNotes != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: KnueTokens.bg(isDark),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: KnueTokens.hairline(isDark),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      releaseNotes,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              if (!forced)
                TextButton(
                  onPressed: () async {
                    if (optionalDismissStamp != null) {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString(
                        _optionalDismissedKey,
                        optionalDismissStamp,
                      );
                    }
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('나중에'),
                ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: KnueTokens.onAccent(primary),
                ),
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
