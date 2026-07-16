import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

class PushNotificationService {
  static final _messaging = FirebaseMessaging.instance;
  static final _flutterLocal = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const init = InitializationSettings(android: android);
    await _flutterLocal.initialize(settings: init);

    await _messaging.requestPermission();

    final token = await _messaging.getToken();
    debugPrint('FCM Token: $token');

    FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
      final notif = msg.notification;
      if (notif != null) {
        _flutterLocal.show(
          id: notif.hashCode,
          title: notif.title,
          body: notif.body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              'bus_channel',
              '버스 알림',
              channelDescription: '버스 도착 알림',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
        );
      }
    });
  }
}
