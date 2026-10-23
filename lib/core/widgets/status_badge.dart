import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// Pill showing a status. With no explicit [tone], the tone is inferred from
/// common backend status words (approved/verified → green, pending → amber…).
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key, this.tone, this.label, this.icon});

  final String? status;
  final Tone? tone;

  /// Display text; defaults to the humanised [status].
  final String? label;
  final IconData? icon;

  static Tone toneFor(String? status) {
    final s = (status ?? '').toLowerCase();
    const success = [
      'approved',
      'verified',
      'accepted',
      'active',
      'complete',
      'completed',
      'success',
      'connected',
      'joined',
      'confirmed',
      'granted',
      'won',
      'qualified',
      'employed',
    ];
    const warning = [
      'pending',
      'submitted',
      'in_review',
      'review',
      'in_progress',
      'awaiting',
      'sent',
      'requested',
      'processing',
      'invited',
      'draft',
      'partial',
      'contacted',
      'awaiting_consent',
      'awaiting_hr',
      'notice_period',
      'needs_review',
    ];
    const danger = [
      'rejected',
      'failed',
      'declined',
      'revoked',
      'expired',
      'inactive',
      'deactivated',
      'mismatch',
      'denied',
      'blocked',
      'lost',
      'disputed',
      'fraud',
      'terminated',
      'cancelled',
    ];
    if (success.contains(s)) return Tone.success;
    if (warning.contains(s)) return Tone.warning;
    if (danger.contains(s)) return Tone.danger;
    if (s.contains('verif') || s.contains('approv')) return Tone.success;
    if (s.contains('pend') || s.contains('await') || s.contains('review')) return Tone.warning;
    if (s.contains('reject') || s.contains('fail') || s.contains('revok')) return Tone.danger;
    return Tone.neutral;
  }

  @override
  Widget build(BuildContext context) {
    final t = tone ?? toneFor(status);
    final text = label ?? humanize(status);
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: t.fg), const SizedBox(width: 4)],
          Text(text, style: TextStyle(color: t.fg, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
