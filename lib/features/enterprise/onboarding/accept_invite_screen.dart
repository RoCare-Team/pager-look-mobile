import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/home_routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/auth_layout.dart';

/// `GET /public/company-invite/:token` → `{ email, name, companyName, roleLabel, expiresAt }`.
final _companyInviteProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, token) async {
  return asMap(await ref.watch(publicApiProvider).fetchCompanyInvite(token));
});

/// Port of `pages/enterprise/AcceptInvite.jsx` — a teammate invited to the
/// employer portal sets a password to activate their account.
class AcceptInviteScreen extends ConsumerStatefulWidget {
  const AcceptInviteScreen({super.key, this.token = ''});

  final String token;

  @override
  ConsumerState<AcceptInviteScreen> createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends ConsumerState<AcceptInviteScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late String _token = widget.token.trim();
  String _error = '';
  bool _submitting = false;
  bool _done = false;

  @override
  void didUpdateWidget(covariant AcceptInviteScreen oldWidget) {
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

  void _goToSignIn() => context.go('/enterprise/login');

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
      final data = asMap(await ref.read(publicApiProvider).acceptCompanyInvite(_token, _password.text));
      // The backend currently answers `{ message, email }` and the user signs
      // in next (web parity). If it ever returns a session, use it directly.
      if (strOrNull(data['accessToken']) != null) {
        await ref.read(authProvider).loginEnterprise(data);
        if (!mounted) return;
        context.go(enterpriseHomeRoute(asMap(data['company'])));
        return;
      }
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _done = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = errorMessage(e, 'Could not accept the invite');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_token.isEmpty) {
      return AuthScaffold(
        showHeroCopy: false,
        onBack: _goToSignIn,
        children: [
          const AuthHeading(
            title: 'Accept your invite',
            subtitle: 'Open the invite link from your email, or paste it below.',
          ),
          PasteLinkCard(
            title: 'Paste your invite link',
            message: 'Copy the "Accept invite" link from the invitation email and paste it here.',
            onToken: (token) => setState(() => _token = token),
          ),
          const SizedBox(height: 20),
          AuthLinkLine(prefix: 'Already have an account?', label: 'Sign in', onTap: _goToSignIn),
        ],
      );
    }

    final inviteAsync = ref.watch(_companyInviteProvider(_token));

    return inviteAsync.when(
      loading: () => const Scaffold(body: LoadingView(label: 'Loading invite...')),
      error: (e, _) => AuthScaffold(
        showHeroCopy: false,
        onBack: _goToSignIn,
        children: [
          InfoBanner(
            tone: Tone.danger,
            title: 'Invalid invite',
            message: errorMessage(e, 'This invite is invalid or has expired.'),
          ),
          const SizedBox(height: 16),
          AppButton(label: 'Go to sign in', onPressed: _goToSignIn),
          const SizedBox(height: 8),
          AppButton(
            label: 'Use a different link',
            variant: AppButtonVariant.ghost,
            onPressed: () => setState(() => _token = ''),
          ),
        ],
      ),
      data: (invite) => _done ? _doneView(invite) : _formView(invite),
    );
  }

  Widget _doneView(Map<String, dynamic> invite) {
    return AuthScaffold(
      showHeroCopy: false,
      children: [
        SuccessPanel(
          title: "You're all set",
          message: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Your account for '),
                TextSpan(text: str(invite['companyName']), style: const TextStyle(fontWeight: FontWeight.w700)),
                const TextSpan(text: ' is ready. Sign in with '),
                TextSpan(text: str(invite['email']), style: const TextStyle(fontWeight: FontWeight.w700)),
                const TextSpan(text: '.'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        AppButton(label: 'Go to sign in', onPressed: _goToSignIn),
      ],
    );
  }

  Widget _formView(Map<String, dynamic> invite) {
    return AuthScaffold(
      showHeroCopy: false,
      onBack: _goToSignIn,
      busy: _submitting,
      busyLabel: 'Creating account…',
      children: [
        const AuthHeading(title: 'Accept your invite'),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: str(invite['companyName']), style: const TextStyle(fontWeight: FontWeight.w700)),
              const TextSpan(text: ' invited you to their employer portal as '),
              TextSpan(text: str(invite['roleLabel']), style: const TextStyle(fontWeight: FontWeight.w700)),
              const TextSpan(text: '. Set a password to activate your account.'),
            ],
          ),
          style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.inkBody),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(AppRadii.control),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'YOUR LOGIN EMAIL',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.inkFaint),
              ),
              const SizedBox(height: 2),
              Text(
                str(invite['email']),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.inkStrong),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                controller: _password,
                label: 'Create password',
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
          label: _submitting ? 'Creating account…' : 'Activate account',
          loading: _submitting,
          onPressed: (_submitting || _password.text.isEmpty || _confirm.text.isEmpty) ? null : _submit,
        ),
        const SizedBox(height: 24),
        AuthLinkLine(prefix: 'Already have an account?', label: 'Sign in', onTap: _goToSignIn),
      ],
    );
  }
}
