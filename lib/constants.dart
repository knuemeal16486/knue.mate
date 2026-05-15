import 'dart:async';
import 'dart:convert';
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

const List<Color> kColorPalette = [
  Color(0xFF2563EB),
  Color(0xFFEF5350),
  Color(0xFFEC407A),
  Color.fromARGB(255, 199, 122, 211),
  Color(0xFFAB47BC),
  Color(0xFF7E57C2),
  Color(0xFF5C6BC0),
  Color(0xFF039BE5),
  Color(0xFF00ACC1),
  Color(0xFF00897B),
  Color(0xFF43A047),
  Color(0xFF7CB342),
  Color(0xFFC0CA33),
  Color(0xFFFDD835),
  Color(0xFFFFB300),
  Color(0xFFFB8C00),
  Color(0xFFF4511E),
  Color(0xFF6D4C41),
  Color(0xFF757575),
  Color(0xFF000000),
];

enum MealSource { a, b }

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

enum AppTab {
  meal("식단", Icons.restaurant_menu_rounded, Colors.orange),
  bus("버스", Icons.directions_bus_rounded, Colors.blue),
  schedule("일정", Icons.calendar_month_rounded, Colors.teal),
  run("런", Icons.directions_run_rounded, Colors.green),
  map("지도", Icons.map_rounded, Colors.deepPurple),
  settings("설정", Icons.settings_rounded, Colors.grey);

  final String label;
  final IconData icon;
  final Color color;
  const AppTab(this.label, this.icon, this.color);
}

// [2] 유틸리티
bool isSameDate(DateTime dt1, DateTime dt2) =>
    dt1.year == dt2.year && dt1.month == dt2.month && dt1.day == dt2.day;

List<String> asStringList(dynamic data) {
  if (data is List) return data.map((e) => e.toString()).toList();
  return [];
}

ServeStatus statusFor(MealType type, DateTime now, DateTime targetDate) {
  if (!isSameDate(now, targetDate)) return ServeStatus.notToday;
  final times = type.timeRange.split("~");
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

  final sourceLabel = source == MealSource.a ? "기숙사" : "학관";
  final dateStr = "${date.month}/${date.day}";
  final menuList = items.map((e) => "· $e").join("\n");

  String shareText = "[$dateStr ${type.label} | $sourceLabel]\n$menuList";

  if (calories != null && calories.isNotEmpty) {
    shareText += "\n\n⚡ 예상: $calories";
  }

  await SharePlus.instance.share(ShareParams(text: shareText.trim()));
}

