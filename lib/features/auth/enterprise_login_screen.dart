import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/home_routes.dart';
import '../../core/providers.dart';
import '../../core/utils/json.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/widgets.dart';
import 'auth_layout.dart';

/// Port of `pages/auth/EnterpriseLogin.jsx`.
class EnterpriseLoginScreen extends ConsumerStatefulWidget {
  const EnterpriseLoginScreen({super.key});

  @override
  ConsumerState<EnterpriseLoginScreen> createState() => _EnterpriseLoginScreenState();
}

class _EnterpriseLoginScreenState extends ConsumerState<EnterpriseLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  bool _touched = false;
  bool _submitting = false;

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
    _password.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  bool get _hasEmailError => _touched && !isValidEmail(_email.text);

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _touched = true);
    if (!isValidEmail(_email.text) || _password.text.isEmpty) {
      showToast('Enter a valid email and password', type: ToastType.error);
      return;
    }
    setState(() => _submitting = true);
    try {
      final data = asMap(await ref.read(authApiProvider).loginEnterprise(_email.text.trim(), _password.text));
      showToast('Welcome back!', type: ToastType.success);
      await ref.read(authProvider).loginEnterprise(data);
      if (!mounted) return;
      context.go(enterpriseHomeRoute(asMap(data['company'])));
    } catch (e) {
      showErrorToast(e, 'Login failed');
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Back always leads to the welcome screen — also after a logout, when
    // there is nothing underneath this screen in the stack.
    void back() => context.canPop() ? context.pop() : context.go('/');

    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/');
      },
      child: AuthScaffold(
      onBack: back,
      busy: _submitting,
      busyLabel: 'Authenticating...',
      children: [
          const AuthHeading(
            title: 'Enterprise Login',
            subtitle: 'Secure access to your workforce trust dashboard',
          ),
          AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Focus(
                  focusNode: _emailFocus,
                  child: AppTextField(
                    controller: _email,
                    label: 'Work Email',
                    hint: 'hr@technova.com',
                    prefixIcon: Icons.alternate_email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    enabled: !_submitting,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _password,
                  label: 'Password',
                  hint: '••••••••',
                  obscure: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  enabled: !_submitting,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    if (_password.text.isNotEmpty && !_submitting) _submit();
                  },
                ),
                if (_hasEmailError) const FormErrorText('Enter a valid company email address.'),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _submitting ? null : () => context.push('/forgot-password'),
              child: const Text('Forgot password?', style: TextStyle(fontSize: 13)),
            ),
          ),
          const SizedBox(height: 4),
          AppButton(
            label: _submitting ? 'Signing you in...' : 'Continue to Dashboard',
            loading: _submitting,
            onPressed: _password.text.isEmpty ? null : _submit,
          ),
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 12),
          AuthLinkLine(
            prefix: 'New company?',
            label: 'Register Now',
            onTap: () => context.push('/enterprise/register'),
          ),
          AuthLinkLine(
            prefix: 'Professional?',
            label: 'Employee Portal',
            onTap: () => context.go('/employee/otp'),
          ),
        ],
    ),
    );
  }
}
