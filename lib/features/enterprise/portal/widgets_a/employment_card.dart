import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/json.dart';
import '../../../../core/widgets/widgets.dart';
import 'team_widgets.dart';

/// Port of `components/enterprise/CompanyEmploymentCard.jsx` — one employer
/// in an employee's verified employment history.

const _ladder = [
  ('profile', 'Profile', 1),
  ('identity', 'Identity', 2),
  ('document_verified', 'Documents', 3),
  ('hr_verified', 'HR Verified', 4),
  ('employer_verified', 'Employer', 5),
];

const _levelTier = {'none': 0, 'document_verified': 3, 'hr_verified': 4, 'employer_verified': 5};

const _docTypeLabels = {
  'offer_letter': 'Offer Letter',
  'salary_slip': 'Salary Slip',
  'experience_letter': 'Experience Letter',
  'relieving_letter': 'Relieving Letter',
  'pf_statement': 'PF Statement',
  'form_16': 'Form 16',
  'other': 'Document',
};

const _ratingLabels = {
  'excellent': 'Excellent',
  'good': 'Good',
  'average': 'Average',
  'below_average': 'Below Average',
  'poor': 'Poor',
};

const _recommendationLabels = {
  'strongly_recommend': 'Strongly recommend',
  'recommend': 'Recommend',
  'neutral': 'Neutral',
  'not_recommend': 'Do not recommend',
};

bool isJobVerified(Map<String, dynamic> job) {
  final level = str(job['verificationLevel'], 'none');
  return asBool(job['isReusable']) || job['status'] == 'verified' || (_levelTier[level] ?? 0) >= 3;
}

class CompanyEmploymentCard extends StatelessWidget {
  const CompanyEmploymentCard({super.key, required this.job, this.canVerify = false, this.onVerify});

  final Map<String, dynamic> job;
  final bool canVerify;
  final ValueChanged<Map<String, dynamic>>? onVerify;

