import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import 'employee_portal_utils.dart';
import 'employee_score_screen.dart';
import 'job_history_screen.dart';

/// `GET /employee/jobs/:id/verification`.
final jobVerificationProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, jobId) async {
  final res = asMap(await ref.watch(employeeApiProvider).fetchJobVerification(jobId));
  // Web: `data?.data || data`.
  if (res['job'] == null && res['data'] is Map) return asMap(res['data']);
  return res;
});

const Map<String, String> _ratingLabels = {
  'excellent': 'Excellent',
  'good': 'Good',
  'average': 'Average',
  'below_average': 'Below Average',
  'poor': 'Poor',
};

const Map<String, String> _recommendationLabels = {
  'strongly_recommend': 'Strongly recommend',
  'recommend': 'Recommend',
  'neutral': 'Neutral',
  'not_recommend': 'Do not recommend',
};

const Map<String, String> _docTypes = {
  'offer_letter': 'Offer Letter',
  'salary_slip': 'Salary Slip',
  'experience_letter': 'Experience Letter',
  'relieving_letter': 'Relieving Letter',
};

const Map<String, String> _levelLabels = {
  'document_verified': 'Document Verified',
  'hr_verified': 'HR Verified',
  'employer_verified': 'Employer Verified',
};

const Map<String, String> _channelLabels = {
  'platform': 'Previous company is on PagerLook — request sent to their HR dashboard',
  'email': 'Verification email sent to HR / Manager',
};

const List<String> _openStatuses = ['pending', 'in_review', 'in_process', 'hr_responded'];
const List<String> _respondedStatuses = ['verified', 'approved', 'hr_responded', 'rejected'];

/// employmentDetails always comes back fully keyed, so only a substantive
/// field means HR actually answered (web `hasHrResponse`).
bool _hasHrResponse(Object? value) {
  if (value is! Map) return false;
  final d = asMap(value);
  return d['workedHere'] != null ||
      strOrNull(d['employmentVerificationStatus']) != null ||
      strOrNull(d['verifierName']) != null ||
      strOrNull(d['designation']) != null ||
      strOrNull(d['feedback']) != null ||
      strOrNull(d['hrRemarks']) != null;
}

/// Port of `JobVerification.jsx`: documents, HR contacts, verification
/// request create / resend, HR response, AI analysis and permanent record.
class JobVerificationScreen extends ConsumerStatefulWidget {
  const JobVerificationScreen({super.key, required this.jobId});

  final String jobId;

  @override
  ConsumerState<JobVerificationScreen> createState() => _JobVerificationScreenState();
}

class _JobVerificationScreenState extends ConsumerState<JobVerificationScreen> {
  List<String> _hrContacts = [''];
  String _syncedContactsKey = '';
  String _uploadType = 'offer_letter';
  bool _uploading = false;
  bool _sending = false;
  bool _resending = false;
  DateTime? _resendTarget;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Drives the resend cool-down countdown.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final target = _resendTarget;
      if (!mounted || target == null) return;
      if (DateTime.now().isBefore(target.add(const Duration(seconds: 1)))) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _invalidateAll({bool score = false}) {
    ref.invalidate(jobVerificationProvider(widget.jobId));
    ref.invalidate(employeeJobsProvider);
    if (score) ref.invalidate(employeeScoreProvider);
  }

