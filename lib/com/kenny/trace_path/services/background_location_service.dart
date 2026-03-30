import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as Math;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'location_settings_service.dart';

/// 后台定位服务（使用原生 Android 前台服务）
/// 通过 MethodChannel 控制 LocationForegroundService
class BackgroundLocationService {
  static final BackgroundLocationService _instance = BackgroundLocationService._();
  factory BackgroundLocationService() => _instance;
  BackgroundLocationService._();

  static const _channel = MethodChannel('com.kenny.trace_path/location_service');

  final LocationSettingsService _settingsService = LocationSettingsService();

  /// 初始化
  Future<void> init() async {
    await _settingsService.load();
  }

  /// 启动服务
  Future<bool> start() async {
    try {
      // 检查权限
      final hasPermission = await _checkPermission();
      if (!hasPermission) {
        print('[BackgroundLocationService] start: 权限检查失败');
        return false;
      }

      // Android 13+ 需要通知权限
      if (Platform.isAndroid) {
        final notifStatus = await Permission.notification.status;
        print('[BackgroundLocationService] 通知权限状态: $notifStatus');
        if (notifStatus.isDenied) {
          print('[BackgroundLocationService] 请求通知权限...');
          final result = await Permission.notification.request();
          print('[BackgroundLocationService] 通知权限请求结果: $result');
        }
      }

      // 确认最新设置值
      await _settingsService.load();
      final interval = _settingsService.settings.intervalSeconds;
      final powerSaving = _settingsService.settings.powerSaving;

      print('[BackgroundLocationService] start: interval=${interval}s, powerSaving=$powerSaving');

      // 启动原生前台服务（带配置）
      await _channel.invokeMethod('start', {
        'interval': interval,
        'powerSaving': powerSaving,
      });

      print('[BackgroundLocationService] start: invokeMethod(start) 完成');
      return true;
    } catch (e) {
      print('[BackgroundLocationService] start 异常: $e');
      return false;
    }
  }

  /// 停止服务
  Future<void> stop() async {
    try {
      await _settingsService.update(enabled: false);
      await _channel.invokeMethod('stop');
    } catch (e) {
      print('[BackgroundLocationService] stop 异常: $e');
    }
  }

