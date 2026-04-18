import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/logger.dart';
import 'address_resolver_base.dart';

/// 高德地图逆地理编码实现
/// - 国内访问稳定
/// - 需要 API Key（高德开放平台申请）
class AMapAddressResolver extends AddressResolverBase {
  /// 高德地图 Web API Key（需要从高德开放平台申请）
  /// https://lbs.amap.com/api/webservice/summary/
  static String apiKey = '';

  static final AMapAddressResolver _instance = AMapAddressResolver._();
  factory AMapAddressResolver() => _instance;
  AMapAddressResolver._();

  @override
  String get name => 'AMap (高德地图)';

  @override
  Future<String?> getAddressFromLatLng(double lat, double lng) async {
    if (apiKey.isEmpty) {
      Log.e(LogTag.NETWORK, 'AMapAddressResolver: API key is not set');
      return null;
    }

    try {
      // 高德地图 API：先将 lat,lng 顺序转为 lng,lat
      final location = '$lng,$lat';
      final url = Uri.parse(
        'https://restapi.amap.com/v3/geocode/regeo?key=$apiKey&location=$location&extensions=base&output=json',
      );

      final response = await http
          .get(
            url,
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == '1' && data['regeocode'] != null) {
          final addressComponent = data['regeocode']['addressComponent'];
          final formattedAddress = data['regeocode']['formatted_address'];

          // 优先使用完整地址，其次逐步拼接
          if (formattedAddress != null && formattedAddress.isNotEmpty) {
            return formattedAddress;
          }

          // 逐步拼接省市区路
          final province = addressComponent['province'] ?? '';
          final city = addressComponent['city'] ?? '';
          final district = addressComponent['district'] ?? '';
          final township = addressComponent['township'] ?? '';
          final street = addressComponent['streetNumber'] ?? '';

          String result = '';
          if (province.isNotEmpty) result += province;
          if (city.isNotEmpty && city != province) result += city;
          if (district.isNotEmpty && district != city) result += district;
          if (township.isNotEmpty && township != district) result += township;
          if (street.isNotEmpty) result += street;

          return result.isEmpty ? null : result;
        } else {
          Log.e(LogTag.NETWORK, 'AMapAddressResolver: API error - ${data['info']}');
        }
      }
      return null;
    } catch (e, s) {
      Log.e(LogTag.NETWORK, 'AMapAddressResolver.getAddressFromLatLng error', e, s);
      return null;
    }
  }
}
