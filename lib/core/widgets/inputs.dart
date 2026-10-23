import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'app_text_field.dart';

/// One-time code input — a single hidden field rendered as digit boxes, so
/// SMS autofill and paste both work. Calls [onCompleted] once all digits are in.
class OtpInput extends StatefulWidget {
  const OtpInput({
    super.key,
    required this.length,
    required this.onChanged,
    this.onCompleted,
    this.enabled = true,
    this.controller,
  });

  final int length;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onCompleted;
  final bool enabled;
  final TextEditingController? controller;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  late final TextEditingController _controller = widget.controller ?? TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _controller.text;
    return GestureDetector(
      onTap: () => _focus.requestFocus(),
      child: Stack(
        children: [
          // The real input: invisible but focusable, receives autofill/paste.
          Opacity(
            opacity: 0,
            child: SizedBox(
              height: 56,
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                enabled: widget.enabled,
                autofocus: true,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(widget.length),
                ],
                onChanged: (value) {
                  setState(() {});
                  widget.onChanged(value);
                  if (value.length == widget.length) widget.onCompleted?.call(value);
                },
              ),
            ),
          ),
          IgnorePointer(
            child: Row(
              children: List.generate(widget.length, (i) {
                final filled = i < text.length;
                final active = _focus.hasFocus && i == text.length.clamp(0, widget.length - 1);
                return Expanded(
                  child: Container(
                    height: 56,
                    margin: EdgeInsets.only(right: i == widget.length - 1 ? 0 : 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadii.control),
                      border: Border.all(
                        color: active ? AppColors.brand600 : (filled ? AppColors.brand100 : AppColors.line),
                        width: active ? 1.6 : 1,
                      ),
                    ),
                    child: Text(
                      filled ? text[i] : '',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.inkStrong),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

/// Country code + mobile number, as on the web `PhoneInput`.
class PhoneField extends StatelessWidget {
  const PhoneField({
    super.key,
    required this.controller,
    required this.countryCode,
    required this.onCountryCodeChanged,
    this.label = 'Mobile number',
    this.enabled = true,
    this.validator,
    this.onChanged,
  });

  final TextEditingController controller;
  final String countryCode;
  final ValueChanged<String> onCountryCodeChanged;
  final String label;
  final bool enabled;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;

  static const codes = ['+91', '+1', '+44', '+61', '+65', '+971', '+966', '+974', '+977', '+880', '+94'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: DropdownButtonFormField<String>(
                initialValue: codes.contains(countryCode) ? countryCode : codes.first,
                isExpanded: true,
                items: codes.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: enabled ? (v) => onCountryCodeChanged(v ?? '+91') : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: controller,
                enabled: enabled,
                validator: validator,
                onChanged: onChanged,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumberNational],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                decoration:
                    const InputDecoration(hintText: '98765 43210', prefixIcon: Icon(Icons.phone_outlined, size: 20)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Text field with debounced async suggestions (company / role / employee search).
/// The typed text is always accepted — suggestions are optional.
class AsyncAutocompleteField<T extends Object> extends StatefulWidget {
  const AsyncAutocompleteField({
    super.key,
    required this.controller,
    required this.search,
    required this.displayString,
    this.onSelected,
    this.label,
    this.hint,
    this.validator,
    this.subtitle,
    this.minChars = 2,
    this.enabled = true,
    this.requiredMark = false,
  });

  final TextEditingController controller;
  final Future<List<T>> Function(String query) search;
  final String Function(T option) displayString;
  final String? Function(T option)? subtitle;
  final ValueChanged<T>? onSelected;
  final String? label;
  final String? hint;
  final FormFieldValidator<String>? validator;
  final int minChars;
  final bool enabled;
  final bool requiredMark;

  @override
  State<AsyncAutocompleteField<T>> createState() => _AsyncAutocompleteFieldState<T>();
}

class _AsyncAutocompleteFieldState<T extends Object> extends State<AsyncAutocompleteField<T>> {
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  List<T> _options = const [];
  String _lastQuery = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _onTextChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < widget.minChars) {
      if (_options.isNotEmpty) setState(() => _options = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      _lastQuery = q;
      try {
        final results = await widget.search(q);
        if (mounted && _lastQuery == q) setState(() => _options = results);
      } catch (_) {
        if (mounted) setState(() => _options = const []);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    // Hide suggestions when the field loses focus (tap elsewhere / next field).
    _focus.addListener(() {
      if (!_focus.hasFocus && _options.isNotEmpty) setState(() => _options = const []);
    });
  }

  void _select(T option) {
    final text = widget.displayString(option);
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _debounce?.cancel();
    _lastQuery = '';
    setState(() => _options = const []);
    widget.onSelected?.call(option);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) FieldLabel(widget.label!, requiredMark: widget.requiredMark),
        TextFormField(
          controller: widget.controller,
          focusNode: _focus,
          enabled: widget.enabled,
          validator: widget.validator,
          onChanged: _onTextChanged,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: widget.hint, suffixIcon: const Icon(Icons.search, size: 20)),
        ),
        if (_options.isNotEmpty && _focus.hasFocus)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadii.control),
              border: Border.all(color: AppColors.line),
            ),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: _options.map((o) {
                final sub = widget.subtitle?.call(o);
                return ListTile(
                  dense: true,
                  title: Text(widget.displayString(o)),
                  subtitle: sub == null ? null : Text(sub),
                  onTap: () => _select(o),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

/// Horizontal scrolling filter chips (status tabs on list screens).
class FilterChipsBar extends StatelessWidget {
  const FilterChipsBar(
      {super.key, required this.options, required this.selected, required this.onSelected, this.padding});

  /// value → label
  final Map<String, String> options;
  final String selected;
  final ValueChanged<String> onSelected;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: options.entries.map((e) {
          final isSelected = e.key == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(e.value),
              selected: isSelected,
              showCheckmark: false,
              labelStyle: TextStyle(
                color: isSelected ? AppColors.brand600 : AppColors.inkBody,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
              side: BorderSide(color: isSelected ? AppColors.brand100 : AppColors.line),
              onSelected: (_) => onSelected(e.key),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Debounced search box for list screens.
class SearchField extends StatefulWidget {
  const SearchField({super.key, required this.onChanged, this.hint = 'Search', this.initialValue = ''});

  final ValueChanged<String> onChanged;
  final String hint;
  final String initialValue;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialValue);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _controller.clear();
                  setState(() {});
                  widget.onChanged('');
                },
              ),
      ),
      onChanged: (value) {
        setState(() {});
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 350), () => widget.onChanged(value.trim()));
      },
      onSubmitted: (value) {
        _debounce?.cancel();
        widget.onChanged(value.trim());
      },
    );
  }
}
