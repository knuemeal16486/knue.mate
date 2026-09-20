import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as htmlParser;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:home_widget/home_widget.dart';
import 'package:flutter/services.dart';
import 'firebase_sync_service.dart';
import 'offline_cache.dart';
import 'schedule_model.dart';

// [1] 전역 설정
const String kBaseUrl = "https://knue-meal-api.onrender.com";
const String kHomeWidgetChannel = 'home_widget';

final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
  ThemeMode.system,
);
final ValueNotifier<Color> themeColor = ValueNotifier(const Color(0xFF2563EB));
final ValueNotifier<MealSource> defaultSourceNotifier = ValueNotifier(
  MealSource.a,
);

final ValueNotifier<double> widgetTransparency = ValueNotifier(0.0);
final ValueNotifier<ThemeMode> widgetTheme = ValueNotifier(ThemeMode.system);
final ValueNotifier<MealSource> widgetSource = ValueNotifier(MealSource.a);

/// 테마 색상 팔레트 — 선명하고 밝은 톤.
///
/// ⚠️ 의도적으로 대비보다 색감을 택한 팔레트다.
/// 이 색들은 헤더·앱바 배경으로 깔리고 그 위에 흰 글씨가 올라가므로, 밝은
/// 색(노랑 1.40:1, 라임 1.79:1)에서는 글씨가 잘 읽히지 않는다. 대비를 맞추려
/// 어둡게 낮춰봤더니 노랑이 머스타드가 되는 등 팔레트 전체가 탁해져서,
/// **선명함을 유지하기로 결정했다.**
///
/// 대신 [KnueTokens.headerTextShadow]로 아주 옅은 그림자를 깔아 글자 가장자리만
/// 잡아준다. 밝은 색을 "읽히게" 만들 만큼 진한 그림자는 그 자체로 지저분해서
/// 쓰지 않는다 — 즉 밝은 테마색을 고르면 헤더 글씨가 흐린 건 감수한 결과다.
const List<Color> kColorPalette = [
  Color(0xFF2563EB), // 청람 블루 (기본)
  Color(0xFFEF5350), // 레드
  Color(0xFFEC407A), // 핑크
  Color(0xFFC77AD3), // 오키드
  Color(0xFFAB47BC), // 퍼플
  Color(0xFF7E57C2), // 딥퍼플
  Color(0xFF5C6BC0), // 인디고
  Color(0xFF039BE5), // 라이트블루
  Color(0xFF00ACC1), // 시안
  Color(0xFF00897B), // 틸
  Color(0xFF43A047), // 그린
  Color(0xFF7CB342), // 라이트그린
  Color(0xFFC0CA33), // 라임
  Color(0xFFFDD835), // 노랑
  Color(0xFFFFB300), // 앰버
  Color(0xFFFB8C00), // 오렌지
  Color(0xFFF4511E), // 딥오렌지
  Color(0xFF6D4C41), // 브라운
  Color(0xFF757575), // 그레이
  Color(0xFF000000), // 블랙
];

/// 무지개 모드용 팔레트 — 색상환을 고르게 도는 12색.
/// 하루에 한 색씩 돌아가며 쓰인다([colorOfDay]).
/// [kColorPalette]에서 그대로 뽑아 써서 어느 날 걸려도 앱 색감이 유지된다.
const List<Color> kRainbowPalette = [
  Color(0xFFEF5350), // 0  빨강
  Color(0xFFF4511E), // 1  주홍
  Color(0xFFFB8C00), // 2  주황
  Color(0xFFFDD835), // 3  노랑
  Color(0xFFC0CA33), // 4  라임
  Color(0xFF7CB342), // 5  연두
  Color(0xFF43A047), // 6  초록
  Color(0xFF00897B), // 7  청록
  Color(0xFF00ACC1), // 8  시안
  Color(0xFF039BE5), // 9  파랑
  Color(0xFF5C6BC0), // 10 남색
  Color(0xFFAB47BC), // 11 보라
];

/// 무지개 모드 on/off. 켜면 사용자가 고른 색 대신 [colorOfDay]가 쓰인다.
/// 수동으로 고른 색은 그대로 저장돼 있어, 끄면 원래 색으로 돌아온다.
final ValueNotifier<bool> rainbowModeNotifier = ValueNotifier(false);

/// 그날의 색. 날짜에서 결정되므로 **하루 동안은 고정**이고, 앱을 껐다 켜도
/// 같은 색이 나온다. "무작위"지만 화면을 볼 때마다 바뀌면 어지럽기 때문이다.
///
/// 연속한 날이 비슷한 색으로 이어지지 않게 7(팔레트 길이 12와 서로소)을
/// 곱해 건너뛴다 — 12일 주기로 모든 색을 한 번씩 돈다.
Color colorOfDay(DateTime date) {
  final epochDay =
      DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/
          Duration.millisecondsPerDay;
  final idx = (epochDay * 7) % kRainbowPalette.length;
  return kRainbowPalette[idx];
}

/// 테마 팔레트에서 무작위로 한 색을 뽑는다(보상형 광고 보상용).
///
/// **지금 쓰고 있는 색은 후보에서 뺀다** — 광고를 끝까지 봤는데 색이 그대로면
/// 보상을 못 받은 것처럼 보인다. 팔레트에 색이 하나뿐이면 어쩔 수 없이 그걸
/// 돌려준다.
///
/// [random]은 테스트에서 결과를 고정하려고 주입하는 용도.
Color pickRandomThemeColor(Color current, {Random? random}) {
  final candidates = kColorPalette
      .where((c) => c.toARGB32() != current.toARGB32())
      .toList();
  if (candidates.isEmpty) return current;
  final r = random ?? Random();
  return candidates[r.nextInt(candidates.length)];
}

/// 식단을 긁어오는 실제 출처.
///
/// a는 www.knue.ac.kr이 "사도교육원식당"이라 부르는 그 식당인데, 학교의 다른
/// 공식 페이지(pot.knue.ac.kr)는 **같은 메뉴를 "기숙사 식당"**으로 싣고
/// 학생들도 "긱식"이라 부른다. 두 페이지의 메뉴가 글자까지 같은 것을 확인했다.
/// 한때 "사도교육원 식당"으로 바꿔 달았더니 학생들이 자기가 먹는 식당이
/// 아닌 줄 알고 "식단이 안 맞는다"고 했다. 그래서 학생이 쓰는 이름으로 둔다.
///
/// b는 pot.knue.ac.kr 첫 번째 표인 "교직원 식당"이다.
/// 라벨을 화면마다 삼항연산자로 흩어두면 또 어긋나므로 여기 한 곳에만 둔다.
///
/// ⚠️ enum 순서는 SharedPreferences에 index로 저장되므로 바꾸거나 중간에
/// 끼워넣지 말 것 ([PreferencesService.keyMealSource]).
enum MealSource {
  a("기숙사 식당", "기숙사"),
  b("교직원 식당", "교직원");

  /// 전체 이름. 다이얼로그·토스트·알림 문구용.
  final String label;

  /// 좁은 자리(앱바 토글, 위젯, 홈 카드 배지)용 축약 이름.
  final String shortLabel;

  const MealSource(this.label, this.shortLabel);
}

enum MealType {
  breakfast("아침", Icons.wb_twilight_rounded, "07:30 ~ 09:00", "breakfast"),
  lunch("점심", Icons.wb_sunny_rounded, "11:30 ~ 13:30", "lunch"),
  dinner("저녁", Icons.nights_stay_rounded, "17:30 ~ 19:00", "dinner");

