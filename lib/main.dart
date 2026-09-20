import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:home_widget/home_widget.dart';
import 'package:google_fonts/google_fonts.dart';
import 'ad_service.dart';
import 'admin_auth_service.dart';
import 'att_service.dart';
import 'rewarded_ad_service.dart';
import 'constants.dart';
import 'building_data.dart';
import 'package:workmanager/workmanager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'firebase_sync_service.dart';
import 'root_screen.dart';
import 'ui_utils.dart';
import 'keyword_alert_service.dart';
import 'club_event_alert_service.dart';

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
      // 백그라운드 작업도 공용 캐시(daily_meals 등)에 쓰므로 로그인이 필요하다.
      // 로그인 상태는 기기에 저장돼 있어 보통은 그대로 복원된다.
      await AdminAuthService.initialize();
      await PreferencesService.loadSettings();
      if (task == kNoticeCheckTask) {
        await KeywordAlertService.checkAndNotify();
      } else if (task == kClubEventCheckTask) {
        await ClubEventAlertService.checkAndNotify();
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
      // 이 화면은 앱 테마가 만들어지기 전에 뜨므로 폰트를 직접 지정해야 한다.
      // 안 그러면 여기만 기본(Roboto) 글씨로 나온다.
      theme: ThemeData(
        useMaterial3: true,
        textTheme: GoogleFonts.notoSansKrTextTheme(
          ThemeData(brightness: Brightness.light).textTheme,
        ),
      ),
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
      MaterialApp(
        debugShowCheckedModeBanner: false,
        // 부팅 화면도 앱 폰트로 — 테마 없이 띄우면 이 짧은 순간만 기본
        // 글씨체로 나와서 첫인상이 어긋난다.
        theme: ThemeData(
          useMaterial3: true,
          textTheme: GoogleFonts.notoSansKrTextTheme(
            ThemeData(brightness: Brightness.light).textTheme,
          ),
        ),
        builder: _buildLoadingScreen,
        home: const Scaffold(backgroundColor: Colors.white),
      ),
    );

    await _initializeFirebase();

    await Future.wait([
      initializeDateFormatting('ko_KR', null).catchError((e) {
        debugPrint("DateFormatting warning: $e");
      }),
      dotenv.load(fileName: ".env").catchError((e) {
        debugPrint("dotenv load warning: $e");
      }),
      loadBuildingData().catchError((e) {
        debugPrint("loadBuildingData warning: $e");
      }),
      PreferencesService.loadSettings().catchError((e) {
        debugPrint("loadSettings warning: $e");
      }),
      loadAppVersion(),
    ]);

    try {
      _initializeBackgroundTasks();
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        // 서로 의존하지 않는 초기화라 병렬로 돌린다 — 순서대로 await하면
        // 지연 시간이 합산되어 첫 화면이 그만큼 늦게 뜬다.
        await Future.wait([
          _initializeHomeWidget(),
          NotificationService().init(),
          // 스폰서가 없을 때 KnueNativeAdCard가 대체로 띄우는 AdMob 광고 —
          // 광고를 요청하기 전에 반드시 끝나 있어야 하므로 runApp보다 앞에 둔다.
          // iOS는 앱 추적 투명성(ATT) 권한을 먼저 물어야 맞춤 광고 허용 여부가
          // 정확히 반영되므로 AdService.initialize()보다 먼저 끝낸다.
          () async {
            await AttService.requestIfNeeded();
            await AdService.initialize();
            // 무지개 모드 잠금 해제용 보상형 광고를 미리 불러둔다. 다 될 때까지
            // runApp을 기다릴 필요는 없어서 await 안 한다 — 설정 화면을 열 즈음엔
            // 대개 이미 준비돼 있다.
            RewardedAdService.preload();
          }(),
        ]);
      }
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
        await ClubEventAlertService.syncRegistration();
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
          // 원본이 2048×2048이라 그냥 그리면 100×100으로 보여주면서도
          // 디코드는 원본 크기로 한다 — 한 장에 램 16MB. cacheWidth를 주면
          // 디코드 단계에서 줄여 받는다(화면 배율을 고려해 넉넉히 300).
          Image.asset('assets/icons/knue_icon.png', width: 100, height: 100, cacheWidth: 300, cacheHeight: 300, errorBuilder: (c, e, s) => const Icon(Icons.school, size: 80, color: Colors.blue)),
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
    // 익명 로그인. Firestore 쓰기 규칙이 로그인을 요구하므로 제보·별점 같은
    // 기본 기능보다 먼저 끝나 있어야 한다. 실패해도 읽기는 되므로 앱은 뜬다.
    await AdminAuthService.initialize();
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      await _setupFirebaseMessaging();
    }
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
  try {
    // 백그라운드 건물 데이터 업로드 (에러 발생 시 무시)
    FirebaseSyncService.uploadBuildingsToFirestore().catchError((e) {
      debugPrint("uploadBuildingsToFirestore background error: $e");
    });
  } catch (e) {
    debugPrint("Background tasks init error: $e");
  }
}

