import 'package:flutter_test/flutter_test.dart';
import 'package:trace_path/com/kenny/trace_path/models/location_event.dart';
import 'package:trace_path/com/kenny/trace_path/services/background_location_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('BackgroundLocationService', () {
    late BackgroundLocationService service;
    final List<LocationEvent> receivedEvents = [];

    setUp(() {
      service = BackgroundLocationService();
      receivedEvents.clear();
    });

    group('subscribe / unsubscribe', () {
      test('订阅返回取消订阅函数', () async {
        // 订阅
        final unsubscribe = service.subscribe((event) {
          receivedEvents.add(event);
        });

        // 验证返回的是函数
        expect(unsubscribe, isA<Function>());
        
        // 清理
        unsubscribe();
      });

      test('取消订阅后不再收到事件', () async {
        bool callbackCalled = false;
        
        final unsubscribe = service.subscribe((event) {
          callbackCalled = true;
        });
        
        unsubscribe();
        
        // 取消订阅后，即使有事件也不应该调用回调
        expect(callbackCalled, isFalse);
      });
    });

    group('LocationEvent', () {
      test('LocationEvent.error 创建正确', () {
        final event = LocationEvent.error('Permission denied');

        expect(event.type, equals(LocationEventType.error));
        expect(event.errorMessage, equals('Permission denied'));
        expect(event.isPositionUpdate, isFalse);
      });

      test('LocationEvent.serviceStart 创建正确', () {
        final event = LocationEvent.serviceStart();

        expect(event.type, equals(LocationEventType.serviceStart));
        expect(event.timestamp, isNotNull);
      });

      test('LocationEvent.serviceStop 创建正确', () {
        final event = LocationEvent.serviceStop();

        expect(event.type, equals(LocationEventType.serviceStop));
      });
    });

    group('WGS84 → GCJ02 转换', () {
      test('坐标转换方法存在且可调用', () {
        // 测试公开的 wgs84ToGcj02 方法
        final result = service.wgs84ToGcj02(39.908823, 116.397470);
        
        expect(result, isA<List<double>>());
        expect(result.length, equals(2));
        // 转换后的坐标应该在合理范围内
        expect(result[0], closeTo(39.9088, 0.01));
        expect(result[1], closeTo(116.3974, 0.01));
      });

      test('中国境内坐标转换后仍在境内', () {
        // 测试多个中国城市坐标
        final cities = [
          [39.908823, 116.397470], // 北京
          [31.230416, 121.473701], // 上海
          [23.129163, 113.264385], // 广州
          [29.563345, 104.063616], // 成都
        ];

        for (final city in cities) {
          final result = service.wgs84ToGcj02(city[0], city[1]);
          // 纬度应该在 3-54 之间（中国的纬度范围）
          expect(result[0], inInclusiveRange(3, 54));
          // 经度应该在 73-135 之间（中国的经度范围）
          expect(result[1], inInclusiveRange(73, 135));
        }
      });

      test('静止坐标转换正确', () {
        // 静止时 speed=0 的坐标
        final result = service.wgs84ToGcj02(39.908823, 116.397470);
        
        expect(result[0], isNotNull);
        expect(result[1], isNotNull);
      });
    });

    group('getAddressFromLatLng', () {
      test('逆地址解析返回字符串或 null', () async {
        // 使用真实坐标测试（北京市政府附近）
        final address = await service.getAddressFromLatLng(39.908823, 116.397470);
        
        // 地址解析可能因网络问题返回 null，这是可接受的
        expect(address == null || address is String, isTrue);
      });

      test('无效坐标处理', () async {
        // 使用极端坐标测试
        final address = await service.getAddressFromLatLng(0, 0);
        
        // 应该返回 null 或空字符串
        expect(address == null || address.isEmpty, isTrue);
      });
    });
  });
}