  final String label;
  final IconData icon;
  final String timeRange;
  final String stdKey;
  const MealType(this.label, this.icon, this.timeRange, this.stdKey);
}

enum ServeStatus { open, waiting, closed, notToday }

/// 공지 알림을 올라오는 즉시 받을지, 하루 중 정해둔 시각에 모아서 받을지.
enum NoticeAlertMode { instant, scheduled }

enum AppTab {
  home("홈", Icons.home_rounded, Colors.indigo),
  meal("식단", Icons.restaurant_menu_rounded, Colors.orange),
  bus("버스", Icons.directions_bus_rounded, Colors.blue),
  run("런", Icons.directions_run_rounded, Colors.green),
  map("지도", Icons.map_rounded, Colors.deepPurple),
  settings("설정", Icons.settings_rounded, Colors.grey);

  final String label;
  final IconData icon;
  final Color color;
  const AppTab(this.label, this.icon, this.color);
}

/// 홈 히어로의 인사말 후보. 시간대별/요일별로 풍부하게 준비하여 접속할 때마다
/// 매일매일 살아 숨쉬는 느낌을 준다.
const Map<String, List<String>> kGreetings = {
  'dawn': [ // 0~5시 (새벽/심야)
    '아직 깨어 있군요',
    '무리하지 말고 조금 쉬어요',
    '새벽 공기가 찹니다',
    '곧 해가 떠요',
    '오늘 밤도 깊어가네요',
    '잠 못 이루는 밤인가요?',
    '충분한 수면도 실력이에요',
    '새벽 감성에 취하는 시간',
    '조용한 캠퍼스의 고요한 밤',
    '따뜻한 물 한 잔 마셔요',
    '내일을 위해 이제 눈을 붙여요',
    '오늘 하루도 참 고생 많았어요',
    '도서관의 불빛처럼 빛나는 밤',
  ],
  'morning': [ // 5~11시 (아침/등교)
    '좋은 아침이에요',
    '오늘도 잘 부탁해요',
    '상쾌한 하루 시작해요',
    '아침 챙겨 드셨나요',
    '오늘은 어떤 하루가 될까요',
    '기분 좋은 하루 되세요',
    '아침 공기 마시며 기지개 쭉!',
    '오늘 1교시도 파이팅이에요',
    '캠퍼스에 부는 싱그러운 바람',
    '오늘 하루도 힘차게 출발!',
    '따뜻한 햇살 가득한 아침이에요',
    '등굣길 발걸음 가볍게!',
    '오늘 하루도 당신을 응원해요',
    '매일 한 걸음씩 나아가는 중',
  ],
  'lunch': [ // 11~14시 (점심시간)
    '점심 시간이에요',
    '오늘 학식 메뉴는 뭘까요?',
    '맛있게 드세요',
    '잘 챙겨 먹어야 힘이 나요',
    '점심 먹고 힘내요',
    '오늘 점심도 든든하게!',
    '식곤증 조심! 오후도 힘내요',
    '청람광장 벤치에서 커피 한 잔 어때요?',
    '밥심으로 달리는 청람인',
    '맛점하시고 충전하세요!',
    '점심 든든히 먹고 남은 하루도 파이팅',
    '잠깐 햇살 받으며 힐링해요',
  ],
  'afternoon': [ // 14~18시 (오후/수업)
    '오늘도 파이팅!',
    '조금만 더 힘내요',
    '나른할 땐 잠깐 걸어요',
    '커피 한 잔 어때요?',
    '오후도 잘 보내고 있나요?',
    '거의 다 왔어요, 힘내요!',
    '스트레칭 한번 쭉 해볼까요?',
    '오후 수업도 집중력 발휘!',
    '미호천 노을이 기다리고 있어요',
    '잠깐 쉬어가는 여유를 가져요',
    '오늘 할 일 차근차근 해내요',
    '뿌듯한 오후를 만들어가요',
    '당신의 노력이 빛을 발할 거예요',
  ],
  'evening': [ // 18~22시 (저녁/하교)
    '오늘 하루도 수고 많으셨어요',
    '오늘 하루 어땠나요?',
    '저녁은 맛있게 드셨어요?',
    '이제 편안하게 쉬어요',
    '오늘도 열심히 잘 버텼어요',
    '노을 지는 교원대 캠퍼스',
    '저녁 바람이 기분 좋게 불어요',
    '오늘의 작은 성취를 칭찬해요',
    '따뜻하고 포근한 저녁 보내세요',
    '하굣길 발걸음 조심히 가세요',
    '오늘도 한 걸음 더 성장했어요',
    '지친 하루 끝 맛있는 저녁 챙겨요',
  ],
  'night': [ // 22~24시 (밤/휴식)
    '편안한 밤 되세요',
    '오늘 하루도 정말 고생했어요',
    '푹 자고 내일 만나요',
    '좋은 꿈 꾸세요',
    '하루의 끝, 온전한 나만의 시간',
    '오늘 있었던 걱정은 훌훌 털어내요',
    '내일은 더 좋은 일이 생길 거예요',
    '별이 빛나는 청람의 밤',
    '오늘 하루도 참 애썼어요',
    '포근한 이불 속으로 쏙!',
    '달콤한 휴식 시간 보내세요',
    '내일을 위해 푹 쉬어요',
  ],
  'monday': [ // 월요일 특별 멘트
    '새로운 한 주의 시작, 힘내요!',
    '월요병 이겨내고 파이팅!',
    '이번 주도 기분 좋게 출발해봐요',
  ],
  'friday': [ // 금요일 특별 멘트
    '드디어 금요일! 오늘만 버텨요',
    '신나는 불금, 조금만 더 힘내요!',
    '주말이 코앞이에요, 파이팅!',
  ],
  'weekend': [ // 주말 특별 멘트
    '여유로운 주말, 푹 쉬세요',
    '행복하고 따뜻한 주말 보내요',
    '주말엔 좋아하는 걸 마음껏 즐겨요',
    '재충전하는 꿀 같은 주말 되세요',
  ],
  'rain': [ // 비/소나기 날씨 멘트
    '강내면에 비가 내려요. 우산 꼭 챙기세요! ☔',
    '촉촉하게 젖은 청람 캠퍼스, 빗길 조심하세요',
    '비 오는 날엔 따뜻한 학식 국물이 딱이죠 🍲',
    '빗소리 들으며 도서관에서 책 한 권 어때요?',
    '갑작스러운 소나기 조심! 우산 챙기셨나요?',
    '비 내리는 강내면, 미끄러우니 발걸음 조심해요',
  ],
  'snow': [ // 눈/한파 날씨 멘트
    '하얗게 눈 덮인 교원대, 빙판길 조심하세요! ❄️',
    '청람광장이 겨울 왕국이 되었어요 ☃️',
    '눈이 펑펑 내려요! 미끄럼 주의하고 따뜻하게 입어요',
    '오늘 날씨가 매섭게 추워요! 핫팩 챙기셨나요? 🔥',
    '추운 날엔 도서관·학생회관 실내에서 포근하게!',
  ],
  'wind_cold': [ // 바람/쌀쌀/환절기 멘트
    '강내면에 쌀쌀한 바람이 불어요. 겉옷 챙기세요! 🧣',
    '캠퍼스 바람이 매서워요! 옷 따뜻하게 여미세요',
    '일교차가 큰 날씨예요. 외투 꼭 챙기기!',
    '감기 조심하세요! 따뜻한 차 한 잔 어때요? 🍵',
    '바람이 많이 부네요. 날아가지 않게 조심! 💨',
    '환절기 건강 유의하시고 따뜻한 하루 보내요',
  ],
  'hot': [ // 무더위/폭염 멘트
    '오늘 날씨가 꽤 더워요. 시원한 물 자주 마셔요! 🧊',
    '햇빛이 쨍쨍 뜨거워요! 도서관 에어컨 힐링 추천 📖',
    '더위에 지치지 않게 시원한 음료로 당 충전해요 🥤',
    '폭염 주의! 실내에서 시원하고 쾌적하게 보내요',
  ],
  'sunny': [ // 맑고 화창한 날 멘트
    '햇살이 눈부신 맑은 날! 미호천 산책 어때요? ☀️',
    '파란 하늘이 예쁜 날, 청람광장에서 광합성해요 🌱',
    '날씨가 정말 쾌청해요! 창밖 풍경 한번 바라보세요',
    '선선한 바람과 따뜻한 햇살, 기분 좋은 하루 되세요',
    '오늘따라 교원대 캠퍼스가 더 푸르고 예뻐요 ✨',
  ],
  'cloudy_fog': [ // 흐림/안개 멘트
    '구름 가득 흐린 날이지만, 마음만은 맑음! ☁️',
    '새벽 안개가 자욱해요. 등굣길 발걸음 조심해요',
    '흐린 날엔 차분한 음악과 함께 집중해봐요 🎧',
  ],
};