/// 위젯을 눌러 앱이 열렸을 때 이동할 탭.
///
/// 앱이 **꺼져 있다가** 위젯으로 열리는 경우, 이 값이 정해지는 시점이
/// RootNavigationScreen이 만들어지기 전이라 그 자리에서 탭을 바꿀 수 없다.
/// 그래서 여기 담아 두고, 첫 화면이 준비되면 그때 꺼내 쓴다.
AppTab? pendingWidgetTab;

/// 위젯 URI(knuemate://meal 등)를 보고 갈 탭을 정한다.
/// 모르는 주소면 null — 그냥 평소 시작 탭으로 연다.
AppTab? widgetTabForUri(Uri? uri) {
  if (uri == null) return null;
  if (uri.scheme != 'knuemate') return null;
  switch (uri.host) {
    case 'meal':
      return AppTab.meal;
    case 'bus':
      return AppTab.bus;
    default:
      return null;
  }
}

void _handleWidgetUri(Uri? uri) {
  final tab = widgetTabForUri(uri);
  if (tab == null) return;
  // 이미 떠 있는 앱이면 바로 옮기고, 아직이면 첫 화면이 가져가게 남겨 둔다.
  if (!RootNavigationScreen.switchTab(tab)) {
    pendingWidgetTab = tab;
  }
}

Future<void> _initializeHomeWidget() async {
  try {
    debugPrint("HomeWidget 초기화 시도...");
    await HomeWidget.setAppGroupId('group.knue.meal');
    // 앱이 꺼져 있다가 위젯 탭으로 열린 경우.
    _handleWidgetUri(await HomeWidget.initiallyLaunchedFromHomeWidget());
    // 앱이 백그라운드에 있다가 위젯 탭으로 돌아온 경우.
    HomeWidget.widgetClicked.listen(_handleWidgetUri);
  } catch (e) {
    debugPrint("HomeWidget 초기화 건너뜀 (플랫폼 제약 가능성): $e");
  }
}

