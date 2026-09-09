import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 环境感知（15.10 定位 + 15.11 天气）
///
/// - 定位：geolocator 粗定位（城市级），结果缓存 45 分钟；开关默认关闭
/// - 天气：Open-Meteo current_weather（免 key、国际可用），依赖定位坐标
/// - 注入：与位置信息合并为一条 system 消息插入角色描述之后
/// - 失败静默跳过（返回空串），绝不打断聊天、不弹错误框
class EnvironmentProvider {
  static const _enabledKey = 'location_enabled';
  static const _positionCacheKey = 'env_position_cache';
  static const _weatherCacheKey = 'env_weather_cache';
  static const _cacheTtl = Duration(minutes: 45);

  // ===== 开关（默认关闭：敏感权限默认关） =====

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  // ===== 定位（缓存 45 分钟） =====

  static Future<({double lat, double lon, int ts})?> _getCachedPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_positionCacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final ts = (data['ts'] as num?)?.toInt() ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - ts > _cacheTtl.inMilliseconds) {
        return null;
      }
      return (
        lat: (data['lat'] as num).toDouble(),
        lon: (data['lon'] as num).toDouble(),
        ts: ts,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _cachePosition(double lat, double lon) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_positionCacheKey, jsonEncode({
      'lat': lat,
      'lon': lon,
      'ts': DateTime.now().millisecondsSinceEpoch,
    }));
  }

  /// 获取坐标（缓存优先，过期后低精度重取）；失败/权限拒绝返回 null
  static Future<({double lat, double lon})?> getPosition() async {
    final cached = await _getCachedPosition();
    if (cached != null) {
      return (lat: cached.lat, lon: cached.lon);
    }
    try {
      var enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // 仅在功能启用时请求（调用方已保证）
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      ).timeout(const Duration(seconds: 15));
      await _cachePosition(position.latitude, position.longitude);
      return (lat: position.latitude, lon: position.longitude);
    } catch (e) {
      debugPrint('environment: getPosition failed: $e');
      return null;
    }
  }

  // ===== 天气（Open-Meteo，缓存 45 分钟） =====

  static Future<String?> _getCachedWeather() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_weatherCacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final ts = (data['ts'] as num?)?.toInt() ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - ts > _cacheTtl.inMilliseconds) {
        return null;
      }
      return data['desc']?.toString();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _cacheWeather(String desc) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_weatherCacheKey, jsonEncode({
      'desc': desc,
      'ts': DateTime.now().millisecondsSinceEpoch,
    }));
  }

  /// 查询 Open-Meteo 当前天气；失败返回 null
  static Future<String?> fetchWeather(double lat, double lon) async {
    try {
      final uri = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current_weather=true&timezone=auto');
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final current = data['current_weather'];
      if (current is! Map<String, dynamic>) return null;
      final temperature = current['temperature'];
      final windspeed = current['windspeed'];
      final code = (current['weathercode'] as num?)?.toInt() ?? 0;
      final desc = wmoWeatherDescription(code);
      return '$desc，气温 $temperature°C，风速 $windspeed km/h';
    } catch (e) {
      debugPrint('environment: fetchWeather failed: $e');
      return null;
    }
  }

  /// WMO weather code → 中文描述（15.11）
  static String wmoWeatherDescription(int code) {
    switch (code) {
      case 0:
        return '晴';
      case 1:
        return '大致晴朗';
      case 2:
        return '多云';
      case 3:
        return '阴';
      case 45:
      case 48:
        return '雾';
      case 51:
      case 53:
      case 55:
        return '毛毛雨';
      case 56:
      case 57:
        return '冻毛毛雨';
      case 61:
      case 63:
      case 65:
        return '雨';
      case 66:
      case 67:
        return '冻雨';
      case 71:
      case 73:
      case 75:
      case 77:
        return '雪';
      case 80:
      case 81:
      case 82:
        return '阵雨';
      case 85:
      case 86:
        return '阵雪';
      case 95:
        return '雷阵雨';
      case 96:
      case 99:
        return '雷阵雨伴冰雹';
      default:
        return '未知天气';
    }
  }

  /// 组装注入文案；开关关闭或数据不可得时返回空串（静默跳过）
  static Future<String> buildInjection() async {
    if (!await isEnabled()) return '';

    var position = await _getCachedPosition();
    if (position == null) {
      final fresh = await getPosition();
      if (fresh == null) return '';
      position = (
        lat: fresh.lat,
        lon: fresh.lon,
        ts: DateTime.now().millisecondsSinceEpoch,
      );
    }

    // 天气缓存与坐标无关紧要（城市级精度），直接复用
    var weather = await _getCachedWeather();
    if (weather == null) {
      weather = await fetchWeather(position.lat, position.lon);
      if (weather != null) {
        await _cacheWeather(weather);
      }
    }

    final latText = position.lat.toStringAsFixed(2);
    final lonText = position.lon.toStringAsFixed(2);
    if (weather == null || weather.isEmpty) {
      return '【环境】用户当前位于北纬$latText、东经$lonText附近。';
    }
    return '【环境】用户当前位于北纬$latText、东经$lonText附近。当地天气：$weather。';
  }
}

/// 供 utils.dart 注入调用的顶层便捷函数
Future<String> getEnvironmentInjection() async {
  try {
    return await EnvironmentProvider.buildInjection();
  } catch (_) {
    // 任何异常静默跳过，不打断聊天
    return '';
  }
}
