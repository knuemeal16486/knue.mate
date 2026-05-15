import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class WeatherData {
  final double temperature;
  final int weatherCode;
  final bool isDay;

  const WeatherData({
    required this.temperature,
    required this.weatherCode,
    required this.isDay,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    final cw = json['current_weather'] as Map<String, dynamic>;
    return WeatherData(
      temperature: (cw['temperature'] as num).toDouble(),
      weatherCode: (cw['weathercode'] as num).toInt(),
      isDay: (cw['is_day'] as num) == 1,
    );
  }

  IconData get icon {
    if (weatherCode == 0) {
      return isDay ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded;
    }
    if (weatherCode <= 2) return Icons.cloud_queue_rounded;
    if (weatherCode == 3) return Icons.cloud_rounded;
    if (weatherCode <= 49) return Icons.foggy;
    if (weatherCode <= 67) return Icons.grain_rounded;
    if (weatherCode <= 77) return Icons.ac_unit_rounded;
    if (weatherCode <= 82) return Icons.umbrella_rounded;
    return Icons.thunderstorm_rounded;
  }

  String get description {
    if (weatherCode == 0) return '맑음';
    if (weatherCode <= 2) return '구름 조금';
    if (weatherCode == 3) return '흐림';
    if (weatherCode <= 49) return '안개';
    if (weatherCode <= 55) return '이슬비';
    if (weatherCode <= 67) return '비';
    if (weatherCode <= 77) return '눈';
    if (weatherCode <= 82) return '소나기';
    return '천둥번개';
  }
}

class WeatherService {
  // 한국교원대학교 좌표 (충북 청주시 강내면)
  static const double _lat = 36.6083;
  static const double _lng = 127.3600;

  static WeatherData? _cache;
  static DateTime? _cacheTime;
  static const _ttl = Duration(minutes: 30);

  static Future<WeatherData?> getCurrent() async {
    if (_cache != null && _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _ttl) {
      return _cache;
    }
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$_lat&longitude=$_lng'
        '&current_weather=true'
        '&timezone=Asia%2FSeoul',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _cache = WeatherData.fromJson(data);
        _cacheTime = DateTime.now();
        return _cache;
      }
    } catch (e) {
      debugPrint('WeatherService error: $e');
    }
    return _cache; // 실패 시 마지막 캐시 반환
  }
}