  Future<void> _upload() async {
    final file = await pickDocumentWithSheet(context, title: 'Upload ${_docTypes[_uploadType] ?? 'document'}');
    if (file == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      await ref.read(employeeApiProvider).uploadJobDocument(widget.jobId, file, documentType: _uploadType);
      showToast('Document uploaded', type: ToastType.success);
      _invalidateAll();
    } catch (e) {
      showErrorToast(e, 'Upload failed');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _requestVerification() async {
    setState(() => _sending = true);
    try {
      final res = asMap(await ref
          .read(employeeApiProvider)
          .createJobVerificationRequest(widget.jobId, {'hrContacts': cleanContacts(_hrContacts)}));
      final result = res['data'] is Map ? asMap(res['data']) : res;
      showToast(
        strOrNull(result['message']) ?? strOrNull(pick(result, 'request.message')) ?? 'Verification request sent',
        type: ToastType.success,
      );
      _invalidateAll(score: true);
    } catch (e) {
      showErrorToast(e, 'Could not start verification');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _resend(String requestId) async {
    setState(() => _resending = true);
    try {
      final res = asMap(await ref
          .read(employeeApiProvider)
          .resendJobVerificationRequest(requestId, {'hrContacts': cleanContacts(_hrContacts)}));
      final result = res['data'] is Map ? asMap(res['data']) : res;
      showToast(strOrNull(result['message']) ?? 'Verification request re-sent', type: ToastType.success);
      _invalidateAll();
    } catch (e) {
      showErrorToast(e, 'Could not re-send the request');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final verifyAsync = ref.watch(jobVerificationProvider(widget.jobId));
    final title = strOrNull(pick(verifyAsync.valueOrNull, 'job.company'));

    return Scaffold(
      appBar: AppBar(
        leading: context.canPop()
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/employee/job-history'),
              ),
        title: Text(title == null ? 'Verify Employment' : 'Verify · $title', overflow: TextOverflow.ellipsis),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(jobVerificationProvider(widget.jobId).future),
        child: AsyncValueView<Map<String, dynamic>>(
          value: verifyAsync,
          loadingLabel: 'Loading...',
          onRetry: () => ref.invalidate(jobVerificationProvider(widget.jobId)),
          data: _buildBody,
        ),
      ),
    );
  }

  Widget _buildBody(Map<String, dynamic> payload) {
    final job = asMap(payload['job']);
    if (job.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          EmptyState(
            icon: Icons.work_off_outlined,
            title: 'Job not found',
            action: AppButton(
              label: 'Back to Job History',
              expand: false,
              onPressed: () => context.go('/employee/job-history'),
            ),
          ),
        ],
      );
    }

    final documents = asMapList(payload['documents']);
    final requests = asMapList(payload['verificationRequests']);
    Map<String, dynamic>? openRequest;
    for (final r in requests) {
      if (_openStatuses.contains(str(r['status']))) {
        openRequest = r;
        break;
      }
    }
    Map<String, dynamic>? respondedRequest;
    for (final r in requests) {
      if (_respondedStatuses.contains(str(r['status'])) && pick(r, 'employmentDetails.workedHere') != null) {
        respondedRequest = r;
        break;
      }
    }
    final resendableRequestId = strOrNull(payload['resendableRequestId']);
    _resendTarget = asDate(payload['resendAvailableAt']);
    final resendSecondsLeft = _resendTarget == null
        ? 0
        : (() {
            final ms = _resendTarget!.difference(DateTime.now()).inMilliseconds;
            return ms <= 0 ? 0 : (ms / 1000).ceil();
          })();

    final record = payload['permanentRecord'] is Map ? asMap(payload['permanentRecord']) : null;
    final hrResponseRaw = [
      record?['hrResponse'],
      openRequest?['employmentDetails'],
      openRequest?['hrResponse'],
      respondedRequest?['employmentDetails'],
    ].firstWhere(_hasHrResponse, orElse: () => null);
    final hrResponse = hrResponseRaw == null ? null : asMap(hrResponseRaw);
    final aiRaw = record?['aiAnalysis'] ?? openRequest?['aiAnalysis'] ?? payload['aiAnalysis'];
    final ai = aiRaw is Map ? asMap(aiRaw) : null;

    // Prefill HR contacts from what was actually mailed, else the job's saved
    // addresses — keyed on the joined list so a re-fetch can't stomp typing.
    final openContacts = asList(openRequest?['hrContacts']).map((e) => str(e)).where((e) => e.isNotEmpty).toList();
    final jobContacts = asList(job['hrContacts']).map((e) => str(e)).where((e) => e.isNotEmpty).toList();
    final saved = openContacts.isNotEmpty
        ? openContacts
        : jobContacts.isNotEmpty
            ? jobContacts
            : [str(job['hrEmail']), str(job['managerEmail'])].where((e) => e.isNotEmpty).toList();
    final savedKey = saved.join(',');
    if (savedKey.isNotEmpty && savedKey != _syncedContactsKey) {
      _syncedContactsKey = savedKey;
      _hrContacts = savedKey.split(',');
    }

    final isVerified = asBool(payload['isVerified']) || asBool(payload['alreadyVerified']);
    final canRequest = asBool(payload['canRequestVerification']) && !asBool(payload['isVerified']);
    final tagLabel = strOrNull(pick(job, 'verificationTag.label')) ?? (isVerified ? 'Verified' : 'Not Verified');
    final company = str(job['company']);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(str(job['title'], '—'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.inkStrong)),
              const SizedBox(height: 2),
              Text(company, style: const TextStyle(color: AppColors.inkMuted)),
              const SizedBox(height: 10),
              StatusBadge(null, label: tagLabel, tone: isVerified ? Tone.success : Tone.neutral),
            ],
          ),
        ),
        if (ai != null && (strOrNull(ai['verdict']) != null || strOrNull(ai['summary']) != null)) ...[
          const SizedBox(height: 12),
          _AiAnalysisCard(analysis: ai),
        ],
        if (hrResponse != null) ...[
          const SizedBox(height: 12),
          _HrResponseCard(details: hrResponse),
        ],
        if (isVerified) ...[
          const SizedBox(height: 12),
          const InfoBanner(
            tone: Tone.success,
            message: 'This employment is verified. Future companies can view this record without repeating verification.',
          ),
          if (record != null) ...[
            const SizedBox(height: 12),
            _VerifiedRecordCard(record: record, company: company),
          ],
        ],

