import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/location_event.dart';
import '../utils/coordinate_utils.dart';
import '../utils/logger.dart';
import 'address_resolver.dart';
import 'geolocator_location_provider.dart';
import 'kotlin_track_recovery.dart';
import 'location_event_handler.dart';
import 'location_provider.dart';
import 'location_settings_service.dart';
import 'native_location_provider.dart';
import 'track_recorder.dart';
import 'user_service.dart';

/// 定位服务回调类型
typedef LocationCallback = void Function(LocationEvent event);

/// 后台定位服务（单例）
///
/// 架构说明：
/// - Android: ForegroundService 内置定位循环，通过 EventChannel 推送位置给 Flutter
/// - iOS: CLLocationManager 封装，通过 EventChannel 推送位置
/// - Flutter: 通过 EventChannel 接收位置，保持 subscriber 广播机制不变
///
/// 通知栏完全由原生服务管理，Flutter 不参与
///
/// 该服务作为门面，委托给以下专门服务：
/// - [LocationEventHandler]: 处理 EventChannel 事件
/// - [KotlinTrackRecovery]: 恢复 Kotlin 侧轨迹数据
/// - [AddressResolver]: 逆地址解析
/// - [CoordinateUtils]: 坐标转换
class BackgroundLocationService {
  static final BackgroundLocationService _instance = BackgroundLocationService._();
  factory BackgroundLocationService() => _instance;
  BackgroundLocationService._();

  // MethodChannel - 用于控制服务启动/停止
  static const _methodChannel = MethodChannel('com.kenny.trace_path/location_service');

  // ========== 依赖服务 ==========
  final LocationSettingsService _settingsService = LocationSettingsService();
  final LocationEventHandler _eventHandler = LocationEventHandler();
  final KotlinTrackRecovery _kotlinRecovery = KotlinTrackRecovery();
  final AddressResolver _addressResolver = AddressResolver();

  // ========== 定位提供者（工厂模式 - 用于单次定位）==========
  LocationProvider? _locationProvider;
  bool _useNativeLocation = true;

  // ========== 订阅者管理 ==========
  final List<LocationCallback> _subscribers = [];
  bool _isSubscribed = false;

  // ========== 服务状态 ==========
  bool _isServiceRunning = false;
  bool _isInitialized = false;
  int _intervalSeconds = 30;
  bool _powerSaving = false;

  // ========== 初始化 ==========
  Future<void> init() async {
    if (_isInitialized) {
      Log.w(LogTag.FBLS, 'BackgroundLocationService::init 已经初始化');
      return;
    }
    _isInitialized = true;

    Log.i(LogTag.FBLS, 'BackgroundLocationService::init START');
    await _settingsService.load();
    _applyAddressResolverFromSettings();
    Log.i(LogTag.FBLS, 'INIT');
    _initLocationProvider();
    Log.i(LogTag.FBLS, 'init: _initLocationProvider done');

    // 启动时检查并申请权限（如果未授权则引导用户授权）
    await _ensurePermissions();

    // 设置事件处理器回调
    _eventHandler.onLocationEvent = (event) {
      _broadcast(event);
    };

    // 尝试从 Kotlin 侧恢复断线期间的轨迹数据
    Log.i(LogTag.FBLS, 'init: calling _recoverKotlinTrackData...');
    await _kotlinRecovery.recover();
    Log.i(LogTag.FBLS, 'init: _recoverKotlinTrackData done');

    // 主动请求一次当前位置（Flutter 重连后，立即在地图上显示当前位置）
    Log.i(LogTag.FBLS, 'init: calling _requestAndBroadcastCurrentLocation...');
    await _requestAndBroadcastCurrentLocation();
    Log.i(LogTag.FBLS, 'init: _requestAndBroadcastCurrentLocation done');

    // 注册 EventChannel 监听（Flutter 启动时就注册，不管服务有没有启动）
    // 注意：不要在 start() 中再次调用，避免重复取消 subscription
    Log.i(LogTag.FBLS, 'init: calling _listenToLocationEvents...');
    _eventHandler.startListening();
    Log.i(LogTag.FBLS, 'init: _listenToLocationEvents done');

    // 启动服务（打开应用时默认开启）- 等待完成确保原生服务启动
    Log.i(LogTag.FBLS, 'init: calling start()...');
    await start();
    Log.i(LogTag.FBLS, '★★★ init() END ★★★');
  }

  /// 主动请求当前位置并广播到地图（Flutter 重连后恢复实时显示）
  Future<void> _requestAndBroadcastCurrentLocation() async {
    try {
      Log.d(LogTag.FBLS, '_requestAndBroadcastCurrentLocation called');
      Log.d(LogTag.FBLS, '_locationProvider=${_locationProvider.runtimeType}');
      final position = await _locationProvider?.getCurrentPosition();
      if (position != null) {
        _broadcast(LocationEvent.position(position));
        _saveToLocal(position);
        Log.i(LogTag.FBLS, '主动请求位置成功: lat=${position.latitude}, lng=${position.longitude}');
      } else {
        Log.w(LogTag.FBLS, '主动请求位置返回 null');
      }
    } catch (e, s) {
      Log.e(LogTag.FBLS, '主动请求位置失败', e, s);
    }
  }

  void _applyAddressResolverFromSettings() {
    final resolverType = _settingsService.settings.addressResolverType;
    AddressResolver.setResolverType(resolverType);
    Log.i(LogTag.NETWORK, '地址解析器已应用: $resolverType (${AddressResolver().name})');
  }

