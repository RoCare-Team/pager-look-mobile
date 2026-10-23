import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/json.dart';
import '../../../../core/widgets/widgets.dart';
import 'sheet_body.dart';

/// Status label + tone — web `getVerificationStatusStyle`.
(String, Tone) verificationStatusStyle(String? status) {
  return switch (status) {
    'pending' => ('Pending', Tone.warning),
    'in_process' => ('In Process', Tone.info),
    'in_review' => ('Email Sent', Tone.info),
    'hr_responded' => ('HR Responded', Tone.brand),
    'verified' => ('Verified', Tone.success),
    'approved' => ('Approved', Tone.success),
    'rejected' => ('Rejected', Tone.danger),
    'expired' => ('Expired', Tone.neutral),
    'completed' => ('Completed', Tone.success),
    _ => ((status == null || status.isEmpty) ? 'Unknown' : status, Tone.neutral),
  };
}

/// Channel label + tone — web `getVerificationChannelStyle`.
(String, Tone) verificationChannelStyle(String? channel) {
  return switch (channel) {
    'platform' => ('Platform', Tone.info),
    'email' => ('Email', Tone.brand),
    _ => ((channel == null || channel.isEmpty) ? 'Unknown' : channel, Tone.neutral),
  };
}

String _dateOnly(Object? value) {
  final s = str(value);
  return s.length > 10 ? s.substring(0, 10) : s;
}

// ─────────────────────────────────────────────────────────────────────────────
// IncomingVerificationApproveModal
// ─────────────────────────────────────────────────────────────────────────────

/// Approve an incoming platform verification. Pops `true` on success.
class IncomingApproveSheet extends ConsumerStatefulWidget {
  const IncomingApproveSheet({super.key, required this.request});

  final Map<String, dynamic> request;

  @override
  ConsumerState<IncomingApproveSheet> createState() => _IncomingApproveSheetState();
}

