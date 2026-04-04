import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as Math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import '../models/location_event.dart';
import 'error_logger_service.dart';
import 'geolocator_location_provider.dart';
import 'location_provider.dart';
import 'location_settings_service.dart';
import 'native_location_provider.dart';
import 'track_recorder.dart';
import 'user_service.dart';

/// 定位服务回调类型
typedef LocationCallback = void Function(LocationEvent event);

/// 后台定位服务（单例）
/// 
/// 重构后架构：
/// - Android: ForegroundService 内置定位循环，通过 EventChannel 推送位置给 Flutter
/// - iOS: CLLocationManager 封装，通过 EventChannel 推送位置
/// - Flutter: 通过 EventChannel 接收位置，保持 subscriber 广播机制不变
/// 
/// 通知栏完全由原生服务管理，Flutter 不参与
class BackgroundLocationService {
  static final BackgroundLocationService _instance = BackgroundLocationService._();
  factory BackgroundLocationService() => _instance;
  BackgroundLocationService._();

  // MethodChannel - 用于控制服务启动/停止
  static const _methodChannel = MethodChannel('com.kenny.trace_path/location_service');
  
  // EventChannel - 用于接收原生服务推送的位置
  static const _eventChannel = EventChannel('com.kenny.trace_path/location_events');

  final LocationSettingsService _settingsService = LocationSettingsService();
  final UserService _userService = UserService();
  final ErrorLoggerService _errorLogger = ErrorLoggerService();

  /// 统一日志方法：同时输出到logcat和文件
  void log(String msg) {
    final timestamp = DateTime.now().toString().substring(11, 23);
    print('[$timestamp] [BackgroundLocationService] $msg');
    _errorLogger.logDebug(msg);
  }

  // ========== 定位提供者（工厂模式 - 用于单次定位）==========
  LocationProvider? _locationProvider;
  bool _useNativeLocation = true;

  // ========== 订阅者管理 ==========
  final List<LocationCallback> _subscribers = [];
  bool _isSubscribed = false;

  // ========== 服务状态 ==========
  StreamSubscription<dynamic>? _eventSubscription;
  bool _isServiceRunning = false;
  int _intervalSeconds = 30;
  bool _powerSaving = false;
  int _successCount = 0;
  bool _hasFirstLocation = false;

  // ========== 初始化 ==========
  Future<void> init() async {
    print('[BackgroundLocationService] ★★★ init() START ★★★');
    await _settingsService.load();
    await _errorLogger.init();
    await _errorLogger.logService(action: 'INIT');
    _initLocationProvider();
    print('[BackgroundLocationService] init: _initLocationProvider done');

    // 尝试从 Kotlin 侧恢复断线期间的轨迹数据
    print('[BackgroundLocationService] init: calling _recoverKotlinTrackData...');
    await _recoverKotlinTrackData();
    print('[BackgroundLocationService] init: _recoverKotlinTrackData done');

    // 主动请求一次当前位置（Flutter 重连后，立即在地图上显示当前位置）
    print('[BackgroundLocationService] init: calling _requestAndBroadcastCurrentLocation...');
    await _requestAndBroadcastCurrentLocation();
    print('[BackgroundLocationService] init: _requestAndBroadcastCurrentLocation done');

    // 注册 EventChannel 监听（Flutter 启动时就注册，不管服务有没有启动）
    print('[BackgroundLocationService] init: calling _listenToLocationEvents...');
    _listenToLocationEvents();
    print('[BackgroundLocationService] ★★★ init() END ★★★');
  }

  /// 主动请求当前位置并广播到地图（Flutter 重连后恢复实时显示）
  Future<void> _requestAndBroadcastCurrentLocation() async {
    try {
      print('[BackgroundLocationService] ★★★ _requestAndBroadcastCurrentLocation called ★★★');
      print('[BackgroundLocationService]   _locationProvider=${_locationProvider.runtimeType}');
      final position = await _locationProvider?.getCurrentPosition();
      if (position != null) {
        _broadcast(LocationEvent.position(position));
        _saveToLocal(position);
        print('[BackgroundLocationService] ★ 主动请求位置成功: lat=${position.latitude}, lng=${position.longitude}');
      } else {
        print('[BackgroundLocationService] 主动请求位置返回 null');
      }
    } catch (e, s) {
      print('[BackgroundLocationService] 主动请求位置失败: $e stack=$s');
    }
  }

