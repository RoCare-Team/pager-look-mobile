import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Marketing copy from the web's `utils/landingData.js` and contact channels
/// from `utils/contactInfo.js`.

// ── Contact (web: utils/contactInfo.js) ───────────────────────────────────
const String supportPhone = '+918510099972';
const String supportPhoneDisplay = '+91 85100 99972';
const String supportEmail = 'info@pagerlook.com';

/// wa.me expects the number without '+' or separators.
String whatsappLink([String? message]) {
  final base = 'https://wa.me/${supportPhone.replaceAll(RegExp(r'\D'), '')}';
  if (message == null || message.isEmpty) return base;
  return '$base?text=${Uri.encodeComponent(message)}';
}

/// Default message of the web's floating WhatsApp button.
const String whatsappDefaultMessage = 'Hi PagerLook, I would like to know more about the platform.';

// ── Features (web: LANDING_FEATURES) ──────────────────────────────────────
class LandingFeature {
  const LandingFeature(this.title, this.description, this.icon, this.tone);
  final String title;
  final String description;
  final IconData icon;
  final Tone tone;
}

const List<LandingFeature> landingFeatures = [
  LandingFeature(
    'Verified Identity',
    'Aadhaar, DigiLocker, and biometric liveness checks create a tamper-proof professional identity.',
    Icons.verified_user_outlined,
    Tone.brand,
  ),
  LandingFeature(
    'Workforce Dashboard',
    'Monitor verification status, join requests, and trust scores across your entire organization.',
    Icons.dashboard_outlined,
    Tone.info,
  ),
  LandingFeature(
    'Trusted Job History',
    'Employees build verified employment records that employers can validate in seconds, not weeks.',
    Icons.work_outline,
    Tone.success,
  ),
  LandingFeature(
    'Document Vault',
    'Encrypted storage for offer letters, experience certificates, and compliance documents.',
    Icons.lock_outline,
    Tone.brand,
  ),
  LandingFeature(
    'QR Onboarding',
    'Onboard field teams instantly with secure QR codes and real-time verification workflows.',
    Icons.qr_code_2,
    Tone.info,
  ),
  LandingFeature(
    'Activity & Consent',
    'Every data access request is logged. Employees approve or deny before anything is shared.',
    Icons.history,
    Tone.warning,
  ),
];

// ── How it works (web: LANDING_STEPS) ─────────────────────────────────────
class LandingStep {
  const LandingStep(this.step, this.title, this.description, this.audience);
  final String step;
  final String title;
  final String description;

  /// 'both' | 'employee' | 'enterprise'
  final String audience;

  String get audienceLabel => switch (audience) {
        'employee' => 'Employee',
        'enterprise' => 'Employer',
        _ => 'Everyone',
      };

  Tone get audienceTone => switch (audience) {
        'employee' || 'enterprise' => Tone.brand,
        _ => Tone.neutral,
      };
}

const List<LandingStep> landingSteps = [
  LandingStep(
    '01',
    'Register or sign in',
    'Employers onboard their company; professionals create a secure profile.',
    'both',
  ),
  LandingStep(
    '02',
    'Verify identity',
    'DigiLocker Aadhaar and biometric checks establish trust at the source.',
    'employee',
  ),
  LandingStep(
    '03',
    'Build professional ID',
    'A cryptographically signed digital ID card and shareable profile link.',
    'employee',
  ),
  LandingStep(
    '04',
    'Manage workforce',
    'Review join requests, verify candidates, and monitor compliance from one hub.',
    'enterprise',
  ),
];

// ── Security (web: LANDING_SECURITY) ──────────────────────────────────────
const List<(String, String)> landingSecurity = [
  ('ISO 27001', 'Certified security framework'),
  ('256-bit SSL', 'End-to-end encryption'),
  ('DigiLocker', 'Government-backed identity'),
  ('GDPR-ready', 'Privacy by design'),
];
