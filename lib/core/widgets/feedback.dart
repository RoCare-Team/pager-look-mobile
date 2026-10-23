import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../network/api_exception.dart';
import '../theme/app_theme.dart';
import 'app_text_field.dart';

/// Root messenger so toasts survive navigation (web: ToastContext).
final GlobalKey<ScaffoldMessengerState> rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

enum ToastType { success, error, info }

void showToast(String message, {ToastType type = ToastType.info}) {
  final messenger = rootMessengerKey.currentState;
  if (messenger == null) return;
  final (color, icon) = switch (type) {
    ToastType.success => (AppColors.success, Icons.check_circle_outline),
    ToastType.error => (AppColors.danger, Icons.error_outline),
    ToastType.info => (AppColors.inkStrong, Icons.info_outline),
  };
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: color,
        duration: Duration(seconds: type == ToastType.error ? 5 : 3),
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
          ],
        ),
      ),
    );
}

void showErrorToast(Object? error, [String fallback = 'Something went wrong']) =>
    showToast(errorMessage(error, fallback), type: ToastType.error);

/// Confirmation dialog. Resolves true only when the user confirms.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(cancelLabel)),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Dialog with one text input (reasons, notes). Returns null when cancelled.
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? label,
  String? hint,
  String? initialValue,
  String confirmLabel = 'Submit',
  bool required = true,
  bool destructive = false,
  int maxLines = 3,
  TextInputType? keyboardType,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _TextInputDialog(
      title: title,
      message: message,
      label: label,
      hint: hint,
      initialValue: initialValue,
      confirmLabel: confirmLabel,
      required: required,
      destructive: destructive,
      maxLines: maxLines,
      keyboardType: keyboardType,
    ),
  );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    this.message,
    this.label,
    this.hint,
    this.initialValue,
    required this.confirmLabel,
    required this.required,
    required this.destructive,
    required this.maxLines,
    this.keyboardType,
  });

  final String title;
  final String? message;
  final String? label;
  final String? hint;
  final String? initialValue;
  final String confirmLabel;
  final bool required;
  final bool destructive;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message != null) ...[Text(widget.message!), const SizedBox(height: 12)],
            AppTextField(
              controller: _controller,
              label: widget.label,
              hint: widget.hint,
              maxLines: widget.maxLines,
              keyboardType: widget.keyboardType,
              autofocus: true,
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          style: widget.destructive ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
          onPressed: widget.required && _controller.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Opens a URL in the external browser / app. Returns false if it could not.
Future<bool> openExternalUrl(String? url) async {
  if (url == null || url.isEmpty) {
    showToast('Link is not available', type: ToastType.error);
    return false;
  }
  final uri = Uri.tryParse(url);
  if (uri == null) {
    showToast('Invalid link', type: ToastType.error);
    return false;
  }
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) showToast('Could not open the link', type: ToastType.error);
  return ok;
}

Future<void> copyToClipboard(String text, {String message = 'Copied to clipboard'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  showToast(message, type: ToastType.success);
}
