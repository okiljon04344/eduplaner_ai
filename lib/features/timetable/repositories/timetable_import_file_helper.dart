import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../../../core/l10n/app_strings.dart';
import '../models/timetable_import_failure.dart';

const int kMaxImportFileBytes = 10 * 1024 * 1024; // 10 MB limit
const int kHeicCompressMaxEdge = 2048;
const int kHeicCompressQuality = 85;

typedef HeicToJpegConverter = Future<Uint8List> Function(Uint8List heicBytes);

/// True only on Android & iOS where `flutter_image_compress` supports HEIC decode.
bool get isClientHeicConversionSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);

Future<Uint8List> defaultHeicToJpegConverter(Uint8List bytes) {
  return FlutterImageCompress.compressWithList(
    bytes,
    minWidth: kHeicCompressMaxEdge,
    minHeight: kHeicCompressMaxEdge,
    quality: kHeicCompressQuality,
    format: CompressFormat.jpeg,
  );
}

/// Detects the MIME type for supported timetable import file extensions.
String? detectImportMimeType(String fileName) {
  final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'csv':
      return 'text/csv';
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case 'pdf':
      return 'application/pdf';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'heic':
    case 'heif':
      return 'image/heic';
    default:
      return null;
  }
}

/// Result of preparing an import file (with validation and HEIC conversion applied).
class PreparedImportFile {
  final String fileName;
  final String mimeType;
  final Uint8List bytes;

  const PreparedImportFile({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });
}

/// Validates file size, rejects HEIC on Desktop/Web BEFORE upload, and converts
/// HEIC/HEIF images to JPEG on mobile before uploading.
Future<PreparedImportFile> prepareImportFile({
  required String rawFileName,
  required Uint8List rawBytes,
  HeicToJpegConverter? heicConverter,
  bool? supportsClientHeicConversion,
}) async {
  if (rawBytes.length > kMaxImportFileBytes) {
    throw FileTooLargeFailure(
      AppStrings.t('tt_import_err_file_too_large'),
      serverReason: 'file_too_large',
    );
  }

  final ext = rawFileName.contains('.')
      ? rawFileName.split('.').last.toLowerCase()
      : '';
  final isHeic = ext == 'heic' || ext == 'heif';

  if (isHeic) {
    final canConvert =
        supportsClientHeicConversion ?? isClientHeicConversionSupported;
    if (!canConvert) {
      throw UnsupportedHeicFailure(
        AppStrings.t('tt_import_err_unsupported_heic'),
        serverReason: 'unsupported_heic',
      );
    }
    final converter = heicConverter ?? defaultHeicToJpegConverter;
    final convertedBytes = await converter(rawBytes);
    if (convertedBytes.isEmpty) {
      throw UnsupportedHeicFailure(
        AppStrings.t('tt_import_err_unsupported_heic'),
        serverReason: 'unsupported_heic',
      );
    }
    final cleanBase =
        rawFileName.replaceAll(RegExp(r'\.(heic|heif)$', caseSensitive: false), '');
    final newName = '$cleanBase.jpg';
    return PreparedImportFile(
      fileName: newName,
      mimeType: 'image/jpeg',
      bytes: convertedBytes,
    );
  }

  final mime = detectImportMimeType(rawFileName);
  if (mime == null) {
    throw UnknownFailure(
      null,
      message: AppStrings.t('tt_import_err_unsupported_format'),
      code: 'invalid-argument',
    );
  }

  return PreparedImportFile(
    fileName: rawFileName,
    mimeType: mime,
    bytes: rawBytes,
  );
}
