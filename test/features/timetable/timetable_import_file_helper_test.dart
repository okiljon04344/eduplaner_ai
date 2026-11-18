import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:edu_planner_ai/features/timetable/models/timetable_import_failure.dart';
import 'package:edu_planner_ai/features/timetable/repositories/timetable_import_file_helper.dart';

void main() {
  group('detectImportMimeType', () {
    test('detects all supported extensions', () {
      expect(detectImportMimeType('sheet.xlsx'),
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      expect(detectImportMimeType('data.csv'), 'text/csv');
      expect(detectImportMimeType('timetable.pdf'), 'application/pdf');
      expect(detectImportMimeType('photo.jpg'), 'image/jpeg');
      expect(detectImportMimeType('photo.jpeg'), 'image/jpeg');
      expect(detectImportMimeType('doc.png'), 'image/png');
      expect(detectImportMimeType('scan.webp'), 'image/webp');
      expect(detectImportMimeType('image.heic'), 'image/heic');
      expect(detectImportMimeType('image.heif'), 'image/heic');
      expect(detectImportMimeType('unsupported.json'), isNull);
      expect(detectImportMimeType('plain.txt'), isNull);
      expect(detectImportMimeType('no_extension'), isNull);
    });
  });

  group('prepareImportFile', () {
    test('passes valid files within 10MB limit', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final prepared = await prepareImportFile(
        rawFileName: 'table.xlsx',
        rawBytes: bytes,
      );

      expect(prepared.fileName, 'table.xlsx');
      expect(prepared.mimeType,
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      expect(prepared.bytes, bytes);
    });

    test('rejects files larger than 10MB', () async {
      final bigBytes = Uint8List(10 * 1024 * 1024 + 1);

      expect(
        () => prepareImportFile(
          rawFileName: 'huge.pdf',
          rawBytes: bigBytes,
        ),
        throwsA(isA<FileTooLargeFailure>()),
      );
    });

    test('converts HEIC to JPEG on mobile using converter', () async {
      final heicBytes = Uint8List.fromList([10, 20, 30]);
      final jpegBytes = Uint8List.fromList([255, 216, 255]); // JPEG header

      final prepared = await prepareImportFile(
        rawFileName: 'IMG_4001.HEIC',
        rawBytes: heicBytes,
        supportsClientHeicConversion: true,
        heicConverter: (bytes) async {
          expect(bytes, heicBytes);
          return jpegBytes;
        },
      );

      expect(prepared.fileName, 'IMG_4001.jpg');
      expect(prepared.mimeType, 'image/jpeg');
      expect(prepared.bytes, jpegBytes);
    });

    test('rejects HEIC BEFORE upload on Desktop/Web without invoking converter', () async {
      final heicBytes = Uint8List.fromList([10, 20, 30]);
      var converterCalled = false;

      await expectLater(
        () => prepareImportFile(
          rawFileName: 'IMG_4001.heic',
          rawBytes: heicBytes,
          supportsClientHeicConversion: false,
          heicConverter: (_) async {
            converterCalled = true;
            return Uint8List(1);
          },
        ),
        throwsA(isA<UnsupportedHeicFailure>()),
      );
      expect(converterCalled, false);
    });

    test('throws UnsupportedHeicFailure if HEIC converter returns empty', () async {
      final heicBytes = Uint8List.fromList([10, 20, 30]);

      expect(
        () => prepareImportFile(
          rawFileName: 'IMG_4002.heif',
          rawBytes: heicBytes,
          supportsClientHeicConversion: true,
          heicConverter: (_) async => Uint8List(0),
        ),
        throwsA(isA<UnsupportedHeicFailure>()),
      );
    });

    test('rejects unsupported extensions with UnknownFailure', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);

      expect(
        () => prepareImportFile(
          rawFileName: 'data.json',
          rawBytes: bytes,
        ),
        throwsA(isA<UnknownFailure>()),
      );
    });
  });
}
