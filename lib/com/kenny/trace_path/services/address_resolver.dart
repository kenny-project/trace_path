import 'address_resolver_base.dart';
import 'nominatim_address_resolver.dart';
import 'amap_address_resolver.dart';
import 'android_geocoder_resolver.dart';
import '../utils/logger.dart';
import '../utils/coordinate_utils.dart';

/// 地址解析服务工厂
/// 通过配置切换使用不同的逆地理编码实现
class AddressResolver {
  static AddressResolverType _resolverType = AddressResolverType.android;
  static String _amapApiKey = '';

  static final AddressResolver _instance = AddressResolver._();
  factory AddressResolver() => _instance;
  AddressResolver._();

  // 距离缓存：30米内不重复请求逆地理编码
  static const double _cacheDistanceThreshold = 30.0; // 米
  double? _lastLat;
  double? _lastLng;
  String? _cachedAddress;

  /// 设置解析器类型
  static void setResolverType(AddressResolverType type) {
    _resolverType = type;
    Log.i(LogTag.NETWORK, 'AddressResolver: switched to $type');
  }

  /// 获取当前解析器类型
  static AddressResolverType get resolverType => _resolverType;

  /// 设置高德地图 API Key
  static void setAmapApiKey(String apiKey) {
    _amapApiKey = apiKey;
    AMapAddressResolver.apiKey = apiKey;
    Log.i(LogTag.NETWORK, 'AddressResolver: AMap API key set');
  }

  /// 获取高德地图 API Key
  static String get amapApiKey => _amapApiKey;

  /// 获取当前解析器名称
  String get name {
    switch (_resolverType) {
      case AddressResolverType.nominatim:
        return NominatimAddressResolver().name;
      case AddressResolverType.amap:
        return AMapAddressResolver().name;
      case AddressResolverType.android:
        return AndroidGeocoderResolver().name;
    }
  }

  /// 逆地址解析
  /// 根据配置的 resolverType 委托给对应的实现
  /// 30米内不重复请求，返回缓存结果
  Future<String?> getAddressFromLatLng(double lat, double lng) async {
    // 距离判断：30米内返回缓存
    if (_lastLat != null && _lastLng != null && _cachedAddress != null) {
      double dist = CoordinateUtils.distance(_lastLat!, _lastLng!, lat, lng);
      if (dist < _cacheDistanceThreshold) {
        Log.d(LogTag.NETWORK, 'AddressResolver: 距离${dist.toStringAsFixed(0)}m<30m，使用缓存地址');
        return _cachedAddress;
      }
    }

    String? result;
    switch (_resolverType) {
      case AddressResolverType.nominatim:
        result = await NominatimAddressResolver().getAddressFromLatLng(lat, lng);
        break;
      case AddressResolverType.amap:
        result = await AMapAddressResolver().getAddressFromLatLng(lat, lng);
        break;
      case AddressResolverType.android:
        result = await AndroidGeocoderResolver().getAddressFromLatLng(lat, lng);
        break;
    }

    // 更新缓存
    _lastLat = lat;
    _lastLng = lng;
    _cachedAddress = result;
    return result;
  }
}