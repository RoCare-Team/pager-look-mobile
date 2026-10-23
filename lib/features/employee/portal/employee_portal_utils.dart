import 'package:flutter/material.dart';

import '../../../core/config/env.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';

/// Local ports of the web employee-portal helpers:
/// `employeeScoreUtils.js`, `employeeJourney.js`, `jobHistoryUtils.js`,
/// `hrContacts.js`, `enterpriseTeamUtils.js` (status styles),
/// `lib/publicProfileUrl.js` and `components/common/HrContactsEditor.jsx`.

// ── Score ───────────────────────────────────────────────────────────────────

const int scoreMin = 300;
const int scoreMax = 1000;

class ScoreRating {
  const ScoreRating({required this.label, required this.tier, required this.tone, required this.description});

  final String label;
  final String tier;
  final Tone tone;
  final String description;
}

/// A segment of the score gauge — same cut-offs as [scoreRatingFor].
class ScoreBand {
  const ScoreBand(this.min, this.max, this.label, this.color);

  final int min;
  final int max;
  final String label;
  final Color color;

  bool contains(num score) => score >= min && score <= max;
}

const List<ScoreBand> scoreBands = [
  ScoreBand(300, 450, 'High Risk', AppColors.scoreHighRisk),
  ScoreBand(451, 600, 'Needs Improvement', AppColors.scoreNeedsWork),
  ScoreBand(601, 750, 'Fair', AppColors.scoreFair),
  ScoreBand(751, 850, 'Good', AppColors.scoreGood),
  ScoreBand(851, 950, 'Excellent', AppColors.scoreExcellent),
  ScoreBand(951, 1000, 'Elite', AppColors.scoreElite),
];

ScoreBand scoreBandFor(num score) => scoreBands.firstWhere((b) => b.contains(score.round()),
    orElse: () => score < 300 ? scoreBands.first : scoreBands.last);

/// The six PagerLook trust bands (web `getScoreRating`).
ScoreRating scoreRatingFor(num score) {
  if (score >= 951) {
    return const ScoreRating(
      label: 'Elite Trust',
      tier: 'A+',
      tone: Tone.brand,
      description: 'Elite trust. Fully verified across identity, employment and compliance.',
    );
  }
  if (score >= 851) {
    return const ScoreRating(
      label: 'Excellent',
      tier: 'A',
      tone: Tone.success,
      description: 'Top-tier verified professional. Highly trusted by employers.',
    );
  }
  if (score >= 751) {
    return const ScoreRating(
      label: 'Good',
      tier: 'B',
      tone: Tone.info,
      description: 'Strong, reliable profile. Employers can hire with confidence.',
    );
  }
  if (score >= 601) {
    return const ScoreRating(
      label: 'Fair',
      tier: 'C',
      tone: Tone.warning,
      description: 'Building trust. Verify more employment and education records.',
    );
  }
  if (score >= 451) {
    return const ScoreRating(
      label: 'Needs Improvement',
      tier: 'D',
      tone: Tone.warning,
      description: 'Getting started. Complete identity and add verified jobs to improve.',
    );
  }
  return const ScoreRating(
    label: 'High Risk',
    tier: 'E',
    tone: Tone.danger,
    description: 'High risk. Start verifying your identity and employment to build trust.',
  );
}

// ── Journey (web `employeeJourney.js`) ─────────────────────────────────────

class JourneyStep {
  const JourneyStep({
    required this.id,
    required this.title,
    required this.description,
    required this.isRequired,
    required this.points,
    required this.path,
  });

  final String id;
  final String title;
  final String description;
  final bool isRequired;
  final int points;
  final String path;
}

const List<JourneyStep> journeySteps = [
  JourneyStep(
    id: 'profile',
    title: 'Your details',
    description: 'Name, role and contact details',
    isRequired: true,
    points: 100,
    path: '/employee/profile-setup',
  ),
  JourneyStep(
    id: 'education',
    title: 'Education',
    description: '10th, 12th and graduation',
    isRequired: false,
    points: 45,
    path: '/employee/profile-setup?step=education',
  ),
  JourneyStep(
    id: 'identity',
    title: 'Aadhaar & Face',
    description: 'Aadhaar e-KYC and a live face check',
    isRequired: false,
    points: 200,
    path: '/employee/verification',
  ),
];

bool hasAnyEducation(Map<String, dynamic>? profile) {
  bool filled(String a, String b) => strOrNull(pick(profile, a)) != null && strOrNull(pick(profile, b)) != null;
  return filled('education.class10.board', 'education.class10.school') ||
      filled('education.class12.board', 'education.class12.school') ||
      filled('education.graduation.degree', 'education.graduation.college');
}

