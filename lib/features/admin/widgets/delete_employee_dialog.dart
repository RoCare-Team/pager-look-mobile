import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Port of `components/admin/DeleteEmployeeModal.jsx`.
///
/// The delete button stays disabled until the admin retypes the employee's
/// name or PagerLook ID (the same check the server runs). [onConfirm] performs
/// the delete and resolves true on success, which closes the dialog; on
/// failure the dialog stays open so the admin can retry or cancel.
///
/// Resolves true when the employee was deleted.
Future<bool> showDeleteEmployeeDialog(
  BuildContext context, {
  required String name,
  required String veriworkId,
  required Future<bool> Function(String confirm) onConfirm,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DeleteEmployeeDialog(name: name, veriworkId: veriworkId, onConfirm: onConfirm),
  );
  return result ?? false;
}

class _DeleteEmployeeDialog extends StatefulWidget {
  const _DeleteEmployeeDialog({required this.name, required this.veriworkId, required this.onConfirm});

  final String name;
  final String veriworkId;
  final Future<bool> Function(String confirm) onConfirm;

  @override
  State<_DeleteEmployeeDialog> createState() => _DeleteEmployeeDialogState();
}

class _DeleteEmployeeDialogState extends State<_DeleteEmployeeDialog> {
  final _controller = TextEditingController();
  bool _busy = false;

  late final List<String> _expected =
      [widget.name, widget.veriworkId].where((v) => v.trim().isNotEmpty && v != '—').toList();

  bool get _matches {
    final typed = _controller.text.trim().toLowerCase();
    return typed.isNotEmpty && _expected.any((v) => v.trim().toLowerCase() == typed);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_matches || _busy) return;
    setState(() => _busy = true);
    final ok = await widget.onConfirm(_controller.text.trim());
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = _expected.isNotEmpty ? _expected.first : '';
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(
          'Delete ${widget.name} permanently?',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This erases the account and everything the platform holds about them — profile, '
                'documents, Aadhaar KYC, vault, employment verifications, endorsements and company '
                'roster entries. It cannot be undone.',
                style: TextStyle(fontSize: 14, color: AppColors.inkBody, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warningBg,
                  borderRadius: BorderRadius.circular(AppRadii.control),
                ),
                child: const Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: 'To block access without losing verification history, use '),
                      TextSpan(text: 'Deactivate', style: TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: ' instead.'),
                    ],
                  ),
                  style: TextStyle(fontSize: 13, color: AppColors.warning),
                ),
              ),
              const SizedBox(height: 14),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Type '),
                    TextSpan(
                      text: primary,
                      style: const TextStyle(fontFamily: 'monospace', color: AppColors.inkStrong),
                    ),
                    const TextSpan(text: ' to confirm'),
                  ],
                ),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkBody),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(hintText: primary),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
              ),
              if (_expected.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Their PagerLook ID '),
                        TextSpan(text: _expected[1], style: const TextStyle(fontFamily: 'monospace')),
                        const TextSpan(text: ' works too.'),
                      ],
                    ),
                    style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              disabledBackgroundColor: AppColors.dangerBg,
              disabledForegroundColor: AppColors.danger.withValues(alpha: 0.5),
            ),
            onPressed: _busy || !_matches ? null : _submit,
            child: Text(_busy ? 'Deleting…' : 'Delete permanently'),
          ),
        ],
      ),
    );
  }
}
