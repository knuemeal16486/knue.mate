import 'dart:io' show Platform;
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
  // 1. 바인딩 초기화
  WidgetsFlutterBinding.ensureInitialized();

  // [추가] UI 에러 핸들러 설정 (화이트 스크린 방지용 최후의 보루)
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return StartupErrorApp(details.exception, details.stack ?? StackTrace.empty);
  };

  try {
    // 2. 초기 로딩 화면 표시 (하얀 화면 방지)
    // [중요] 앱이 실행되자마자 UI를 먼저 그려서 OS와의 연결을 유지함
    runApp(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: _buildLoadingScreen,
        home: Scaffold(backgroundColor: Colors.white),
      ),
    );

    // 3. 최우선 순위: Firebase 초기화
    // 다른 모든 서비스(Firestore 등)가 Firebase에 의존하므로 가장 먼저 처리
    await _initializeFirebase();

    // 4. 나머지 중요 설정 병렬 로드
    await Future.wait([
      initializeDateFormatting(),
      dotenv.load(fileName: ".env"),
      loadBuildingData(), // 이제 Firebase가 있으므로 내부에서 Firestore 접근 가능
      PreferencesService.loadSettings(),
    ]);

    // 5. 플러그인 및 기타 비필수 초기화
    try {
      _initializeBackgroundTasks();
      await _initializeHomeWidget();
      await NotificationService().init();
    } catch (e) {
      debugPrint("Plugin initialization error: $e");
    }

    // 6. 워크매니저 초기화
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
        await Workmanager().registerPeriodicTask(
          "meal_widget_update_task",
          "widget_update",
          frequency: const Duration(minutes: 15),
          constraints: Constraints(networkType: NetworkType.connected),
        );
      } catch (e) {
        debugPrint("Workmanager setup error: $e");
      }
    }

    // 7. 메인 앱 실행
    runApp(const MyApp());
  } catch (e, stackTrace) {
    debugPrint("Native/Fatal Init Error: $e\n$stackTrace");
    // 치명적 오류 시 전전용 에러 앱 표시
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
          // 앱 로고 이미지가 있다면 여기에 배치 (assets/icons/knuesquare.png)
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
    // 1. Firebase 초기화 완료 대기
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    // 2. 초기화 완료 후 서비스 설정
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // FCM 설정 (비동기, 메인 루프 방해 안 함)
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
      // iOS에서는 APNS 토큰이 먼저 준비되어야 FCM 토큰을 정상적으로 받아올 수 있음
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
      } catch (e) {
        debugPrint("FCM Token fetch error: $e");
      }
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
    debugPrint("Firebase messaging setup error: $e");
  }
}

void _initializeBackgroundTasks() {
  // Firebase에 건물 데이터 업로드 (백그라운드)
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
              home: const MealMainScreen(),
            );
          },
        );
      },
    );
  }
}