/// 강내면 실시간 날씨 데이터 모델
class KnueWeatherInfo {
  final double temp;
  final int weatherCode;
  final double windSpeed;

  const KnueWeatherInfo({
    required this.temp,
    required this.weatherCode,
    required this.windSpeed,
  });

  bool get isRaining =>
      (weatherCode >= 51 && weatherCode <= 67) ||
      (weatherCode >= 80 && weatherCode <= 82) ||
      (weatherCode >= 95 && weatherCode <= 99);

  bool get isSnowing =>
      (weatherCode >= 71 && weatherCode <= 77) ||
      (weatherCode >= 85 && weatherCode <= 86);

  bool get isColdOrWindy => temp <= 8.0 || windSpeed >= 18.0;

  bool get isHot => temp >= 28.0;

  bool get isFoggyOrCloudy =>
      weatherCode == 45 || weatherCode == 48 || weatherCode == 3;

  bool get isSunny => weatherCode == 0 || weatherCode == 1;

  String get emoji {
    if (isSnowing) return '❄️';
    if (isRaining) return weatherCode >= 95 ? '⛈️' : '🌧️';
    if (weatherCode == 45 || weatherCode == 48) return '🌫️';
    if (weatherCode == 0) return '☀️';
    if (weatherCode <= 2) return '🌤️';
    if (weatherCode == 3) return '☁️';
    return '🌤️';
  }
}

/// 강내면(교원대) 실시간 날씨 데이터 가져오기 (Open-Meteo)
Future<KnueWeatherInfo?> fetchGangnaeWeather() async {
  try {
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast?latitude=36.6093&longitude=127.3585&current_weather=true&timezone=Asia%2FSeoul',
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 5));
    if (res.statusCode == 200) {
      final j = json.decode(res.body) as Map;
      final cw = j['current_weather'] as Map;
      return KnueWeatherInfo(
        temp: (cw['temperature'] as num).toDouble(),
        weatherCode: (cw['weathercode'] as num).toInt(),
        windSpeed: (cw['windspeed'] as num).toDouble(),
      );
    }
  } catch (_) {}
  return null;
}

/// [now]의 시간대, 요일, [weather] 날씨에 맞는 인사말 하나를 무작위로 고른다.
/// [random]을 주면 결과가 고정되므로 테스트에서 쓸 수 있다.
String pickGreeting(
  DateTime now, {
  KnueWeatherInfo? weather,
  Random? random,
}) {
  final rng = random ?? Random();
  final hour = now.hour;
  final weekday = now.weekday; // 1: 월, ..., 5: 금, 6: 토, 7: 일

  // 1. 강한 날씨 조건(비, 눈, 강풍, 한파 등)일 때 높은 확률로 날씨 멘트 직접 반환
  if (weather != null) {
    if (weather.isRaining) {
      final rains = kGreetings['rain'] ?? [];
      if (rains.isNotEmpty && rng.nextDouble() < 0.6) {
        return rains[rng.nextInt(rains.length)];
      }
    } else if (weather.isSnowing) {
      final snows = kGreetings['snow'] ?? [];
      if (snows.isNotEmpty && rng.nextDouble() < 0.6) {
        return snows[rng.nextInt(snows.length)];
      }
    } else if (weather.isColdOrWindy && hour >= 6 && hour <= 23) {
      final colds = kGreetings['wind_cold'] ?? [];
      if (colds.isNotEmpty && rng.nextDouble() < 0.45) {
        return colds[rng.nextInt(colds.length)];
      }
    } else if (weather.isHot && hour >= 11 && hour <= 18) {
      final hots = kGreetings['hot'] ?? [];
      if (hots.isNotEmpty && rng.nextDouble() < 0.45) {
        return hots[rng.nextInt(hots.length)];
      }
    }
  }

  final List<String> candidates = [];

  // 2. 시간대별 기본 멘트 풀 추가
  final String slot;
  if (hour < 5) {
    slot = 'dawn';
  } else if (hour < 11) {
    slot = 'morning';
  } else if (hour < 14) {
    slot = 'lunch';
  } else if (hour < 18) {
    slot = 'afternoon';
  } else if (hour < 22) {
    slot = 'evening';
  } else {
    slot = 'night';
  }
  candidates.addAll(kGreetings[slot] ?? []);

  // 3. 요일별 특별 멘트 풀 가중치 추가
  if (weekday == DateTime.monday && hour >= 6 && hour <= 18) {
    candidates.addAll(kGreetings['monday'] ?? []);
  } else if (weekday == DateTime.friday && hour >= 10 && hour <= 22) {
    candidates.addAll(kGreetings['friday'] ?? []);
  } else if ((weekday == DateTime.saturday || weekday == DateTime.sunday) &&
      hour >= 8 &&
      hour <= 22) {
    candidates.addAll(kGreetings['weekend'] ?? []);
  }

  // 4. 온화한 날씨(맑음, 흐림) 멘트 믹스
  if (weather != null && hour >= 7 && hour <= 19) {
    if (weather.isSunny) {
      candidates.addAll(kGreetings['sunny'] ?? []);
    } else if (weather.isFoggyOrCloudy) {
      candidates.addAll(kGreetings['cloudy_fog'] ?? []);
    }
  }

  return candidates[rng.nextInt(candidates.length)];
}

// [2] 유틸리티
bool isSameDate(DateTime dt1, DateTime dt2) =>
    dt1.year == dt2.year && dt1.month == dt2.month && dt1.day == dt2.day;

List<String> asStringList(dynamic data) {
  if (data is List) return data.map((e) => e.toString()).toList();
  return [];
}

/// 식당(source)별 실제 운영 시간. 사도교육원 식당(a)은 [MealType.timeRange]와 같지만,
/// 교직원 식당(b)은 시간이 다르고 조식을 운영하지 않는다 — _isRatingAllowed/_getTimeRangeText
/// (meal_screen.dart)와 같은 값으로 맞춰뒀다.
String? mealTimeRangeFor(MealType type, MealSource source) {
  if (source == MealSource.a) return type.timeRange;
  switch (type) {
    case MealType.breakfast:
      return null; // 교직원 식당 조식 미운영
    case MealType.lunch:
      return "11:00 ~ 14:00";
    case MealType.dinner:
      return "17:00 ~ 18:30";
  }
}

