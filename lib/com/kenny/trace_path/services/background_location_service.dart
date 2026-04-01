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
import 'location_settings_service.dart';
import 'track_recorder.dart';
import 'user_service.dart';

/// 定位服务回调类型
typedef LocationCallback = void Function(LocationEvent event);

/// 后台定位服务（单例）
/// 统一管理定位，作为消息中心向各订阅者分发位置更新
class BackgroundLocationService {
  static final BackgroundLocationService _instance = BackgroundLocationService._();
  factory BackgroundLocationService() => _instance;
  BackgroundLocationService._();

  static const _channel = MethodChannel('com.kenny.trace_path/location_service');

  final LocationSettingsService _settingsService = LocationSettingsService();
  final UserService _userService = UserService();
  final ErrorLoggerService _errorLogger = ErrorLoggerService();

  // ========== 订阅者管理 ==========
  final List<LocationCallback> _subscribers = [];
  bool _isSubscribed = false;

  // ========== 定位状态 ==========
  Timer? _locationTimer;
  Timer? _gpsRetryTimer; // GPS失败重试定时器
  bool _isTracking = false;
  int _intervalSeconds = 30;
  bool _powerSaving = false;
  int _successCount = 0; // 成功计数，用于每10次记录一次日志
  int _gpsRetryCount = 0; // GPS重试次数
  bool _gpsRetryInProgress = false; // 是否正在进行GPS重试
  bool _hasFirstLocation = false; // 是否已有首次定位
  bool _isManualRefresh = false; // 是否是手动刷新

  // GPS重试参数：最大5次，指数退避最大5分钟
  static const int _maxGpsRetryCount = 5;
  static const int _baseGpsRetryDelaySec = 15;
  static const int _maxGpsRetryDelaySec = 300;

  // ========== 初始化 ==========
  Future<void> init() async {
    await _settingsService.load();
    await _errorLogger.init();
    await _errorLogger.logService(action: 'INIT');
  }

  /// 订阅定位更新
  /// 返回 unsubscribe 函数
  VoidCallback subscribe(LocationCallback callback) {
    _subscribers.add(callback);
    _isSubscribed = _subscribers.isNotEmpty;
    
    // 返回取消订阅的函数
    return () {
      _subscribers.remove(callback);
      _isSubscribed = _subscribers.isNotEmpty;
    };
  }