        // ── In progress ────────────────────────────────────────────────────
        if (openRequest != null && !isVerified) ...[
          const SizedBox(height: 12),
          AppCard(
            title: 'Verification in progress',
            subtitle: 'Your request is being processed. If HR does not respond within 14 days, '
                'verification may complete via document review.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RequestStatusTile(request: openRequest),
                if (resendableRequestId != null && !isVerified) ...[
                  const SizedBox(height: 14),
                  _resendBox(openRequest, resendableRequestId, resendSecondsLeft, company),
                ],
              ],
            ),
          ),
        ],

        // ── Start verification ─────────────────────────────────────────────
        if (!isVerified && openRequest == null) ...[
          const SizedBox(height: 12),
          AppCard(
            title: 'Step 1 — Upload documents',
            subtitle: 'Offer letter, salary slips, experience letter, or relieving letter.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _docTypes.entries
                      .map(
                        (e) => ChoiceChip(
                          label: Text(e.value),
                          selected: _uploadType == e.key,
                          showCheckmark: false,
                          onSelected: _uploading ? null : (_) => setState(() => _uploadType = e.key),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
                AppButton(
                  label: _uploading ? 'Uploading...' : 'Choose file to upload',
                  icon: Icons.upload_file,
                  variant: AppButtonVariant.secondary,
                  loading: _uploading,
                  onPressed: _upload,
                ),
                if (documents.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final doc in documents) _DocumentTile(doc: doc),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            title: 'Step 2 — HR contacts',
            subtitle: 'Required if the previous company is not registered on PagerLook (Case B). '
                'If registered, request goes to their HR dashboard (Case A).',
            child: HrContactsEditor(
              key: ValueKey('start-$_syncedContactsKey'),
              initial: _hrContacts,
              enabled: !_sending,
              label: 'HR contacts',
              hint: 'Add every HR or manager mailbox worth trying — each one receives the same verification link.',
              onChanged: (list) => _hrContacts = list,
            ),
          ),
          const SizedBox(height: 16),
          AppButton(
            label: _sending ? 'Sending...' : 'Verify Employment',
            icon: Icons.verified_outlined,
            loading: _sending,
            onPressed: (!canRequest || documents.isEmpty) ? null : _requestVerification,
          ),
          if (!canRequest && documents.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'A verification request is already in progress for this job.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
              ),
            ),
          if (documents.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Upload at least one document before requesting verification.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
              ),
            ),
        ],

        if (requests.isNotEmpty && openRequest == null && !isVerified) ...[
          const SizedBox(height: 16),
          AppCard(
            title: 'Previous requests',
            child: Column(
              children: [
                for (var i = 0; i < requests.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _RequestStatusTile(request: requests[i]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _resendBox(Map<String, dynamic> openRequest, String requestId, int secondsLeft, String company) {
    final isEmail = str(openRequest['verificationChannel']) == 'email';
    final String label;
    if (_resending) {
      label = 'Sending...';
    } else if (secondsLeft > 0) {
      label = 'Resend in ${secondsLeft}s';
    } else {
      label = isEmail ? 'Resend request' : 'Send reminder';
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('No response yet?',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkBody)),
          const SizedBox(height: 2),
          Text(
            isEmail
                ? 'Send the request again. Fix the HR emails below, or add more contacts, if the first ones were wrong.'
                : 'Send $company a reminder on their PagerLook dashboard.',
            style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
          if (isEmail) ...[
            const SizedBox(height: 4),
            HrContactsEditor(
              key: ValueKey('resend-$_syncedContactsKey'),
              initial: _hrContacts,
              enabled: !_resending,
              label: 'HR contacts',
              hint: 'Everyone listed here gets the same verification link.',
              onChanged: (list) => _hrContacts = list,
            ),
          ],
          const SizedBox(height: 10),
          AppButton(
            label: label,
            variant: AppButtonVariant.secondary,
            loading: _resending,
            onPressed: secondsLeft > 0 ? null : () => _resend(requestId),
          ),
        ],
      ),
    );
  }
}

class _RequestStatusTile extends StatelessWidget {
  const _RequestStatusTile({required this.request});

  final Map<String, dynamic> request;

  @override
  Widget build(BuildContext context) {
    final channel = strOrNull(request['verificationChannel']);
    final notes = strOrNull(request['verificationNotes']);
    final reminders = asInt(request['remindersSent']);
    final status = str(request['status']);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  str(request['statusLabel'], humanize(status)),
                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.inkStrong),
                ),
              ),
              if (request['requestedAt'] != null)
                Text(formatDate(request['requestedAt']), style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            ],
          ),
          if (channel != null) ...[
            const SizedBox(height: 4),
            Text(_channelLabels[channel] ?? channel, style: const TextStyle(fontSize: 12, color: AppColors.inkBody)),
          ],
          if (notes != null) ...[
            const SizedBox(height: 6),
            Text(notes, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
          ],
          if (reminders > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Re-sent $reminders ${reminders == 1 ? 'time' : 'times'}'
              '${request['lastRemindedAt'] != null ? ' — last on ${formatDate(request['lastRemindedAt'])}' : ''}',
              style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({required this.doc});

  final Map<String, dynamic> doc;

  @override
  Widget build(BuildContext context) {
    final url = mediaUrl(doc['url']);
    final type = str(doc['documentType'], 'document');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadii.control),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          dense: true,
          onTap: url == null ? null : () => openExternalUrl(url),
          leading: const Icon(Icons.description_outlined, color: AppColors.brand600),
          title: Text(str(doc['originalName'], 'Document'), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(_docTypes[type] ?? humanize(type), style: const TextStyle(fontSize: 11.5)),
          trailing: url == null ? null : const Icon(Icons.open_in_new, size: 18, color: AppColors.inkFaint),
        ),
      ),
    );
  }
}

