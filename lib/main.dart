import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:home_widget/home_widget.dart';
import 'package:google_fonts/google_fonts.dart';
import 'constants.dart';
import 'building_data.dart';
import 'package:workmanager/workmanager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'firebase_sync_service.dart';
import 'root_screen.dart';
import 'push_notification_service.dart';
import 'keyword_alert_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("Handling a background message: ${message.messageId}");
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await PreferencesService.loadSettings();
      if (task == kNoticeCheckTask) {
        await KeywordAlertService.checkAndNotify();
      } else {
        final targetDate = getWidgetTargetDate(defaultSourceNotifier.value);
        await fetchMealApi(targetDate, defaultSourceNotifier.value);
      }
    } catch (e) {
      debugPrint("Workmanager error: $e");
    }
    return Future.value(true);
  });
}

class StartupErrorApp extends StatelessWidget {
  final Object error;
  final StackTrace stackTrace;
  const StartupErrorApp(this.error, this.stackTrace, {super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                const Text(
                  "앱 초기화 오류",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black),
                ),
                const SizedBox(height: 8),
                Text(
                  "문제가 발생하여 앱을 시작할 수 없습니다.\n아래 내용을 개발자에게 전달해 주세요.",
                  style: TextStyle(color: Colors.grey[700]),
                ),
                const Divider(height: 32),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "$error\n\n$stackTrace",
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.redAccent),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return StartupErrorApp(details.exception, details.stack ?? StackTrace.empty);
  };

  try {
    runApp(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: _buildLoadingScreen,
        home: Scaffold(backgroundColor: Colors.white),
      ),
    );

    await _initializeFirebase();

    await Future.wait([
      initializeDateFormatting(),
      dotenv.load(fileName: ".env"),
      loadBuildingData(),
      PreferencesService.loadSettings(),
    ]);

    try {
      _initializeBackgroundTasks();
      await _initializeHomeWidget();
      await NotificationService().init();
      await PushNotificationService.init();
    } catch (e) {
      debugPrint("Plugin initialization error: $e");
    }

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
        await Workmanager().registerPeriodicTask(
          "meal_widget_update_task",
          "widget_update",
          frequency: const Duration(minutes: 15),
          constraints: Constraints(networkType: NetworkType.connected),
        );
        await KeywordAlertService.syncRegistration();
      } catch (e) {
        debugPrint("Workmanager setup error: $e");
      }
    }

    runApp(const MyApp());
  } catch (e, stackTrace) {
    debugPrint("Native/Fatal Init Error: $e\n$stackTrace");
    runApp(StartupErrorApp(e, stackTrace));
  }
}

Widget _buildLoadingScreen(BuildContext context, Widget? child) {
  return Scaffold(
    backgroundColor: Colors.white,
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset('assets/icons/knuesquare.png', width: 100, height: 100, errorBuilder: (c, e, s) => const Icon(Icons.school, size: 80, color: Colors.blue)),
          const SizedBox(height: 24),
          const CircularProgressIndicator(strokeWidth: 3),
          const SizedBox(height: 16),
          const Text("캠퍼스 데이터를 불러오는 중...", style: TextStyle(color: Colors.grey)),
        ],
      ),
    ),
  );
}

Future<void> _initializeFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    _setupFirebaseMessaging();
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }
}

Future<void> _setupFirebaseMessaging() async {
  try {
    final messaging = FirebaseMessaging.instance;
    NotificationSettings settings;
    try {
      settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      debugPrint("Firebase Messaging requestPermission error: $e");
      return;
    }

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        try {
          final apnsToken = await messaging.getAPNSToken();
          if (apnsToken == null) {
            debugPrint("APNS Token not yet available. FCM token might fail.");
            return;
          }
        } catch (e) {
          debugPrint("APNS Token fetch error: $e");
          return;
        }
      }

      try {
        final fcmToken = await messaging.getToken();
        if (fcmToken != null) {
          final displayToken = fcmToken.length > 20 ? fcmToken.substring(0, 20) : fcmToken;
          debugPrint("FCM Token: $displayToken...");
        }
      } on PlatformException catch (e) {
        debugPrint("FCM Token fetch PlatformException (Denied/Disabled): $e");
      } catch (e) {
        debugPrint("FCM Token fetch error: $e");
      }

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (message.notification != null) {
          NotificationService().showNotification(
            message.notification.hashCode,
            message.notification!.title ?? '알림',
            message.notification!.body ?? '',
          );
        }
      });
    } else {
      debugPrint("FCM 알림 권한 없음 (status: ${settings.authorizationStatus}). 포그라운드 알림 비활성화.");
    }
  } catch (e) {
    debugPrint("Firebase messaging setup error: $e");
  }
}

void _initializeBackgroundTasks() {
  FirebaseSyncService.uploadBuildingsToFirestore();
}

Future<void> _initializeHomeWidget() async {
  try {
    debugPrint("HomeWidget 초기화 시도...");
    await HomeWidget.setAppGroupId('group.knue.meal');
    final launchedFromWidget = await HomeWidget.initiallyLaunchedFromHomeWidget();
    if (launchedFromWidget != null) {
      final title = await HomeWidget.getWidgetData<String>('title');
      debugPrint("위젯 데이터 - title: $title");
    }
  } catch (e) {
    debugPrint("HomeWidget 초기화 건너뜀 (플랫폼 제약 가능성): $e");
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, child) {
        return ValueListenableBuilder<Color>(
          valueListenable: themeColor,
          builder: (context, color, child) {
            return MaterialApp(
              title: 'KNUE Mate',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.light,
                primaryColor: color,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: color,
                  primary: color,
                  secondary: color.withOpacity(0.8),
                  brightness: Brightness.light,
                ),
                textTheme: GoogleFonts.notoSansKrTextTheme(
                  ThemeData(brightness: Brightness.light).textTheme,
                ),
                scaffoldBackgroundColor: const Color(0xFFF8F9FE),
                cardColor: Colors.white,
                cardTheme: CardThemeData(
                  elevation: 8,
                  shadowColor: Colors.black.withOpacity(0.04),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  color: Colors.white,
                  surfaceTintColor: Colors.transparent,
                ),
                appBarTheme: AppBarTheme(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  titleTextStyle: GoogleFonts.notoSansKr(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                pageTransitionsTheme: const PageTransitionsTheme(
                  builders: {
                    TargetPlatform.android: CupertinoPageTransitionsBuilder(),
                    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                  },
                ),
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.dark,
                primaryColor: color,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: color,
                  primary: color,
                  secondary: color.withOpacity(0.8),
                  brightness: Brightness.dark,
                  surface: const Color(0xFF161618),
                ),
                textTheme: GoogleFonts.notoSansKrTextTheme(
                  ThemeData(brightness: Brightness.dark).textTheme,
                ),
                scaffoldBackgroundColor: const Color(0xFF0D0D0F),
                cardColor: const Color(0xFF1E1E22),
                cardTheme: CardThemeData(
                  elevation: 8,
                  shadowColor: Colors.black.withOpacity(0.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  color: const Color(0xFF1E1E22),
                  surfaceTintColor: Colors.transparent,
                ),
                appBarTheme: AppBarTheme(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  titleTextStyle: GoogleFonts.notoSansKr(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                pageTransitionsTheme: const PageTransitionsTheme(
                  builders: {
                    TargetPlatform.android: CupertinoPageTransitionsBuilder(),
                    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                  },
                ),
              ),
              themeMode: mode,
              home: const RootNavigationScreen(),
            );
          },
        );
      },
    );
  }
}
