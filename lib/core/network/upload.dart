import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

/// A file chosen on the device (camera, gallery or file browser).
///
/// Uploads must carry a real mimetype: the backend's multer filter rejects
/// anything that isn't PDF/JPEG/PNG/WEBP/GIF, and Dio's default is
/// `application/octet-stream`.
class PickedDoc {
  const PickedDoc({required this.path, required this.name, required this.size, this.mimeType});

  final String path;
  final String name;
  final int size;
  final String? mimeType;

  String get resolvedMimeType => mimeType ?? lookupMimeType(name) ?? lookupMimeType(path) ?? 'application/octet-stream';

  bool get isImage => resolvedMimeType.startsWith('image/');
  bool get isPdf => resolvedMimeType == 'application/pdf';

  String get sizeLabel {
    if (size >= 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (size >= 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
    return '$size B';
  }

  Future<MultipartFile> toMultipart() =>
      MultipartFile.fromFile(path, filename: name, contentType: MediaType.parse(resolvedMimeType));
}

/// Build a multipart body. `files` maps a field name to one file or a list
/// (repeated field, e.g. biometric `poses`). Null/empty fields are skipped.
Future<FormData> buildFormData({
  Map<String, Object?> fields = const {},
  Map<String, Object?> files = const {},
}) async {
  final form = FormData();
  fields.forEach((key, value) {
    if (value != null) form.fields.add(MapEntry(key, value.toString()));
  });
  for (final entry in files.entries) {
    final value = entry.value;
    if (value is PickedDoc) {
      form.files.add(MapEntry(entry.key, await value.toMultipart()));
    } else if (value is List) {
      for (final item in value.whereType<PickedDoc>()) {
        form.files.add(MapEntry(entry.key, await item.toMultipart()));
      }
    }
  }
  return form;
}

const int maxDocumentBytes = 10 * 1024 * 1024;
const int maxPhotoBytes = 5 * 1024 * 1024;
const List<String> documentExtensions = ['pdf', 'jpg', 'jpeg', 'png', 'webp'];
const List<String> imageExtensions = ['jpg', 'jpeg', 'png', 'webp'];

/// Same rules as the web's `validateDocumentFile`.
String? validateDocument(PickedDoc? file) {
  if (file == null) return 'No file selected';
  if (file.size > maxDocumentBytes) return 'File must be 10MB or smaller';
  final ext = file.name.split('.').last.toLowerCase();
  if (!documentExtensions.contains(ext) && !(file.isImage || file.isPdf)) {
    return 'Only PDF and image files (JPG, PNG) are allowed';
  }
  return null;
}

/// Same rules as the web's `validateImageFile`, with the backend's photo limit.
String? validateImage(PickedDoc? file, {int maxBytes = maxDocumentBytes}) {
  if (file == null) return 'No file selected';
  if (file.size > maxBytes) return 'Image must be ${maxBytes ~/ (1024 * 1024)}MB or smaller';
  final ext = file.name.split('.').last.toLowerCase();
  if (!imageExtensions.contains(ext) && !file.isImage) {
    return 'Only image files (JPG, PNG, WEBP) are allowed';
  }
  return null;
}
