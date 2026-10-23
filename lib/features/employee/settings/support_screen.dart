import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/widgets.dart';

// Web `utils/contactInfo.js` — single source of truth for support channels.
const String _supportPhone = '+918510099972';
const String _supportPhoneDisplay = '+91 85100 99972';
const String _supportEmail = 'info@pagerlook.com';
const String _instagramUrl = 'https://www.instagram.com/pagerlook/';

String _whatsappLink([String? message]) {
  final base = 'https://wa.me/${_supportPhone.replaceAll(RegExp(r'\D'), '')}';
  if (message == null || message.isEmpty) return base;
  return '$base?text=${Uri.encodeComponent(message)}';
}

String _mailtoLink({String? subject, String? body}) {
  final params = <String>[
    if (subject != null && subject.isNotEmpty) 'subject=${Uri.encodeComponent(subject)}',
    if (body != null && body.isNotEmpty) 'body=${Uri.encodeComponent(body)}',
  ];
  return params.isEmpty ? 'mailto:$_supportEmail' : 'mailto:$_supportEmail?${params.join('&')}';
}

class _Channel {
  const _Channel(this.label, this.hint, this.icon, this.tone, this.url);
  final String label;
  final String hint;
  final IconData icon;
  final Tone tone;
  final String url;
}

/// Port of `Support.jsx`.
class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({super.key});

  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  final _issue = TextEditingController();

  @override
  void initState() {
    super.initState();
    _issue.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _issue.dispose();
    super.dispose();
  }

  /// The web form is a front-end stub; on mobile the ticket is sent to the
  /// support mailbox through the user's mail app.
  Future<void> _createTicket() async {
    final issue = _issue.text.trim();
    if (issue.isEmpty) return;
    final veriworkId = ref.read(authProvider).profile?['veriworkId'];
    final body = veriworkId == null ? issue : '$issue\n\nPagerLook ID: $veriworkId';
    final opened = await openExternalUrl(_mailtoLink(subject: 'PagerLook support request', body: body));
    if (opened && mounted) {
      _issue.clear();
      showToast("Ticket drafted — send the email and we'll get back to you soon.", type: ToastType.success);
    }
  }

  Future<void> _logout() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Log out?',
      message: 'You will need to verify your mobile number again to sign in.',
      confirmLabel: 'Log out',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await ref.read(authProvider).logout();
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final channels = [
      _Channel(
        'WhatsApp',
        _supportPhoneDisplay,
        Icons.chat_outlined,
        Tone.success,
        _whatsappLink('Hi PagerLook support, I need help with my verification.'),
      ),
      const _Channel('Call us', _supportPhoneDisplay, Icons.call_outlined, Tone.brand, 'tel:$_supportPhone'),
      _Channel('Email', _supportEmail, Icons.mail_outline, Tone.brand, _mailtoLink(subject: 'PagerLook support request')),
      const _Channel('Instagram', '@pagerlook', Icons.camera_alt_outlined, Tone.danger, _instagramUrl),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Support & Resources')),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          const PageIntro(
            title: 'Support & Resources',
            subtitle: 'Get help with verification and account issues',
          ),
          StatGrid(
            children: channels
                .map(
                  (c) => AppCard(
                    onTap: () => openExternalUrl(c.url),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
                    child: Column(
                      children: [
                        Icon(c.icon, size: 30, color: c.tone.fg),
                        const SizedBox(height: 8),
                        Text(c.label, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.inkStrong)),
                        const SizedBox(height: 2),
                        Text(
                          c.hint,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 20),
          AppCard(
            color: AppColors.infoBg,
            title: 'Open a Support Ticket',
            subtitle: 'Have an issue with your verification? Our team typically responds within 2 hours.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(
                  controller: _issue,
                  label: 'Describe your issue',
                  hint: 'e.g. Job verification pending...',
                  maxLines: 4,
                  minLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 12),
                AppButton(
                  label: 'Create Ticket',
                  icon: Icons.send_outlined,
                  onPressed: _issue.text.trim().isEmpty ? null : _createTicket,
                ),
              ],
            ),
          ),
          MenuSection(
            children: [
              MenuTile(
                icon: Icons.logout,
                title: 'Logout Session',
                destructive: true,
                onTap: _logout,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
