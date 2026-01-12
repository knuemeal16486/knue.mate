import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:home_widget/home_widget.dart';

// [1] 전역 설정
const String kBaseUrl = "https://knue-meal-api.onrender.com";
const String kHomeWidgetChannel = 'home_widget';

final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.system);
final ValueNotifier<Color> themeColor = ValueNotifier(const Color(0xFF2563EB));
final ValueNotifier<MealSource> defaultSourceNotifier = ValueNotifier(MealSource.a);

final ValueNotifier<double> widgetTransparency = ValueNotifier(0.0);
final ValueNotifier<ThemeMode> widgetTheme = ValueNotifier(ThemeMode.system);
final ValueNotifier<MealSource> widgetSource = ValueNotifier(MealSource.a);

const List<Color> kColorPalette = [
  Color(0xFF2563EB), Color(0xFFEF5350), Color(0xFFEC407A), Color(0xFFAB47BC),
  Color(0xFF7E57C2), Color(0xFF5C6BC0), Color(0xFF039BE5), Color(0xFF00ACC1),
  Color(0xFF00897B), Color(0xFF43A047), Color(0xFF7CB342), Color(0xFFC0CA33),
  Color(0xFFFDD835), Color(0xFFFFB300), Color(0xFFFB8C00), Color(0xFFF4511E),
  Color(0xFF6D4C41), Color(0xFF757575), Color(0xFF546E7A), Color(0xFF000000),
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
  final start = DateTime(now.year, now.month, now.day, int.parse(startStr[0]), int.parse(startStr[1]));
  final end = DateTime(now.year, now.month, now.day, int.parse(endStr[0]), int.parse(endStr[1]));
  
  if (now.isBefore(start)) return ServeStatus.waiting;
  if (now.isAfter(end)) return ServeStatus.closed;
  return ServeStatus.open;
}

