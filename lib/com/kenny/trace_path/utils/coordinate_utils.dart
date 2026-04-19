import 'dart:math' as math;

/// 坐标系统类型
enum CoordinateSystem {
  wgs84,  // GPS默认坐标系
  gcj02,  // 国测局坐标系（高德、腾讯地图使用）
  bd09,   // 百度坐标系
}

/// 坐标转换工具类
/// 提供 WGS84、GCJ-02、BD-09 之间的相互转换
///
/// 参考标准：
/// - WGS84: GPS设备输出的原始坐标
/// - GCJ-02: 国测局坐标，中国大陆地区地图使用
/// - BD-09: 百度坐标，基于GCJ-02二次加密
class CoordinateUtils {
  CoordinateUtils._();

  static const double _pi = 3.1415926535897932384626;
  static const double _a = 6378245.0; // 椭球长半轴
  static const double _ee = 0.00669342162296594323; // 扁率

  /// WGS84 → GCJ-02
  static List<double> wgs84ToGcj02(double lat, double lng) {
    double dLat = _transformLat(lng - 105.0, lat - 35.0);
    double dLng = _transformLng(lng - 105.0, lat - 35.0);

    double radLat = lat / 180.0 * _pi;
    double sinLat = math.sin(radLat);
    double cosLat = math.cos(radLat);
    double magic = 1 - _ee * sinLat * sinLat;
    double sqrtMagic = math.sqrt(magic);

    dLat = (dLat * 180.0) / ((_a * (1 - _ee)) / (magic * sqrtMagic) * _pi);
    dLng = (dLng * 180.0) / (_a / sqrtMagic * cosLat * _pi);

    return [lat + dLat, lng + dLng];
  }

  /// GCJ-02 → WGS84（迭代法）
  static List<double> gcj02ToWgs84(double lat, double lng) {
    double wgs84Lat = lat;
    double wgs84Lon = lng;
    for (int i = 0; i < 5; i++) {
      final gcj = wgs84ToGcj02(wgs84Lat, wgs84Lon);
      wgs84Lat += lat - gcj[0];
      wgs84Lon += lng - gcj[1];
    }
    return [wgs84Lat, wgs84Lon];
  }

  /// GCJ-02 → BD-09
  static List<double> gcj02ToBd09(double lat, double lng) {
    double x = lng, y = lat;
    double z = math.sqrt(x * x + y * y) + 0.00002 * math.sin(y * _pi * 3000.0 / 180.0);
    double theta = math.atan2(y, x) + 0.000003 * math.cos(x * _pi * 3000.0 / 180.0);
    return [z * math.sin(theta) + 0.006, z * math.cos(theta) + 0.0065];
  }

  /// BD-09 → GCJ-02
  static List<double> bd09ToGcj02(double lat, double lng) {
    double x = lng - 0.0065, y = lat - 0.006;
    double z = math.sqrt(x * x + y * y) - 0.00002 * math.sin(y * _pi * 3000.0 / 180.0);
    double theta = math.atan2(y, x) - 0.000003 * math.cos(x * _pi * 3000.0 / 180.0);
    return [z * math.sin(theta), z * math.cos(theta)];
  }

  /// WGS84 → BD-09
  static List<double> wgs84ToBd09(double lat, double lng) {
    final gcj = wgs84ToGcj02(lat, lng);
    return gcj02ToBd09(gcj[0], gcj[1]);
  }

  /// BD-09 → WGS84
  static List<double> bd09ToWgs84(double lat, double lng) {
    final gcj = bd09ToGcj02(lat, lng);
    return gcj02ToWgs84(gcj[0], gcj[1]);
  }

  /// 转换坐标
  static List<double> convert(double lat, double lng, CoordinateSystem from, CoordinateSystem to) {
    if (from == to) return [lat, lng];

    switch (from) {
      case CoordinateSystem.wgs84:
        switch (to) {
          case CoordinateSystem.wgs84:
            return [lat, lng];
          case CoordinateSystem.gcj02:
            return wgs84ToGcj02(lat, lng);
          case CoordinateSystem.bd09:
            return wgs84ToBd09(lat, lng);
        }
      case CoordinateSystem.gcj02:
        switch (to) {
          case CoordinateSystem.wgs84:
            return gcj02ToWgs84(lat, lng);
          case CoordinateSystem.gcj02:
            return [lat, lng];
          case CoordinateSystem.bd09:
            return gcj02ToBd09(lat, lng);
        }
      case CoordinateSystem.bd09:
        switch (to) {
          case CoordinateSystem.wgs84:
            return bd09ToWgs84(lat, lng);
          case CoordinateSystem.gcj02:
            return bd09ToGcj02(lat, lng);
          case CoordinateSystem.bd09:
            return [lat, lng];
        }
    }
  }

  /// 校验坐标是否在中国大陆范围内（用于过滤异常坐标）
  static bool isInChina(double lat, double lng) {
    // 大致边界
    return lat >= 15 && lat <= 55 && lng >= 73 && lng <= 135;
  }

  /// 校验坐标是否有效
  static bool isValid(double lat, double lng) {
    if (lat.isNaN || lat.isInfinite || lng.isNaN || lng.isInfinite) return false;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return false;
    if (lat == 0 && lng == 0) return false; // GPS未锁定常见值
    return true;
  }

  /// 计算两点之间的距离（米），基于 Haversine 公式
  /// [lat1], [lng1] 第一个点的纬度和经度
  /// [lat2], [lng2] 第二个点的纬度和经度
  static double distance(double lat1, double lng1, double lat2, double lng2) {
    const double r = 6371000; // 地球半径（米）
    double dLat = _toRad(lat2 - lat1);
    double dLng = _toRad(lng2 - lng1);
    double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) * math.cos(_toRad(lat2)) *
        math.sin(dLng / 2) * math.sin(dLng / 2);
    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _toRad(double deg) => deg * _pi / 180;

  static double _transformLat(double x, double y) {
    double ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y;
    double sqrtX = x >= 0 ? x : -x;
    ret += 0.2 * math.sqrt(sqrtX);
    ret += (20.0 * math.sin(6.0 * x * _pi) + 20.0 * math.sin(2.0 * x * _pi)) * 2.0 / 3.0;
    ret += (20.0 * math.sin(y * _pi) + 40.0 * math.sin(y / 3.0 * _pi)) * 2.0 / 3.0;
    ret += (160.0 * math.sin(y / 12.0 * _pi) + 320.0 * math.sin(y * _pi / 30.0)) * 2.0 / 3.0;
    return ret;
  }

  static double _transformLng(double x, double y) {
    double ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y;
    double sqrtX = x >= 0 ? x : -x;
    ret += 0.1 * math.sqrt(sqrtX);
    ret += (20.0 * math.sin(6.0 * x * _pi) + 20.0 * math.sin(2.0 * x * _pi)) * 2.0 / 3.0;
    ret += (20.0 * math.sin(x * _pi) + 40.0 * math.sin(x / 3.0 * _pi)) * 2.0 / 3.0;
    ret += (150.0 * math.sin(x / 12.0 * _pi) + 300.0 * math.sin(x / 30.0 * _pi)) * 2.0 / 3.0;
    return ret;
  }
}
