import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:trace_path/com/kenny/trace_path/services/track_recorder.dart';
import 'package:trace_path/com/kenny/trace_path/services/track_service.dart';
import 'package:trace_path/com/kenny/trace_path/services/track_storage_manager.dart';
import '../mocks/mock_local_csv_storage.dart';
import '../mocks/in_memory_user_storage.dart';
import 'package:trace_path/com/kenny/trace_path/services/user_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TrackService', () {
    late Directory tempDir;
    late TestableLocalCsvStorage csvStorage;
    late TrackRecorder recorder;
    late TrackService trackService;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('track_service_test_');

      // Mock path_provider to use temp directory
      PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);

      // Initialize TrackStorageManager
      await TrackStorageManager().init();

      csvStorage = TestableLocalCsvStorage(tempDir.path);
      recorder = TrackRecorder();
      recorder.setStorage(csvStorage);
    });

    setUp(() async {
      // Ensure each test uses csvStorage
      recorder.setStorage(csvStorage);

      // Initialize user
      final userStorage = InMemoryUserStorage();
      final userService = UserService();
      userService.setStorage(userStorage);
      await userService.init();
      await userService.saveUser(User(phoneNumber: '13800138000'));

      // Create a fresh TrackService instance for each test
      trackService = TrackService();
    });

    tearDown(() async {
      // Clean up temp directory data
      try {
        final storageDir = Directory('${tempDir.path}/location_tracks');
        if (await storageDir.exists()) {
          await storageDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    tearDownAll(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      // Reset PathProviderPlatform
      PathProviderPlatform.instance = PathProviderPlatform.instance;
    });

    group('saveLocation / readDayTrack / deleteDayTrack', () {
      test('saveLocation saves successfully and returns true', () async {
        final result = await trackService.saveLocation(
          phoneNumber: '13800138000',
          lat: 39.908823,
          lng: 116.397470,
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
        );

        expect(result, isTrue);
      });

      test('saveLocation then readDayTrack finds the data', () async {
        await trackService.saveLocation(
          phoneNumber: '13800138000',
          lat: 39.908823,
          lng: 116.397470,
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
        );

        final now = DateTime.now();
        final points = await trackService.readDayTrack('13800138000', now.year, now.month, now.day);

        expect(points.isNotEmpty, isTrue);
        // TrackService.readDayTrack applies WGS84→GCJ02 conversion
        expect(points[0].latitude, closeTo(39.9102, 0.001));
      });

      test('readDayTrack for non-existent date returns empty list', () async {
        final points = await trackService.readDayTrack('13800138000', 2099, 12, 31);
        expect(points, isEmpty);
      });

      test('deleteDayTrack returns true and removes data', () async {
        final now = DateTime.now();
        await trackService.saveLocation(
          phoneNumber: '13800138000',
          lat: 39.908823,
          lng: 116.397470,
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
        );

        final result = await trackService.deleteDayTrack('13800138000', now.year, now.month, now.day);
        expect(result, isTrue);

        final points = await trackService.readDayTrack('13800138000', now.year, now.month, now.day);
        expect(points, isEmpty);
      });

      test('deleteDayTrack for non-existent file returns true', () async {
        final result = await trackService.deleteDayTrack('13800138000', 2099, 12, 31);
        expect(result, isTrue);
      });

      test('multiple saves result in multiple points', () async {
        final now = DateTime.now();

        await trackService.saveLocation(
          phoneNumber: '13800138000',
          lat: 39.908823,
          lng: 116.397470,
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
        );

        await trackService.saveLocation(
          phoneNumber: '13800138000',
          lat: 39.908824,
          lng: 116.397471,
          altitude: 51.0,
          speed: 6.0,
          accuracy: 11.0,
        );

        final points = await trackService.readDayTrack('13800138000', now.year, now.month, now.day);
        expect(points.length, equals(2));
      });

      test('readDayTrack returns points sorted by timestamp', () async {
        final now = DateTime.now();

        await trackService.saveLocation(
          phoneNumber: '13800138000',
          lat: 39.908825,
          lng: 116.397472,
          altitude: 52.0,
          speed: 7.0,
          accuracy: 12.0,
        );

        await trackService.saveLocation(
          phoneNumber: '13800138000',
          lat: 39.908823,
          lng: 116.397470,
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
        );

        final points = await trackService.readDayTrack('13800138000', now.year, now.month, now.day);
        expect(points.length, equals(2));
        expect(points[0].timestamp.isBefore(points[1].timestamp), isTrue);
      });
    });

    group('WGS84 to GCJ02 conversion', () {
      test('readDayTrack converts coordinates to GCJ02', () async {
        final now = DateTime.now();

        // Write a WGS84 point directly via storage
        final wgs84Point = TrackPoint(
          timestamp: DateTime(now.year, now.month, now.day, 10, 0, 0),
          latitude: 39.908823,
          longitude: 116.397470,
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
        );
        await csvStorage.write('13800138000', wgs84Point);

        final points = await trackService.readDayTrack('13800138000', now.year, now.month, now.day);

        expect(points.isNotEmpty, isTrue);
        // GCJ02 conversion changes the latitude
        expect(points[0].latitude, isNot(equals(39.908823)));
      });
    });

    group('getTrackHierarchy', () {
      test('empty directory returns empty hierarchy', () async {
        final hierarchy = await trackService.getTrackHierarchy();
        expect(hierarchy, isEmpty);
      });

      test('hierarchy reflects saved data correctly', () async {
        final now = DateTime.now();

        await trackService.saveLocation(
          phoneNumber: '13800138000',
          lat: 39.908823,
          lng: 116.397470,
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
        );

        final hierarchy = await trackService.getTrackHierarchy();

        expect(hierarchy.containsKey('13800138000'), isTrue);
        final yearMap = hierarchy['13800138000']!;
        expect(yearMap.containsKey('${now.year}'), isTrue);
        final monthMap = yearMap['${now.year}']!;
        expect(monthMap.containsKey('${now.month.toString().padLeft(2, '0')}'), isTrue);
      });
    });

    group('getPhonesWithTracks / getYearsWithTracks / getMonthsWithTracks / getDaysWithTracks', () {
      test('getPhonesWithTracks returns phones with track data', () async {
        await trackService.saveLocation(
          phoneNumber: '13800138000',
          lat: 39.908823,
          lng: 116.397470,
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
        );

        final phones = await trackService.getPhonesWithTracks();
        expect(phones, contains('13800138000'));
      });

      test('getYearsWithTracks returns years sorted descending', () async {
        final now = DateTime.now();

        await trackService.saveLocation(
          phoneNumber: '13800138000',
          lat: 39.908823,
          lng: 116.397470,
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
        );

        final years = await trackService.getYearsWithTracks('13800138000');

        expect(years.isNotEmpty, isTrue);
        expect(years[0], equals('${now.year}')); // newest year first
      });

      test('getMonthsWithTracks returns months sorted descending', () async {
        final now = DateTime.now();

        await trackService.saveLocation(
          phoneNumber: '13800138000',
          lat: 39.908823,
          lng: 116.397470,
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
        );

        final months = await trackService.getMonthsWithTracks('13800138000', '${now.year}');

        expect(months.isNotEmpty, isTrue);
        expect(months[0], equals('${now.month.toString().padLeft(2, '0')}'));
      });

      test('getDaysWithTracks returns empty for non-existent phone', () async {
        final now = DateTime.now();
        final days = await trackService.getDaysWithTracks(
          '99999999999',
          '${now.year}',
          '${now.month.toString().padLeft(2, '0')}',
        );
        expect(days, isEmpty);
      });

      test('getDaysWithTracks returns empty for non-existent month', () async {
        final now = DateTime.now();
        // Save a location first
        await trackService.saveLocation(
          phoneNumber: '13800138000',
          lat: 39.908823,
          lng: 116.397470,
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
        );

        // Query non-existent month
        final days = await trackService.getDaysWithTracks(
          '13800138000',
          '${now.year}',
          '99', // non-existent month
        );
        expect(days, isEmpty);
      });

      test('non-existent phone returns empty list', () async {
        final years = await trackService.getYearsWithTracks('99999999999');
        expect(years, isEmpty);
      });
    });

    group('getFileModifyTime', () {
      test('existing file returns modify time', () async {
        final now = DateTime.now();

        await trackService.saveLocation(
          phoneNumber: '13800138000',
          lat: 39.908823,
          lng: 116.397470,
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
        );

        final modifyTime = await trackService.getFileModifyTime(
          '13800138000',
          now.year,
          now.month,
          now.day,
        );

        expect(modifyTime, isNotNull);
      });

      test('non-existent file returns null', () async {
        final modifyTime = await trackService.getFileModifyTime(
          '13800138000',
          2099,
          12,
          31,
        );

        expect(modifyTime, isNull);
      });
    });

    group('consistency with TrackRecorder', () {
      test('TrackService saves, TrackRecorder reads', () async {
        final now = DateTime.now();

        await trackService.saveLocation(
          phoneNumber: '13800138000',
          lat: 39.908823,
          lng: 116.397470,
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
        );

        final points = await recorder.readDay('13800138000', now.year, now.month, now.day);
        expect(points.isNotEmpty, isTrue);
      });

      test('TrackRecorder saves, TrackService reads', () async {
        final now = DateTime.now();

        await recorder.recordFor('13800138000', Position(
          latitude: 39.908823,
          longitude: 116.397470,
          timestamp: DateTime(now.year, now.month, now.day, 10, 0, 0),
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
          altitudeAccuracy: 5.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speedAccuracy: 1.0,
        ));

        final points = await trackService.readDayTrack('13800138000', now.year, now.month, now.day);
        expect(points.isNotEmpty, isTrue);
      });

      test('TrackService delete removes data from TrackRecorder view', () async {
        final now = DateTime.now();

        await trackService.saveLocation(
          phoneNumber: '13800138000',
          lat: 39.908823,
          lng: 116.397470,
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
        );

        await trackService.deleteDayTrack('13800138000', now.year, now.month, now.day);

        final points = await recorder.readDay('13800138000', now.year, now.month, now.day);
        expect(points, isEmpty);
      });
    });
  });
}

/// Fake path provider for testing
class FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String tempPath;

  FakePathProviderPlatform(this.tempPath);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempPath;

  @override
  Future<String?> getApplicationSupportPath() async => tempPath;

  @override
  Future<String?> getTemporaryPath() async => tempPath;
}