/// [TextTheme.apply]의 letterSpacingDelta는 모든 스타일에 letterSpacing이
/// 지정돼 있어야만 쓸 수 있다(null이면 assert 실패 → 앱 전체가 ErrorWidget으로
/// 대체된다). 웹 빌드의 타이포그래피는 일부 스타일의 letterSpacing이 null이라
/// 그대로 쓰면 시작하자마자 깨진다. null은 0으로 보고 델타를 직접 더한다.
TextTheme _applyLetterSpacingDelta(TextTheme base, double delta) {
  TextStyle? tighten(TextStyle? style) => style?.copyWith(
        letterSpacing: (style.letterSpacing ?? 0) + delta,
      );
  return base.copyWith(
    displayLarge: tighten(base.displayLarge),
    displayMedium: tighten(base.displayMedium),
    displaySmall: tighten(base.displaySmall),
    headlineLarge: tighten(base.headlineLarge),
    headlineMedium: tighten(base.headlineMedium),
    headlineSmall: tighten(base.headlineSmall),
    titleLarge: tighten(base.titleLarge),
    titleMedium: tighten(base.titleMedium),
    titleSmall: tighten(base.titleSmall),
    bodyLarge: tighten(base.bodyLarge),
    bodyMedium: tighten(base.bodyMedium),
    bodySmall: tighten(base.bodySmall),
    labelLarge: tighten(base.labelLarge),
    labelMedium: tighten(base.labelMedium),
    labelSmall: tighten(base.labelSmall),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 앱을 켜 둔 채 자정을 넘겼을 수 있으므로, 돌아올 때마다 오늘의 색을
    // 다시 확인한다. 무지개 모드가 꺼져 있으면 아무 일도 하지 않는다.
    if (state == AppLifecycleState.resumed) {
      PreferencesService.refreshRainbowColorIfNeeded();
    }
  }

  /// 팝업(다이얼로그·바텀시트) 공통 모양.
  ///
  /// 화면마다 손으로 만든 팝업이 제각각이라 모서리 반경·배경색·버튼 모양이
  /// 다 달랐다. 여기서 한 번 정해두면 기본 AlertDialog/showModalBottomSheet를
  /// 쓰는 곳은 호출부를 안 고쳐도 같은 모양으로 맞춰진다.
  DialogThemeData _dialogTheme(bool isDark) => DialogThemeData(
    backgroundColor: KnueTokens.surface(isDark),
    surfaceTintColor: Colors.transparent,
    elevation: 12,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    titleTextStyle: GoogleFonts.notoSansKr(
      fontSize: 17,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.4,
      color: isDark ? Colors.white : Colors.black87,
    ),
    contentTextStyle: GoogleFonts.notoSansKr(
      fontSize: 13.5,
      height: 1.5,
      letterSpacing: -0.2,
      color: isDark ? Colors.white70 : Colors.black87,
    ),
  );

  BottomSheetThemeData _bottomSheetTheme(bool isDark) => BottomSheetThemeData(
    backgroundColor: KnueTokens.surface(isDark),
    surfaceTintColor: Colors.transparent,
    elevation: 12,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    showDragHandle: true,
    dragHandleColor: isDark ? Colors.white24 : Colors.black26,
  );

  /// 팝업 하단 버튼. 기본 TextButton은 글씨가 얇고 터치 영역이 들쭉날쭉해서
  /// "취소/확인"이 본문보다 눈에 덜 들어왔다.
  TextButtonThemeData _textButtonTheme(Color seed) => TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: seed,
      textStyle: GoogleFonts.notoSansKr(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );

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
                textTheme: _applyLetterSpacingDelta(
                  GoogleFonts.notoSansKrTextTheme(
                    ThemeData(brightness: Brightness.light).textTheme,
                  ),
                  -0.4,
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
                  // iOS는 AppBar 제목을 가운데로 보내는 게 기본이라, 화면마다
                  // 따로 끄던 것을 여기서 한 번에 끈다(안 끈 화면이 8개 있었다).
                  centerTitle: false,
                  titleTextStyle: GoogleFonts.notoSansKr(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    shadows: KnueTokens.headerTextShadow,
                  ),
                ),
                dialogTheme: _dialogTheme(false),
                bottomSheetTheme: _bottomSheetTheme(false),
                textButtonTheme: _textButtonTheme(color),
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
                textTheme: _applyLetterSpacingDelta(
                  GoogleFonts.notoSansKrTextTheme(
                    ThemeData(brightness: Brightness.dark).textTheme,
                  ),
                  -0.4,
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
                  centerTitle: false,
                  titleTextStyle: GoogleFonts.notoSansKr(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    shadows: KnueTokens.headerTextShadow,
                  ),
                ),
                dialogTheme: _dialogTheme(true),
                bottomSheetTheme: _bottomSheetTheme(true),
                textButtonTheme: _textButtonTheme(color),
              ),
              themeMode: mode,
              home: RootNavigationScreen(key: RootNavigationScreen.navKey),
            );
          },
        );
      },
    );
  }
}
