import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/json.dart';
import '../../../../core/widgets/widgets.dart';

/// `GET /company/settings/smtp`.
final smtpSettingsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return asMap(await ref.watch(enterpriseApiProvider).fetchSmtpSettings());
});

// ─────────────────────────────────────────────────────────────────────────────
// SmtpSettingsSection
// ─────────────────────────────────────────────────────────────────────────────

class SmtpSettingsCard extends ConsumerStatefulWidget {
  const SmtpSettingsCard({super.key, this.canManage = true});

  /// Saving / testing needs `settings: manage` on the backend.
  final bool canManage;

  @override
  ConsumerState<SmtpSettingsCard> createState() => _SmtpSettingsCardState();
}

class _SmtpSettingsCardState extends ConsumerState<SmtpSettingsCard> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '587');
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _senderName = TextEditingController();
  final _senderEmail = TextEditingController();
  bool _secure = false;
  bool _hasPassword = false;
  bool _saving = false;
  bool _testing = false;
  bool _initialised = false;
  ProviderSubscription<AsyncValue<Map<String, dynamic>>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref.listenManual<AsyncValue<Map<String, dynamic>>>(
      smtpSettingsProvider,
      (previous, next) {
        // Skip the refresh's "loading with previous value" state so a reload
        // doesn't flash the old values over the form.
        if (next.isLoading) return;
        final s = next.valueOrNull;
        if (s != null) _apply(s);
      },
      fireImmediately: true,
    );
    _initialised = true;
  }

  void _apply(Map<String, dynamic> s) {
    _host.text = str(s['host']);
    final port = asInt(s['port']);
    _port.text = '${port == 0 ? 587 : port}';
    _username.text = str(s['username']);
    _password.clear();
    _senderName.text = str(s['senderName']);
    _senderEmail.text = str(s['senderEmail'] ?? s['defaultSenderEmail']);
    _secure = asBool(s['secure']);
    _hasPassword = asBool(s['hasPassword']);
    if (_initialised && mounted) setState(() {});
  }

  @override
  void dispose() {
    _sub?.close();
    for (final c in [_host, _port, _username, _password, _senderName, _senderEmail]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final port = int.tryParse(_port.text.trim()) ?? 0;
    try {
      final s = asMap(await ref.read(enterpriseApiProvider).updateSmtpSettings({
        'host': _host.text.trim(),
        'port': port == 0 ? 587 : port,
        'secure': _secure,
        'username': _username.text.trim(),
        // Write-only: only sent when a new one was typed.
        if (_password.text.isNotEmpty) 'password': _password.text,
        'senderName': _senderName.text.trim(),
        'senderEmail': _senderEmail.text.trim(),
      }));
      _hasPassword = asBool(s['hasPassword']);
      _password.clear();
      showToast(
        asBool(s['configured'])
            ? 'SMTP settings saved'
            : 'SMTP settings saved (incomplete — add a password to enable sending)',
        type: ToastType.success,
      );
      ref.invalidate(smtpSettingsProvider);
    } catch (e) {
      showErrorToast(e, 'Failed to save SMTP settings');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    try {
      final r = asMap(await ref.read(enterpriseApiProvider).sendSmtpTest(<String, dynamic>{}));
      final sent = asBool(r['sent']);
      showToast(
        sent ? 'Test email sent to ${str(r['to'])}' : 'Test not sent — check configuration',
        type: sent ? ToastType.success : ToastType.error,
      );
    } catch (e) {
      showErrorToast(e, 'SMTP test failed');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(smtpSettingsProvider);
    final settings = async.valueOrNull ?? const <String, dynamic>{};
    final configured = asBool(settings['configured']);
    final defaultSender = str(settings['defaultSenderEmail']);
    final editable = widget.canManage && !_saving;

    if (async.isLoading && !async.hasValue) {
      return const AppCard(
        title: 'SMTP Settings',
        child: Text('Loading…', style: TextStyle(color: AppColors.inkMuted)),
      );
    }
    if (async.hasError && !async.hasValue) {
      return AppCard(
        title: 'SMTP Settings',
        child: Text(errorMessage(async.error), style: const TextStyle(color: AppColors.danger)),
      );
    }

    return AppCard(
      title: 'SMTP Settings',
      subtitle: 'Configure your mail server once — all employment verification emails are sent from here.',
      action: StatusBadge(
        configured ? 'active' : 'not_configured',
        label: configured ? 'Active' : 'Not configured',
        tone: configured ? Tone.success : Tone.warning,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: AppTextField(
                  controller: _host,
                  label: 'SMTP Host',
                  hint: 'smtp.yourprovider.com',
                  keyboardType: TextInputType.url,
                  enabled: editable,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: AppTextField(
                  controller: _port,
                  label: 'Port',
                  hint: '587',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  enabled: editable,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AppTextField(
            controller: _username,
            label: 'Username',
            hint: 'mailer@yourcompany.com',
            keyboardType: TextInputType.emailAddress,
            enabled: editable,
          ),
          const SizedBox(height: 14),
          AppTextField(
            controller: _password,
            label: 'Password',
            hint: _hasPassword ? '•••••••• (unchanged)' : 'SMTP password / app key',
            obscure: true,
            enabled: editable,
          ),
          const SizedBox(height: 14),
          AppTextField(
            controller: _senderName,
            label: 'Sender Name',
            hint: 'Your Company HR',
            enabled: editable,
          ),
          const SizedBox(height: 14),
          AppTextField(
            controller: _senderEmail,
            label: 'Sender Email',
            hint: defaultSender.isEmpty ? 'no-reply@yourcompany.com' : defaultSender,
            helper: 'Defaults to your registered email${defaultSender.isEmpty ? '' : ' ($defaultSender)'}.',
            keyboardType: TextInputType.emailAddress,
            enabled: editable,
          ),
          SwitchListTile(
            value: _secure,
            onChanged: editable ? (v) => setState(() => _secure = v) : null,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Use SSL/TLS (secure connection, usually port 465)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          if (widget.canManage) ...[
            const SizedBox(height: 4),
            AppButton(
              label: _saving ? 'Saving…' : 'Save SMTP settings',
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
            const SizedBox(height: 8),
            AppButton(
              label: _testing ? 'Sending…' : 'Send test email',
              variant: AppButtonVariant.secondary,
              loading: _testing,
              onPressed: _testing || !configured ? null : _test,
            ),
          ],
          if (!configured)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Save a complete configuration (host, username, password, sender email) to enable test emails '
                'and live sending.',
                style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ChangePasswordSection
// ─────────────────────────────────────────────────────────────────────────────

class ChangePasswordCard extends ConsumerStatefulWidget {
  const ChangePasswordCard({super.key});

  @override
  ConsumerState<ChangePasswordCard> createState() => _ChangePasswordCardState();
}

class _ChangePasswordCardState extends ConsumerState<ChangePasswordCard> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String _error = '';
  bool _saving = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = '');
    if (_next.text.length < 8) {
      setState(() => _error = 'New password must be at least 8 characters');
      return;
    }
    if (_next.text != _confirm.text) {
      setState(() => _error = 'New password and confirmation do not match');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(authApiProvider).changePassword(_current.text, _next.text);
      showToast('Password updated successfully', type: ToastType.success);
      _current.clear();
      _next.clear();
      _confirm.clear();
      if (mounted) setState(() => _error = '');
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Failed to update password'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _current.text.isNotEmpty && _next.text.isNotEmpty && _confirm.text.isNotEmpty;
    return AppCard(
      title: 'Change Password',
      subtitle: 'Update the password you use to sign in to your employer portal.',
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              controller: _current,
              label: 'Current password',
              obscure: true,
              enabled: !_saving,
              autofillHints: const [AutofillHints.password],
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _next,
              label: 'New password',
              hint: 'At least 8 characters',
              obscure: true,
              enabled: !_saving,
              autofillHints: const [AutofillHints.newPassword],
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _confirm,
              label: 'Confirm new password',
              obscure: true,
              enabled: !_saving,
              autofillHints: const [AutofillHints.newPassword],
              onChanged: (_) => setState(() {}),
            ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _error,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.danger, fontWeight: FontWeight.w500),
                ),
              ),
            const SizedBox(height: 16),
            AppButton(
              label: _saving ? 'Updating…' : 'Update password',
              loading: _saving,
              onPressed: _saving || !ready ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
