import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:home_widget/home_widget.dart';
import 'package:google_fonts/google_fonts.dart';
import 'constants.dart';
import 'meal_screen.dart';
import 'building_data.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 백그라운드 메시지 핸들링
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase 초기화
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // FCM 백그라운드 메시지 핸들러 등록
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 푸시 알림 권한 요청 (iOS) 및 알림 설정
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  print('Push messaging permission: ${settings.authorizationStatus}');

  // 현재 기기의 푸시 토큰 가져오기 (테스트 및 서버 전송용)
  String? fcmToken = await messaging.getToken();
  print("FCM Registration Token: $fcmToken");

  // 앱이 켜져있을 때 (Foreground) 푸시 알림이 오면 처리하는 로직
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('Foreground message received: ${message.messageId}');
    if (message.notification != null) {
      // constants.dart에 방금 만든 showNotification 함수 호출
      NotificationService().showNotification(
        message.notification.hashCode,
        message.notification!.title ?? '알림',
        message.notification!.body ?? '',
      );
    }
  });

  // JSON 건물 데이터 로드
  await loadBuildingData();

  // 디버그 모드 설정
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      print(message);
    }
  };

  print("=== 앱 시작 ===");

  // .env 파일 로드
  try {
    await dotenv.load(fileName: ".env");
    print(".env 파일 로드 성공");
  } catch (e) {
    print(".env Load Error: $e");
  }

  await initializeDateFormatting();
  print("날짜 형식 초기화 완료");

  // HomeWidget 초기화
  try {
    // iOS용 App Group ID (Android에서는 무시됨)
    await HomeWidget.setAppGroupId('group.knue.meal');
    print("HomeWidget AppGroupId 설정 완료");

    // 위젯에서 앱 실행 여부 확인
    try {
      final launchedFromWidget =
          await HomeWidget.initiallyLaunchedFromHomeWidget();
      print("위젯에서 실행됨: $launchedFromWidget");

      if (launchedFromWidget == true) {
        final title = await HomeWidget.getWidgetData<String>('title');
        print("위젯 데이터 - title: $title");
      }
    } catch (e) {
      print("위젯 실행 확인 오류: $e");
    }
  } catch (e) {
    print("HomeWidget 초기화 오류: $e");
  }

  // 설정 로드
  await PreferencesService.loadSettings();
  print("설정 로드 완료");

  // 알람 초기화
  await NotificationService().init();
  print("알림 서비스 초기화 완료");

  runApp(const MyApp());
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