class _IncomingApproveSheetState extends ConsumerState<IncomingApproveSheet> {
  late final Map<String, dynamic> r = widget.request;
  late final _designation = TextEditingController(text: str(r['jobTitle'] ?? r['title']));
  late final _duration = TextEditingController(text: str(r['duration']));
  late final _employeeCode = TextEditingController(text: str(r['employeeCode']));
  late final _department = TextEditingController(text: str(r['department']));
  late final _uan = TextEditingController(text: str(r['uanNumber']));
  late final _pf = TextEditingController(text: str(r['pfNumber']));
  late final _esi = TextEditingController(text: str(r['esiNumber']));
  final _feedback = TextEditingController();
  late String _joiningDate = _dateOnly(r['joiningDate']);
  late String _exitDate = _dateOnly(r['exitDate']);
  bool _rehireEligible = true;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_designation, _duration, _employeeCode, _department, _uan, _pf, _esi, _feedback]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      await ref.read(enterpriseApiProvider).approveVerificationRequest(idOf(r), {
        'workedHere': true,
        'designation': _designation.text,
        'joiningDate': _joiningDate,
        'exitDate': _exitDate,
        'duration': _duration.text,
        'employeeCode': _employeeCode.text,
        'department': _department.text,
        'uanNumber': _uan.text,
        'pfNumber': _pf.text,
        'esiNumber': _esi.text,
        'feedback': _feedback.text,
        'rehireEligible': _rehireEligible,
        'employmentStatus': 'confirmed',
      });
      showToast('Employment verified — Employer Verified', type: ToastType.success);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      showErrorToast(e, 'Failed to approve');
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final company = str(r['previousCompanyName'] ?? r['companyName']);
    return SheetBody(
      title: 'Approve Employment Verification',
      subtitle: 'Confirm details for ${str(r['employeeName'])} at $company.',
      actions: [
        SheetButtonRow(children: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.outline,
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
          ),
          AppButton(label: 'Approve → Employer Verified', loading: _saving, onPressed: _saving ? null : _submit),
        ]),
      ],
      children: [
        AppTextField(controller: _designation, label: 'Designation', enabled: !_saving),
        const SizedBox(height: 14),
        AppDateField(
          label: 'Joining date',
          value: _joiningDate.isEmpty ? null : _joiningDate,
          enabled: !_saving,
          onChanged: (v) => setState(() => _joiningDate = v),
        ),
        const SizedBox(height: 14),
        AppDateField(
          label: 'Exit date',
          value: _exitDate.isEmpty ? null : _exitDate,
          enabled: !_saving,
          onChanged: (v) => setState(() => _exitDate = v),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: AppTextField(controller: _employeeCode, label: 'Employee ID', enabled: !_saving)),
            const SizedBox(width: 10),
            Expanded(child: AppTextField(controller: _department, label: 'Department', enabled: !_saving)),
          ],
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: _uan,
          label: 'UAN (PF)',
          enabled: !_saving,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: AppTextField(controller: _pf, label: 'PF Member ID', enabled: !_saving)),
            const SizedBox(width: 10),
            Expanded(child: AppTextField(controller: _esi, label: 'ESI Number', enabled: !_saving)),
          ],
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: _duration,
          label: 'Duration',
          hint: 'e.g. Jan 2022 – Mar 2024',
          enabled: !_saving,
        ),
        CheckboxListTile(
          value: _rehireEligible,
          onChanged: _saving ? null : (v) => setState(() => _rehireEligible = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Eligible for rehire', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
        AppTextField(controller: _feedback, label: 'HR feedback', maxLines: 3, enabled: !_saving),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EmailVerificationCompleteModal
// ─────────────────────────────────────────────────────────────────────────────

/// Record the outcome of an email (Case B) verification. Pops `true` on success.
class EmailVerificationCompleteSheet extends ConsumerStatefulWidget {
  const EmailVerificationCompleteSheet({super.key, required this.request});

  final Map<String, dynamic> request;

  @override
  ConsumerState<EmailVerificationCompleteSheet> createState() => _EmailVerificationCompleteSheetState();
}

class _EmailVerificationCompleteSheetState extends ConsumerState<EmailVerificationCompleteSheet> {
  final _notes = TextEditingController();
  bool _verified = true;
  bool _useDocuments = false;
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    final api = ref.read(enterpriseApiProvider);
    final id = idOf(widget.request);
    final notes = _notes.text.trim();
    try {
      if (_useDocuments) {
        await api.confirmDocumentVerification(id, {if (notes.isNotEmpty) 'notes': notes});
      } else {
        await api.completeEmailVerification(id, {
          'verified': _verified,
          if (notes.isNotEmpty) 'notes': notes,
        });
      }
      showToast('Verification updated', type: ToastType.success);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      showErrorToast(e, 'Failed to update verification');
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = str(widget.request['employeeName'], 'this employee');
    return SheetBody(
      title: 'Complete Email Verification',
      subtitle: "Record the outcome for $name's employment verification.",
      actions: [
        SheetButtonRow(children: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.outline,
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
          ),
          AppButton(label: 'Submit', loading: _saving, onPressed: _saving ? null : _submit),
        ]),
      ],
      children: [
        CheckboxListTile(
          value: _useDocuments,
          onChanged: _saving ? null : (v) => setState(() => _useDocuments = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'Verify using uploaded documents (no HR response)',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
        if (!_useDocuments) ...[
          const SizedBox(height: 8),
          SheetButtonRow(children: [
            ChoiceToggle(
              label: 'Verified',
              selected: _verified,
              tone: Tone.success,
              onTap: _saving ? null : () => setState(() => _verified = true),
            ),
            ChoiceToggle(
              label: 'Not Verified',
              selected: !_verified,
              tone: Tone.danger,
              onTap: _saving ? null : () => setState(() => _verified = false),
            ),
          ]),
        ],
        const SizedBox(height: 16),
        AppTextField(
          controller: _notes,
          label: 'Notes (optional)',
          maxLines: 3,
          enabled: !_saving,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HrResponseReviewModal
// ─────────────────────────────────────────────────────────────────────────────

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

/// Review what the previous employer's HR submitted. Pops `true` on success.
class HrResponseReviewSheet extends ConsumerStatefulWidget {
  const HrResponseReviewSheet({super.key, required this.request});

  final Map<String, dynamic> request;

  @override
  ConsumerState<HrResponseReviewSheet> createState() => _HrResponseReviewSheetState();
}

class _HrResponseReviewSheetState extends ConsumerState<HrResponseReviewSheet> {
  final _notes = TextEditingController();

  /// 'approve' | 'reject' | 'documents' while a request is in flight.
  String? _pending;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _run(String action) async {
    setState(() => _pending = action);
    final api = ref.read(enterpriseApiProvider);
    final id = idOf(widget.request);
    final notes = _notes.text.trim();
    try {
      switch (action) {
        case 'approve':
          await api.reviewHrResponse(id, {'approved': true, if (notes.isNotEmpty) 'notes': notes});
          showToast('HR verification approved — status: HR Verified', type: ToastType.success);
        case 'reject':
          await api.reviewHrResponse(id, {'approved': false, if (notes.isNotEmpty) 'notes': notes});
          showToast('HR response rejected', type: ToastType.success);
        default:
          await api.confirmDocumentVerification(id, {'notes': notes});
          showToast('Verified using submitted documents', type: ToastType.success);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      final fallback = switch (action) {
        'approve' => 'Failed to approve HR response',
        'reject' => 'Failed to reject',
        _ => 'Document verification failed',
      };
      showErrorToast(e, fallback);
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final d = asMap(r['employmentDetails']);
    final busy = _pending != null;
    final verifierLine = [str(d['verifierName']), str(d['verifierDesignation'])].where((s) => s.isNotEmpty).join(' · ');
    final worked = d['workedHere'];
    final dates = [str(d['joiningDate']), str(d['exitDate'])].where((s) => s.isNotEmpty).join(' — ');
    final remarks = str(d['hrRemarks'] ?? d['feedback'] ?? d['verificationNotes']);
    final docUrl = strOrNull(d['supportingDocumentUrl']);

    Widget row(String label, String value) => value.isEmpty ? const SizedBox.shrink() : LabeledValue(label: label, value: value);

    return SheetBody(
      title: 'Review HR Response',
      subtitle: 'Previous employer HR submitted feedback for ${str(r['employeeName'], 'this employee')} at '
          '${str(r['companyName'] ?? r['previousCompanyName'])}.',
      actions: [
        AppButton(
          label: 'Approve → HR Verified',
          loading: _pending == 'approve',
          onPressed: busy ? null : () => _run('approve'),
        ),
        AppButton(
          label: 'Reject HR Response',
          variant: AppButtonVariant.secondary,
          loading: _pending == 'reject',
          onPressed: busy ? null : () => _run('reject'),
        ),
        AppButton(
          label: 'Verify using documents instead',
          variant: AppButtonVariant.outline,
          loading: _pending == 'documents',
          onPressed: busy ? null : () => _run('documents'),
        ),
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: busy ? null : () => Navigator.of(context).pop(),
        ),
      ],
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LabeledValue(
                label: 'Worked here',
                value: worked == true ? 'Yes' : (worked == false ? 'No' : '—'),
              ),
              row('Designation', str(d['designation'])),
              row('Duration', dates),
              row('Department', str(d['department'])),
              row('Reporting manager', str(d['reportingManager'])),
              if (d['rehireEligible'] != null) row('Rehire eligible', asBool(d['rehireEligible']) ? 'Yes' : 'No'),
              row('Performance rating', _ratingLabels[str(d['performanceRating'])] ?? ''),
              row('Recommendation', _recommendationLabels[str(d['recommendation'])] ?? ''),
              row('Behavior / Conduct', str(d['behaviorRemarks'])),
              if (d['disciplinaryIssues'] != null)
                row(
                  'Disciplinary issues',
                  asBool(d['disciplinaryIssues'])
                      ? 'Yes${str(d['disciplinaryDetails']).isNotEmpty ? ' — ${str(d['disciplinaryDetails'])}' : ''}'
                      : 'None reported',
                ),
              row('HR remarks', remarks),
              if (docUrl != null)
                LabeledValue(
                  label: 'Supporting document',
                  value: '',
                  valueWidget: InkWell(
                    onTap: () => openExternalUrl(mediaUrl(docUrl)),
                    child: Text(
                      str(d['supportingDocumentName'], 'View document'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brand600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              row('Verified by', verifierLine),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppTextField(controller: _notes, label: 'Your notes (optional)', maxLines: 2, enabled: !busy),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VerificationRequestModal — start a verification for an employee's past job.
// ─────────────────────────────────────────────────────────────────────────────

/// Start an employment verification (Case A platform / Case B HR email).
/// Pops the API result map on success (null when cancelled).
class VerificationRequestSheet extends ConsumerStatefulWidget {
  const VerificationRequestSheet({
    super.key,
    required this.employeeId,
    required this.jobExperienceId,
    this.jobTitle = '',
    this.companyName = '',
    this.previousCompanyOnPlatform = false,
    this.matchedPlatformCompany,
    this.defaultHrEmail = '',
    this.defaultManagerEmail = '',
    this.defaultHrName = '',
    this.department = '',
    this.duration = '',
    this.employmentType = '',
  });

  final String employeeId;
  final String jobExperienceId;
  final String jobTitle;
  final String companyName;
  final bool previousCompanyOnPlatform;

  /// `{ id, name, city }` when the backend matched the company by name.
  final Map<String, dynamic>? matchedPlatformCompany;
  final String defaultHrEmail;
  final String defaultManagerEmail;
  final String defaultHrName;
  final String department;
  final String duration;
  final String employmentType;

  @override
  ConsumerState<VerificationRequestSheet> createState() => _VerificationRequestSheetState();
}

class _VerificationRequestSheetState extends ConsumerState<VerificationRequestSheet> {
  late final _hrEmail = TextEditingController(text: widget.defaultHrEmail);
  late final _managerEmail = TextEditingController(text: widget.defaultManagerEmail);
  late final _hrName = TextEditingController(text: widget.defaultHrName);
  final _search = TextEditingController();
  late Map<String, dynamic>? _selected = widget.matchedPlatformCompany;
  bool _forceEmail = false;
  bool _saving = false;
  bool _searching = false;
  List<Map<String, dynamic>> _results = const [];
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_hrEmail, _managerEmail, _hrName, _search]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isCaseA =>
      !_forceEmail && ((_selected != null && idOf(_selected).isNotEmpty) || widget.previousCompanyOnPlatform);

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 2 || _isCaseA) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      try {
        final res = await ref.read(enterpriseApiProvider).searchPlatformCompanies(q);
        if (!mounted || _search.text.trim() != q) return;
        setState(() => _results = listFrom(res, const ['companies', 'items']));
      } catch (_) {
        if (mounted) setState(() => _results = const []);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    final selectedId = _selected == null ? '' : idOf(_selected);
    final hrEmail = _hrEmail.text.trim();
    final managerEmail = _managerEmail.text.trim();
    final hrName = _hrName.text.trim();
    try {
      final res = await ref.read(enterpriseApiProvider).createVerificationRequest({
        'employeeId': widget.employeeId,
        'jobExperienceId': widget.jobExperienceId,
        if (_forceEmail) 'forceEmail': true else if (selectedId.isNotEmpty) 'targetCompanyId': selectedId,
        if (hrEmail.isNotEmpty) 'hrEmail': hrEmail,
        if (managerEmail.isNotEmpty) 'managerEmail': managerEmail,
        if (hrName.isNotEmpty) 'hrName': hrName,
      });
      final result = asMap(res);
      if (asBool(result['alreadyVerified'])) {
        showToast(
          str(result['message'], 'Employment already verified — reusable record available'),
          type: ToastType.success,
        );
      } else {
        showToast(
          str(result['message'] ?? pick(result, 'request.message'), 'Verification request submitted'),
          type: ToastType.success,
        );
      }
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      showErrorToast(e, 'Failed to submit request');
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final platformName =
        str(_selected?['name'], str(widget.matchedPlatformCompany?['name'], widget.companyName));
    final caseA = _isCaseA;

    return SheetBody(
      title: 'Start Employment Verification',
      actions: [
        SheetButtonRow(children: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.outline,
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
          ),
          AppButton(
            label: _saving
                ? 'Sending...'
                : (caseA ? 'Request employee consent' : 'Send HR email verification'),
            loading: _saving,
            onPressed: _saving ? null : _submit,
          ),
        ]),
      ],
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(AppRadii.control),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'PREVIOUS EMPLOYMENT · AUTO-FILLED',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.inkFaint),
                ),
              ),
              Row(children: [
                Expanded(child: LabeledValue(label: 'Company', value: widget.companyName)),
                Expanded(child: LabeledValue(label: 'Designation', value: widget.jobTitle)),
              ]),
              Row(children: [
                Expanded(child: LabeledValue(label: 'Department', value: widget.department)),
                Expanded(child: LabeledValue(label: 'Duration', value: widget.duration)),
              ]),
              if (widget.employmentType.isNotEmpty) LabeledValue(label: 'Type', value: widget.employmentType),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Verify '),
            TextSpan(text: widget.jobTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
            const TextSpan(text: ' at '),
            TextSpan(text: widget.companyName, style: const TextStyle(fontWeight: FontWeight.w700)),
            const TextSpan(text: '.'),
          ]),
          style: const TextStyle(fontSize: 14, color: AppColors.inkBody),
        ),
        const SizedBox(height: 12),
        if (caseA) ..._caseA(platformName) else ..._caseB(),
      ],
    );
  }

  List<Widget> _caseA(String platformName) {
    return [
      InfoBanner(
        tone: Tone.info,
        title: 'Case A — Direct platform verification',
        message: '$platformName is registered on PagerLook.\n'
            '1. Employee gets consent request\n'
            '2. After approve → $platformName HR sees it in Incoming\n'
            '3. They verify → Employer Verified on profile',
      ),
      if (widget.matchedPlatformCompany == null && _selected != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _saving ? null : () => setState(() => _selected = null),
            child: const Text('Change selected company'),
          ),
        ),
      const SizedBox(height: 10),
      InfoBanner(
        tone: Tone.warning,
        message: 'Is $platformName not the same company${widget.jobTitle.isNotEmpty ? ' they worked at' : ''}? '
            'We matched it by name, so it can be wrong.',
        action: TextButton(
          onPressed: _saving
              ? null
              : () => setState(() {
                    _forceEmail = true;
                    _selected = null;
                  }),
          child: const Text('Verify by HR email instead →'),
        ),
      ),
    ];
  }

  List<Widget> _caseB() {
    return [
      if (_forceEmail) ...[
        InfoBanner(
          tone: Tone.brand,
          message: 'Sending to the HR contacts on this employment record instead of the matched company.',
          action: TextButton(
            onPressed: _saving ? null : () => setState(() => _forceEmail = false),
            child: const Text('Undo'),
          ),
        ),
        const SizedBox(height: 12),
      ],
      AppCard(
        color: AppColors.canvas,
        title: 'Is ${widget.companyName} on PagerLook?',
        subtitle: 'Search and select if registered — verification goes directly to their HR dashboard.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _search,
              enabled: !_saving,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Search company name...',
                prefixIcon: Icon(Icons.search, size: 20),
              ),
            ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Searching...', style: TextStyle(fontSize: 12, color: AppColors.inkFaint)),
              ),
            if (_results.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadii.control),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(
                  children: _results
                      .map(
                        (c) => ListTile(
                          dense: true,
                          title: Text(str(c['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: strOrNull(c['city']) == null ? null : Text(str(c['city'])),
                          onTap: () {
                            _debounce?.cancel();
                            _search.clear();
                            setState(() {
                              _selected = c;
                              _results = const [];
                            });
                          },
                        ),
                      )
                      .toList(),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'OR — CASE B EMAIL VERIFICATION',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.inkFaint, letterSpacing: 0.5),
      ),
      const SizedBox(height: 4),
      const Text(
        "Contact details are pre-filled from the employee's records. Review or edit, then send. "
        "The email is delivered securely from your company's configured mailbox.",
        style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
      ),
      const SizedBox(height: 12),
      AppTextField(controller: _hrName, label: 'HR Contact Name', hint: 'Optional', enabled: !_saving),
      const SizedBox(height: 14),
      AppTextField(
        controller: _hrEmail,
        label: 'HR Email',
        hint: 'Required for email verification',
        keyboardType: TextInputType.emailAddress,
        enabled: !_saving,
      ),
      const SizedBox(height: 14),
      AppTextField(
        controller: _managerEmail,
        label: 'Manager Email',
        hint: 'Alternative contact',
        keyboardType: TextInputType.emailAddress,
        enabled: !_saving,
      ),
    ];
  }
}
