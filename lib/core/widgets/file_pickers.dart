import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../network/upload.dart';
import 'feedback.dart';

final ImagePicker _imagePicker = ImagePicker();

/// Take a photo or choose one from the gallery. Returns null when cancelled.
Future<PickedDoc?> pickImage({
  ImageSource source = ImageSource.gallery,
  CameraDevice camera = CameraDevice.rear,
  int imageQuality = 85,
  double maxWidth = 2000,
}) async {
  try {
    final XFile? file = await _imagePicker.pickImage(
      source: source,
      preferredCameraDevice: camera,
      imageQuality: imageQuality,
      maxWidth: maxWidth,
    );
    if (file == null) return null;
    final size = await File(file.path).length();
    return PickedDoc(path: file.path, name: _nameWithExtension(file.name, 'jpg'), size: size, mimeType: file.mimeType);
  } catch (e) {
    showToast(
        'Could not access the ${source == ImageSource.camera ? 'camera' : 'photo library'}. '
        'Check app permissions.',
        type: ToastType.error);
    return null;
  }
}

/// Choose a PDF or image from files. Returns null when cancelled.
Future<PickedDoc?> pickDocument({List<String> extensions = documentExtensions}) async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      withData: false,
    );
    final file = result?.files.single;
    if (file == null || file.path == null) return null;
    return PickedDoc(path: file.path!, name: file.name, size: file.size);
  } catch (e) {
    showToast('Could not open files. Check app permissions.', type: ToastType.error);
    return null;
  }
}

/// Bottom sheet offering camera / gallery / files, then validates the choice
/// with the same rules as the web. Returns null when cancelled or invalid.
Future<PickedDoc?> pickDocumentWithSheet(
  BuildContext context, {
  bool allowFiles = true,
  bool imagesOnly = false,
  int maxBytes = maxDocumentBytes,
  String title = 'Add a file',
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.of(ctx).pop('camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.of(ctx).pop('gallery'),
          ),
          if (allowFiles && !imagesOnly)
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Choose a PDF or file'),
              onTap: () => Navigator.of(ctx).pop('files'),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  PickedDoc? picked;
  switch (choice) {
    case 'camera':
      picked = await pickImage(source: ImageSource.camera);
    case 'gallery':
      picked = await pickImage(source: ImageSource.gallery);
    case 'files':
      picked = await pickDocument();
    default:
      return null;
  }
  if (picked == null) return null;

  final error = imagesOnly ? validateImage(picked, maxBytes: maxBytes) : validateDocument(picked);
  if (error != null) {
    showToast(error, type: ToastType.error);
    return null;
  }
  if (picked.size > maxBytes) {
    showToast('File must be ${maxBytes ~/ (1024 * 1024)}MB or smaller', type: ToastType.error);
    return null;
  }
  return picked;
}

String _nameWithExtension(String name, String fallbackExt) => name.contains('.') ? name : '$name.$fallbackExt';
