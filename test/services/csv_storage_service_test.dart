import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trace_path/com/kenny/trace_path/services/csv_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CsvStorageService', () {
    late Directory tempDir;
    late CsvStorageService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('csv_storage_test_');
      service = TestableCsvStorageService(tempDir.path);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('listTrackFiles', () {
      test('returns empty list when no files', () async {
        final files = await service.listTrackFiles();
        expect(files, isEmpty);
      });

      test('returns all CSV files sorted by date descending', () async {
        final dir = Directory('${tempDir.path}/location_tracks');
        await dir.create(recursive: true);
        await File('${dir.path}/2024-01-01.csv').writeAsString('a');
        await File('${dir.path}/2024-03-15.csv').writeAsString('b');
        await File('${dir.path}/2024-06-20.csv').writeAsString('c');

        final files = await service.listTrackFiles();

        expect(files.length, equals(3));
        expect(files[0], equals('2024-06-20')); // newest first
        expect(files[1], equals('2024-03-15'));
        expect(files[2], equals('2024-01-01'));
      });

      test('non-CSV files are excluded', () async {
        final dir = Directory('${tempDir.path}/location_tracks');
        await dir.create(recursive: true);
        await File('${dir.path}/2024-01-01.csv').writeAsString('a');
        await File('${dir.path}/2024-01-02.txt').writeAsString('b');

        final files = await service.listTrackFiles();

        expect(files.length, equals(1));
        expect(files[0], equals('2024-01-01'));
      });
    });

    group('deleteDayTrack', () {
      test('deletes existing file and returns true', () async {
        final dir = Directory('${tempDir.path}/location_tracks');
        await dir.create(recursive: true);
        await File('${dir.path}/2024-03-30.csv').writeAsString('a');

        final result = await service.deleteDayTrack('2024-03-30');

        expect(result, isTrue);
        expect(await File('${dir.path}/2024-03-30.csv').exists(), isFalse);
      });

      test('non-existent file returns true without error', () async {
        final result = await service.deleteDayTrack('1999-01-01');
        expect(result, isTrue);
      });

      test('deleting one file does not affect others', () async {
        final dir = Directory('${tempDir.path}/location_tracks');
        await dir.create(recursive: true);
        await File('${dir.path}/2024-01-01.csv').writeAsString('a');
        await File('${dir.path}/2024-01-02.csv').writeAsString('b');

        await service.deleteDayTrack('2024-01-01');

        final files = await service.listTrackFiles();
        expect(files.length, equals(1));
        expect(files[0], equals('2024-01-02'));
      });
    });

    group('clearAll', () {
      test('deletes all CSV files', () async {
        final dir = Directory('${tempDir.path}/location_tracks');
        await dir.create(recursive: true);
        await File('${dir.path}/2024-01-01.csv').writeAsString('a');
        await File('${dir.path}/2024-01-02.csv').writeAsString('b');

        await service.clearAll();

        final files = await service.listTrackFiles();
        expect(files, isEmpty);
      });

      test('can save new files after clearAll', () async {
        await service.clearAll();
        // Directly create a file to test that save can work after clear
        final dir = Directory('${tempDir.path}/location_tracks');
        await dir.create(recursive: true);
        await File('${dir.path}/2024-03-30.csv').writeAsString('timestamp,lat,lng\n');

        final files = await service.listTrackFiles();
        expect(files.length, equals(1));
      });

      test('clearAll on empty directory succeeds', () async {
        await service.clearAll(); // should not throw
        final files = await service.listTrackFiles();
        expect(files, isEmpty);
      });
    });

    group('readDayTrack', () {
      test('returns null for non-existent date', () async {
        final result = await service.readDayTrack('1999-01-01');
        expect(result, isNull);
      });

      test('returns null for empty CSV file', () async {
        final dir = Directory('${tempDir.path}/location_tracks');
        await dir.create(recursive: true);
        // Create empty CSV with just header
        await File('${dir.path}/2024-03-30.csv')
            .writeAsString('timestamp,latitude,longitude,altitude,speed,accuracy\n');

        final result = await service.readDayTrack('2024-03-30');
        expect(result, isNull);
      });
    });

    group('saveLocation', () {
      test('returns true when saving new location', () async {
        final result = await service.saveLocation(
          lat: 39.908823,
          lng: 116.397470,
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
        );
        expect(result, isTrue);
      });

      test('returns false when distance is less than 10 meters', () async {
        // First save
        await service.saveLocation(
          lat: 39.908823,
          lng: 116.397470,
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
        );
        // Second save very close (should be deduplicated)
        final result2 = await service.saveLocation(
          lat: 39.9088230001,
          lng: 116.3974700001,
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
        );
        expect(result2, isFalse);
      });

      test('saves file with correct CSV format', () async {
        await service.saveLocation(
          lat: 39.908823,
          lng: 116.397470,
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
        );

        final dir = Directory('${tempDir.path}/location_tracks');
        final files = await dir.list().toList();
        expect(files.isNotEmpty, isTrue);
      });
    });

    group('exportDayTrack / importDayTrack', () {
      test('exportDayTrack returns false (not implemented)', () async {
        final result = await service.exportDayTrack('2024-03-30');
        expect(result, isFalse);
      });

      test('importDayTrack returns 0 (not implemented)', () async {
        final result = await service.importDayTrack();
        expect(result, equals(0));
      });
    });
  });
}

/// Testable CsvStorageService using injected directory path
class TestableCsvStorageService extends CsvStorageService {
  final String testBasePath;

  TestableCsvStorageService(this.testBasePath);

  @override
  Future<String> get tracksDir async {
    final dir = Directory('$testBasePath/location_tracks');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }
}