/// 지금이 [type](이 식당 기준) 운영 종료 10분 전부터 종료 시각까지인지.
/// 순수 함수 — 테스트 대상. meal_reminder.dart의 "식사하셨나요?" 팝업이
/// 언제 뜰지 판단하는 데 쓴다.
bool isMealEndingSoon(MealType type, MealSource source, DateTime now) {
  final range = mealTimeRangeFor(type, source);
  if (range == null) return false; // 이 식당은 이 끼니를 운영 안 함
  final endStr = range.split("~")[1].trim().split(":");
  final end = DateTime(
    now.year,
    now.month,
    now.day,
    int.parse(endStr[0]),
    int.parse(endStr[1]),
  );
  final tenMinBefore = end.subtract(const Duration(minutes: 10));
  return !now.isBefore(tenMinBefore) && !now.isAfter(end);
}

/// 지금 곧 끝나가는 끼니 하나(있으면). 아침/점심/저녁 사이 간격이 넉넉해
/// 두 끼가 동시에 "곧 끝남" 구간에 걸칠 일은 없다.
MealType? mealEndingSoonNow(MealSource source, DateTime now) {
  for (final type in MealType.values) {
    if (isMealEndingSoon(type, source, now)) return type;
  }
  return null;
}

ServeStatus statusFor(
  MealType type,
  DateTime now,
  DateTime targetDate, {
  MealSource source = MealSource.a,
}) {
  if (!isSameDate(now, targetDate)) return ServeStatus.notToday;
  final range = mealTimeRangeFor(type, source);
  if (range == null) return ServeStatus.closed;
  final times = range.split("~");
  final startStr = times[0].trim().split(":");
  final endStr = times[1].trim().split(":");
  final start = DateTime(
    now.year,
    now.month,
    now.day,
    int.parse(startStr[0]),
    int.parse(startStr[1]),
  );
  final end = DateTime(
    now.year,
    now.month,
    now.day,
    int.parse(endStr[0]),
    int.parse(endStr[1]),
  );

  if (now.isBefore(start)) return ServeStatus.waiting;
  if (now.isAfter(end)) return ServeStatus.closed;
  return ServeStatus.open;
}

Future<void> shareMenu(
  BuildContext context,
  DateTime date,
  MealSource source,
  MealType type,
  List<String>? items, {
  String? calories,
}) async {
  if (items == null || items.isEmpty) return;

  final sourceLabel = source.shortLabel;
  final dateStr = "${date.month}/${date.day}";
  final menuList = items.map((e) => "· $e").join("\n");

  String shareText = "[$dateStr ${type.label} | $sourceLabel]\n$menuList";

  if (calories != null && calories.isNotEmpty) {
    shareText += "\n\n⚡ 예상: $calories";
  }

  await SharePlus.instance.share(ShareParams(text: shareText.trim()));
}

void showToast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg, textAlign: TextAlign.center),
      duration: const Duration(seconds: 1),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      backgroundColor: Colors.grey.withOpacity(0.9),
    ),
  );
}

// [3] API 및 위젯 로직
DateTime getWidgetTargetDate(MealSource source) {
  final now = DateTime.now();
  final hour = now.hour;
  if (source == MealSource.a && hour >= 19) {
    return now.add(const Duration(days: 1));
  } else if (source == MealSource.b && hour >= 18) {
    return now.add(const Duration(days: 1));
  }
  return now;
}

/// KNUE 식당 HTML 스크래퍼
/// 주간 캘린더 테이블에서 요청된 날짜의 조식/중식/석식 메뉴를 추출
/// 식단 로컬 캐시. 공지·동아리와 같은 "캐시 먼저, 갱신은 뒤에서" 방식.
///
/// 예전에는 매번 Firestore(최대 3초) → HTML 스크래핑 순서로 네트워크를 두 번
/// 타서, 홈 화면이 7초 가까이 스피너만 보여줬다. 이제 두 번째 실행부터는
/// 저장해둔 값으로 즉시 그리고 갱신은 뒤에서 한다.
class MealCache {
  /// 백그라운드 갱신이 끝나면 값이 바뀐다. 화면은 이걸 구독해 다시 그린다.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static String _key(DateTime date, MealSource source) =>
      'mealCache_${date.year}-${date.month}-${date.day}_${source.name}';

  static Future<Map<String, dynamic>?> load(
      DateTime date, MealSource source) async {
    // 지난 식단은 바뀌지 않으므로 넉넉히 잡는다. 오래된 값이라도
    // 빈 화면보다는 낫고, 어차피 뒤에서 갱신된다.
    final raw = await JsonCache.load(_key(date, source),
        maxAge: const Duration(days: 7));
    return raw is Map<String, dynamic> ? raw : null;
  }

  static Future<void> save(
      DateTime date, MealSource source, Map<String, dynamic> data) async {
    // 내용이 그대로면 revision을 올리지 않는다 — 올리면 화면이 다시 로드하고,
    // 그게 또 갱신을 부르는 무한 루프가 된다.
    if (await JsonCache.save(_key(date, source), data)) revision.value++;
  }
}

Future<dynamic> fetchMealApi(
  DateTime date,
  MealSource source, {
  bool forceRefresh = false,
}) async {
  if (!forceRefresh) {
    final cached = await MealCache.load(date, source);
    if (cached != null) {
      // 캐시를 즉시 돌려주고 갱신은 await 없이 뒤에서 — 화면이 안 기다린다.
      // throttle이 없으면 갱신→재로드→갱신으로 계속 네트워크를 두드린다.
      RefreshThrottle.deferred(
        MealCache._key(date, source),
        () => _fetchMealFromNetwork(date, source),
      );
      return cached;
    }
  }
  return _fetchMealFromNetwork(date, source);
}

