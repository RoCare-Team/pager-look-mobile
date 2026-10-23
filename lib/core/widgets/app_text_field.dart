import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Labelled text input — label sits above the field, as on the web forms.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.helper,
    this.initialValue,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.obscure = false,
    this.enabled = true,
    this.readOnly = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.prefixIcon,
    this.prefixText,
    this.suffix,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
    this.onTap,
    this.requiredMark = false,
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? helper;
  final String? initialValue;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscure;
  final bool enabled;
  final bool readOnly;
  final int maxLines;
  final int? minLines;
  final int? maxLength;
  final IconData? prefixIcon;
  final String? prefixText;
  final Widget? suffix;
  final Iterable<String>? autofillHints;
  final TextCapitalization textCapitalization;
  final VoidCallback? onTap;
  final bool requiredMark;
  final bool autofocus;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _hidden = widget.obscure;

  @override
  Widget build(BuildContext context) {
    Widget? suffix = widget.suffix;
    if (widget.obscure) {
      suffix = IconButton(
        tooltip: _hidden ? 'Show password' : 'Hide password',
        icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
        onPressed: () => setState(() => _hidden = !_hidden),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) FieldLabel(widget.label!, requiredMark: widget.requiredMark),
        TextFormField(
          controller: widget.controller,
          initialValue: widget.controller == null ? widget.initialValue : null,
          validator: widget.validator,
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onSubmitted,
          keyboardType: widget.obscure ? TextInputType.visiblePassword : widget.keyboardType,
          textInputAction: widget.textInputAction,
          inputFormatters: widget.inputFormatters,
          obscureText: _hidden,
          enabled: widget.enabled,
          readOnly: widget.readOnly,
          maxLines: widget.obscure ? 1 : widget.maxLines,
          minLines: widget.minLines,
          maxLength: widget.maxLength,
          autofillHints: widget.autofillHints,
          textCapitalization: widget.textCapitalization,
          onTap: widget.onTap,
          autofocus: widget.autofocus,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: InputDecoration(
            hintText: widget.hint,
            helperText: widget.helper,
            helperMaxLines: 3,
            errorMaxLines: 3,
            prefixIcon: widget.prefixIcon == null ? null : Icon(widget.prefixIcon, size: 20),
            prefixText: widget.prefixText,
            suffixIcon: suffix,
            counterText: widget.maxLength == null ? null : '',
          ),
        ),
      ],
    );
  }
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.requiredMark = false});

  final String text;
  final bool requiredMark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          text: text,
          children: [
            if (requiredMark) const TextSpan(text: ' *', style: TextStyle(color: AppColors.danger)),
          ],
        ),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkBody),
      ),
    );
  }
}

/// A labelled dropdown. [options] maps value → label.
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint,
    this.validator,
    this.enabled = true,
    this.requiredMark = false,
  });

  final Map<T, String> options;
  final T? value;
  final ValueChanged<T?> onChanged;
  final String? label;
  final String? hint;
  final FormFieldValidator<T>? validator;
  final bool enabled;
  final bool requiredMark;

  @override
  Widget build(BuildContext context) {
    final current = options.containsKey(value) ? value : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) FieldLabel(label!, requiredMark: requiredMark),
        DropdownButtonFormField<T>(
          initialValue: current,
          isExpanded: true,
          validator: validator,
          hint: hint == null ? null : Text(hint!, style: const TextStyle(color: AppColors.inkFaint)),
          items: options.entries
              .map((e) => DropdownMenuItem<T>(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: enabled ? onChanged : null,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
      ],
    );
  }
}

/// Tappable read-only field that opens a date picker. [value] is `YYYY-MM-DD`.
class AppDateField extends StatelessWidget {
  const AppDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.hint = 'Select date',
    this.validator,
    this.requiredMark = false,
    this.enabled = true,
  });

  final String label;
  final String? value;
  final ValueChanged<String> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String hint;
  final FormFieldValidator<String>? validator;
  final bool requiredMark;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      key: ValueKey('date-$label-$value'),
      label: label,
      hint: hint,
      initialValue: value ?? '',
      readOnly: true,
      enabled: enabled,
      requiredMark: requiredMark,
      validator: validator,
      prefixIcon: Icons.calendar_today_outlined,
      onTap: () async {
        final now = DateTime.now();
        final initial = DateTime.tryParse(value ?? '') ?? now;
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: firstDate ?? DateTime(1950),
          lastDate: lastDate ?? DateTime(now.year + 5),
        );
        if (picked != null) {
          onChanged(
            '${picked.year.toString().padLeft(4, '0')}-'
            '${picked.month.toString().padLeft(2, '0')}-'
            '${picked.day.toString().padLeft(2, '0')}',
          );
        }
      },
    );
  }
}