  /// 检查权限
  Future<bool> _checkPermission() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return false;
      }

      if (permission == LocationPermission.deniedForever) return false;

      return true;
    } catch (e) {
      print('[BackgroundLocationService] 权限检查异常: $e');
      return false;
    }
  }

  /// 获取当前位置（WGS84转GCJ-02用于高德地图显示）
  /// 实现了 GPS → 网络定位 的 fallback 策略
  Future<Position?> getCurrentPosition() async {
    String timeStr(DateTime t) => '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}:${t.second.toString().padLeft(2,'0')}.${t.millisecond.toString().padLeft(3,'0')}';
    
    try {
      final hasPermission = await _checkPermission();
      if (!hasPermission) {
        print('[BackgroundLocationService] GPS permission denied, time=${timeStr(DateTime.now())}');
        return null;
      }

      // ========== 策略1: 优先 GPS ==========
      final reqStart = DateTime.now();
      print('[BackgroundLocationService] GPS request START, time=${timeStr(reqStart)}');
      
      Position? position = await _getGpsPosition(timeStr);
      
      if (position != null && position.accuracy < 100) {
        // GPS 定位成功且精度 < 100米
        print('[BackgroundLocationService] GPS 定位成功, time=${timeStr(DateTime.now())}, acc=${position.accuracy}m');
        return _convertToGcj02(position);
      }

      // ========== 策略2: GPS 失败或精度差 → 网络定位 ==========
      print('[BackgroundLocationService] GPS 定位失败或精度差，尝试网络定位...');
      position = await _getNetworkPosition(timeStr);
      
      if (position != null) {
        print('[BackgroundLocationService] 网络定位成功, time=${timeStr(DateTime.now())}, acc=${position.accuracy}m');
        return _convertToGcj02(position);
      }

      // ========== 策略3: 全部失败 ==========
      print('[BackgroundLocationService] 所有定位方式均失败');
      return null;
    } catch (e) {
      print('[BackgroundLocationService] getCurrentPosition 异常: $e');
      return null;
    }
  }

  /// 获取 GPS 定位
  Future<Position?> _getGpsPosition(String Function(DateTime) timeStr) async {
    try {
      final reqStart = DateTime.now();
      print('[BackgroundLocationService] GPS START, time=${timeStr(reqStart)}');
      
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 15),  // 15秒超时
      );
      
      final diff = DateTime.now().difference(reqStart);
      print('[BackgroundLocationService] GPS result, time=${timeStr(DateTime.now())}, diff=${diff.inMilliseconds}ms, acc=${position.accuracy}m');
      
      return position;
    } catch (e) {
      print('[BackgroundLocationService] GPS 异常: $e');
      return null;
    }
  }

  /// 获取网络定位（Wi-Fi/基站）
  Future<Position?> _getNetworkPosition(String Function(DateTime) timeStr) async {
    try {
      final reqStart = DateTime.now();
      print('[BackgroundLocationService] Network START, time=${timeStr(reqStart)}');
      
      // 使用低功耗模式请求网络定位
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),  // 网络定位通常更快
      );
      
      final diff = DateTime.now().difference(reqStart);
      print('[BackgroundLocationService] Network result, time=${timeStr(DateTime.now())}, diff=${diff.inMilliseconds}ms, acc=${position.accuracy}m');
      
      return position;
    } catch (e) {
      print('[BackgroundLocationService] Network 异常: $e');
      return null;
    }
  }

  /// 坐标系转换（WGS84 → GCJ-02）
  Position _convertToGcj02(Position position) {
    final gcj02 = wgs84ToGcj02(position.latitude, position.longitude);
    return Position(
      latitude: gcj02[0],
      longitude: gcj02[1],
      timestamp: position.timestamp,
      accuracy: position.accuracy,
      altitude: position.altitude,
      altitudeAccuracy: position.altitudeAccuracy,
      heading: position.heading,
      headingAccuracy: position.headingAccuracy,
      speed: position.speed,
      speedAccuracy: position.speedAccuracy,
    );
  }

  /// WGS84 坐标系转 GCJ-02 坐标系（用于中国境内高德/腾讯地图）
  List<double> wgs84ToGcj02(double lat, double lon) {
    const double pi = 3.1415926535897932384626;
    const double a = 6378245.0; // 地球长半轴
    const double ee = 0.00669342162296594323; // 扁率

    double dLat = _transformLat(lon - 105.0, lat - 35.0);
    double dLon = _transformLon(lon - 105.0, lat - 35.0);

    double radLat = lat / 180.0 * pi;
    double sinLat = Math.sin(radLat);
    double cosLat = Math.cos(radLat);
    double magic = 1 - ee * sinLat * sinLat;
    double sqrtMagic = Math.sqrt(magic);

    dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * pi);
    dLon = (dLon * 180.0) / (a / sqrtMagic * cosLat * pi);

    return [lat + dLat, lon + dLon];
  }

  double _transformLat(double x, double y) {
    const double pi = 3.1415926535897932384626;
    double ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y;
    double sqrtX = x >= 0 ? x : -x;
    ret += 0.2 * Math.sqrt(sqrtX);
    ret += (20.0 * Math.sin(6.0 * x * pi) + 20.0 * Math.sin(2.0 * x * pi)) * 2.0 / 3.0;
    ret += (20.0 * Math.sin(y * pi) + 40.0 * Math.sin(y / 3.0 * pi)) * 2.0 / 3.0;
    ret += (160.0 * Math.sin(y / 12.0 * pi) + 320.0 * Math.sin(y * pi / 30.0)) * 2.0 / 3.0;
    return ret;
  }

  double _transformLon(double x, double y) {
    const double pi = 3.1415926535897932384626;
    double ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y;
    double sqrtX = x >= 0 ? x : -x;
    ret += 0.1 * Math.sqrt(sqrtX);
    ret += (20.0 * Math.sin(6.0 * x * pi) + 20.0 * Math.sin(2.0 * x * pi)) * 2.0 / 3.0;
    ret += (20.0 * Math.sin(x * pi) + 40.0 * Math.sin(x / 3.0 * pi)) * 2.0 / 3.0;
    ret += (150.0 * Math.sin(x / 12.0 * pi) + 300.0 * Math.sin(x / 30.0 * pi)) * 2.0 / 3.0;
    return ret;
  }

  /// 更新设置（热更新）
  Future<void> updateSettings({
    int? intervalSeconds,
    bool? powerSaving,
  }) async {
    await _settingsService.update(
      intervalSeconds: intervalSeconds,
      powerSaving: powerSaving,
    );

    // 通知原生服务更新配置
    try {
      await _channel.invokeMethod('updateConfig', {
        'interval': _settingsService.settings.intervalSeconds,
        'powerSaving': _settingsService.settings.powerSaving,
      });
    } catch (e) {
      print('[BackgroundLocationService] updateConfig 异常: $e');
    }
  }

  /// 是否正在运行
  Future<bool> checkRunning() async {
    try {
      final result = await _channel.invokeMethod<bool>('isRunning');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 根据经纬度获取地址描述（逆地址解析）
  /// 使用 Nominatim (OpenStreetMap) 免费服务
  Future<String?> getAddressFromLatLng(double lat, double lng) async {
    try {
      // 使用 OpenStreetMap Nominatim API (免费，无需API Key)
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1',
      );
      
      final response = await http.get(
        url,
        headers: {'User-Agent': 'TracePath/1.0'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['address'] != null) {
          final address = data['address'];
          final road = address['road'] ?? '';
          final suburb = address['suburb'] ?? '';
          final city = address['city'] ?? address['town'] ?? address['village'] ?? '';
          final district = address['city_district'] ?? address['district'] ?? '';
          
          // 构建地址: 城市 + 区/县 + 街道
          String result = '';
          if (city.isNotEmpty) result += city;
          if (district.isNotEmpty && district != city) result += district;
          if (suburb.isNotEmpty && suburb != district && suburb != city) result += suburb;
          if (road.isNotEmpty) result += road;
          
          return result.isEmpty ? null : result;
        }
      }
      return null;
    } catch (e) {
      print('[BackgroundLocationService] getAddressFromLatLng error: $e');
      return null;
    }
  }

  Future<void> dispose() async {
    await stop();
  }
}