Future<dynamic> _fetchMealFromNetwork(DateTime date, MealSource source) async {
  final monday = date.subtract(Duration(days: date.weekday - 1));
  final dateStr =
      "${monday.year}${monday.month.toString().padLeft(2, '0')}${monday.day.toString().padLeft(2, '0')}";

  final url = source == MealSource.a
      ? 'https://www.knue.ac.kr/www/selectDietInfoWebList.do?key=1959&siteSe=one&searchStdde=$dateStr'
      : 'https://www.knue.ac.kr/www/selectDietInfoWebList.do?key=1960&siteSe=cafe&searchStdde=$dateStr';

  try {
    // 1. 파이어베이스에서 먼저 확인.
    //    로컬 캐시가 앞단에 생겨서 여기까지 오는 건 "처음 보는 날짜"뿐이다.
    //    실패(권한 오류 등) 시 오래 매달리지 않도록 1.5초로 줄였다.
    //    규칙 미배포 등으로 이미 실패한 적이 있으면 아예 건너뛴다.
    final cachedMeal = FirestoreHealth.isAvailable
        ? await FirebaseSyncService.getMealFromFirestore(date, source)
            .timeout(const Duration(milliseconds: 1500), onTimeout: () {
            FirestoreHealth.reportFailure();
            return null;
          })
        : null;

    if (cachedMeal != null) {
      FirestoreHealth.reportSuccess();
      // Firestore 문서에는 lastUpdated(Timestamp)처럼 JSON으로 못 바꾸는 값이
      // 섞여 있다. 통째로 캐시에 넣으면 jsonEncode가 터지므로 메뉴만 남긴다.
      MealCache.save(date, source, {'meals': cachedMeal['meals']});
      if (DateUtils.isSameDay(date, getWidgetTargetDate(source))) {
        // 위젯 업데이트는 비동기로 진행하고 데이터를 즉시 반환
        _updateWidgetDataInternal(cachedMeal, source, date);
      }
      return cachedMeal;
    }

    // 2. 직접 스크래핑 시도
    final response = await http
        .get(
          Uri.parse(url),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36',
            'Accept': 'text/html,*/*',
          },
        )
        .timeout(const Duration(seconds: 20)); // 스크래핑은 조금 더 여유를 줌 (20초)

    if (response.statusCode == 200) {
      final html = utf8.decode(response.bodyBytes, allowMalformed: true);
      // 교직원 식당(b)의 출처가 pot.knue.ac.kr(mon_list/tbl_4 구조)에서
      // 학교 자체 페이지(key=1960&siteSe=cafe)로 바뀌었는데, 이 페이지는
      // 사도교육원식당(a)과 똑같은 p-calendar-list 구조를 쓴다 — 그래서
      // parseCafeHtml이 아무것도 못 찾고 항상 빈 값만 냈다(2026-09-16 확인).
      final result = parseSadoHtml(html, date);

      // 3. 크롤링 결과 저장 (사용자를 기다리게 하지 않음)
      final meals = result['meals'] as Map<String, dynamic>;
      bool hasData = meals.values.any((list) => (list as List).isNotEmpty);

      // 공용 Firestore에는 실제 메뉴가 있을 때만 올린다(빈 값으로 덮어쓰지 않게).
      if (hasData) {
        FirebaseSyncService.saveMealToFirestore(date, source, result); // await 없이
      }
      // 로컬 캐시는 결과가 비었더라도 저장한다. "이 날은 급식이 없다"도 정답이고,
      // 캐시하지 않으면 방학 내내 매 실행마다 7초짜리 스크래핑을 반복하게 된다.
      MealCache.save(date, source, result);

      if (DateUtils.isSameDay(date, getWidgetTargetDate(source))) {
        _updateWidgetDataInternal(result, source, date);
      }
      return result;
    }
  } catch (e) {
    debugPrint('fetchMealApi error: $e');
  }
  return _emptyMeals();
}

Map<String, dynamic> _emptyMeals() => {
  'meals': {'breakfast': <String>[], 'lunch': <String>[], 'dinner': <String>[]},
};

/// \uc0ac\ub3c4\uad50\uc721\uc6d0 \uc2dd\ub2f9 HTML \ud30c\uc11c
@visibleForTesting
Map<String, dynamic> parseSadoHtml(String html, DateTime date) {
  final doc = htmlParser.parse(html);
  final table = doc.querySelector('table.p-calendar-list');
  if (table == null) return _emptyMeals();

  // \ud5e4\ub354\uc5d0\uc11c \ub0a0\uc9dc \ub9e4\ub9e4: th[data-day=N] \u2192 \uc624\ub298\uc5d0 \uc77c\uce58\ud558\ub294 \uc778\ub371\uc2a4 \ucc3e\uae30
  int? targetDay;
  for (final th in table.querySelectorAll('thead th[data-day]')) {
    final dayIdx = th.attributes['data-day'];
    final spanText = th.querySelector('span')?.text.trim() ?? '';
    final datePart = spanText.split('\n').first.trim(); // \"MM/DD\"
    final parts = datePart.split('/');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]);
      final d = int.tryParse(parts[1]);
      if (m == date.month && d == date.day) {
        targetDay = int.tryParse(dayIdx ?? '');
        break;
      }
    }
  }
  if (targetDay == null) return _emptyMeals();

  final rows = table.querySelectorAll('tbody tr');
  final mealKeys = ['breakfast', 'lunch', 'dinner'];
  final meals = <String, List<String>>{
    'breakfast': [],
    'lunch': [],
    'dinner': [],
  };

  for (int i = 0; i < rows.length && i < mealKeys.length; i++) {
    final td = rows[i].querySelector('td[data-day="$targetDay"]');
    if (td == null) continue;
    for (final li in td.querySelectorAll('ul.menu_list li')) {
      final items = li.text
          .split(RegExp(r'[\n\r]'))
          .map((s) => s.trim().replaceAll('&amp;', '&'))
          .where((s) => s.isNotEmpty && !_isCafeNoiseLine(s))
          .toList();
      meals[mealKeys[i]]!.addAll(items);
    }
  }
  return {'meals': meals};
}

/// 끼니 이름 머리글. 표에서는 th에 들어가지만, 과거 마크업에서는 셀 본문에
/// 섞여 들어온 적이 있어 방어적으로 걸러낸다.
const _kCafeMealHeadings = {'조식', '중식', '석식', '아침', '점심', '저녁'};

/// 메뉴가 아닌 줄(끼니 머리글, 대괄호 주석)인지 판정한다.
///
/// 이전에는 `startsWith('석')`으로 "석식"을, `startsWith('삼일절')`로 휴무
/// 안내를 걸러냈다. 접두사 매칭이라 "석박지" 같은 실제 메뉴까지 함께 사라졌다.
/// 부분 문자열 매칭도 안 되는데, 실제 메뉴에 "셀프계란후라이(미운영-비빔밥에
/// 들어가있음)"처럼 안내 문구가 이름 안에 박혀 나오기 때문이다. 그래서 머리글은
/// 정확히 일치할 때만 제외하고, 나머지는 대괄호 주석만 거른다 — 메뉴를 잘못
/// 지우는 것보다 안내 한 줄이 섞이는 편이 낫다.
bool _isCafeNoiseLine(String s) {
  if (_kCafeMealHeadings.contains(s)) return true;
  if (s.startsWith('[')) return true; // "[알레르기 정보 …]" 같은 주석
  return false;
}

@visibleForTesting
Map<String, dynamic> parseCafeHtml(String html, DateTime date) {
  final doc = htmlParser.parse(html);

  String dayId;
  switch (date.weekday) {
    case 1:
      dayId = 'mon_list';
      break;
    case 2:
      dayId = 'tue_list';
      break;
    case 3:
      dayId = 'wed_list';
      break;
    case 4:
      dayId = 'thu_list';
      break;
    case 5:
      dayId = 'fri_list';
      break;
    case 6:
      dayId = 'sat_list';
      break;
    case 7:
      dayId = 'sun_list';
      break;
    default:
      dayId = 'mon_list';
  }

  // pot.knue.ac.kr은 "이번 주" 한 주치만 싣는다. 요일 div만 보고 고르면
  // 다른 주의 날짜를 물어도 이번 주 같은 요일 메뉴를 그대로 돌려준다.
  // 그렇게 8/31에 저장된 "9/16 교직원 식당"이 실은 9/2 메뉴였고, 공용
  // Firestore에 굳어 2주 내내 틀린 메뉴가 나갔다.
  final now = DateTime.now();
  final monday = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - 1));
  final target = DateTime(date.year, date.month, date.day);
  if (target.isBefore(monday) ||
      target.isAfter(monday.add(const Duration(days: 6)))) {
    return _emptyMeals();
  }

  final contentDiv = doc.querySelector('#$dayId');
  if (contentDiv == null) return _emptyMeals();

  // 페이지는 "( 2026년 09월 16일 )"처럼 날짜를 직접 밝힌다. 그것과 다르면
  // 틀린 주를 보고 있다는 뜻이니 아무것도 주지 않는다 — 틀린 메뉴보다는
  // 비어 있는 편이 낫다.
  final printed = RegExp(r'(\d{4})년\s*(\d{1,2})월\s*(\d{1,2})일')
      .firstMatch(contentDiv.text);
  if (printed != null &&
      (int.parse(printed.group(1)!) != date.year ||
          int.parse(printed.group(2)!) != date.month ||
          int.parse(printed.group(3)!) != date.day)) {
    return _emptyMeals();
  }

  final tables = contentDiv.querySelectorAll('table.tbl_4');
  if (tables.isEmpty) return _emptyMeals();

  final table = tables.first;
  final rows = table.querySelectorAll('tbody tr');
  final mealKeys = ['breakfast', 'lunch', 'dinner'];
  final meals = <String, List<String>>{
    'breakfast': [],
    'lunch': [],
    'dinner': [],
  };

  for (int i = 0; i < rows.length && i < mealKeys.length; i++) {
    final tds = rows[i].querySelectorAll('td');
    if (tds.isEmpty) continue;
    final td = tds.first;
    final text = td.text.trim();
    if (text.isEmpty) continue;
    final items = text
        .split(RegExp(r'[\n\r]'))
        .map((s) => s.trim().replaceAll('&amp;', '&'))
        .where((s) => s.isNotEmpty && !_isCafeNoiseLine(s))
        .toList();
    meals[mealKeys[i]]!.addAll(items);
  }
  return {'meals': meals};
}

