import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:home_widget/home_widget.dart';
import 'package:google_fonts/google_fonts.dart';
import 'constants.dart';
import 'meal_screen.dart';
import 'building_data.dart';
import 'package:workmanager/workmanager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'firebase_sync_service.dart';

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
      final targetDate = getWidgetTargetDate(defaultSourceNotifier.value);
      await fetchMealApi(targetDate, defaultSourceNotifier.value);
    } catch (e) {
      debugPrint("Workmanager error: $e");
    }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 워크매니저 초기화 및 정기적 위젯 업데이트 등록 (최소 15분 주기)
  Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false,
  );
  Workmanager().registerPeriodicTask(
    "meal_widget_update_task",
    "widget_update",
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
  );

  // [개선] 초기화 작업을 병렬로 실행하여 앱 시작 시간 단축

  await Future.wait([
    // Firebase 초기화
    _initializeFirebase(),
    // 날짜 형식 초기화
    initializeDateFormatting(),
    // dotenv 로드
    dotenv.load(fileName: ".env"),
    // Gebäude 데이터 로드
    loadBuildingData(),
    // 설정 로드
    PreferencesService.loadSettings(),
  ]);

  // 백그라운드 작업들 (병렬로 실행해도 무방)
  _initializeBackgroundTasks();

  // HomeWidget 초기화 (UI Blocking 방지)
  _initializeHomeWidget();

  // 알림 서비스 초기화
  await NotificationService().init();

  runApp(const MyApp());
}

Future<void> _initializeFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // FCM 권한 요청 및 토큰 가져오기
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      final fcmToken = await messaging.getToken();
      debugPrint("FCM Token: ${fcmToken?.substring(0, 20)}...");
    }

    // 포그라운드 메시지 리스너
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        NotificationService().showNotification(
          message.notification.hashCode,
          message.notification!.title ?? '알림',
          message.notification!.body ?? '',
        );
      }
    });
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }
}

void _initializeBackgroundTasks() {
  // Firebase에 건물 데이터 업로드 (백그라운드)
  FirebaseSyncService.uploadBuildingsToFirestore();
}

Future<void> _initializeHomeWidget() async {
  try {
    await HomeWidget.setAppGroupId('group.knue.meal');
    final launchedFromWidget =
        await HomeWidget.initiallyLaunchedFromHomeWidget();
    if (launchedFromWidget == true) {
      // Uri? 타입이므로 == true로 비교
      final title = await HomeWidget.getWidgetData<String>('title');
      debugPrint("위젯 데이터 - title: $title");
    }
  } catch (e) {
    debugPrint("HomeWidget 초기화 오류: $e");
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
              home: const MealMainScreen(),
            );
          },
        );
      },
    );
  }
}
