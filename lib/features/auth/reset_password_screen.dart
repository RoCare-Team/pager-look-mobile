import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import 'auth_layout.dart';

/// Port of `pages/auth/ResetPassword.jsx`. Opened from the emailed link
/// (`/reset-password?token=…`); without a token the user can paste the link.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.token = ''});

  final String token;

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late String _token = widget.token.trim();
  String _error = '';
  bool _submitting = false;
  bool _done = false;

  @override
  void didUpdateWidget(covariant ResetPasswordScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.token != oldWidget.token && widget.token.trim().isNotEmpty) {
      _token = widget.token.trim();
    }
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = '');
    if (_password.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(authApiProvider).resetPassword(_token, _password.text);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _done = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = errorMessage(e, 'Could not reset your password');
      });
    }
  }

  void _goToSignIn() => context.go('/enterprise/login');

  @override
  Widget build(BuildContext context) {
    if (_token.isEmpty) {
      return AuthScaffold(
        showHeroCopy: false,
        onBack: _goToSignIn,
        children: [
          const AuthHeading(
            title: 'Invalid reset link',
            subtitle: 'This link is missing its token. Paste the reset link from your email, or request a new one.',
          ),
          PasteLinkCard(
            title: 'Paste your reset link',
            message: 'Copy the link from the password reset email and paste it here.',
            onToken: (token) => setState(() => _token = token),
          ),
          const SizedBox(height: 20),
          AuthLinkLine(label: 'Request a new link', onTap: () => context.go('/forgot-password')),
        ],
      );
    }

    if (_done) {
      return AuthScaffold(
        showHeroCopy: false,
        children: [
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(color: AppColors.successBg, shape: BoxShape.circle),
              child: const Icon(Icons.check, color: AppColors.success, size: 30),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Password updated',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.inkStrong),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your password has been reset. You can now sign in with your new password.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.inkBody),
          ),
          const SizedBox(height: 24),
          AppButton(label: 'Go to sign in', onPressed: _goToSignIn),
        ],
      );
    }

    return AuthScaffold(
      showHeroCopy: false,
      onBack: _goToSignIn,
      children: [
        const AuthHeading(
          title: 'Set a new password',
          subtitle: "Choose a strong password you don't use elsewhere.",
        ),
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                controller: _password,
                label: 'New password',
                hint: 'At least 8 characters',
                obscure: true,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                enabled: !_submitting,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _confirm,
                label: 'Confirm password',
                hint: 'Re-enter your password',
                obscure: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                enabled: !_submitting,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        if (_error.isNotEmpty) FormErrorText(_error),
        const SizedBox(height: 16),
        AppButton(
          label: _submitting ? 'Updating...' : 'Reset password',
          loading: _submitting,
          onPressed: (_password.text.isEmpty || _confirm.text.isEmpty) ? null : _submit,
        ),
        const SizedBox(height: 28),
        const Divider(),
        const SizedBox(height: 12),
        AuthLinkLine(label: 'Back to sign in', onTap: _goToSignIn),
      ],
    );
  }
}