  /// 获取 Android filesDir 路径
  Future<String?> _getFilesDir() async {
    try {
      final result = await _methodChannel.invokeMethod<String>('getFilesDir');
      return result;
    } catch (e) {
      print('[BackgroundLocationService] getFilesDir 失败: $e');
      return null;
    }
  }

  /// 从 Kotlin 的 CSV 文件恢复轨迹数据
  /// Kotlin 在 Flutter 被杀期间会持续写入 filesDir/location_tracks/track_YYYY-MM-DD.csv
  Future<void> _recoverKotlinTrackData() async {
    try {
      final filesDir = await _getFilesDir();
      if (filesDir == null) return;

      final trackDir = Directory('$filesDir/location_tracks');
      if (!await trackDir.exists()) {
        print('[BackgroundLocationService] Kotlin 轨迹目录不存在，跳过恢复');
        return;
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // 只读取今天的 Kotlin 文件（避免读取历史垃圾数据）
      final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final kotlinFile = File('${trackDir.path}/track_$dateStr.csv');

      if (!await kotlinFile.exists()) {
        print('[BackgroundLocationService] Kotlin 今日轨迹文件不存在: track_$dateStr.csv');
        return;
      }

      final lines = await kotlinFile.readAsLines();
      if (lines.length <= 1) return; // 只有表头

      int recoveredCount = 0;
      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        final parts = line.split(',');
        if (parts.length < 6) continue;

        try {
          final timestamp = int.parse(parts[0]);
          final latitude = double.parse(parts[1]);
          final longitude = double.parse(parts[2]);
          final accuracy = double.parse(parts[3]);
          final altitude = double.parse(parts[4]);
          final speed = double.parse(parts[5]);

          final position = Position(
            latitude: latitude,
            longitude: longitude,
            timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
            accuracy: accuracy,
            altitude: altitude,
            speed: speed,
            heading: 0,
            altitudeAccuracy: 0,
            headingAccuracy: 0,
            speedAccuracy: 0,
          );

          await TrackRecorder().record(position);
          recoveredCount++;
        } catch (e) {
          // 解析失败跳过
        }
      }

      if (recoveredCount > 0) {
        print('[BackgroundLocationService] 从 Kotlin 侧恢复了 $recoveredCount 个轨迹点');
        await _errorLogger.logService(action: 'KOTLIN_TRACK_RECOVERED', extra: 'count=$recoveredCount');
      }
    } catch (e) {
      print('[BackgroundLocationService] 恢复 Kotlin 轨迹数据失败: $e');
    }
  }

  void _initLocationProvider() {
    _locationProvider?.dispose();
    if (_useNativeLocation) {
      _locationProvider = NativeLocationProvider();
      print('[BackgroundLocationService] 定位提供者: NativeLocationProvider');
    } else {
      _locationProvider = GeolocatorLocationProvider();
      print('[BackgroundLocationService] 定位提供者: GeolocatorLocationProvider');
    }
  }

  void setUseNativeLocation(bool useNative) {
    if (_useNativeLocation == useNative) return;
    _useNativeLocation = useNative;
    _initLocationProvider();
    print('[BackgroundLocationService] 切换定位方式: _useNativeLocation=$_useNativeLocation');
  }

  /// 订阅定位更新
  /// 返回 unsubscribe 函数
  VoidCallback subscribe(LocationCallback callback) {
    _subscribers.add(callback);
    _isSubscribed = _subscribers.isNotEmpty;
    return () {
      _subscribers.remove(callback);
      _isSubscribed = _subscribers.isNotEmpty;
    };
  }

