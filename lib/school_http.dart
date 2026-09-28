import 'package:package_info_plus/package_info_plus.dart';

/// 학교 서버가 우리에게 연락할 주소.
const String kSchoolContactEmail = 'knuemeal16486@gmail.com';

/// 학교 서버(knue.ac.kr 계열)로 보내는 모든 요청의 User-Agent.
/// 순수 함수 — 테스트 대상.
///
/// 2026-09-28 정보전산원이 부탁했다: 앱 이름과 연락처가 있으면 문제가 생겼을
/// 때 막기 전에 먼저 연락할 수 있다. 예전엔 게시판은 브라우저 흉내, 학사일정은
/// Dart 기본값, 식단은 또 다른 값이라 한 앱의 요청인지조차 알 수 없었다.
/// 학교에는 "KNUE MOA"라는 이름으로 알려져 있어 둘 다 넣는다.
String schoolUserAgent(String version) =>
    'KNUE-Mate/$version (KNUE MOA; +$kSchoolContactEmail)';

class SchoolHttp {
  static String? _userAgent;

  /// 학교 서버 요청에 붙일 헤더. 버전은 한 번 읽어 둔다.
  /// (Future가 아니라 결과 문자열을 들고 있는다 — 다른 Zone에서 만든 Future를
  /// 기다리면 위젯 테스트에서 영영 안 끝난다.)
  static Future<Map<String, String>> headers() async =>
      {'User-Agent': _userAgent ??= await _loadUserAgent()};

  static Future<String> _loadUserAgent() async {
    try {
      // 버전을 못 읽는다고 학교 요청이 멈추면 안 된다.
      final info = await PackageInfo.fromPlatform().timeout(
        const Duration(seconds: 2),
      );
      return schoolUserAgent(info.version);
    } catch (_) {
      return schoolUserAgent('unknown');
    }
  }
}
