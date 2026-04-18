/// 逆地理编码接口
abstract class AddressResolverBase {
  /// 根据经纬度获取地址
  Future<String?> getAddressFromLatLng(double lat, double lng);

  /// 获取当前解析器名称
  String get name;
}

/// 解析器类型枚举
enum AddressResolverType {
  /// OpenStreetMap Nominatim（国外，无Key）
  nominatim,

  /// 高德地图（国内，需要Key）
  amap,

  /// Android 原生 Geocoder（需要原生平台）
  android,
}