  void _broadcast(LocationEvent event) {
    if (!_isSubscribed) return;
    for (final callback in _subscribers) {
      try {
        callback(event);
      } catch (e) {
        print('[BackgroundLocationService] 广播异常: $e');
      }
    }
  }

  // ========== 服务控制 ==========
  /// 启动服务
  Future<bool> start() async {
    try {
      // 检查权限
      final hasPermission = await _locationProvider?.checkPermission() ?? false;
      if (!hasPermission) {
        print('[BackgroundLocationService] start: 权限检查失败');
        await _errorLogger.logPermission(permission: 'LOCATION', reason: 'PERMISSION_DENIED');
        _broadcast(LocationEvent.error('定位权限被拒绝'));
        return false;
      }

      // Android 13+ 需要通知权限
      if (Platform.isAndroid) {
        final notifStatus = await Permission.notification.status;
        if (notifStatus.isDenied) {
          final result = await Permission.notification.request();
          if (!result.isGranted) {
            print('[BackgroundLocationService] 通知权限被拒绝');
            await _errorLogger.logPermission(permission: 'NOTIFICATION', reason: 'PERMISSION_DENIED');
          }
        }
      }

      // 确认最新设置值
      await _settingsService.load();
      _intervalSeconds = _settingsService.settings.intervalSeconds;
      _powerSaving = _settingsService.settings.powerSaving;

      // 启动原生前台服务（通过 MethodChannel）
      await _methodChannel.invokeMethod('startLocationService', {
        'interval': _intervalSeconds,
        'powerSaving': _powerSaving,
      });

      // 监听原生服务推送的位置（通过 EventChannel）
      _listenToLocationEvents();

      // 更新设置状态
      await _settingsService.update(enabled: true);
      _isServiceRunning = true;

      _broadcast(LocationEvent.serviceStart());

      print('[BackgroundLocationService] 服务启动成功');
      await _errorLogger.logService(action: 'START_SUCCESS');
      return true;
    } catch (e) {
      print('[BackgroundLocationService] start 异常: $e');
      _broadcast(LocationEvent.error(e.toString()));
      return false;
    }
  }

  /// 停止服务
  Future<void> stop() async {
    try {
      // 取消 EventChannel 监听
      await _eventSubscription?.cancel();
      _eventSubscription = null;

      await _settingsService.update(enabled: false);
      await _methodChannel.invokeMethod('stopLocationService');

      _isServiceRunning = false;
      _broadcast(LocationEvent.serviceStop());

      print('[BackgroundLocationService] 服务已停止');
      await _errorLogger.logService(action: 'STOP_SUCCESS');
    } catch (e) {
      print('[BackgroundLocationService] stop 异常: $e');
      await _errorLogger.logService(action: 'STOP_FAILED', extra: 'error=$e');
    }
  }

  /// 更新配置（热更新）
  Future<void> updateSettings({
    int? intervalSeconds,
    bool? powerSaving,
  }) async {
    await _settingsService.update(
      intervalSeconds: intervalSeconds,
      powerSaving: powerSaving,
    );

    _intervalSeconds = _settingsService.settings.intervalSeconds;
    _powerSaving = _settingsService.settings.powerSaving;

    // 通知原生服务更新配置
    try {
      await _methodChannel.invokeMethod('updateLocationConfig', {
        'interval': _intervalSeconds,
        'powerSaving': _powerSaving,
      });
    } catch (e) {
      print('[BackgroundLocationService] updateConfig 异常: $e');
    }
  }

