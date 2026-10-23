import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import 'landing_data.dart';

/// Entry point for signed-out users (`/`): a full-screen app onboarding —
/// swipeable illustrated slides, then the two sign-in choices pinned at the
/// bottom. Same destinations as the web landing page's portal chooser:
/// professional sign-in, employer sign-in / registration, QR scan, demo,
/// WhatsApp and the admin console. Signed-in users never see it.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final PageController _pages = PageController();
  Timer? _timer;
  int _page = 0;

  static const _slides = [
    _Slide(
      audience: _Audience.employee,
      art: _IdCardArt(),
      title: 'Your verified\nwork identity',
      subtitle: 'Verify your Aadhaar once and carry a trusted professional ID everywhere you work.',
    ),
    _Slide(
      audience: _Audience.employee,
      art: _IconArt(icon: Icons.work_history_outlined, badge: Icons.verified_rounded),
      title: 'Jobs verified\nby real employers',
      subtitle: 'Your past companies confirm your experience — no more fake resumes.',
    ),
    _Slide(
      audience: _Audience.employer,
      art: _IconArt(icon: Icons.apartment_rounded, badge: Icons.groups_rounded),
      title: 'Hire with\nconfidence',
      subtitle: 'Employers onboard, verify and manage their workforce in one place.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_pages.hasClients) return;
      _pages.animateToPage(
        (_page + 1) % _slides.length,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  void _onMenu(String value) {
    switch (value) {
      case 'demo':
        context.push('/demo-request');
      case 'whatsapp':
        openExternalUrl(whatsappLink(whatsappDefaultMessage));
      case 'admin':
        context.push('/admin/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: Column(
            children: [
              // ── Top bar ───────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 4, 0),
                child: Row(
                  children: [
                    const BrandLogo(height: 28),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Scan a PagerLook QR code',
                      onPressed: () => context.push('/scan'),
                      icon: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.brand600),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      icon: const Icon(Icons.more_vert_rounded, color: AppColors.brand600),
                      color: AppColors.surface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      onSelected: _onMenu,
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'demo',
                          child: _MenuRow(icon: Icons.event_available_outlined, label: 'Book a demo'),
                        ),
                        PopupMenuItem(
                          value: 'whatsapp',
                          child: _MenuRow(icon: Icons.chat_bubble_outline_rounded, label: 'Chat on WhatsApp'),
                        ),
                        PopupMenuItem(
                          value: 'admin',
                          child: _MenuRow(icon: Icons.admin_panel_settings_outlined, label: 'Platform admin'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Slides ────────────────────────────────────────────────────
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: _slides.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) => _slides[i],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _slides.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page ? AppColors.brand600 : AppColors.brand100,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Actions ───────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Who are you?',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.brand900),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _BigButton(
                      label: "I'm an Employee",
                      subtitle: 'Get your verified work ID',
                      icon: Icons.person_outline_rounded,
                      filled: true,
                      onTap: () => context.push('/employee/otp'),
                    ),
                    const SizedBox(height: 12),
                    _BigButton(
                      label: "I'm an Employer",
                      subtitle: 'Company / HR — verify & manage your team',
                      icon: Icons.apartment_rounded,
                      filled: false,
                      onTap: () => context.push('/enterprise/login'),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('New company?', style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted)),
                        TextButton(
                          onPressed: () => context.push('/enterprise/register'),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
                          child: const Text('Register your company', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Who an onboarding slide speaks to — shown as a pill above its title.
enum _Audience {
  employee('For employees', Icons.person_rounded),
  employer('For employers', Icons.apartment_rounded);

  const _Audience(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// One onboarding page: illustration, audience tag, title and a one-line explanation.
class _Slide extends StatelessWidget {
  const _Slide({required this.audience, required this.art, required this.title, required this.subtitle});

  final _Audience audience;
  final Widget art;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Shrink the art on short screens so the text always fits.
        final artSize = (constraints.maxHeight * 0.55).clamp(150.0, 280.0);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: artSize,
                height: artSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.skyBg),
                    ),
                    Container(
                      margin: EdgeInsets.all(artSize * 0.12),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.brand100.withValues(alpha: 0.45),
                      ),
                    ),
                    FittedBox(child: Padding(padding: const EdgeInsets.all(24), child: art)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(color: AppColors.skyBg, borderRadius: BorderRadius.circular(99)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(audience.icon, size: 14, color: AppColors.brand600),
                    const SizedBox(width: 6),
                    Text(
                      audience.label.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: AppColors.brand600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(
                  fontSize: 27,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: AppColors.brand900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14.5, height: 1.45, color: AppColors.inkMuted),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : AppColors.brand600;
    return SizedBox(
      width: double.infinity,
      height: 66,
      child: Material(
        color: filled ? AppColors.brand600 : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: filled ? BorderSide.none : const BorderSide(color: AppColors.brand100, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Icon(icon, color: fg, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: fg),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: fg.withValues(alpha: 0.75)),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_rounded, color: fg, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.brand600),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.inkStrong)),
      ],
    );
  }
}

/// A small tilted Professional ID card — art for the first slide.
class _IdCardArt extends StatelessWidget {
  const _IdCardArt();

  @override
  Widget build(BuildContext context) {
    Widget line(double w, Color c) => Container(
          width: w,
          height: 7,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(99)),
        );

    return Transform.rotate(
      angle: -0.07,
      child: Container(
        width: 150,
        height: 182,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Color(0x33152763), blurRadius: 24, offset: Offset(0, 12))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              height: 34,
              color: AppColors.brand600,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: const Row(
                children: [
                  Icon(Icons.verified_user_rounded, size: 14, color: Colors.white),
                  SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      'PAGERLOOK ID',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(color: AppColors.skyBg, shape: BoxShape.circle),
              child: const Icon(Icons.person_rounded, color: AppColors.brand600, size: 32),
            ),
            const SizedBox(height: 12),
            line(84, AppColors.brand100),
            const SizedBox(height: 6),
            line(56, AppColors.hairline),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.successBg, borderRadius: BorderRadius.circular(99)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, size: 12, color: AppColors.success),
                  SizedBox(width: 4),
                  Text(
                    'Verified',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.success),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A big icon on a white disc with a small green badge — art for slides 2 & 3.
class _IconArt extends StatelessWidget {
  const _IconArt({required this.icon, required this.badge});

  final IconData icon;
  final IconData badge;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      height: 170,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 130,
            height: 130,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [BoxShadow(color: Color(0x2E152763), blurRadius: 24, offset: Offset(0, 12))],
            ),
            child: Icon(icon, size: 62, color: AppColors.brand600),
          ),
          Positioned(
            right: 18,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: Icon(badge, size: 22, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