/// iOS 홈 위젯의 WidgetKit kind 문자열.
///
/// ios/MealWidget/MealWidget.swift의 `let kind`와 **반드시 같아야 한다**.
/// 다르면 앱이 데이터를 저장해도 위젯이 다시 그려지지 않아, 예전 메뉴가
/// 그대로 남아 있는 것처럼 보인다(조용히 틀리는 종류의 버그).
const String kIosMealWidgetKind = 'MealWidget';

// [핵심] 위젯 데이터 가공 및 저장
Future<void> _updateWidgetDataInternal(
  Map<String, dynamic> data,
  MealSource source,
  DateTime requestedDate,
) async {
  try {
    final now = DateTime.now();
    final hour = now.hour;
    final isTomorrow =
        requestedDate.day != now.day || requestedDate.month != now.month;

    String timeText = "";
    String mealKey = "";
    String sourceName = source.label;

    // 시간대 로직 (요구사항 반영)
    if (source == MealSource.a) {
      // 기숙사
      if (hour < 9) {
        timeText = "오늘 아침";
        mealKey = "breakfast";
      } else if (hour < 14) {
        timeText = "오늘 점심";
        mealKey = "lunch";
      } else if (hour < 19) {
        timeText = "오늘 저녁";
        mealKey = "dinner";
      } else {
        timeText = "내일 아침";
        mealKey = "breakfast";
      }
    } else {
      // 학생회관
      if (hour < 14) {
        timeText = "오늘 점심";
        mealKey = "lunch";
      } else if (hour < 18) {
        timeText = "오늘 저녁";
        mealKey = "dinner";
      } else {
        timeText = "내일 점심";
        mealKey = "lunch";
      }
    }

    // 데이터 파싱
    final meals = data['meals'] ?? {};
    dynamic targetList;

    // 키 매핑 (API 응답 유연성 확보)
    if (mealKey == 'breakfast') {
      targetList = meals['조식'] ?? meals['아침'] ?? meals['breakfast'];
    } else if (mealKey == 'lunch') {
      targetList = meals['중식'] ?? meals['점심'] ?? meals['lunch'];
    } else {
      targetList = meals['석식'] ?? meals['저녁'] ?? meals['dinner'];
    }

    List<String> menuItems = asStringList(targetList ?? []);
    String menuText = menuItems.isNotEmpty
        ? menuItems.map((e) => "· ${e.trim()}").join("\n")
        : "등록된 메뉴가 없습니다.";

    // 학생회관의 경우, "내일"이 주말(토/일)이거나 공휴일이면 예외 문구 처리
    if (source == MealSource.b && isTomorrow) {
      final isWeekend =
          requestedDate.weekday == DateTime.saturday ||
          requestedDate.weekday == DateTime.sunday;
      // Note: 간단히 주말만 체크. 공휴일을 완벽히 체크하려면 법정공휴일 API가 필요하지만, 데이터(menuItems)가 없으면 엎어버릴 수 있음
      if (isWeekend || menuItems.isEmpty) {
        menuText = "내일은 식당을 운영하지 않아요 🥺";
      }
    }

    // 데이터 저장
    await HomeWidget.saveWidgetData<String>('widget_title', sourceName);
    await HomeWidget.saveWidgetData<String>('widget_time', timeText);
    await HomeWidget.saveWidgetData<String>('widget_menu', menuText);

    // 설정 저장
    await HomeWidget.saveWidgetData<int>('themeMode', widgetTheme.value.index);
    await HomeWidget.saveWidgetData<String>(
      'transparency',
      widgetTransparency.value.toString(),
    );

    // [수정] 위젯 업데이트 시 전체 패키지명 사용 (가장 확실한 방법)
    // iOSName은 WidgetKit의 kind 문자열 — ios/MealWidget/MealWidget.swift의
    // `let kind`와 같아야 앱이 갱신할 때 위젯이 다시 그려진다.
    await HomeWidget.updateWidget(
      name: 'MealWidgetProvider',
      androidName: 'MealWidgetProvider',
      qualifiedAndroidName: 'com.knue.knuemate.MealWidgetProvider',
      iOSName: kIosMealWidgetKind,
    );

    debugPrint("위젯 업데이트 완료: $sourceName / $timeText");
  } catch (e) {
    debugPrint("위젯 업데이트 실패: $e");
  }
}

// [4] 설정 저장 및 강제 업데이트
Future<void> saveWidgetSettingsAndUpdate(
  double trans,
  ThemeMode theme,
  MealSource source,
  BuildContext context,
) async {
  widgetTransparency.value = trans;
  widgetTheme.value = theme;
  widgetSource.value = source;

  await PreferencesService.saveWidgetSettings(trans, theme, source);

  try {
    // 로딩 상태 먼저 표시
    await HomeWidget.saveWidgetData<String>(
      'widget_menu',
      "데이터를 불러오는 중...\n(최대 30초 소요)",
    );
    await HomeWidget.updateWidget(
      name: 'MealWidgetProvider',
      androidName: 'MealWidgetProvider',
      iOSName: kIosMealWidgetKind,
    );

    // 실제 데이터 호출
    final targetDate = getWidgetTargetDate(source);
    await fetchMealApi(targetDate, source);

    if (context.mounted) showToast(context, "위젯 설정이 적용되었습니다.");
  } catch (e) {
    if (context.mounted) showToast(context, "데이터 갱신 실패");
  }
}

Future<void> forceUpdateWidgetWithCurrentSettings() async {
  await PreferencesService.loadSettings();
  final targetDate = getWidgetTargetDate(defaultSourceNotifier.value);
  await fetchMealApi(targetDate, defaultSourceNotifier.value);
}

Future<void> testBasicWidgetFunction() async {
  // 테스트용 함수
  await HomeWidget.saveWidgetData<String>('widget_title', '테스트 식당');
  await HomeWidget.saveWidgetData<String>('widget_time', '테스트 시간');
  await HomeWidget.saveWidgetData<String>(
    'widget_menu',
    '· 쌀밥\n· 김치찌개\n· 계란말이\n· 깍두기',
  );
  await HomeWidget.updateWidget(
    name: 'MealWidgetProvider',
    androidName: 'MealWidgetProvider',
    iOSName: kIosMealWidgetKind,
  );
}

