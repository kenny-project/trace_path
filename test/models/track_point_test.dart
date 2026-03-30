import 'package:flutter_test/flutter_test.dart';
import 'package:trace_path/com/kenny/trace_path/services/track_recorder.dart';

void main() {
  group('TrackPoint', () {
    group('坐标转换 WGS84 → GCJ02', () {
      test('北京天安门坐标转换正确', () {
        // 北京天安门 WGS84 坐标
        final point = TrackPoint(
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          latitude: 39.908823,
          longitude: 116.397470,
          altitude: 50.0,
          speed: 0.0,
          accuracy: 10.0,
        );

        final converted = point.toGcj02();

        // GCJ02 转换后应该在合理范围内
        // 由于转换算法，转换后纬度/经度会有微小变化
        expect(converted.latitude, closeTo(39.9088, 0.01));
        expect(converted.longitude, closeTo(116.3974, 0.01));
        // 原始属性应该保持不变
        expect(converted.altitude, equals(50.0));
        expect(converted.speed, equals(0.0));
        expect(converted.accuracy, equals(10.0));
      });

      test('相同坐标转换后 timestamp 保持不变', () {
        final timestamp = DateTime(2024, 3, 30, 10, 0, 0);
        final point = TrackPoint(
          timestamp: timestamp,
          latitude: 39.908823,
          longitude: 116.397470,
        );

        final converted = point.toGcj02();

        expect(converted.timestamp, equals(timestamp));
      });

      test('边界坐标：上海', () {
        final point = TrackPoint(
          timestamp: DateTime.now(),
          latitude: 31.230416,
          longitude: 121.473701,
        );

        final converted = point.toGcj02();

        expect(converted.latitude, closeTo(31.2304, 0.01));
        expect(converted.longitude, closeTo(121.4737, 0.01));
      });

      test('边界坐标：广州', () {
        final point = TrackPoint(
          timestamp: DateTime.now(),
          latitude: 23.129163,
          longitude: 113.264385,
        );

        final converted = point.toGcj02();

        expect(converted.latitude, closeTo(23.1291, 0.01));
        expect(converted.longitude, closeTo(113.2644, 0.01));
      });
    });

    group('toCsvLine', () {
      test('生成包含所有字段的 CSV 行', () {
        final point = TrackPoint(
          timestamp: DateTime(2024, 3, 30, 10, 5, 30, 123),
          latitude: 39.908823,
          longitude: 116.397470,
          altitude: 50.123,
          speed: 5.678,
          accuracy: 10.5,
        );

        final csvLine = point.toCsvLine();

        expect(csvLine, contains('2024-03-30T10:05:30.123'));
        expect(csvLine, contains('39.908823'));
        expect(csvLine, contains('116.397470'));
        expect(csvLine, contains('50.12')); // 2位小数
        expect(csvLine, contains('5.68')); // 2位小数
        expect(csvLine, contains('10.5'));
      });

      test('默认参数处理', () {
        final point = TrackPoint(
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          latitude: 39.908823,
          longitude: 116.397470,
        );

        final csvLine = point.toCsvLine();

        expect(csvLine, contains('39.908823'));
        expect(csvLine, contains('116.397470'));
        expect(csvLine, contains('0.00')); // 默认 altitude
        expect(csvLine, contains('0.00')); // 默认 speed
        expect(csvLine, contains('0.0')); // 默认 accuracy
      });

      test('前导零填充正确', () {
        final point = TrackPoint(
          timestamp: DateTime(2024, 1, 5, 8, 3, 2),
          latitude: 39.908823,
          longitude: 116.397470,
        );

        final csvLine = point.toCsvLine();

        // 检查日期时间格式
        expect(csvLine, contains('2024-01-05T08:03:02'));
      });
    });

    group('toLatLng', () {
      test('转换为 LatLng 对象', () {
        final point = TrackPoint(
          timestamp: DateTime.now(),
          latitude: 39.908823,
          longitude: 116.397470,
        );

        final latLng = point.toLatLng();

        expect(latLng.latitude, equals(39.908823));
        expect(latLng.longitude, equals(116.397470));
      });
    });
  });
}
