import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/material.dart'; // TimeOfDay 용도

class AlarmService {
  static final FlutterLocalNotificationsPlugin _notiPlugin =
      FlutterLocalNotificationsPlugin();
  static const String _channelId = 'knue_meal_alarm';
  static const String _channelName = '식단 알림';
  static const String _desc = '매일 점심/저녁 시간에 식단 알림을 보냅니다.';

  // 초기화 (main.dart에서 호출)
  static Future<void> init() async {
    tz.initializeTimeZones();
    // 한국 시간대 설정
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS 설정 (권한 요청 포함)
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notiPlugin.initialize(settings);
  }

  // 알람 켜기/끄기 토글
  static Future<bool> toggleAlarm(bool enable) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('alarm_enabled', enable);

    if (enable) {
      // 알람 켜기: 권한 확인 후 스케줄링
      final bool? result = await _notiPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();

      if (result == false) return false; // 권한 거부됨

      await _scheduleDailyAlarm();
      return true;
    } else {
      // 알람 끄기: 예약된 알람 취소
      await _notiPlugin.cancelAll();
      return false;
    }
  }

  // 저장된 설정 불러오기
  static Future<bool> loadAlarmState() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('alarm_enabled') ?? false;
  }

  // 매일 오전 11:30 알람 등록
  static Future<void> _scheduleDailyAlarm() async {
    await _notiPlugin.zonedSchedule(
      0, // ID
      '오늘의 점심 메뉴 🍽️',
      '맛있는 점심 드실 시간입니다! 앱에서 메뉴를 확인하세요.',
      _nextInstanceOf1130(),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _desc,
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // 매일 같은 시간에 반복
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  // 다음 11시 30분 계산
  static tz.TZDateTime _nextInstanceOf1130() {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      11,
      30,
    );
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }
}
