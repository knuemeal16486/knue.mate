import 'dart:async'; // TimeoutException을 위해 추가
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

// -----------------------------------------------------------------------------
// [1] 전역 설정 및 상태
// -----------------------------------------------------------------------------
const String kBaseUrl = "https://knue-meal-api.onrender.com";

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
  Color(0xFF546E7A),
  Color(0xFF000000),
  Color(0xFF8E8E93),
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

// -----------------------------------------------------------------------------
// [2] 유틸리티 함수
// -----------------------------------------------------------------------------
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
  List<String>? items,
) async {
  if (items == null || items.isEmpty) return;
  final title = "${date.month}월 ${date.day}일 ${type.label} 메뉴";
  final content = items.join("\n");
  await Share.share("[$title]\n\n$content");
}

void showToast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
  );
}

// -----------------------------------------------------------------------------
// [3] API 호출 및 위젯 업데이트
// -----------------------------------------------------------------------------
String _weekdayToDayParam(DateTime d) {
  switch (d.weekday) {
    case 1:
      return "mon";
    case 2:
      return "tue";
    case 3:
      return "wed";
    case 4:
      return "thu";
    case 5:
      return "fri";
    case 6:
      return "sat";
    default:
      return "sun";
  }
}

Future<dynamic> fetchMealApi(DateTime date, MealSource source) async {
  late Uri uri;
  if (source == MealSource.a) {
    uri = Uri.parse(
      "$kBaseUrl/meals-a?y=${date.year}&m=${date.month}&d=${date.day}",
    );
  } else {
    uri = Uri.parse("$kBaseUrl/meals-b?day=${_weekdayToDayParam(date)}");
  }

  try {
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));

      // 오늘 날짜인 경우 위젯 업데이트
      if (isSameDate(date, DateTime.now()) && source == widgetSource.value) {
        _updateWidgetWithData(decoded, source).catchError((e) {
          print("위젯 업데이트 실패: $e");
        });
      }
      return decoded;
    }
  } on TimeoutException catch (e) {
    print("API 타임아웃: $e");
  } on SocketException catch (e) {
    print("네트워크 오류: $e");
  } catch (e) {
    print("Fetch Error: $e");
  }
  
  // 에러 시 빈 식단 반환
  return {
    "meals": {"breakfast": [], "lunch": [], "dinner": []},
  };
}

Future<void> _updateWidgetWithData(
  Map<String, dynamic> data,
  MealSource source,
) async {
  try {
    if (source != widgetSource.value) return;
    final now = DateTime.now();
    final time = now.hour * 60 + now.minute;
    String title = "";
    List<dynamic> menu = [];

    // JSON 구조에 맞춰 안전하게 데이터 추출
    final meals = data['meals'] ?? {};
    final breakfast = meals['조식'] ?? meals['아침'] ?? meals['breakfast'] ?? [];
    final lunch = meals['중식'] ?? meals['점심'] ?? meals['lunch'] ?? [];
    final dinner = meals['석식'] ?? meals['저녁'] ?? meals['dinner'] ?? [];

    if (time < 570) {
      title = "오늘 아침";
      menu = breakfast;
    } else if (time < 840) {
      title = "오늘 점심";
      menu = lunch;
    } else if (time < 1170) {
      title = "오늘 저녁";
      menu = dinner;
    } else {
      title = "내일 메뉴";
      menu = ["내일 식단을 확인하세요"];
    }

    String menuString = menu.isEmpty
        ? "정보 없음"
        : menu.map((e) => "· $e").join("\n");
    await HomeWidget.saveWidgetData<String>('title', title);
    await HomeWidget.saveWidgetData<String>('content', menuString);
    await HomeWidget.saveWidgetData<int>('themeMode', widgetTheme.value.index);
    await HomeWidget.saveWidgetData<double>(
      'transparency',
      widgetTransparency.value,
    );
    await HomeWidget.updateWidget(name: 'MealWidgetProvider');
  } catch (e) {
    print("위젯 업데이트 오류: $e");
  }
}

// -----------------------------------------------------------------------------
// [4] 설정 저장 서비스
// -----------------------------------------------------------------------------
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
  }
}

// -----------------------------------------------------------------------------
// [5] 알림 서비스 (스케줄링 포함) - 수정된 버전
// -----------------------------------------------------------------------------
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    } catch (_) {}

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
  }

  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  Future<void> cancelAll() async =>
      await flutterLocalNotificationsPlugin.cancelAll();

  // 알람 스케줄링
  Future<void> scheduleAlarm({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    // 이미 지난 시간이면 내일로 설정
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
        matchDateTimeComponents: DateTimeComponents.time, // 매일 반복
      );
    } catch (e) {
      print("알림 예약 실패: $e");
    }
  }
}