  void _initLocationProvider() {
    _locationProvider?.dispose();
    if (_useNativeLocation) {
      _locationProvider = NativeLocationProvider();
      Log.i(LogTag.FBLS, '定位提供者: NativeLocationProvider');
    } else {
      _locationProvider = GeolocatorLocationProvider();
      Log.i(LogTag.FBLS, '定位提供者: GeolocatorLocationProvider');
    }
  }

  void setUseNativeLocation(bool useNative) {
    if (_useNativeLocation == useNative) return;
    _useNativeLocation = useNative;
    _initLocationProvider();
    Log.i(LogTag.FBLS, '切换定位方式: _useNativeLocation=$_useNativeLocation');
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
      } catch (e, s) {
        Log.e(LogTag.FBLS, '广播异常', e, s);
      }
    }
  }

  /// 确保应用拥有所需权限（启动时调用）
  /// checkPermission() 会自动请求权限，所以这里只检查最终结果
  Future<void> _ensurePermissions() async {
    // 检查定位权限（内部会自动请求）
    final hasLocation = await _locationProvider?.checkPermission() ?? false;
    if (!hasLocation) {
      Log.w(LogTag.FBLS, '_ensurePermissions: 定位权限被拒绝');
    }

    // 检查通知权限（Android 13+）
    if (Platform.isAndroid) {
      final notifStatus = await Permission.notification.status;
      if (notifStatus.isDenied) {
        final result = await Permission.notification.request();
        if (!result.isGranted) {
          Log.w(LogTag.FBLS, '_ensurePermissions: 通知权限被拒绝');
        }
      }
    }
  }

  // ========== 服务控制 ==========
  /// 启动服务
  Future<bool> start() async {
    try {
      // 检查定位权限（内部会自动请求）
      final hasPermission = await _locationProvider?.checkPermission() ?? false;
      if (!hasPermission) {
        Log.w(LogTag.FBLS, 'start: 定位权限被拒绝');
        _broadcast(LocationEvent.error('定位权限被拒绝'));
        return false;
      }

      // Android 13+ 需要通知权限
      if (Platform.isAndroid) {
        final notifStatus = await Permission.notification.status;
        if (notifStatus.isDenied) {
          final result = await Permission.notification.request();
          if (!result.isGranted) {
            Log.w(LogTag.FBLS, '通知权限被拒绝');
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

      // 重新注册 EventChannel 监听（服务重启后需要恢复连接）
      // 注意：会先取消旧订阅再创建新订阅，避免重复
      _eventHandler.startListening();

      // 更新设置状态
      await _settingsService.update(enabled: true);
      _isServiceRunning = true;

      _broadcast(LocationEvent.serviceStart());

      Log.i(LogTag.FBLS, ' START_SUCCESS');
      return true;
    } catch (e, s) {
      Log.e(LogTag.FBLS, 'START_FAILED', e, s);
      _broadcast(LocationEvent.error(e.toString()));
      return false;
    }
  }

  /// 停止服务
  Future<void> stop() async {
    try {
      // 注意：不在这里取消 EventChannel 订阅
      // Kotlin 服务被停止时会自动清理 EventChannel（onCancel 会由系统调用）
      // Flutter 侧的订阅会在 dispose() 时由 _locationUnsubscribe 取消

      await _settingsService.update(enabled: false);
      await _methodChannel.invokeMethod('stopLocationService');

      _isServiceRunning = false;
      _broadcast(LocationEvent.serviceStop());

      Log.i(LogTag.FBLS, 'STOP_SUCCESS');
    } catch (e, s) {
      Log.e(LogTag.FBLS, 'STOP_FAILED', e, s);
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
    } catch (e, s) {
      Log.e(LogTag.FBLS, 'updateConfig 异常', e, s);
    }
  }

  /// 是否正在运行
  Future<bool> checkRunning() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('isLocationServiceRunning');
      Log.d(LogTag.FBLS, 'checkRunning: result=$result');
      return result ?? false;
    } catch (e, s) {
      Log.e(LogTag.FBLS, 'checkRunning 异常', e, s);
      return false;
    }
  }

  /// 保存位置到本地
  Future<void> _saveToLocal(Position position) async {
    try {
      await TrackRecorder().record(position);
    } catch (e, s) {
      Log.e(LogTag.TRACK, 'BackgroundLocationService::saveToLocal fail', e, s);
    }
  }

  // ========== 单次定位（委托给 LocationProvider - 用于非持续定位场景）==========
  Future<Position?> getCurrentPosition() async {
    Log.d(LogTag.FBLS, 'getCurrentPosition start provider=${_useNativeLocation ? "NativeLocationProvider" : "GeolocatorLocationProvider"}');
    return _locationProvider?.getCurrentPosition();
  }

  // ========== 坐标转换（委托给 CoordinateUtils）==========
  List<double> wgs84ToGcj02(double lat, double lon) {
    return CoordinateUtils.wgs84ToGcj02(lat, lon);
  }

  List<double> gcj02ToWgs84(double lat, double lon) {
    return CoordinateUtils.gcj02ToWgs84(lat, lon);
  }

  // ========== 逆地址解析（委托给 AddressResolver）==========
  Future<String?> getAddressFromLatLng(double lat, double lng) {
    return _addressResolver.getAddressFromLatLng(lat, lng);
  }

  Future<void> dispose() async {
    await stop();
    _subscribers.clear();
    _locationProvider?.dispose();
  }
}
