import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/logger.dart';
import 'address_resolver_base.dart';

/// OpenStreetMap Nominatim 逆地理编码实现
/// - 免费，无需 API Key
/// - 海外数据更完整
/// - 国内需要 VPN 访问
class NominatimAddressResolver extends AddressResolverBase {
  static final NominatimAddressResolver _instance = NominatimAddressResolver._();
  factory NominatimAddressResolver() => _instance;
  NominatimAddressResolver._();

  @override
  String get name => 'Nominatim (OpenStreetMap)';

  @override
  Future<String?> getAddressFromLatLng(double lat, double lng) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1',
      );

      final response = await http
          .get(
            url,
            headers: {'User-Agent': 'TracePath/1.0'},
          )
          .timeout(const Duration(seconds: 10));

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
    } catch (e, s) {
      Log.e(LogTag.NETWORK, 'NominatimAddressResolver.getAddressFromLatLng error', e, s);
      return null;
    }
  }
}