  /// 是否正在运行
  Future<bool> checkRunning() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('isLocationServiceRunning');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  // ========== EventChannel 监听 ==========
  /// 监听原生服务推送的位置
  void _listenToLocationEvents() {
    print('[BackgroundLocationService] ★★★ _listenToLocationEvents called ★★★');
    _eventSubscription?.cancel();
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        print('[BackgroundLocationService] EventChannel received event: ${event.runtimeType}');
        _handleLocationEvent(event);
      },
      onError: (dynamic error) {
        print('[BackgroundLocationService] EventChannel error: $error');
        _errorLogger.logService(action: 'EVENT_CHANNEL_ERROR', extra: 'error=$error');
      },
    );
    print('[BackgroundLocationService] EventChannel listener registered');
  }

  /// 处理原生服务推送的位置
  void _handleLocationEvent(dynamic event) {
    print('[BackgroundLocationService] ★★★ _handleLocationEvent called ★★★ event=${event.runtimeType}: $event');

    if (event is! Map) {
      print('[BackgroundLocationService] Invalid event type: ${event.runtimeType}');
      return;
    }

    try {
      final latitude = (event['latitude'] as num?)?.toDouble();
      final longitude = (event['longitude'] as num?)?.toDouble();
      final accuracy = (event['accuracy'] as num?)?.toDouble();
      final altitude = (event['altitude'] as num?)?.toDouble() ?? 0.0;
      final speed = (event['speed'] as num?)?.toDouble() ?? 0.0;
      final timestamp = (event['timestamp'] as num?)?.toInt();

      if (latitude == null || longitude == null) {
        print('[BackgroundLocationService] Invalid location data: $event');
        return;
      }

      print('[BackgroundLocationService] ★ 收到EventChannel位置: lat=$latitude, lng=$longitude, acc=$accuracy');

      // 构造 Position 对象
      final position = Position(
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy ?? 0.0,
        altitude: altitude,
        speed: speed,
        heading: 0.0,
        timestamp: timestamp != null
            ? DateTime.fromMillisecondsSinceEpoch(timestamp)
            : DateTime.now(),
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
        speedAccuracy: 0.0,
      );

      _successCount++;

      // 首次定位记录
      if (!_hasFirstLocation) {
        _hasFirstLocation = true;
        _errorLogger.logFirstLocation(
          lat: latitude,
          lng: longitude,
          accuracy: accuracy ?? 0.0,
        );
      }

      // 每10次成功记录一次
      if (_successCount % 10 == 0) {
        _errorLogger.logGpsSuccess(
          lat: latitude,
          lng: longitude,
          accuracy: accuracy ?? 0.0,
          successCount: _successCount,
        );
      }

      // 广播位置给所有订阅者
      _broadcast(LocationEvent.position(position));

      // 保存到本地
      _saveToLocal(position);

    } catch (e) {
      print('[BackgroundLocationService] 处理位置事件异常: $e');
      _errorLogger.logService(action: 'EVENT_HANDLE_ERROR', extra: 'error=$e');
    }
  }

  /// 保存位置到本地
  Future<void> _saveToLocal(Position position) async {
    try {
      await TrackRecorder().record(position);
    } catch (e) {
      print('[BackgroundLocationService] 保存位置失败: $e');
    }
  }

  // ========== 单次定位（委托给 LocationProvider - 用于非持续定位场景）==========
  Future<Position?> getCurrentPosition() async {
    log('========== 单次定位请求 ==========');
    log('定位参数: provider=${_useNativeLocation ? "Native" : "Geolocator"}');
    return await _locationProvider?.getCurrentPosition();
  }

  // ========== 坐标转换 ==========
  List<double> wgs84ToGcj02(double lat, double lon) {
    const double pi = 3.1415926535897932384626;
    const double a = 6378245.0;
    const double ee = 0.00669342162296594323;

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

  List<double> gcj02ToWgs84(double lat, double lon) {
    double wgs84Lat = lat;
    double wgs84Lon = lon;
    for (int i = 0; i < 5; i++) {
      final gcj = wgs84ToGcj02(wgs84Lat, wgs84Lon);
      wgs84Lat += lat - gcj[0];
      wgs84Lon += lon - gcj[1];
    }
    return [wgs84Lat, wgs84Lon];
  }

  // ========== 逆地址解析 ==========
  Future<String?> getAddressFromLatLng(double lat, double lng) async {
    try {
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
    _subscribers.clear();
    _locationProvider?.dispose();
  }
}
