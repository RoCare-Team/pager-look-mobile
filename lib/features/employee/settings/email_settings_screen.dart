import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';

/// Web `unwrap(res)` — `res?.data || res`.
Map<String, dynamic> _unwrap(Object? res) {
  final m = asMap(res);
  return m['data'] is Map ? asMap(m['data']) : m;
}

final _smtpProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return _unwrap(await ref.watch(employeeApiProvider).fetchSmtpSettings());
});

/// Port of `EmailSettings.jsx` + `SmtpSettingsSection.jsx`.
class EmailSettingsScreen extends ConsumerStatefulWidget {
  const EmailSettingsScreen({super.key});

  @override
  ConsumerState<EmailSettingsScreen> createState() => _EmailSettingsScreenState();
}

class _EmailSettingsScreenState extends ConsumerState<EmailSettingsScreen> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '587');
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _senderName = TextEditingController();
  final _senderEmail = TextEditingController();
  bool _secure = false;
  bool _hasPassword = false;
  bool _seeded = false;
  bool _saving = false;
  bool _testing = false;

  @override
  void dispose() {
    for (final c in [_host, _port, _username, _password, _senderName, _senderEmail]) {
      c.dispose();
    }
    super.dispose();
  }

  void _seed(Map<String, dynamic> s) {
    _host.text = str(s['host']);
    _port.text = '${asInt(s['port'], 587) == 0 ? 587 : asInt(s['port'], 587)}';
    _secure = asBool(s['secure']);
    _username.text = str(s['username']);
    _password.text = '';
    _senderName.text = str(s['senderName']);
    _senderEmail.text = strOrNull(s['senderEmail']) ?? str(s['defaultSenderEmail']);
    _hasPassword = asBool(s['hasPassword']);
    _seeded = true;
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final port = int.tryParse(_port.text.trim());
      final res = _unwrap(await ref.read(employeeApiProvider).updateSmtpSettings({
        'host': _host.text.trim(),
        'port': (port == null || port == 0) ? 587 : port,
        'secure': _secure,
        'username': _username.text.trim(),
        // Write-only: only send a password the user typed.
        if (_password.text.isNotEmpty) 'password': _password.text,
        'senderName': _senderName.text.trim(),
        'senderEmail': _senderEmail.text.trim(),
      }));
      if (!mounted) return;
      setState(() {
        _hasPassword = asBool(res['hasPassword']);
        _password.clear();
      });
      ref.invalidate(_smtpProvider);
      showToast(
        asBool(res['configured'])
            ? 'Email settings saved'
            : 'Email settings saved (incomplete — add a password to enable sending)',
        type: ToastType.success,
      );
    } catch (e) {
      showErrorToast(e, 'Failed to save email settings');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    try {
      final r = _unwrap(await ref.read(employeeApiProvider).sendSmtpTest({}));
      if (asBool(r['sent'])) {
        showToast('Test email sent to ${str(r['to'])}', type: ToastType.success);
      } else {
        showToast('Test not sent — check configuration', type: ToastType.error);
      }
    } catch (e) {
      showErrorToast(e, 'Email test failed');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final smtpAsync = ref.watch(_smtpProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Email & Verification Sending')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(_smtpProvider.future),
        child: AsyncValueView<Map<String, dynamic>>(
          value: smtpAsync,
          loadingLabel: 'Loading…',
          onRetry: () => ref.invalidate(_smtpProvider),
          data: (settings) {
            if (!_seeded) _seed(settings);
            final configured = asBool(settings['configured']);
            final defaultSender = strOrNull(settings['defaultSenderEmail']);
            final busy = _saving || _testing;

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                const PageIntro(
                  title: 'Email & Verification Sending',
                  subtitle: 'Send employment verification requests from your own mailbox',
                ),
                const AppCard(
                  color: AppColors.infoBg,
                  title: 'How self-verification works',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Step(1, 'You request verification of a past job from Job History.'),
                      _Step(2, 'A secure request email is sent from your mailbox to your previous HR.'),
                      _Step(3, 'HR fills the response — it is locked and cannot be edited afterwards.'),
                      _Step(4, 'The response is analysed and attached to that experience for future employers.'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppCard(
                  title: 'Email (SMTP) Settings',
                  subtitle: 'Configure your mailbox once — when you request verification of a past job, the '
                      'request email is sent to the HR from your own address.',
                  action: StatusBadge(
                    null,
                    label: configured ? 'ACTIVE' : 'NOT CONFIGURED',
                    tone: configured ? Tone.success : Tone.warning,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppTextField(
                        controller: _host,
                        label: 'SMTP Host',
                        hint: 'smtp.gmail.com',
                        keyboardType: TextInputType.url,
                        enabled: !busy,
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        controller: _port,
                        label: 'Port',
                        hint: '587',
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
                        enabled: !busy,
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        controller: _username,
                        label: 'Username',
                        hint: 'you@gmail.com',
                        keyboardType: TextInputType.emailAddress,
                        enabled: !busy,
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        controller: _password,
                        label: 'Password',
                        hint: _hasPassword ? '•••••••• (unchanged)' : 'SMTP password / app password',
                        obscure: true,
                        autofillHints: const [AutofillHints.newPassword],
                        enabled: !busy,
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        controller: _senderName,
                        label: 'Sender Name',
                        hint: 'Your full name',
                        textCapitalization: TextCapitalization.words,
                        enabled: !busy,
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        controller: _senderEmail,
                        label: 'Sender Email',
                        hint: defaultSender ?? 'you@gmail.com',
                        helper: 'Defaults to your registered email${defaultSender == null ? '' : ' ($defaultSender)'}.',
                        keyboardType: TextInputType.emailAddress,
                        enabled: !busy,
                      ),
                      const SizedBox(height: 6),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _secure,
                        onChanged: busy ? null : (v) => setState(() => _secure = v),
                        title: const Text(
                          'Use SSL/TLS',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: const Text('Secure connection, usually port 465'),
                      ),
                      const SizedBox(height: 8),
                      AppButton(
                        label: _saving ? 'Saving…' : 'Save email settings',
                        loading: _saving,
                        onPressed: _testing ? null : _save,
                      ),
                      const SizedBox(height: 10),
                      AppButton(
                        label: _testing ? 'Sending…' : 'Send test email',
                        variant: AppButtonVariant.secondary,
                        loading: _testing,
                        onPressed: (!configured || _saving) ? null : _test,
                      ),
                      if (!configured)
                        const Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: Text(
                            'Save a complete configuration (host, username, password, sender email) to enable '
                            'test emails and live sending.',
                            style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.number, this.text);

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: Text('$number.', style: const TextStyle(fontSize: 12.5, color: AppColors.brand600, fontWeight: FontWeight.w700)),
          ),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, color: AppColors.inkBody))),
        ],
      ),
    );
  }
}