// [5] 설정 저장 서비스
class PreferencesService {
  static const String keyThemeColor = 'theme_color';
  static const String keyRainbowMode = 'rainbow_mode';
  static const String keyThemeMode = 'theme_mode';
  static const String keyMealSource = 'meal_source';
  static const String keyWidgetTrans = 'widget_trans';
  static const String keyWidgetTheme = 'widget_theme';
  static const String keyWidgetSource = 'widget_source';
  static const String keyTabOrder = 'tab_order_v2'; // v1 → v2
  static const String keyNoticeKeywords = 'notice_keywords';
  static const String keyFavBoards = 'fav_boards';
  static const String keyNoticeAlarm = 'notice_alarm_on';
  static const String keyNoticeAlertMode = 'notice_alert_mode';
  static const String keyNoticeAlertHours = 'notice_alert_hours';
  static const String keyDdayItems = 'dday_items';
  static const String keyPersonalEvents = 'personal_events';

  static final ValueNotifier<List<AppTab>> tabOrder = ValueNotifier([
    AppTab.home,
    AppTab.meal,
    AppTab.bus,
    AppTab.map,
    AppTab.settings,
  ]);

  static final ValueNotifier<List<String>> noticeKeywords = ValueNotifier([
    '장학',
    '수강',
    '졸업',
  ]);
  static final ValueNotifier<List<String>> favoriteBoards = ValueNotifier([
    '대학소식',
    '학사공지',
  ]);
  static final ValueNotifier<bool> noticeAlarmOn = ValueNotifier(true);
  static final ValueNotifier<NoticeAlertMode> noticeAlertMode =
      ValueNotifier(NoticeAlertMode.instant);
  /// scheduled 모드일 때 알림을 모아 보낼 시각(0~23시, 정렬됨).
  static final ValueNotifier<List<int>> noticeAlertHours =
      ValueNotifier([9, 18]);
  static final ValueNotifier<List<DdayItem>> ddayItems = ValueNotifier([]);
  static final ValueNotifier<List<PersonalEvent>> personalEvents =
      ValueNotifier([]);

  /// 하단 탭에 배치 가능한 탭 (run은 캠퍼스런 화면으로만 진입, 하단 탭엔 없음)
  static const List<AppTab> navigableTabs = [
    AppTab.home,
    AppTab.meal,
    AppTab.bus,
    AppTab.map,
    AppTab.settings,
  ];

  /// 저장된 탭 이름 목록 → 5탭 구조로 정규화. 순수 함수(테스트 대상).
  /// home은 완전히 사라진 경우에만 맨 앞에 재삽입되고, 나머지 탭 순서(설정 포함)는
  /// 사용자가 자유롭게 정할 수 있다 — 강제로 고정되는 위치는 없다.
  static List<AppTab> migrateTabOrder(List<String> savedNames) {
    final mapped = savedNames
        .map((name) {
          try {
            return AppTab.values.firstWhere((t) => t.name == name);
          } catch (_) {
            return null;
          }
        })
        .whereType<AppTab>()
        .where((t) => navigableTabs.contains(t))
        .toList();
    final result = <AppTab>[];
    for (final t in mapped) {
      if (!result.contains(t)) result.add(t);
    }
    if (!result.contains(AppTab.home)) result.insert(0, AppTab.home);
    for (final t in navigableTabs) {
      if (!result.contains(t)) result.add(t);
    }
    return result;
  }

  static Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final int? colorValue = prefs.getInt(keyThemeColor);
    if (colorValue != null) themeColor.value = Color(colorValue);
    // 무지개 모드는 저장된 색을 덮어쓰지 않고 런타임 값만 바꾼다 —
    // 꺼면 사용자가 고른 색으로 그대로 돌아온다.
    rainbowModeNotifier.value = prefs.getBool(keyRainbowMode) ?? false;
    if (rainbowModeNotifier.value) {
      themeColor.value = colorOfDay(DateTime.now());
    }
    final int? modeIndex = prefs.getInt(keyThemeMode);
    if (modeIndex != null)
      themeModeNotifier.value = ThemeMode.values[modeIndex];
    final int? sourceIndex = prefs.getInt(keyMealSource);
    if (sourceIndex != null)
      defaultSourceNotifier.value = MealSource.values[sourceIndex];

    widgetTransparency.value = prefs.getDouble(keyWidgetTrans) ?? 0.0;
    final int? wTheme = prefs.getInt(keyWidgetTheme);
    if (wTheme != null) widgetTheme.value = ThemeMode.values[wTheme];
    final int? wSource = prefs.getInt(keyWidgetSource);
    if (wSource != null) widgetSource.value = MealSource.values[wSource];

    final savedV2 = prefs.getStringList(keyTabOrder);
    final savedV1 = prefs.getStringList('tab_order_v1');
    if (savedV2 != null) {
      tabOrder.value = migrateTabOrder(savedV2);
    } else if (savedV1 != null) {
      tabOrder.value = migrateTabOrder(savedV1);
      await prefs.setStringList(
        keyTabOrder,
        tabOrder.value.map((t) => t.name).toList(),
      );
    }
    noticeKeywords.value =
        prefs.getStringList(keyNoticeKeywords) ?? ['장학', '수강', '졸업'];
    favoriteBoards.value =
        prefs.getStringList(keyFavBoards) ?? ['대학소식', '학사공지'];
    noticeAlarmOn.value = prefs.getBool(keyNoticeAlarm) ?? true;
    final savedMode = prefs.getString(keyNoticeAlertMode);
    noticeAlertMode.value = savedMode == NoticeAlertMode.scheduled.name
        ? NoticeAlertMode.scheduled
        : NoticeAlertMode.instant;
    final savedHours = prefs.getStringList(keyNoticeAlertHours);
    if (savedHours != null && savedHours.isNotEmpty) {
      final parsedHours = savedHours
          .map((s) => int.tryParse(s))
          .whereType<int>()
          .where((h) => h >= 0 && h <= 23)
          .toSet()
          .toList()
        ..sort();
      // 저장된 원본 목록은 비어있지 않았지만(isNotEmpty 통과) 파싱 후
      // 전부 걸러질 수 있다(손상된 값 등) — 그 경우 기본값으로 되돌린다.
      // 안 그러면 scheduled 모드인데 지정 시각이 0개가 되어 isDigestDue가
      // 항상 false를 반환해, 알림이 영영 안 오는데 원인이 안 보이는 상태가 된다.
      noticeAlertHours.value = parsedHours.isNotEmpty ? parsedHours : [9, 18];
    }

    // 별도 try/catch — 한쪽 JSON이 손상되어도 다른 쪽까지 조용히 날아가지 않도록.
    try {
      final ddayRaw = prefs.getString(keyDdayItems);
      if (ddayRaw != null) {
        ddayItems.value = (jsonDecode(ddayRaw) as List)
            .map((e) => DdayItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('dday load error: $e');
    }
    try {
      final peRaw = prefs.getString(keyPersonalEvents);
      if (peRaw != null) {
        personalEvents.value = (jsonDecode(peRaw) as List)
            .map((e) => PersonalEvent.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('personal event load error: $e');
    }
  }

  static Future<void> saveTabOrder(List<AppTab> order) async {
    final prefs = await SharedPreferences.getInstance();
    tabOrder.value = order;
    await prefs.setStringList(keyTabOrder, order.map((e) => e.name).toList());
  }

  static Future<void> saveNoticeKeywords(List<String> keywords) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(keyNoticeKeywords, keywords);
    noticeKeywords.value = List.from(keywords);
  }

  static Future<void> saveFavoriteBoards(List<String> boards) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(keyFavBoards, boards);
    favoriteBoards.value = List.from(boards);
  }

  static Future<void> saveNoticeAlarm(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyNoticeAlarm, on);
    noticeAlarmOn.value = on;
  }