Future<void> shareMenu(BuildContext context, DateTime date, MealSource source, MealType type, List<String>? items) async {
  if (items == null || items.isEmpty) return;
  final title = "${date.month}월 ${date.day}일 ${type.label} 메뉴";
  final content = items.join("\n");
  await Share.share("[$title]\n\n$content");
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

// [3] API 및 위젯 로직 (수정됨)
String _weekdayToDayParam(DateTime d) {
  switch (d.weekday) {
    case 1: return "mon"; case 2: return "tue"; case 3: return "wed";
    case 4: return "thu"; case 5: return "fri"; case 6: return "sat";
    default: return "sun";
  }
}

Future<dynamic> fetchMealApi(DateTime date, MealSource source) async {
  late Uri uri;
  if (source == MealSource.a) {
    uri = Uri.parse("$kBaseUrl/meals-a?y=${date.year}&m=${date.month}&d=${date.day}");
  } else {
    uri = Uri.parse("$kBaseUrl/meals-b?day=${_weekdayToDayParam(date)}");
  }

  try {
    // [수정] 타임아웃 30초로 증가 (무료 서버 수면 모드 대비)
    final response = await http.get(uri).timeout(const Duration(seconds: 30));
    
    if (response.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      
      // 날짜가 오늘인 경우에만 위젯 업데이트 시도
      if (DateUtils.isSameDay(date, DateTime.now())) {
         await _updateWidgetDataInternal(decoded, source);
      }
      return decoded;
    }
  } catch (e) {
    print("Fetch Error: $e");
  }
  return {"meals": {"breakfast": [], "lunch": [], "dinner": []}};
}

// [핵심] 위젯 데이터 가공 및 저장
Future<void> _updateWidgetDataInternal(Map<String, dynamic> data, MealSource source) async {
  try {
    final now = DateTime.now();
    final hour = now.hour;
    
    String timeText = "";
    String mealKey = "";
    String sourceName = source == MealSource.a ? "기숙사 식당" : "학생회관 식당";

    // 시간대 로직 (요구사항 반영)
    if (source == MealSource.a) { // 기숙사
      if (hour < 9) {
        timeText = "오늘 아침"; mealKey = "breakfast";
      } else if (hour < 14) {
        timeText = "오늘 점심"; mealKey = "lunch";
      } else {
        timeText = "오늘 저녁"; mealKey = "dinner";
      }
    } else { // 학생회관
      if (hour < 14) {
        timeText = "오늘 점심"; mealKey = "lunch";
      } else {
        timeText = "오늘 저녁"; mealKey = "dinner";
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

    // 데이터 저장
    await HomeWidget.saveWidgetData<String>('widget_title', sourceName);
    await HomeWidget.saveWidgetData<String>('widget_time', timeText);
    await HomeWidget.saveWidgetData<String>('widget_menu', menuText);
    
    // 설정 저장
    await HomeWidget.saveWidgetData<int>('themeMode', widgetTheme.value.index);
    await HomeWidget.saveWidgetData<String>('transparency', widgetTransparency.value.toString());

    // [수정] 위젯 업데이트 시 전체 패키지명 사용 (가장 확실한 방법)
    await HomeWidget.updateWidget(
      name: 'MealWidgetProvider',
      androidName: 'MealWidgetProvider',
      qualifiedAndroidName: 'com.knue.knuemate.MealWidgetProvider',
    );
    
    print("위젯 업데이트 요청 완료: $sourceName / $timeText");
    
  } catch (e) {
    print("위젯 내부 업데이트 실패: $e");
  }
}

// [4] 설정 저장 및 강제 업데이트
Future<void> saveWidgetSettingsAndUpdate(
    double trans, ThemeMode theme, MealSource source, BuildContext context) async {
  
  widgetTransparency.value = trans;
  widgetTheme.value = theme;
  widgetSource.value = source;

  await PreferencesService.saveWidgetSettings(trans, theme, source);

  try {
    // 로딩 상태 먼저 표시
    await HomeWidget.saveWidgetData<String>('widget_menu', "데이터를 불러오는 중...\n(최대 30초 소요)");
    await HomeWidget.updateWidget(name: 'MealWidgetProvider', androidName: 'MealWidgetProvider');

    // 실제 데이터 호출
    await fetchMealApi(DateTime.now(), source);
    
    if (context.mounted) showToast(context, "위젯 설정이 적용되었습니다.");
  } catch (e) {
    if (context.mounted) showToast(context, "데이터 갱신 실패");
  }
}

Future<void> forceUpdateWidgetWithCurrentSettings() async {
  await PreferencesService.loadSettings();
  await fetchMealApi(DateTime.now(), defaultSourceNotifier.value);
}

Future<void> testBasicWidgetFunction() async {
  // 테스트용 함수
  await HomeWidget.saveWidgetData<String>('widget_title', '테스트 식당');
  await HomeWidget.saveWidgetData<String>('widget_time', '테스트 시간');
  await HomeWidget.saveWidgetData<String>('widget_menu', '· 쌀밥\n· 김치찌개\n· 계란말이\n· 깍두기');
  await HomeWidget.updateWidget(name: 'MealWidgetProvider', androidName: 'MealWidgetProvider');
}

// [5] 설정 저장 서비스
class PreferencesService {
  static const String keyThemeColor = 'theme_color';
  static const String keyThemeMode = 'theme_mode';
  static const String keyMealSource = 'meal_source';
  static const String keyWidgetTrans = 'widget_trans';
  static const String keyWidgetTheme = 'widget_theme';
  static const String keyWidgetSource = 'widget_source';

  static Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final int? colorValue = prefs.getInt(keyThemeColor);
    if (colorValue != null) themeColor.value = Color(colorValue);
    final int? modeIndex = prefs.getInt(keyThemeMode);
    if (modeIndex != null) themeModeNotifier.value = ThemeMode.values[modeIndex];
    final int? sourceIndex = prefs.getInt(keyMealSource);
    if (sourceIndex != null) defaultSourceNotifier.value = MealSource.values[sourceIndex];

    widgetTransparency.value = prefs.getDouble(keyWidgetTrans) ?? 0.0;
    final int? wTheme = prefs.getInt(keyWidgetTheme);
    if (wTheme != null) widgetTheme.value = ThemeMode.values[wTheme];
    final int? wSource = prefs.getInt(keyWidgetSource);
    if (wSource != null) widgetSource.value = MealSource.values[wSource];
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

  static Future<void> saveWidgetSettings(double trans, ThemeMode theme, MealSource source) async {
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

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    tz.initializeTimeZones();
    try { tz.setLocalLocation(tz.getLocation('Asia/Seoul')); } catch (_) {}

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
  }

  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      await flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      await flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  Future<void> cancelAll() async => await flutterLocalNotificationsPlugin.cancelAll();

  Future<void> scheduleAlarm({required int id, required String title, required String body, required DateTime scheduledTime}) async {
    if (scheduledTime.isBefore(DateTime.now())) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }
    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id, title, body,
        tz.TZDateTime.from(scheduledTime, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails('meal_alarm_channel', '식단 알림', importance: Importance.max),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      print("알림 예약 실패: $e");
    }
  }
}