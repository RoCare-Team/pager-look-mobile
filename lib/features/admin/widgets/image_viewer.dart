import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';

/// Full-screen, pinch-to-zoom viewer for an uploaded image (card scans,
/// selfies, document photos). [url] must already be absolute.
Future<void> showImageViewer(BuildContext context, String url, {String? title}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          shape: const Border(),
          title: Text(title ?? '', style: const TextStyle(color: Colors.white, fontSize: 16)),
        ),
        body: SafeArea(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 6,
            child: Center(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const Center(child: CircularProgressIndicator(color: Colors.white)),
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Could not load this image', style: TextStyle(color: Colors.white70)),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// An uploaded image shown inline; tap opens [showImageViewer].
/// When [path] is empty, shows a dashed-style "<label> not uploaded" placeholder.
class AdminImageTile extends StatelessWidget {
  const AdminImageTile({
    super.key,
    required this.label,
    required this.path,
    this.aspectRatio = 1.6,
    this.showCaption = true,
  });

  final String label;

  /// Backend media path or absolute URL.
  final String? path;
  final double aspectRatio;
  final bool showCaption;

  @override
  Widget build(BuildContext context) {
    final src = mediaUrl(path);
    if (src == null) {
      return AspectRatio(
        aspectRatio: aspectRatio,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: AppColors.line),
          ),
          child: Text('$label not uploaded', style: const TextStyle(fontSize: 13, color: AppColors.inkFaint)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => showImageViewer(context, src, title: label),
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: AppColors.hairline),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.network(
                src,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const Center(
                        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image_outlined, color: AppColors.inkFaint, size: 32),
                ),
              ),
            ),
          ),
        ),
        if (showCaption)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '$label · tap to zoom',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.inkMuted),
            ),
          ),
      ],
    );
  }
}
