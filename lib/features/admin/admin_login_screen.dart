import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/json.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/widgets.dart';

/// Port of `pages/admin/AdminLogin.jsx`.
///
/// Credentials are always typed fresh — no autofill hints, so saved
/// enterprise/employee logins are not offered here.
class AdminLoginScreen extends ConsumerStatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  ConsumerState<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends ConsumerState<AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid || !isValidEmail(_email.text) || _password.text.isEmpty) {
      showToast('Enter valid admin credentials', type: ToastType.error);
      return;
    }

    setState(() => _submitting = true);
    try {
      final data = await ref.read(authApiProvider).loginAdmin(_email.text.trim(), _password.text);
      await ref.read(authProvider).loginAdmin(asMap(data));
      showToast('Welcome, Admin', type: ToastType.success);
      if (mounted) context.go('/admin/dashboard');
    } catch (e) {
      showErrorToast(e, 'Login failed');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin'),
        leading: context.canPop() ? null : IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/')),
      ),
      body: BusyOverlay(
        busy: _submitting,
        label: 'Authenticating...',
        child: SafeArea(
          top: false,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
              children: [
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.inkStrong,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.shield_outlined, color: Colors.white, size: 28),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Admin Console',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.inkStrong, letterSpacing: -0.4),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Review and approve enterprise registrations',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: AppColors.inkMuted),
                ),
                const SizedBox(height: 28),
                AppTextField(
                  controller: _email,
                  label: 'Admin Email',
                  hint: 'Enter admin email',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  enabled: !_submitting,
                  requiredMark: true,
                  validator: (v) => emailValidator(v),
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _password,
                  label: 'Password',
                  hint: 'Enter admin password',
                  obscure: true,
                  textInputAction: TextInputAction.done,
                  enabled: !_submitting,
                  requiredMark: true,
                  validator: (v) => (v == null || v.isEmpty) ? 'Password is required' : null,
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 24),
                AppButton(
                  label: _submitting ? 'Signing in...' : 'Sign In to Admin',
                  loading: _submitting,
                  onPressed: _submitting ? null : _submit,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Enterprise portal?', style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint)),
                    TextButton(
                      onPressed: _submitting ? null : () => context.go('/enterprise/login'),
                      child: const Text('Employer Login', style: TextStyle(fontSize: 12.5)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
