import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';

/// Mobile version of the web `AuthLayout` + `AuthHero`: a navy brand hero at
/// the top (logo + portal copy) and the form panel underneath.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.children,
    this.onBack,
    this.showHeroCopy = true,
    this.busy = false,
    this.busyLabel,
  });

  final List<Widget> children;

  /// Shows a back arrow in the hero when set.
  final VoidCallback? onBack;

  /// The hero tagline is shown on the main sign-in screen only.
  final bool showHeroCopy;

  /// Blocks the form with a spinner overlay (web: `<Loader variant="overlay">`).
  final bool busy;
  final String? busyLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: BusyOverlay(
        busy: busy,
        label: busyLabel,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AuthHero(onBack: onBack, showCopy: showHeroCopy),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthHero extends StatelessWidget {
  const _AuthHero({this.onBack, required this.showCopy});

  final VoidCallback? onBack;
  final bool showCopy;

  @override
  Widget build(BuildContext context) {
    // Compact app header: back, logo and a small portal badge — no marketing copy.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.skyBg, AppColors.surface],
          ),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 48,
                  child: onBack == null
                      ? null
                      : IconButton(
                          tooltip: 'Back',
                          onPressed: onBack,
                          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.inkStrong),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 12, top: 4),
                  child: Row(
                    children: [
                      const BrandLogo(height: 32, white: false),
                      const Spacer(),
                      if (showCopy)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.skyBg,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppColors.sky.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.apartment_rounded, size: 14, color: AppColors.skyDeep),
                              SizedBox(width: 6),
                              Text(
                                'Employer',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.skyDeep),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Centered page heading used on the auth screens.
class AuthHeading extends StatelessWidget {
  const AuthHeading({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: AppColors.brand600,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14.5, height: 1.45, color: AppColors.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Question? Link" line used in auth footers.
class AuthLinkLine extends StatelessWidget {
  const AuthLinkLine({super.key, this.prefix, required this.label, required this.onTap});

  final String? prefix;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (prefix != null)
          Flexible(
            child: Text(prefix!, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
          ),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

/// Inline red error line under a form (web: `<p role="alert">`).
class FormErrorText extends StatelessWidget {
  const FormErrorText(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        message,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.danger),
      ),
    );
  }
}

/// Green tick + message block shown after a successful action.
class SuccessPanel extends StatelessWidget {
  const SuccessPanel({super.key, required this.title, required this.message});

  final String title;
  final Widget message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: AppColors.success, size: 26),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.inkStrong),
          ),
          const SizedBox(height: 6),
          DefaultTextStyle.merge(
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5, height: 1.45, color: AppColors.inkBody),
            child: message,
          ),
        ],
      ),
    );
  }
}

/// Pull a `token` out of a pasted link (`…/reset-password?token=abc`), or
/// accept a bare token. Returns an empty string when nothing usable was given.
String extractLinkToken(String input) {
  final text = input.trim();
  if (text.isEmpty) return '';
  final uri = Uri.tryParse(text);
  if (uri != null) {
    final fromQuery = uri.queryParameters['token'];
    if (fromQuery != null && fromQuery.trim().isNotEmpty) return fromQuery.trim();
  }
  // A bare token has no spaces and is not itself a URL.
  if (text.contains(RegExp(r'\s')) || text.contains('://') || text.contains('/')) return '';
  return text;
}

/// Card asking the user to paste the link (or token) from their email.
class PasteLinkCard extends StatefulWidget {
  const PasteLinkCard({
    super.key,
    required this.title,
    required this.message,
    required this.onToken,
    this.buttonLabel = 'Continue',
  });

  final String title;
  final String message;
  final ValueChanged<String> onToken;
  final String buttonLabel;

  @override
  State<PasteLinkCard> createState() => _PasteLinkCardState();
}

class _PasteLinkCardState extends State<PasteLinkCard> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final token = extractLinkToken(_controller.text);
    if (token.isEmpty) {
      setState(() => _error = 'Paste the full link from your email, or the token it contains.');
      return;
    }
    setState(() => _error = null);
    widget.onToken(token);
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: widget.title,
      subtitle: widget.message,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _controller,
            label: 'Link or token',
            hint: 'https://…?token=…',
            keyboardType: TextInputType.url,
            maxLines: 3,
            minLines: 1,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          if (_error != null) FormErrorText(_error!),
          const SizedBox(height: 14),
          AppButton(label: widget.buttonLabel, onPressed: _submit),
        ],
      ),
    );
  }
}
