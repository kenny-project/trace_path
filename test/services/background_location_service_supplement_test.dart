import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trace_path/com/kenny/trace_path/models/location_event.dart';
import 'package:trace_path/com/kenny/trace_path/services/background_location_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackgroundLocationService supplement tests', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('bg_loc_supplement_test_');

      // Mock path_provider for LocationSettingsService
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'getApplicationDocumentsDirectory') {
            return tempDir.path;
          }
          return null;
        },
      );
    });

    setUp(() async {
      // Reset location_service channel before each test
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.kenny.trace_path/location_service'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'start') return true;
          if (methodCall.method == 'stop') return null;
          if (methodCall.method == 'updateConfig') return null;
          if (methodCall.method == 'isRunning') return false;
          return null;
        },
      );
    });

    tearDownAll(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter/platform'),
        null,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.kenny.trace_path/location_service'),
        null,
      );
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('wgs84ToGcj02 produces different coordinates from input', () {
      final service = BackgroundLocationService();

      // WGS84 Beijing Tiananmen: 39.908823, 116.397470
      final result = service.wgs84ToGcj02(39.908823, 116.397470);

      // Lat should change after conversion
      expect(result[0], isNot(equals(39.908823)));
      // Lng should change after conversion
      expect(result[1], isNot(equals(116.397470)));
    });

    test('wgs84ToGcj02 near equator produces measurable shift', () {
      final service = BackgroundLocationService();

      // 0,0 should shift
      final result = service.wgs84ToGcj02(0.0, 0.0);
      expect(result[0], isNot(equals(0.0)));
      expect(result[1], isNot(equals(0.0)));
    });

    test('wgs84ToGcj02 southernmost China produces coordinate shift', () {
      final service = BackgroundLocationService();

      // China's southernmost point (WGS84): 3.0, 73.0
      // After GCJ02 conversion, coordinates shift
      final result = service.wgs84ToGcj02(3.0, 73.0);
      // Longitude always shifts; latitude may shift slightly in either direction
      expect(result[1], isNot(equals(73.0))); // longitude definitely changes
    });

    test('wgs84ToGcj02 returns list of length 2', () {
      final service = BackgroundLocationService();

      final result = service.wgs84ToGcj02(39.908823, 116.397470);
      expect(result, isA<List<double>>());
      expect(result.length, equals(2));
    });

    test('init does not throw when path_provider is mocked', () async {
      final service = BackgroundLocationService();
      await service.init(); // should not throw
    });

    test('multiple init calls do not throw', () async {
      final service = BackgroundLocationService();
      await service.init();
      await service.init(); // should not throw
    });

    test('subscribe returns unsubscribe function', () async {
      final service = BackgroundLocationService();
      await service.init();

      final events = <LocationEvent>[];
      final unsubscribe = service.subscribe((e) => events.add(e));
      expect(unsubscribe, isA<Function>());

      // Calling unsubscribe should work
      unsubscribe();
    });

    test('updateSettings with valid values does not throw', () async {
      final service = BackgroundLocationService();
      await service.init();
      await service.updateSettings(intervalSeconds: 60, powerSaving: true);
    });

    test('updateSettings with null values does not throw', () async {
      final service = BackgroundLocationService();
      await service.init();
      await service.updateSettings(); // all null
    });

    test('checkRunning returns bool', () async {
      final service = BackgroundLocationService();
      await service.init();
      final result = await service.checkRunning();
      expect(result, isA<bool>());
    });

    test('dispose does not throw', () async {
      final service = BackgroundLocationService();
      await service.init();
      await service.dispose();
    });

    test('dispose can be called multiple times', () async {
      final service = BackgroundLocationService();
      await service.init();
      await service.dispose();
      await service.dispose(); // should not throw
    });
  });
}