  static Future<void> saveNoticeAlertMode(NoticeAlertMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyNoticeAlertMode, mode.name);
    noticeAlertMode.value = mode;
  }

  static Future<void> saveNoticeAlertHours(List<int> hours) async {
    final sorted = hours.toSet().toList()..sort();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      keyNoticeAlertHours,
      sorted.map((h) => h.toString()).toList(),
    );
    noticeAlertHours.value = sorted;
  }

  static Future<void> saveDdayItems(List<DdayItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      keyDdayItems,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
    ddayItems.value = List.from(items);
  }

  static Future<void> savePersonalEvents(List<PersonalEvent> events) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      keyPersonalEvents,
      jsonEncode(events.map((e) => e.toJson()).toList()),
    );
    personalEvents.value = List.from(events);
  }

  static Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyThemeMode, mode.index);
  }

  static Future<void> saveThemeColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyThemeColor, color.value);
  }

  /// 무지개 모드 토글. 켜면 오늘의 색을 즉시 적용하고, 끄면 저장해둔
  /// 사용자 선택 색으로 되돌린다.
  static Future<void> setRainbowMode(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyRainbowMode, on);
    rainbowModeNotifier.value = on;
    if (on) {
      themeColor.value = colorOfDay(DateTime.now());
    } else {
      final saved = prefs.getInt(keyThemeColor);
      themeColor.value = saved != null ? Color(saved) : kColorPalette.first;
    }
  }

  /// 날짜가 바뀌었는지 확인해 오늘의 색으로 갱신한다.
  /// 앱을 켜 둔 채로 자정을 넘긴 경우를 위해 재개(resume) 시점에 부른다.
  static void refreshRainbowColorIfNeeded() {
    if (!rainbowModeNotifier.value) return;
    final today = colorOfDay(DateTime.now());
    if (themeColor.value != today) themeColor.value = today;
  }

  static Future<void> saveMealSource(MealSource source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyMealSource, source.index);
    // 홈/월간 탭 등 defaultSourceNotifier를 구독하는 화면이 재시작 없이 바로 반영되게.
    defaultSourceNotifier.value = source;
  }

  static Future<void> saveWidgetSettings(
    double trans,
    ThemeMode theme,
    MealSource source,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(keyWidgetTrans, trans);
    await prefs.setInt(keyWidgetTheme, theme.index);
    await prefs.setInt(keyWidgetSource, source.index);
    widgetTransparency.value = trans;
    widgetTheme.value = theme;
    widgetSource.value = source;
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    themeColor.value = const Color(0xFF2563EB);
    themeModeNotifier.value = ThemeMode.system;
    widgetTransparency.value = 0.0;
    widgetTheme.value = ThemeMode.system;
    widgetSource.value = MealSource.a;
    // prefs.clear()는 저장소만 지운다 — 이미 화면들이 구독 중인 나머지 알림자들도
    // 기본값으로 되돌려야 재시작 없이도 화면이 초기화 상태를 반영한다.
    defaultSourceNotifier.value = MealSource.a;
    tabOrder.value = [
      AppTab.home,
      AppTab.meal,
      AppTab.bus,
      AppTab.map,
      AppTab.settings,
    ];
    noticeKeywords.value = ['장학', '수강', '졸업'];
    favoriteBoards.value = ['대학소식', '학사공지'];
    noticeAlarmOn.value = true;
    noticeAlertMode.value = NoticeAlertMode.instant;
    noticeAlertHours.value = [9, 18];
    ddayItems.value = [];
    personalEvents.value = [];
  }
}

// [6] 알림 서비스 (변동 없음)
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    } catch (_) {}

    // flutter_local_notifications는 아이콘 이름을 drawable 타입으로만 찾는다
    // (res/drawable-*/ic_stat_notify.png). "@mipmap/..." 같은 XML 참조 문법이
    // 아니라 순수 리소스 이름만 받는다 — 접두사가 붙어 있으면 조회에 실패해
    // 기본(뭉개진) 아이콘으로 조용히 대체된다.
    const android = AndroidInitializationSettings('ic_stat_notify');
    // [수정] 초기화 시점에 자동으로 권한을 요청하지 않음.
    // 권한이 거부된 상태에서 requestAlert/Badge/SoundPermission: true(기본값)이면
    // initialize() 자체가 PlatformException을 던집니다.
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    try {
      await flutterLocalNotificationsPlugin.initialize(
        settings: const InitializationSettings(android: android, iOS: ios),
      );
    } on PlatformException catch (e) {
      debugPrint(
        "Native Notification Platform Error (Likely permission denied): $e",
      );
    } catch (e) {
      debugPrint("Local Notifications initialize error: $e");
    }
  }

  Future<void> requestPermissions() async {
    if (kIsWeb) return;
    try {
      if (Platform.isAndroid) {
        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      } else if (Platform.isIOS || Platform.isMacOS) {
        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (e) {
      debugPrint("Notification permission request error: $e");
    }
  }

  /// 권한을 요청하고 실제 허가 여부를 반환합니다.
  /// iOS는 requestPermissions()의 결과(bool?)를 직접 사용,
  /// Android는 예외 없이 완료되면 granted로 간주합니다.
  Future<bool> checkAndRequestPermission() async {
    if (kIsWeb) return false;
    try {
      if (Platform.isAndroid) {
        final result = await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
        return result ?? true; // null이면 이미 허용된 것으로 간주
      } else if (Platform.isIOS) {
        final result = await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
        return result ?? false;
      }
    } catch (e) {
      debugPrint("checkAndRequestPermission error: $e");
      return false;
    }
    return false;
  }

  Future<void> cancelAll() async {
    try {
      await flutterLocalNotificationsPlugin.cancelAll();
    } catch (e) {
      debugPrint("cancelAll error: $e");
    }
  }

  Future<void> cancelAlarm(int id) async {
    try {
      await flutterLocalNotificationsPlugin.cancel(id: id);
    } catch (e) {
      debugPrint("cancelAlarm error: $e");
    }
  }

  Future<void> scheduleAlarm({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    if (scheduledTime.isBefore(DateTime.now())) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }
    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(scheduledTime, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'meal_alarm_channel',
            '식단 알림',
            importance: Importance.max,
            icon: 'ic_stat_notify',
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      print("알림 예약 실패: $e");
    }
  }

  // FCM 포그라운드 수신용 즉시 알림 메서드
  Future<void> showNotification(int id, String title, String body) async {
    const android = AndroidNotificationDetails(
      'fcm_general_channel',
      '기본 알림',
      importance: Importance.max,
      priority: Priority.high,
      icon: 'ic_stat_notify',
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    try {
      await flutterLocalNotificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: android,
          iOS: ios,
        ),
      );
    } catch (e) {
      // 알림 권한이 없거나 플랫폼 제약으로 실패한 경우 — 앱 크래시 방지
      debugPrint("showNotification 실패 (권한 없음 또는 플랫폼 오류): $e");
    }
  }
}