class _AiAnalysisCard extends StatelessWidget {
  const _AiAnalysisCard({required this.analysis});

  final Map<String, dynamic> analysis;

  @override
  Widget build(BuildContext context) {
    final verdict = str(analysis['verdict']);
    final (String label, Tone tone) = switch (verdict) {
      'verified' => ('Verified', Tone.success),
      'unverified' => ('Unverified', Tone.danger),
      _ => ('Inconclusive', Tone.warning),
    };
    final flags = asList(analysis['flags'] ?? analysis['redFlags'])
        .map((f) => f is String ? f : str(asMap(f)['message'] ?? asMap(f)['label']))
        .where((s) => s.isNotEmpty)
        .toList();
    final summary = strOrNull(analysis['summary']);

    return AppCard(
      color: tone.bg,
      borderColor: tone.fg.withValues(alpha: 0.2),
      title: 'AI Analysis',
      subtitle: 'Automated review of the HR response for this experience.',
      action: StatusBadge(null, label: label.toUpperCase(), tone: tone),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (analysis['confidence'] != null)
            Text('Confidence: ${analysis['confidence']}%',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.inkBody)),
          if (summary != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(summary, style: const TextStyle(fontSize: 13.5, color: AppColors.inkBody)),
            ),
          for (final flag in flags)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ', style: TextStyle(color: AppColors.inkMuted)),
                  Expanded(child: Text(flag, style: const TextStyle(fontSize: 12.5, color: AppColors.inkBody))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HrResponseCard extends StatelessWidget {
  const _HrResponseCard({required this.details});

  final Map<String, dynamic> details;

  @override
  Widget build(BuildContext context) {
    final d = details;
    final workedHere = d['workedHere'];
    final verifierLine = [str(d['verifierName']), str(d['verifierDesignation'])].where((s) => s.isNotEmpty).join(' · ');
    final duration = [str(d['joiningDate']), str(d['exitDate'])].where((s) => s.isNotEmpty).join(' — ');
    final remarks = strOrNull(d['hrRemarks']) ?? strOrNull(d['feedback']) ?? strOrNull(d['verificationNotes']);
    final docUrl = mediaUrl(d['supportingDocumentUrl']);

    String? disciplinary;
    if (d['disciplinaryIssues'] != null) {
      final extra = strOrNull(d['disciplinaryDetails']);
      disciplinary = asBool(d['disciplinaryIssues'])
          ? 'Yes${extra == null ? '' : ' — $extra'}'
          : 'None reported';
    }

    Widget row(String label, String? value) {
      if (value == null || value.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Eyebrow(label),
            const SizedBox(height: 3),
            Text(value, style: const TextStyle(fontSize: 13.5, color: AppColors.inkStrong)),
          ],
        ),
      );
    }

    return AppCard(
      title: 'HR Response',
      subtitle: 'Submitted by your previous employer — locked and attached to this experience.',
      action: const StatusBadge(null, label: 'LOCKED', tone: Tone.neutral, icon: Icons.lock_outline),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(AppRadii.control)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row('Worked here', workedHere == true ? 'Yes' : (workedHere == false ? 'No' : '—')),
            row('Designation', strOrNull(d['designation'])),
            row('Duration', duration),
            row('Department', strOrNull(d['department'])),
            row('Reporting manager', strOrNull(d['reportingManager'])),
            if (d['rehireEligible'] != null) row('Rehire eligible', asBool(d['rehireEligible']) ? 'Yes' : 'No'),
            row('Performance rating', _ratingLabels[str(d['performanceRating'])]),
            row('Recommendation', _recommendationLabels[str(d['recommendation'])]),
            row('Behavior / Conduct', strOrNull(d['behaviorRemarks'])),
            row('Disciplinary issues', disciplinary),
            row('HR remarks', remarks),
            if (docUrl != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow('Supporting document'),
                    TextButton.icon(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      onPressed: () => openExternalUrl(docUrl),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: Text(str(d['supportingDocumentName'], 'View document')),
                    ),
                  ],
                ),
              ),
            row('Verified by', verifierLine),
          ],
        ),
      ),
    );
  }
}

class _VerifiedRecordCard extends StatelessWidget {
  const _VerifiedRecordCard({required this.record, required this.company});

  final Map<String, dynamic> record;
  final String company;

  @override
  Widget build(BuildContext context) {
    final verifiedBy = switch (str(record['verifiedBy'])) {
      'employer_platform' => '$company HR (Platform)',
      'hr_email' => '$company HR (Email)',
      'document_fallback' => 'Document review (no HR response)',
      _ => '—',
    };
    final status = strOrNull(pick(record, 'verificationTag.label')) ??
        _levelLabels[str(record['verificationLevel'])] ??
        'Verified';
    return AppCard(
      title: 'Verification record',
      subtitle: 'This record stays on your profile — future employers can reuse it.',
      child: Column(
        children: [
          InfoRow(label: 'Company', value: str(record['company'], company)),
          InfoRow(label: 'Status', value: status),
          InfoRow(label: 'Verified by', value: verifiedBy),
          InfoRow(label: 'Verified on', value: record['verifiedAt'] == null ? '—' : formatDate(record['verifiedAt'])),
          if (record['confidenceScore'] != null)
            InfoRow(label: 'Confidence score', value: '${record['confidenceScore']}%'),
        ],
      ),
    );
  }
}
