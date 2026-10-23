import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/json.dart';
import '../../../../core/widgets/widgets.dart';
import 'team_utils.dart';

/// Web `EmploymentStatusBadge`.
class EmploymentStatusBadge extends StatelessWidget {
  const EmploymentStatusBadge({super.key, this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = employmentStatusStyle(status);
    return StatusBadge(status, label: label, tone: tone);
  }
}

/// Small uppercase caption used above values.
class CaptionText extends StatelessWidget {
  const CaptionText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style:
          const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: AppColors.inkFaint),
    );
  }
}

/// "Profile / Docs / Verify" chips for granted access (web `AccessGrantedBadges`).
class AccessGrantedBadges extends StatelessWidget {
  const AccessGrantedBadges({super.key, required this.access});

  final Map<String, dynamic> access;

  @override
  Widget build(BuildContext context) {
    final full =
        access['fullProfileAccess'] == true || access['full_profile_access'] == true || access['hasAllAccess'] == true;
    final items = <(String, Color)>[
      if (full || access['profileAccess'] == true) ('Profile', AppColors.success),
      if (full || access['backgroundCheck'] == true) ('Docs', AppColors.info),
      if (full || access['verificationData'] == true) ('Verify', const Color(0xFF7C3AED)),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: items
          .map(
            (i) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(999)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: i.$2, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(i.$1,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.inkBody)),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

/// Team member row — merges the web `TeamEmployeeRow` (team page) and
/// `TeamEmployeeCard` (department page) into a compact, tappable list row:
/// avatar, name, role, one status line and the score. Secondary actions live
/// in the ⋮ menu; pass null callbacks to hide actions the user's role can't do.
class TeamEmployeeCard extends StatelessWidget {
  const TeamEmployeeCard({
    super.key,
    required this.employee,
    this.department,
    this.onRequestAccess,
    this.onRemoveAccess,
    this.onAssign,
  });

  final Map<String, dynamic> employee;
  final String? department;
  final ValueChanged<Map<String, dynamic>>? onRequestAccess;
  final ValueChanged<Map<String, dynamic>>? onRemoveAccess;
  final ValueChanged<Map<String, dynamic>>? onAssign;

  @override
  Widget build(BuildContext context) {
    final name = employeeName(employee);
    final role = employeeRole(employee);
    final rawDept = department ?? strOrNull(employee['department']);
    final dept = rawDept != null && rawDept != 'Unassigned' ? rawDept : null;
    final profilePath = employeeProfilePath(employee);
    final stage = str(employee['onboardingStage'], 'incoming');
    final score = asNum(employee['trustScore']);
    final accessButton = resolveEmployeeAccessButton(employee);

    // One status line: the onboarding stage, or the employment status once active.
    final (employmentLabel, employmentTone) =
        employmentStatusStyle(strOrNull(employee['employmentStatus']) ?? 'active');
    final (String statusLabel, Color statusColor) = switch (stage) {
      'pending_verification' => ('Pending verification', AppColors.warning),
      'verified' => ('Ready to assign', AppColors.info),
      _ => (employmentLabel, employmentTone.fg),
    };

    final actions = <(String, IconData, VoidCallback?)>[
      if (stage == 'pending_verification' && profilePath != null)
        ('Verify employment', Icons.verified_outlined, () => context.push(profilePath)),
      if (stage == 'verified' && onAssign != null)
        ('Assign department', Icons.apartment_outlined, () => onAssign!(employee)),
      if (accessButton == AccessButton.requestAccess && onRequestAccess != null)
        ('Request access', Icons.key_outlined, () => onRequestAccess!(employee)),
      if (accessButton == AccessButton.pending) ('Access pending', Icons.hourglass_empty_rounded, null),
      if (accessButton == AccessButton.removeAccess && onRemoveAccess != null)
        ('Remove access', Icons.key_off_outlined, () => onRemoveAccess!(employee)),
      if (profilePath != null) ('View profile', Icons.person_outline_rounded, () => context.push(profilePath)),
    ];

    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      onTap: profilePath == null ? null : () => context.push(profilePath),
      child: Row(
        children: [
          AppAvatar(name: name, imageUrl: employeePhoto(employee), size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.inkStrong),
                ),
                const SizedBox(height: 1),
                Text(
                  [role, if (dept != null) dept].where((s) => s.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        statusLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                score == null ? '—' : '${score.round()}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.inkStrong),
              ),
              const Text('Score', style: TextStyle(fontSize: 11, color: AppColors.inkFaint)),
            ],
          ),
          PopupMenuButton<int>(
            tooltip: 'Actions',
            icon: const Icon(Icons.more_vert_rounded, color: AppColors.inkMuted),
            color: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (i) => actions[i].$3?.call(),
            itemBuilder: (_) => [
              for (var i = 0; i < actions.length; i++)
                PopupMenuItem(
                  value: i,
                  enabled: actions[i].$3 != null,
                  child: Row(
                    children: [
                      Icon(actions[i].$2, size: 20, color: AppColors.inkMuted),
                      const SizedBox(width: 12),
                      Text(actions[i].$1),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pending invitation row (web `PendingInvitationsTab` row / `PendingInvitationCard`).
class PendingInvitationTile extends StatelessWidget {
  const PendingInvitationTile({super.key, required this.invitation, this.showCopyLink = true});

  final Map<String, dynamic> invitation;
  final bool showCopyLink;

  @override
  Widget build(BuildContext context) {
    final email = str(invitation['employeeEmail'] ?? invitation['email']);
    final mobile = str(invitation['employeeMobile']);
    final name = strOrNull(invitation['employeeName']) ??
        (email.isNotEmpty ? email : (mobile.isNotEmpty ? mobile : 'Invited employee'));
    final department = strOrNull(invitation['department']) ?? '—';
    final contact = [email, mobile].where((s) => s.isNotEmpty).join(' · ');
    final link = strOrNull(invitation['registrationLink']);
    final when = formatRelativeInviteDate(invitation['invitedAt'] ?? invitation['createdAt']);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.warningBg, shape: BoxShape.circle),
            child: Text(initials(name),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.warning)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.inkStrong)),
                const SizedBox(height: 2),
                Text(
                  '${contact.isNotEmpty ? '$contact · ' : ''}$when · $department',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                ),
                const SizedBox(height: 6),
                StatusBadge('pending', label: str(invitation['dashboardStatus'], 'Pending'), tone: Tone.warning),
              ],
            ),
          ),
          if (showCopyLink && link != null)
            IconButton(
              tooltip: 'Copy link',
              icon: const Icon(Icons.link, color: AppColors.brand600),
              onPressed: () => copyToClipboard(link, message: 'Invite link copied'),
            ),
        ],
      ),
    );
  }
}

/// Dashboard join request row (web `JoinRequestCard`).
class JoinRequestTile extends StatelessWidget {
  const JoinRequestTile({super.key, required this.name, required this.role, this.score});

