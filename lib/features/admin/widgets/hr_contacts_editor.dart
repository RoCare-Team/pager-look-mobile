import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Port of `components/common/HrContactsEditor.jsx` — an open-ended list of
/// HR contact emails. Owns its text controllers and reports every change.
class HrContactsEditor extends StatefulWidget {
  const HrContactsEditor({
    super.key,
    required this.initialContacts,
    required this.onChanged,
    this.max = 10,
    this.enabled = true,
    this.label = 'HR contacts',
    this.hint = '',
  });

  final List<String> initialContacts;
  final ValueChanged<List<String>> onChanged;
  final int max;
  final bool enabled;
  final String label;
  final String hint;

  @override
  State<HrContactsEditor> createState() => _HrContactsEditorState();
}

class _HrContactsEditorState extends State<HrContactsEditor> {
  late final List<TextEditingController> _controllers = [
    for (final c in (widget.initialContacts.isEmpty ? const [''] : widget.initialContacts))
      TextEditingController(text: c),
  ];

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _emit() => widget.onChanged(_controllers.map((c) => c.text).toList());

  void _add() {
    setState(() => _controllers.add(TextEditingController()));
    _emit();
  }

  void _removeAt(int index) {
    final removed = _controllers[index];
    setState(() {
      _controllers.removeAt(index);
      if (_controllers.isEmpty) _controllers.add(TextEditingController());
    });
    // Dispose after the row's TextField has been rebuilt without it.
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label.isNotEmpty)
          Text(widget.label,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.inkBody)),
        if (widget.hint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(widget.hint, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
          ),
        const SizedBox(height: 8),
        for (var i = 0; i < _controllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controllers[i],
                    enabled: widget.enabled,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: InputDecoration(
                      hintText: i == 0 ? 'hr@company.com' : 'another.hr@company.com',
                    ),
                    onChanged: (_) => _emit(),
                  ),
                ),
                if (_controllers.length > 1) ...[
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: widget.enabled ? () => _removeAt(i) : null,
                    style: TextButton.styleFrom(foregroundColor: AppColors.inkMuted),
                    child: const Text('Remove'),
                  ),
                ],
              ],
            ),
          ),
        if (_controllers.length < widget.max)
          TextButton(
            onPressed: widget.enabled ? _add : null,
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
            child: const Text('+ Add another HR contact'),
          )
        else
          Text(
            'You can add up to ${widget.max} HR contacts.',
            style: const TextStyle(fontSize: 12, color: AppColors.inkFaint),
          ),
      ],
    );
  }
}