  @override
  Widget build(BuildContext context) {
    final level = str(job['verificationLevel'], 'none');
    final verified = isJobVerified(job);
    final tagLabel = strOrNull(pick(job, 'verificationTag.label')) ??
        strOrNull(pick(job, 'verificationMeta.label')) ??
        'Not Verified';
    final Tone badgeTone = switch (level) {
      'employer_verified' => Tone.brand,
      'hr_verified' => Tone.info,
      'document_verified' => Tone.success,
      _ => job['status'] == 'in_process' ? Tone.warning : Tone.neutral,
    };

    final start = job['joiningDate'] ?? job['startDate'];
    final end = job['exitDate'] ?? job['endDate'];
    final dateRange = start != null && str(start).isNotEmpty
        ? '${formatDate(start)} – ${end != null && str(end).isNotEmpty ? formatDate(end) : (asBool(job['isPresent']) ? 'Present' : '—')}'
        : str(job['duration'], '—');

    final onPlatform = asBool(job['previousCompanyOnPlatform']);
    final matchedName = strOrNull(pick(job, 'matchedPlatformCompany.name'));
    final pathLabel = onPlatform
        ? (matchedName != null
            ? 'Case A — $matchedName on PagerLook'
            : 'Case A — Platform (company on PagerLook)')
        : 'Case B — Email HR verification';

    final rehire = job['rehireEligible'];
    final cells = <(String, String?)>[
      ('Employment type', strOrNull(job['employmentType'])),
      ('Department', strOrNull(job['department'])),
      ('Employee ID', strOrNull(job['employeeCode'])),
      ('Work location', strOrNull(job['workLocation'])),
      ('Duration', strOrNull(job['duration'])),
      ('Salary band', strOrNull(job['salaryBand'])),
      ('UAN (PF)', strOrNull(job['uanNumber'])),
      ('PF Member ID', strOrNull(job['pfNumber'])),
      ('ESI Number', strOrNull(job['esiNumber'])),
      ('Company PAN', strOrNull(job['companyPan'])),
      ('CIN', strOrNull(job['companyCin'])),
      ('GSTIN', strOrNull(job['companyGst'])),
      ('Manager', strOrNull(job['managerName'])),
      ('Verified on', job['verifiedAt'] != null ? formatDate(job['verifiedAt']) : null),
      ('Verification path', strOrNull(job['verificationChannel']) != null ? pathLabel : null),
      ('Confidence', job['confidenceScore'] != null ? '${job['confidenceScore']}%' : null),
      ('Rehire eligible', rehire == true ? 'Yes' : (rehire == false ? 'No' : null)),
      ('Resolved via', strOrNull(job['resolvedVia'])?.replaceAll('_', ' ')),
    ].where((c) => c.$2 != null && c.$2!.isNotEmpty).toList();

    final hrEmail = strOrNull(job['hrEmail']);
    final managerEmail = strOrNull(job['managerEmail']);
    final latest = job['latestVerificationRequest'] is Map ? asMap(job['latestVerificationRequest']) : null;
    final documents = asMapList(job['documents']);
    final company = str(job['company']);

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.brand600, borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    company.isEmpty ? '?' : company[0].toUpperCase(),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(company,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.inkStrong)),
                      Text(str(job['title']),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.inkBody)),
                      const SizedBox(height: 2),
                      Text(dateRange, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          StatusBadge(level,
                              label: tagLabel, tone: badgeTone, icon: verified ? Icons.check : null),
                          if (asBool(job['isReusable']))
                            const StatusBadge('reusable', label: 'Reusable record', tone: Tone.brand, icon: Icons.recycling),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(),

          // Trust hierarchy
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CaptionText('Trust hierarchy'),
                const SizedBox(height: 8),
                _VerificationLadder(level: level),
              ],
            ),
          ),

          if (cells.isNotEmpty) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(children: cells.map((c) => InfoRow(label: c.$1, value: c.$2)).toList()),
            ),
          ],

          if (hrEmail != null || managerEmail != null) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CaptionText('HR contacts'),
                  const SizedBox(height: 6),
                  if (hrEmail != null) InfoRow(label: 'HR', value: hrEmail),
                  if (managerEmail != null) InfoRow(label: 'Manager', value: managerEmail),
                ],
              ),
            ),
          ],

          _HrFeedbackPanel(job: job),

          if (latest != null) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CaptionText('Latest verification request'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (strOrNull(latest['verificationChannel']) != null)
                        StatusBadge('channel',
                            label: '${humanize(latest['verificationChannel'])} channel', tone: Tone.neutral),
                      if (strOrNull(latest['status']) != null)
                        StatusBadge(str(latest['status']), label: humanize(latest['status'])),
                      if (latest['requestedAt'] != null)
                        Text('Requested ${formatDate(latest['requestedAt'])}',
                            style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                    ],
                  ),
                ],
              ),
            ),
          ],

          if (documents.isNotEmpty) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CaptionText('Employment documents (${documents.length})'),
                  const SizedBox(height: 8),
                  ...documents.map((doc) {
                    final url = mediaUrl(doc['url']);
                    final type = str(doc['documentType']);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: DocumentRow(
                        title: _docTypeLabels[type] ?? str(doc['originalName'], 'Document'),
                        subtitle: strOrNull(doc['originalName']),
                        url: url,
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],

          if (canVerify) ...[
            const Divider(),
            Container(
              color: AppColors.canvas,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    verified
                        ? 'This record is verified and reusable for future employers.'
                        : onPlatform
                            ? 'Verify via PagerLook — employee consent, then ${matchedName ?? company} HR reviews.'
                            : 'Not on PagerLook — send verification email to HR, or search registered company in modal.',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                  ),
                  const SizedBox(height: 10),
                  if (!verified)
                    AppButton(
                      label: 'Start Verification',
                      compact: true,
                      onPressed: onVerify == null ? null : () => onVerify!(job),
                    )
                  else
                    const Row(
                      children: [
                        Icon(Icons.check_circle, size: 18, color: AppColors.success),
                        SizedBox(width: 6),
                        Text('Verified', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.success)),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VerificationLadder extends StatelessWidget {
  const _VerificationLadder({required this.level});

  final String level;

  @override
  Widget build(BuildContext context) {
    final tier = _levelTier[level] ?? (level == 'in_process' ? 2 : 0);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: _ladder.map((step) {
        final done = tier >= step.$3;
        final active = tier == step.$3;
        final Color bg = done ? (active ? AppColors.brand600 : AppColors.successBg) : const Color(0xFFF4F4F5);
        final Color fg = done ? (active ? Colors.white : AppColors.success) : AppColors.inkFaint;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
          child: Text(
            '${done ? '✓' : step.$3} ${step.$2}',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
          ),
        );
      }).toList(),
    );
  }
}

class _HrFeedbackPanel extends StatelessWidget {
  const _HrFeedbackPanel({required this.job});

  final Map<String, dynamic> job;

  @override
  Widget build(BuildContext context) {
    final details = asMap(pick(job, 'latestVerificationRequest.employmentDetails'));
    final remarks = strOrNull(details['hrRemarks']) ??
        strOrNull(details['feedback']) ??
        strOrNull(job['verificationFeedback']) ??
        strOrNull(details['verificationNotes']) ??
        strOrNull(job['verificationNotes']);
    final verifierLine =
        [str(details['verifierName']), str(details['verifierDesignation'])].where((s) => s.isNotEmpty).join(' · ');
    final verifierContact =
        [str(details['verifierEmail']), str(details['verifierPhone'])].where((s) => s.isNotEmpty).join(' · ');
    final docUrl = mediaUrl(details['supportingDocumentUrl']);
    final disciplinary = details['disciplinaryIssues'];
    final rehire = details['rehireEligible'];

    final hasStructured = strOrNull(details['performanceRating']) != null ||
        strOrNull(details['recommendation']) != null ||
        strOrNull(details['behaviorRemarks']) != null ||
        strOrNull(details['reportingManager']) != null ||
        disciplinary != null ||
        verifierLine.isNotEmpty ||
        docUrl != null;
    if (remarks == null && !hasStructured) return const SizedBox.shrink();

    final rows = <(String, String?)>[
      ('Performance rating', _ratingLabels[str(details['performanceRating'])]),
      ('Recommendation', _recommendationLabels[str(details['recommendation'])]),
      ('Rehire eligible', rehire == true ? 'Yes' : (rehire == false ? 'No' : null)),
      ('Reporting manager', strOrNull(details['reportingManager'])),
      (
        'Disciplinary issues',
        disciplinary == true
            ? 'Yes${strOrNull(details['disciplinaryDetails']) != null ? ' — ${details['disciplinaryDetails']}' : ''}'
            : (disciplinary == false ? 'None reported' : null)
      ),
      ('Behavior / Conduct', strOrNull(details['behaviorRemarks'])),
    ].where((r) => r.$2 != null).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        Container(
          color: AppColors.brand50.withValues(alpha: 0.5),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CaptionText('Employer / HR feedback'),
              if (hasStructured && rows.isNotEmpty) ...[
                const SizedBox(height: 6),
                ...rows.map((r) => InfoRow(label: r.$1, value: r.$2)),
              ],
              if (remarks != null) ...[
                const SizedBox(height: 8),
                Text(remarks, style: const TextStyle(fontSize: 13.5, color: AppColors.inkBody, height: 1.45)),
              ],
              if (verifierLine.isNotEmpty || verifierContact.isNotEmpty || docUrl != null) ...[
                const SizedBox(height: 10),
                if (verifierLine.isNotEmpty)
                  Text('Verified by $verifierLine', style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                if (verifierContact.isNotEmpty)
                  Text(verifierContact, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                if (docUrl != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => openExternalUrl(docUrl),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text(str(details['supportingDocumentName'], 'View supporting document')),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// File row with a "View" action (web `DocumentRow`).
class DocumentRow extends StatelessWidget {
  const DocumentRow({super.key, required this.title, this.subtitle, this.status, this.url});

  final String title;
  final String? subtitle;
  final String? status;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final verified = status == 'verified' || status == 'approved';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          const Icon(Icons.description_outlined, size: 20, color: AppColors.inkMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.inkStrong)),
                if (subtitle != null && subtitle != title)
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.inkMuted)),
                if (status != null && status!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  StatusBadge(status, tone: verified ? Tone.success : Tone.warning),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (url != null)
            AppButton(
              label: 'View',
              compact: true,
              expand: false,
              variant: AppButtonVariant.secondary,
              onPressed: () => openExternalUrl(url),
            )
          else
            const Text('No link', style: TextStyle(fontSize: 12, color: AppColors.inkFaint)),
        ],
      ),
    );
  }
}