void showToast(BuildContext context, String msg, {bool isError = false}) {
  ScaffoldMessenger.of(context).clearSnackBars();
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final primary = Theme.of(context).primaryColor;
  final bgColor = isError
      ? Colors.red.shade700
      : isDark
          ? const Color(0xFF2C2C30)
          : const Color(0xFF1A1A2E);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isError)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.error_outline, color: Colors.white, size: 18),
            ),
          Flexible(
            child: Text(
              msg,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      duration: Duration(seconds: isError ? 2 : 1),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: bgColor,
      elevation: 4,
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
Future<dynamic> fetchMealApi(DateTime date, MealSource source) async {
  final monday = date.subtract(Duration(days: date.weekday - 1));
  final dateStr =
      "${monday.year}${monday.month.toString().padLeft(2, '0')}${monday.day.toString().padLeft(2, '0')}";

  final url = source == MealSource.a
      ? 'https://www.knue.ac.kr/www/selectDietInfoWebList.do?key=1959&siteSe=one&searchStdde=$dateStr'
      : 'https://pot.knue.ac.kr/enview/knue/mobileMenu.html#';

  try {
    // 1. 파이어베이스에서 먼저 확인 (타임아웃 단축 - 3초로 충분히 확인 가능)
    final cachedMeal = await FirebaseSyncService.getMealFromFirestore(
      date,
      source,
    ).timeout(const Duration(seconds: 3), onTimeout: () => null);

    if (cachedMeal != null) {
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
      final result = source == MealSource.a
          ? _parseSadoHtml(html, date)
          : _parseCafeHtml(html, date);

      // 3. 크롤링 결과 저장 (사용자를 기다리게 하지 않음)
      final meals = result['meals'] as Map<String, dynamic>;
      bool hasData = meals.values.any((list) => (list as List).isNotEmpty);

      if (hasData) {
        // await 없이 즉시 실행
        FirebaseSyncService.saveMealToFirestore(date, source, result);
      }

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
Map<String, dynamic> _parseSadoHtml(String html, DateTime date) {
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
          .where((s) => s.isNotEmpty)
          .toList();
      meals[mealKeys[i]]!.addAll(items);
    }
  }
  return {'meals': meals};
}

Map<String, dynamic> _parseCafeHtml(String html, DateTime date) {
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

  final contentDiv = doc.querySelector('#$dayId');
  if (contentDiv == null) return _emptyMeals();

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
        .where(
          (s) =>
              s.isNotEmpty &&
              !s.startsWith('[') &&
              !s.startsWith('삼일절') &&
              !s.startsWith('석'),
        )
        .toList();
    meals[mealKeys[i]]!.addAll(items);
  }
  return {'meals': meals};
}

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
    String sourceName = source == MealSource.a ? "기숙사 식당" : "학생회관 식당";

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
    await HomeWidget.updateWidget(
      name: 'MealWidgetProvider',
      androidName: 'MealWidgetProvider',
      qualifiedAndroidName: 'com.knue.knuemate.MealWidgetProvider',
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

Future<void> updateBusWidget({
  required String outgoingNext,
  required String incomingNext,
  String upcoming = '',
}) async {
  try {
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} 기준';

    await HomeWidget.saveWidgetData<String>('bus_outgoing_next', outgoingNext);
    await HomeWidget.saveWidgetData<String>('bus_incoming_next', incomingNext);
    await HomeWidget.saveWidgetData<String>('bus_upcoming', upcoming);
    await HomeWidget.saveWidgetData<String>('bus_updated_at', timeStr);
    await HomeWidget.saveWidgetData<int>('themeMode', widgetTheme.value.index);

    await HomeWidget.updateWidget(
      name: 'BusWidgetProvider',
      androidName: 'BusWidgetProvider',
      qualifiedAndroidName: 'com.knue.knuemate.BusWidgetProvider',
    );
    debugPrint('버스 위젯 업데이트 완료');
  } catch (e) {
    debugPrint('버스 위젯 업데이트 실패: $e');
  }
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
  );
}

// [5] 설정 저장 서비스
class PreferencesService {
  static const String keyThemeColor = 'theme_color';
  static const String keyThemeMode = 'theme_mode';
  static const String keyMealSource = 'meal_source';
  static const String keyWidgetTrans = 'widget_trans';
  static const String keyWidgetTheme = 'widget_theme';
  static const String keyWidgetSource = 'widget_source';
  static const String keyTabOrder = 'tab_order_v1';

  static final ValueNotifier<List<AppTab>> tabOrder = ValueNotifier([
    AppTab.meal,
    AppTab.bus,
    AppTab.schedule,
    AppTab.run,
    AppTab.map,
    AppTab.settings,
  ]);

  static Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final int? colorValue = prefs.getInt(keyThemeColor);
    if (colorValue != null) themeColor.value = Color(colorValue);
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

    final List<String>? savedOrder = prefs.getStringList(keyTabOrder);
    if (savedOrder != null) {
      try {
        tabOrder.value = savedOrder
            .map((e) => AppTab.values.firstWhere((t) => t.name == e))
            .toList();
      } catch (e) {
        debugPrint("PreferencesService: 탭 순서 로드 실패 - $e");
      }
    }
  }

  static Future<void> saveTabOrder(List<AppTab> order) async {
    final prefs = await SharedPreferences.getInstance();
    tabOrder.value = order;
    await prefs.setStringList(keyTabOrder, order.map((e) => e.name).toList());
  }

  static Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyThemeMode, mode.index);
  }

  static Future<void> saveThemeColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyThemeColor, color.value);
  }

  static Future<void> saveMealSource(MealSource source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyMealSource, source.index);
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

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
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
        const InitializationSettings(android: android, iOS: ios),
      );
    } on PlatformException catch (e) {
      debugPrint("Native Notification Platform Error (Likely permission denied): $e");
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
      await flutterLocalNotificationsPlugin.cancel(id);
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
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledTime, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'meal_alarm_channel',
            '식단 알림',
            importance: Importance.max,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint("알림 예약 실패: $e");
    }
  }

  // FCM 포그라운드 수신용 즉시 알림 메서드
  Future<void> showNotification(int id, String title, String body) async {
    const android = AndroidNotificationDetails(
      'fcm_general_channel',
      '기본 알림',
      importance: Importance.max,
      priority: Priority.high,
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    try {
      await flutterLocalNotificationsPlugin.show(
        id,
        title,
        body,
        const NotificationDetails(android: android, iOS: ios),
      );
    } catch (e) {
      // 알림 권한이 없거나 플랫폼 제약으로 실패한 경우 — 앱 크래시 방지
      debugPrint("showNotification 실패 (권한 없음 또는 플랫폼 오류): $e");
    }
  }
}