List<String> completedJourneySteps(Map<String, dynamic>? profile) {
  if (profile == null) return const [];
  return [
    if (asBool(profile['profileSetupComplete'])) 'profile',
    if (hasAnyEducation(profile)) 'education',
    if (asBool(profile['aadhaarVerified']) && asBool(profile['biometricVerified'])) 'identity',
  ];
}

List<JourneyStep> missingJourneySteps(Map<String, dynamic>? profile) {
  final done = completedJourneySteps(profile);
  return journeySteps.where((s) => !done.contains(s.id) && !s.isRequired).toList();
}

// ── Jobs (web `jobHistoryUtils.js`) ─────────────────────────────────────────

String formatJobPeriod(Map<String, dynamic> job) {
  final duration = strOrNull(job['duration']);
  if (duration != null) return duration;
  if (strOrNull(job['joiningDate']) == null) return '—';
  final start = formatDate(job['joiningDate']);
  if (asBool(job['isPresent'])) return '$start – Present';
  if (strOrNull(job['exitDate']) != null) return '$start – ${formatDate(job['exitDate'])}';
  return start;
}

const List<String> _verifiedLevels = ['document_verified', 'hr_verified', 'employer_verified'];

bool isJobVerified(Map<String, dynamic> job) {
  if (str(job['status']) == 'verified') return true;
  return _verifiedLevels.contains(str(job['verificationLevel'], 'none'));
}

class JobBadge {
  const JobBadge(this.label, this.tone);
  final String label;
  final Tone tone;
}

JobBadge jobVerificationBadge(Map<String, dynamic> job) {
  final level = str(job['verificationLevel'], 'none');
  final tagLabel = strOrNull(pick(job, 'verificationTag.label')) ?? strOrNull(job['statusLabel']) ?? 'Not Verified';
  switch (level) {
    case 'employer_verified':
    case 'hr_verified':
      return JobBadge(tagLabel, Tone.success);
    case 'document_verified':
      return JobBadge(tagLabel, Tone.info);
  }
  if (str(job['status']) == 'in_process') return const JobBadge('Verification in progress', Tone.warning);
  return JobBadge(tagLabel, Tone.neutral);
}

String companyInitials(String company) {
  final words = company.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return 'CO';
  if (words.length == 1) {
    final w = words.first;
    return (w.length > 2 ? w.substring(0, 2) : w).toUpperCase();
  }
  return '${words[0][0]}${words[1][0]}'.toUpperCase();
}

// ── HR contacts (web `hrContacts.js`) ───────────────────────────────────────

/// Trimmed, non-empty, case-insensitively deduped (order preserved).
List<String> cleanContacts(Iterable<String> contacts) {
  final seen = <String>{};
  final out = <String>[];
  for (final value in contacts) {
    final email = value.trim();
    if (email.isEmpty) continue;
    if (seen.add(email.toLowerCase())) out.add(email);
  }
  return out;
}

// ── Status styles (web `enterpriseTeamUtils.js`) ────────────────────────────

class StatusStyle {
  const StatusStyle(this.label, this.tone);
  final String label;
  final Tone tone;
}

StatusStyle accessRequestStatusStyle(String? status) {
  switch (status) {
    case 'accepted':
      return const StatusStyle('Accepted', Tone.success);
    case 'approved':
      return const StatusStyle('Approved', Tone.success);
    case 'pending':
      return const StatusStyle('Pending', Tone.warning);
    case 'rejected':
      return const StatusStyle('Rejected', Tone.danger);
  }
  return StatusStyle((status == null || status.isEmpty) ? 'Unknown' : status, Tone.neutral);
}

StatusStyle invitationStatusStyle(String? status) {
  switch (status) {
    case 'pending':
      return const StatusStyle('Invitation Sent', Tone.info);
    case 'pending_registration':
      return const StatusStyle('Pending Registration', Tone.neutral);
    case 'accepted':
      return const StatusStyle('Accepted', Tone.success);
    case 'rejected':
      return const StatusStyle('Rejected', Tone.danger);
  }
  return StatusStyle((status == null || status.isEmpty) ? 'Unknown' : status, Tone.neutral);
}

String formatRequestType(String? type) {
  const labels = {
    'profile_access': 'Profile Access',
    'background_check': 'Background Check',
    'verification_data': 'Verification Data',
    'full_profile_access': 'Get Full Profile Access',
  };
  if (type == null || type.isEmpty) return '—';
  final known = labels[type];
  if (known != null) return known;
  return type.split('_').where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
}

