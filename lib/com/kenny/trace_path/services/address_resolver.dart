import 'address_resolver_base.dart';
import 'nominatim_address_resolver.dart';
import 'amap_address_resolver.dart';
import 'android_geocoder_resolver.dart';
import '../utils/logger.dart';

/// 地址解析服务工厂
/// 通过配置切换使用不同的逆地理编码实现
class AddressResolver {
  static AddressResolverType _resolverType = AddressResolverType.android;
  static String _amapApiKey = '';

  static final AddressResolver _instance = AddressResolver._();
  factory AddressResolver() => _instance;
  AddressResolver._();

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
  Future<String?> getAddressFromLatLng(double lat, double lng) async {
    switch (_resolverType) {
      case AddressResolverType.nominatim:
        return NominatimAddressResolver().getAddressFromLatLng(lat, lng);
      case AddressResolverType.amap:
        return AMapAddressResolver().getAddressFromLatLng(lat, lng);
      case AddressResolverType.android:
        return AndroidGeocoderResolver().getAddressFromLatLng(lat, lng);
    }
  }
}