  final String name;
  final String role;
  final num? score;

  @override
  Widget build(BuildContext context) {
    final value = score ?? 0;
    final (_, color) = scoreRating(value);
    return Row(
      children: [
        AppAvatar(name: name, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.inkStrong)),
              Text(role,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${value.round()}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
              const Text('PAGERLOOK SCORE',
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: AppColors.inkFaint)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Grouped bars for up to a few series per label (employee activity trend).
/// Dependency-free, like the core [MiniBarChart].
class GroupedTrendChart extends StatelessWidget {
  const GroupedTrendChart({
    super.key,
    required this.labels,
    required this.series,
    this.height = 180,
    this.emptyTitle = 'No employee activity yet',
    this.emptyMessage = 'Invite or approve employees to see daily trends',
  });

  final List<String> labels;
  final List<TrendSeries> series;
  final double height;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final hasData = labels.isNotEmpty && series.any((s) => s.values.any((v) => v > 0));
    if (!hasData) {
      return Container(
        height: height,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.canvas,
          borderRadius: BorderRadius.circular(AppRadii.control),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emptyTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.inkBody)),
            const SizedBox(height: 4),
            Text(emptyMessage,
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.inkFaint)),
          ],
        ),
      );
    }

    final maxValue = series.expand((s) => s.values).fold<double>(0, (m, v) => math.max(m, v.toDouble()));
    final scale = maxValue <= 0 ? 1.0 : maxValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(labels.length, (i) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: series.map((s) {
                            final v = i < s.values.length ? s.values[i] : 0;
                            return Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (v > 0)
                                    Text('${v.round()}',
                                        style: const TextStyle(
                                            fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.inkBody)),
                                  Flexible(
                                    child: FractionallySizedBox(
                                      heightFactor: (v / scale).clamp(0.015, 1).toDouble(),
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 0.5),
                                        decoration: BoxDecoration(
                                          color: s.color,
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        labels[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.inkMuted),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: series
              .map(
                (s) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 18,
                      height: 4,
                      decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(99)),
                    ),
                    const SizedBox(width: 6),
                    Text(s.label,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.inkBody)),
                  ],
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

/// Department split as bars with share percentages (web `DepartmentDonutChart`).
class DepartmentSplit extends StatelessWidget {
  const DepartmentSplit({super.key, required this.data, this.emptyText = 'No department data'});

  final Map<String, num> data;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(child: Text(emptyText, style: const TextStyle(color: AppColors.inkMuted))),
      );
    }
    final total = data.values.fold<num>(0, (a, b) => a + b);
    final safeTotal = total <= 0 ? 1 : total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$total total',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.inkMuted)),
        const SizedBox(height: 10),
        ...data.entries.map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: LabeledProgress(
              label: e.key,
              value: e.value,
              max: safeTotal,
              trailing: '${e.value.round()} (${(e.value / safeTotal * 100).round()}%)',
            ),
          ),
        ),
      ],
    );
  }
}

/// Bar chart from label → value (web `TrustScoreBarChart`).
class LabeledBarChart extends StatelessWidget {
  const LabeledBarChart(
      {super.key, required this.data, this.emptyText = 'No trust score distribution', this.height = 170});

  final Map<String, num> data;
  final String emptyText;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(child: Text(emptyText, style: const TextStyle(color: AppColors.inkMuted))),
      );
    }
    return MiniBarChart(
      height: height,
      points: data.entries.map((e) => ChartPoint(e.key, e.value)).toList(),
    );
  }
}