// ── Public profile link (web `lib/publicProfileUrl.js`) ─────────────────────

/// `publicSlug` first, `veriworkId` as fallback.
String publicProfileIdentity(Map<String, dynamic>? profile) =>
    strOrNull(profile?['publicSlug']) ?? strOrNull(profile?['veriworkId']) ?? '';

String buildPublicProfileUrl(Map<String, dynamic>? profile) {
  final identity = publicProfileIdentity(profile);
  if (identity.isEmpty) return '';
  return '${Env.appOrigin}/u/${Uri.encodeComponent(identity)}';
}

// ── Small shared widgets ────────────────────────────────────────────────────

/// Uppercase eyebrow label used above card titles.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color = AppColors.inkFaint});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.7, color: color),
    );
  }
}

/// Small grey tag (employment type, department …).
class TagChip extends StatelessWidget {
  const TagChip(this.text, {super.key, this.tone = Tone.neutral});

  final String text;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: tone.fg)),
    );
  }
}

/// Editable list of HR contact emails (web `HrContactsEditor.jsx`).
///
/// Owns its text controllers; reports the full list (blanks included) through
/// [onChanged]. Give it a new `key` to re-seed it from [initial].
class HrContactsEditor extends StatefulWidget {
  const HrContactsEditor({
    super.key,
    required this.initial,
    required this.onChanged,
    this.max = 10,
    this.minRows = 1,
    this.enabled = true,
    this.label,
    this.hint,
    this.rowLabel,
    this.placeholder,
    this.addLabel = 'Add another HR contact',
    this.showLimitNote = true,
  });

  final List<String> initial;
  final ValueChanged<List<String>> onChanged;
  final int max;

  /// Rows that can never be removed.
  final int minRows;
  final bool enabled;
  final String? label;
  final String? hint;

  /// Per-row field label, e.g. `HR Contact 1`.
  final String Function(int index)? rowLabel;
  final String Function(int index)? placeholder;
  final String addLabel;
  final bool showLimitNote;

  @override
  State<HrContactsEditor> createState() => _HrContactsEditorState();
}

class _HrContactsEditorState extends State<HrContactsEditor> {
  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    final rows = [...widget.initial];
    final min = widget.minRows < 1 ? 1 : widget.minRows;
    while (rows.length < min) {
      rows.add('');
    }
    _controllers = rows.map((e) => TextEditingController(text: e)).toList();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _emit() => widget.onChanged(_controllers.map((c) => c.text).toList());

  void _add() {
    if (_controllers.length >= widget.max) return;
    setState(() => _controllers.add(TextEditingController()));
    _emit();
  }

  void _remove(int index) {
    final min = widget.minRows < 1 ? 1 : widget.minRows;
    if (_controllers.length <= min) return;
    final removed = _controllers.removeAt(index);
    setState(() {});
    // Dispose after the field using it has been unmounted.
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
    _emit();
  }

  String _placeholder(int i) => widget.placeholder?.call(i) ?? (i == 0 ? 'hr@company.com' : 'another.hr@company.com');

  @override
  Widget build(BuildContext context) {
    final min = widget.minRows < 1 ? 1 : widget.minRows;
    final canRemove = _controllers.length > min;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null)
          Text(widget.label!,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkBody)),
        if (widget.hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(widget.hint!, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
          ),
        for (var i = 0; i < _controllers.length; i++)
          Padding(
            key: ObjectKey(_controllers[i]),
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.rowLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      widget.rowLabel!(i),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkBody),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controllers[i],
                        enabled: widget.enabled,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        onChanged: (_) => _emit(),
                        decoration: InputDecoration(
                          hintText: _placeholder(i),
                          prefixIcon: const Icon(Icons.mail_outline, size: 20),
                        ),
                      ),
                    ),
                    if (canRemove)
                      IconButton(
                        tooltip: 'Remove HR contact ${i + 1}',
                        onPressed: widget.enabled ? () => _remove(i) : null,
                        icon: const Icon(Icons.close, size: 20, color: AppColors.inkMuted),
                      ),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        if (_controllers.length < widget.max)
          TextButton.icon(
            onPressed: widget.enabled ? _add : null,
            icon: const Icon(Icons.add, size: 18),
            label: Text(widget.addLabel),
          )
        else if (widget.showLimitNote)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'You can add up to ${widget.max} HR contacts.',
              style: const TextStyle(fontSize: 12, color: AppColors.inkFaint),
            ),
          ),
      ],
    );
  }
}
