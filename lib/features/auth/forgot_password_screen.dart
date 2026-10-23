import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/widgets.dart';
import 'auth_layout.dart';

/// Port of `pages/auth/ForgotPassword.jsx`.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _emailFocus = FocusNode();
  bool _touched = false;
  bool _sending = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _emailFocus.addListener(() {
      if (!_emailFocus.hasFocus && !_touched) setState(() => _touched = true);
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _touched = true);
    if (!isValidEmail(_email.text)) return;
    setState(() => _sending = true);
    try {
      await ref.read(authApiProvider).requestPasswordReset(_email.text.trim());
    } catch (_) {
      // The API always responds generically, so any outcome means "we tried".
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      _sent = true;
    });
  }

  void _backToSignIn() => context.go('/enterprise/login');

  @override
  Widget build(BuildContext context) {
    final hasError = _touched && !isValidEmail(_email.text);
    return AuthScaffold(
      showHeroCopy: false,
      onBack: () => context.canPop() ? context.pop() : _backToSignIn(),
      children: [
        const AuthHeading(
          title: 'Reset your password',
          subtitle: "Enter your account email and we'll send you a secure reset link.",
        ),
        if (_sent)
          SuccessPanel(
            title: 'Check your inbox',
            message: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'If an account exists for '),
                  TextSpan(text: _email.text.trim(), style: const TextStyle(fontWeight: FontWeight.w700)),
                  const TextSpan(text: ', a password reset link is on its way. The link expires in 60 minutes.'),
                ],
              ),
            ),
          )
        else ...[
          Focus(
            focusNode: _emailFocus,
            child: AppTextField(
              controller: _email,
              label: 'Account Email',
              hint: 'hr@technova.com',
              prefixIcon: Icons.alternate_email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              enabled: !_sending,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (!_sending && _email.text.isNotEmpty) _submit();
              },
            ),
          ),
          if (hasError) const FormErrorText('Enter a valid email address.'),
          const SizedBox(height: 16),
          AppButton(
            label: _sending ? 'Sending link...' : 'Send reset link',
            loading: _sending,
            onPressed: _email.text.isEmpty ? null : _submit,
          ),
        ],
        const SizedBox(height: 28),
        const Divider(),
        const SizedBox(height: 12),
        AuthLinkLine(prefix: 'Remembered it?', label: 'Back to sign in', onTap: _backToSignIn),
      ],
    );
  }
}
