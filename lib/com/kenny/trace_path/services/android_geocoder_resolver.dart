import 'package:flutter/services.dart';
import '../utils/logger.dart';
import 'address_resolver_base.dart';

/// Android 原生 Geocoder 逆地理编码实现
/// 通过 MethodChannel 调用 Android 原生 Geocoder API
class AndroidGeocoderResolver extends AddressResolverBase {
  static const MethodChannel _channel = MethodChannel('com.kenny.trace_path/geocoder_service');

  static final AndroidGeocoderResolver _instance = AndroidGeocoderResolver._();
  factory AndroidGeocoderResolver() => _instance;
  AndroidGeocoderResolver._();

  @override
  String get name => 'Android Geocoder';

  @override
  Future<String?> getAddressFromLatLng(double lat, double lng) async {
    try {
      final result = await _channel.invokeMethod<String>('getAddressFromLatLng', {
        'latitude': lat,
        'longitude': lng,
      });
      return result;
    } on PlatformException catch (e) {
      Log.e(LogTag.network, 'AndroidGeocoderResolver.getAddressFromLatLng error: ${e.message}', e);
      return null;
    } catch (e, s) {
      Log.e(LogTag.network, 'AndroidGeocoderResolver.getAddressFromLatLng error', e, s);
      return null;
    }
  }
}