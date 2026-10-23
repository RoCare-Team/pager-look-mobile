import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';

/// "Book a demo" — port of the web `DemoRequestModal`. Files a lead into the
/// admin console; the visitor needs no account.
class DemoRequestScreen extends ConsumerStatefulWidget {
  const DemoRequestScreen({super.key});

  @override
  ConsumerState<DemoRequestScreen> createState() => _DemoRequestScreenState();
}

const Map<String, String> _teamSizes = {
  '1-10': '1-10 people',
  '11-50': '11-50 people',
  '51-200': '51-200 people',
  '201-1000': '201-1000 people',
  '1000+': '1000+ people',
};

class _DemoRequestScreenState extends ConsumerState<DemoRequestScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _company = TextEditingController();
  final _message = TextEditingController();
  String? _teamSize;

  bool _pending = false;
  bool _done = false;
  String _error = '';

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _company.dispose();
    _message.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    final phoneDigits = _phone.text.replaceAll(RegExp(r'\D'), '');
    return _name.text.trim().length >= 2 &&
        RegExp(r'\S+@\S+\.\S+').hasMatch(_email.text) &&
        phoneDigits.length >= 10;
  }

  Future<void> _submit() async {
    if (!_canSubmit || _pending) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _pending = true;
      _error = '';
    });
    try {
      // Same body as the web form state.
      await ref.read(publicApiProvider).submitDemoRequest({
        'name': _name.text,
        'email': _email.text,
        'phone': _phone.text,
        'company': _company.text,
        'teamSize': _teamSize ?? '',
        'message': _message.text,
      });
      if (!mounted) return;
      setState(() => _done = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorMessage(e, 'Could not send your request. Please try again.'));
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Book a demo')),
      body: SafeArea(child: _done ? _buildDone() : _buildForm()),
    );
  }

  Widget _buildDone() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: AppColors.successBg, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, size: 34, color: AppColors.success),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Request received',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.inkStrong),
        ),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Our team will call you on '),
              TextSpan(text: _phone.text, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkStrong)),
              TextSpan(text: " to fix a time. You'll also get a confirmation at ${_email.text}."),
            ],
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.inkBody),
        ),
        const SizedBox(height: 28),
        AppButton(label: 'Done', onPressed: _close),
      ],
    );
  }

  Widget _buildForm() {
    void changed(String _) => setState(() {});

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        const PageIntro(
          title: 'Book a demo',
          subtitle: 'See PagerLook on your own workforce — a 20-minute walkthrough.',
        ),
        if (_error.isNotEmpty) ...[
          InfoBanner(message: _error, tone: Tone.danger),
          const SizedBox(height: 16),
        ],
        AppTextField(
          controller: _name,
          label: 'Your name',
          hint: 'Priya Sharma',
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          enabled: !_pending,
          onChanged: changed,
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: _email,
          label: 'Work email',
          hint: 'you@company.com',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          enabled: !_pending,
          onChanged: changed,
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: _phone,
          label: 'Phone',
          hint: '98765 43210',
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.telephoneNumber],
          enabled: !_pending,
          onChanged: changed,
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: _company,
          label: 'Company (optional)',
          hint: 'Acme Pvt Ltd',
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.organizationName],
          enabled: !_pending,
        ),
        const SizedBox(height: 14),
        AppDropdown<String>(
          label: 'Team size (optional)',
          hint: 'Select',
          options: _teamSizes,
          value: _teamSize,
          enabled: !_pending,
          onChanged: (v) => setState(() => _teamSize = v),
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: _message,
          label: 'What would you like to see? (optional)',
          hint: 'Bulk onboarding for 200 field staff, Aadhaar verification…',
          maxLines: 5,
          minLines: 3,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
          enabled: !_pending,
        ),
        const SizedBox(height: 22),
        AppButton(
          label: _pending ? 'Sending…' : 'Request demo',
          loading: _pending,
          onPressed: _canSubmit ? _submit : null,
        ),
        const SizedBox(height: 10),
        const Text(
          'We only use these details to contact you about the demo.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
        ),
      ],
    );
  }
}
