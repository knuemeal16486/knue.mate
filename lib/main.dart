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
  return const _AnimatedSplashScreen();
}

class _AnimatedSplashScreen extends StatefulWidget {
  const _AnimatedSplashScreen();
  @override
  State<_AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<_AnimatedSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.6, curve: Curves.easeOut)),
    );
    _scale = Tween<double>(begin: 0.75, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.7, curve: Curves.elasticOut)),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _scale,
                child: Container(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2563EB).withOpacity(0.35),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset(
                      'assets/icons/knuesquare.png',
                      fit: BoxFit.cover,
                      errorBuilder: (c, e, s) =>
                          const Icon(Icons.school, size: 60, color: Colors.white),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                "KNUE Mate",
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1A1A2E),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "한국교원대학교 올인원 캠퍼스",
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF9CA3AF),
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 56),
              const _PulsingDots(),
            ],
          ),
        ),
      ),
    );
  }
}

class _PulsingDots extends StatefulWidget {
  const _PulsingDots();
  @override
  State<_PulsingDots> createState() => _PulsingDotsState();
}

class _PulsingDotsState extends State<_PulsingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = ((_ctrl.value - i * 0.25) % 1.0).clamp(0.0, 1.0);
            final t = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
            final scale = 0.6 + t * 0.7;
            final opacity = 0.3 + t * 0.7;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity,
                  child: const CircleAvatar(
                    radius: 5,
                    backgroundColor: Color(0xFF2563EB),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
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
                scaffoldBackgroundColor: const Color(0xFFF5F5F7),
                cardColor: Colors.white,
                cardTheme: CardThemeData(
                  elevation: 0,
                  shadowColor: Colors.black.withOpacity(0.06),
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
                navigationBarTheme: NavigationBarThemeData(
                  labelTextStyle: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return GoogleFonts.notoSansKr(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color,
                      );
                    }
                    return GoogleFonts.notoSansKr(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.black38,
                    );
                  }),
                  iconTheme: WidgetStateProperty.resolveWith((states) {
                    return IconThemeData(
                      size: 24,
                      color: states.contains(WidgetState.selected)
                          ? color
                          : Colors.black38,
                    );
                  }),
                  height: 72,
                  indicatorColor: color.withOpacity(0.12),
                  indicatorShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
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
                  elevation: 0,
                  shadowColor: Colors.black.withOpacity(0.3),
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
                navigationBarTheme: NavigationBarThemeData(
                  labelTextStyle: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return GoogleFonts.notoSansKr(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color,
                      );
                    }
                    return GoogleFonts.notoSansKr(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.white38,
                    );
                  }),
                  iconTheme: WidgetStateProperty.resolveWith((states) {
                    return IconThemeData(
                      size: 24,
                      color: states.contains(WidgetState.selected)
                          ? color
                          : Colors.white38,
                    );
                  }),
                  height: 72,
                  indicatorColor: color.withOpacity(0.2),
                  indicatorShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
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
