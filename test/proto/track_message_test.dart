import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:trace_path/com/kenny/trace_path/proto/track_message.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TrackPointMessage', () {
    test('编码后解码数据一致', () {
      final original = TrackPointMessage(
        timestampMs: 1711785600000,
        latitude: 39.908823,
        longitude: 116.397470,
        altitude: 38.5,
        speed: 2.5,
        accuracy: 10.0,
      );

      final encoded = original.encode();
      final decoded = TrackPointMessage.decode(encoded, 0);

      expect(decoded, isNotNull);
      expect(decoded!.timestampMs, equals(original.timestampMs));
      expect(decoded.latitude, equals(original.latitude));
      expect(decoded.longitude, equals(original.longitude));
      expect(decoded.altitude, equals(original.altitude));
      expect(decoded.speed, equals(original.speed));
      expect(decoded.accuracy, equals(original.accuracy));
    });

    test('编码后字节数组长度固定为44字节', () {
      final point = TrackPointMessage(
        timestampMs: 1711785600000,
        latitude: 39.908823,
        longitude: 116.397470,
        altitude: 38.5,
        speed: 2.5,
        accuracy: 10.0,
      );

      final encoded = point.encode();
      expect(encoded.length, equals(44));
      expect(point.encodedSize, equals(44));
    });

    test('解码超出边界范围时返回null', () {
      final data = Uint8List(10); // 太小，无法容纳44字节
      final decoded = TrackPointMessage.decode(data, 0);
      expect(decoded, isNull);
    });

    test('解码偏移量超过数据长度时返回null', () {
      final data = Uint8List(100);
      final decoded = TrackPointMessage.decode(data, 200);
      expect(decoded, isNull);
    });

    test('零值字段编码解码一致', () {
      final original = TrackPointMessage(
        timestampMs: 0,
        latitude: 0,
        longitude: 0,
        altitude: 0,
        speed: 0,
        accuracy: 0,
      );

      final encoded = original.encode();
      final decoded = TrackPointMessage.decode(encoded, 0);

      expect(decoded, isNotNull);
      expect(decoded!.timestampMs, equals(0));
      expect(decoded.latitude, equals(0));
      expect(decoded.longitude, equals(0));
      expect(decoded.altitude, equals(0));
      expect(decoded.speed, equals(0));
      expect(decoded.accuracy, equals(0));
    });

    test('fromPosition工厂构造器生成等效对象', () {
      final fromConstructor = TrackPointMessage(
        timestampMs: 1000000,
        latitude: 31.0,
        longitude: 120.0,
        altitude: 10.0,
        speed: 3.0,
        accuracy: 5.0,
      );

      final fromFactory = TrackPointMessage.fromPosition(
        timestampMs: 1000000,
        latitude: 31.0,
        longitude: 120.0,
        altitude: 10.0,
        speed: 3.0,
        accuracy: 5.0,
      );

      final encoded1 = fromConstructor.encode();
      final encoded2 = fromFactory.encode();

      expect(encoded1.length, equals(encoded2.length));
      for (int i = 0; i < encoded1.length; i++) {
        expect(encoded1[i], equals(encoded2[i]));
      }
    });

    test('多字节varint时间戳正确编码解码', () {
      // timestampMs = 1711785600000 需要多个字节的varint
      final original = TrackPointMessage(
        timestampMs: 1711785600000,
        latitude: 39.908823,
        longitude: 116.397470,
        altitude: 0,
        speed: 0,
        accuracy: 0,
      );

      final encoded = original.encode();
      final decoded = TrackPointMessage.decode(encoded, 0);

      expect(decoded, isNotNull);
      expect(decoded!.timestampMs, equals(original.timestampMs));
    });

    test('编码后可在任意偏移位置解码', () {
      final point = TrackPointMessage(
        timestampMs: 1711785600000,
        latitude: 39.908823,
        longitude: 116.397470,
        altitude: 38.5,
        speed: 2.5,
        accuracy: 10.0,
      );

      final paddingBefore = Uint8List(16);
      final paddingAfter = Uint8List(8);
      final combined = Uint8List(paddingBefore.length + 44 + paddingAfter.length);

      combined.setRange(paddingBefore.length, paddingBefore.length + 44, point.encode());

      final decoded = TrackPointMessage.decode(combined, paddingBefore.length);

      expect(decoded, isNotNull);
      expect(decoded!.timestampMs, equals(point.timestampMs));
      expect(decoded.latitude, equals(point.latitude));
      expect(decoded.longitude, equals(point.longitude));
      expect(decoded.altitude, equals(point.altitude));
      expect(decoded.speed, equals(point.speed));
      expect(decoded.accuracy, equals(point.accuracy));
    });
  });
}
