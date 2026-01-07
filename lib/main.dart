import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // [수정] import 추가
import 'constants.dart';
import 'meal_screen.dart';
import 'alarm_service.dart'; // [수정] 알람 초기화를 위해 필요 (없다면 constants.dart의 NotificationService 사용)

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // .env 파일 로드 (예외 처리 추가)
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    print(".env Load Error: $e");
  }

  await initializeDateFormatting();
  
  // 알람 초기화
  await NotificationService().init();

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
              title: 'KNUE All-in-One',
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