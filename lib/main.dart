import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:home_widget/home_widget.dart';
import 'constants.dart';
import 'meal_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
                  brightness: Brightness.light,
                ),
                scaffoldBackgroundColor: const Color(0xFFF9FAFB),
                cardColor: Colors.white,
                appBarTheme: AppBarTheme(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                ),
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.dark,
                primaryColor: color,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: color,
                  primary: color,
                  brightness: Brightness.dark,
                  surface: const Color(0xFF121212),
                ),
                scaffoldBackgroundColor: const Color(0xFF121212),
                cardColor: const Color(0xFF1E1E1E),
                appBarTheme: AppBarTheme(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
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