  /// 向所有订阅者广播事件
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
  /// 启动服务（前台通知栏保活）
  Future<bool> start() async {
    try {
      // 检查权限
      final hasPermission = await _checkPermission();
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

      // 启动原生前台服务（只保活）
      await _channel.invokeMethod('start', {
        'interval': _intervalSeconds,
        'powerSaving': _powerSaving,
      });

      // 更新设置状态
      await _settingsService.update(enabled: true);

      // 启动 Dart 层的定位循环
      _startLocationLoop();

      // 立即触发一次定位（不等定时器）
      _fetchAndBroadcastLocation();

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
      _stopLocationLoop();
      
      await _settingsService.update(enabled: false);
      await _channel.invokeMethod('stop');
      
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

    // 如果正在追踪，重启定位循环
    if (_isTracking) {
      _stopLocationLoop();
      _startLocationLoop();
    }

    // 通知原生服务更新配置
    try {
      await _channel.invokeMethod('updateConfig', {
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
      final result = await _channel.invokeMethod<bool>('isRunning');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  // ========== 定位循环 ==========
  void _startLocationLoop() {
    if (_isTracking) return;
    
    _isTracking = true;
    _scheduleNextLocation();
  }

  void _stopLocationLoop() {
    _isTracking = false;
    _locationTimer?.cancel();
    _locationTimer = null;
    _gpsRetryTimer?.cancel();
    _gpsRetryTimer = null;
    _gpsRetryCount = 0;
    _gpsRetryInProgress = false;
  }

  void _scheduleNextLocation() {
    if (!_isTracking) return;
    
    _locationTimer?.cancel();
    
    // 如果GPS重试正在进行中，跳过本次定时调度，等重试处理
    if (_gpsRetryInProgress) {
      print('[BackgroundLocationService] GPS重试进行中，跳过本次定时调度');
      return;
    }
    
    // 计算实际间隔（省电模式用更长间隔，最小30秒）
    int actualInterval = _powerSaving ? Math.max(_intervalSeconds, 60) : _intervalSeconds;
    print('[BackgroundLocationService] 🔄 调度下次定位，_intervalSeconds=${_intervalSeconds}s, actualInterval=${actualInterval}s, _powerSaving=${_powerSaving}');
    
    _locationTimer = Timer(Duration(seconds: actualInterval), () async {
      print('[BackgroundLocationService] ⏰ 定时器触发！isTracking=$_isTracking');
      if (!_isTracking) return;
      
      final success = await _fetchAndBroadcastLocation();
      // 成功后继续调度；失败时由 _fetchAndBroadcastLocation 内部调度了GPS重试
      if (success) {
        _scheduleNextLocation();
      }
    });
  }

  /// GPS失败后调度指数退避重试
  void _scheduleGpsRetry() {
    // 最多重试 _maxGpsRetryCount 次
    if (_gpsRetryCount >= _maxGpsRetryCount) {
      print('[BackgroundLocationService] GPS重试次数已达上限(${_maxGpsRetryCount})，停止重试，等待下次定时触发');
      _gpsRetryCount = 0;
      _gpsRetryInProgress = false;
      return;
    }
    
    _gpsRetryInProgress = true;
    
    // 指数退避: 15s -> 30s -> 60s -> 120s -> 240s，上限5分钟
    int delay = _baseGpsRetryDelaySec * (1 << _gpsRetryCount);
    if (delay > _maxGpsRetryDelaySec) delay = _maxGpsRetryDelaySec;
    
    print('[BackgroundLocationService] 调度GPS重试(${_gpsRetryCount + 1}/$_maxGpsRetryCount)，${delay}s后');
    
    _gpsRetryTimer?.cancel();
    _gpsRetryTimer = Timer(Duration(seconds: delay), () async {
      if (!_isTracking) return;
      
      _gpsRetryCount++;
      print('[BackgroundLocationService] GPS重试计时器触发，开始重试定位...');
      
      final position = await getCurrentPosition();
      if (position != null) {
        _gpsRetryCount = 0;
        _gpsRetryInProgress = false;
        
        print('[BackgroundLocationService] GPS重试成功: lat=${position.latitude}, lng=${position.longitude}');
        _broadcast(LocationEvent.position(position));
        await _saveToLocal(position);
        
        // 重试成功后继续正常调度
        _scheduleNextLocation();
      } else {
        print('[BackgroundLocationService] GPS重试仍然失败');
        // 继续调度下一次重试
        _scheduleGpsRetry();
      }
    });
  }

  Future<bool> _fetchAndBroadcastLocation() async {
    print('[BackgroundLocationService] 📍 _fetchAndBroadcastLocation 开始');
    // 记录定位请求及关键参数（方便排查问题）
    final params = [
      'interval=${_intervalSeconds}s',
      'powerSaving=$_powerSaving',
      'accuracy=best',
      'gpsTimeout=15s',
      'netTimeout=10s',
    ];
    await _errorLogger.logService(
      action: _isManualRefresh ? 'MANUAL_REFRESH_REQUEST' : 'AUTO_LOCATION_REQUEST',
      extra: params.join(' '),
    );
    
    final position = await getCurrentPosition();
    if (position != null) {
      _successCount++;
      
      print('[BackgroundLocationService] 定位成功: lat=${position.latitude}, lng=${position.longitude}, acc=${position.accuracy}m');
      _broadcast(LocationEvent.position(position));
      
      // 首次定位记录
      if (!_hasFirstLocation) {
        _hasFirstLocation = true;
        await _errorLogger.logFirstLocation(
          lat: position.latitude,
          lng: position.longitude,
          accuracy: position.accuracy,
        );
      }
      
      // 每10次成功记录一次
      if (_successCount % 10 == 0) {
        await _errorLogger.logGpsSuccess(
          lat: position.latitude,
          lng: position.longitude,
          accuracy: position.accuracy,
          successCount: _successCount,
        );
      }
      
      // 同时保存到本地
      await _saveToLocal(position);
      
      // 成功后重置GPS重试状态
      _gpsRetryCount = 0;
      _gpsRetryInProgress = false;
      
      // 重置手动刷新标志
      _isManualRefresh = false;
      print('[BackgroundLocationService] ✅ _fetchAndBroadcastLocation 结束（成功）');
      return true;
    } else {
      print('[BackgroundLocationService] ❌ _fetchAndBroadcastLocation 结束（失败）');
      print('[BackgroundLocationService] 定位失败，未获取到有效位置');
      await _errorLogger.logGpsFail(reason: 'NO_POSITION_RETURNED');
      
      // GPS失败时调度立即重试（不等定时器）
      _scheduleGpsRetry();
      
      // 重置手动刷新标志
      _isManualRefresh = false;
      print('[BackgroundLocationService] ❌ _fetchAndBroadcastLocation 结束（失败-重试）');
      return false;
    }
  }

  /// 保存位置到本地（通过 TrackRecorder）
  Future<void> _saveToLocal(Position position) async {
    try {
      await TrackRecorder().record(position);
    } catch (e) {
      print('[BackgroundLocationService] 保存位置失败: $e');
    }
  }

  // ========== 权限检查 ==========
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

  // ========== 单次定位（GPS → 网络 fallback）==========
  /// 获取当前位置（WGS84转GCJ-02用于高德地图显示）
  Future<Position?> getCurrentPosition() async {
    String timeStr(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}.${t.millisecond.toString().padLeft(3, '0')}';

    try {
      // === 请求开始：记录定位参数 ===
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      LocationPermission permission = await Geolocator.checkPermission();
      final logParams = [
        'serviceEnabled=$serviceEnabled',
        'permission=$permission',
        'interval=${_intervalSeconds}s',
        'powerSaving=$_powerSaving',
        'gpsAccuracy=best',
        'gpsTimeout=15s',
        'gpsAccThresh=50m',
        'netAccuracy=medium',
        'netTimeout=10s',
        'netAccThresh=200m',
      ];
      print('[BackgroundLocationService] ========== 定位请求开始 ==========');
      print('[BackgroundLocationService] 定位参数: ${logParams.join(', ')}');

      if (!serviceEnabled) {
        print('[BackgroundLocationService] 定位服务未开启');
        await _errorLogger.logGpsFail(reason: 'LOCATION_SERVICE_DISABLED');
        return null;
      }

      final hasPermission = await _checkPermission();
      if (!hasPermission) {
        print('[BackgroundLocationService] GPS permission denied');
        await _errorLogger.logPermission(permission: 'LOCATION', reason: 'PERMISSION_DENIED');
        return null;
      }

      // 策略1: 优先 GPS（精度阈值 50m：室外 GPS 良好时一般 3-30m，50m 可过滤掉信号差的结果）
      Position? position = await _getGpsPosition(timeStr);
      if (position != null && position.accuracy < 50) {
        return position; // 返回原始 WGS84
      }

      // 策略2: GPS 失败或精度差 → 网络定位（城市 Wi-Fi/基站 20-100m，乡村 100-500m，接受 <200m 的结果）
      print('[BackgroundLocationService] GPS 定位失败或精度差（acc=${position?.accuracy ?? 'null'}m），尝试网络定位...');
      position = await _getNetworkPosition(timeStr);
      if (position != null && position.accuracy < 200) {
        return position; // 返回原始 WGS84
      }

      print('[BackgroundLocationService] 所有定位方式均失败');
      await _errorLogger.logGpsFail(reason: 'ALL_METHODS_FAILED');
      return null;
    } catch (e, st) {
      print('[BackgroundLocationService] getCurrentPosition 异常: type=${e.runtimeType}, message=$e');
      print('[BackgroundLocationService] getCurrentPosition stackTrace: $st');
      await _errorLogger.logGpsFail(reason: 'EXCEPTION', extra: 'type=${e.runtimeType}, msg=$e\n$st');
      return null;
    }
  }

  Future<Position?> _getGpsPosition(String Function(DateTime) timeStr) async {
    try {
      print('[BackgroundLocationService] 尝试 GPS 定位...');
      print('[BackgroundLocationService] GPS params: accuracy=best, timeLimit=15s');
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 15),
      );
      print('[BackgroundLocationService] GPS 定位成功: acc=${position.accuracy}m');
      return position;
    } catch (e, st) {
      String reason = 'GPS_TIMEOUT';
      if (e.toString().contains('PERMISSION_DENIED')) {
        reason = 'GPS_PERMISSION_DENIED';
      } else if (e.toString().contains('LOCATION_SERVICE_DISABLED')) {
        reason = 'GPS_SERVICE_DISABLED';
      } else if (e.toString().contains('timeout')) {
        reason = 'GPS_TIMEOUT';
      } else {
        reason = 'GPS_UNKNOWN';
      }
      print('[BackgroundLocationService] ========== GPS 定位失败 ==========');
      print('[BackgroundLocationService] GPS FAIL: type=${e.runtimeType}, message=$e');
      print('[BackgroundLocationService] GPS FAIL stackTrace:\n$st');
      print('[BackgroundLocationService] GPS FAIL reason=$reason');
      await _errorLogger.logGpsFail(reason: reason, accuracy: null, timeout: 15, extra: 'type=${e.runtimeType}\n$e\n$st');
      return null;
    }
  }

  Future<Position?> _getNetworkPosition(String Function(DateTime) timeStr) async {
    try {
      print('[BackgroundLocationService] 尝试网络定位...');
      print('[BackgroundLocationService] Network params: accuracy=medium, timeLimit=10s');
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );
      print('[BackgroundLocationService] 网络定位成功: acc=${position.accuracy}m');
      return position;
    } catch (e, st) {
      String reason = 'NETWORK_TIMEOUT';
      if (e.toString().contains('PERMISSION_DENIED')) {
        reason = 'NETWORK_PERMISSION_DENIED';
      } else if (e.toString().contains('NETWORK')) {
        reason = 'NETWORK_UNAVAILABLE';
      } else if (e.toString().contains('timeout')) {
        reason = 'NETWORK_TIMEOUT';
      } else {
        reason = 'NETWORK_UNKNOWN';
      }
      print('[BackgroundLocationService] ========== 网络定位失败 ==========');
      print('[BackgroundLocationService] Network FAIL: type=${e.runtimeType}, message=$e');
      print('[BackgroundLocationService] Network FAIL stackTrace:\n$st');
      print('[BackgroundLocationService] Network FAIL reason=$reason');
      await _errorLogger.logNetworkFail(reason: reason, timeout: 10, extra: 'type=${e.runtimeType}\n$e\n$st');
      return null;
    }
  }

  /// WGS84 坐标系转 GCJ-02 坐标系（供显示层调用）
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

  /// GCJ-02 坐标系转 WGS84 坐标系（逆转换，用于地址解析）
  List<double> gcj02ToWgs84(double lat, double lon) {
    double wgs84Lat = lat;
    double wgs84Lon = lon;
    // 迭代逼近，通常5次足够
    for (int i = 0; i < 5; i++) {
      final gcj = wgs84ToGcj02(wgs84Lat, wgs84Lon);
      wgs84Lat += lat - gcj[0];
      wgs84Lon += lon - gcj[1];
    }
    return [wgs84Lat, wgs84Lon];
  }

  // ========== 逆地址解析 ==========
  /// 根据经纬度获取地址描述
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
  }
}
