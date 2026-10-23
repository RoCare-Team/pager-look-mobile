import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/json.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/widgets.dart';

/// HR's response to an employment-verification email (`/verify-employment/:token`)
/// — port of `pages/public/VerifyEmployment.jsx`. Shows the claim on record,
/// collects the structured verification, and lets HR attach a document.
final _verificationProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, token) async {
  final res = asMap(await ref.watch(publicApiProvider).fetchEmploymentVerification(token));
  return res['data'] is Map ? asMap(res['data']) : res;
});

const Map<String, String> _ratingOptions = {
  'excellent': 'Excellent',
  'good': 'Good',
  'average': 'Average',
  'below_average': 'Below Average',
  'poor': 'Poor',
};

const Map<String, String> _recommendationOptions = {
  'strongly_recommend': 'Strongly recommend',
  'recommend': 'Recommend',
  'neutral': 'Neutral',
  'not_recommend': 'Do not recommend',
};

class _Opt<T> {
  const _Opt(this.value, this.label, {this.negative = false});
  final T value;
  final String label;
  final bool negative;
}

const List<_Opt<String>> _verifyOptions = [
  _Opt('verified', 'Verified'),
  _Opt('unverified', 'Unverified', negative: true),
];

const List<_Opt<bool>> _yesNo = [
  _Opt(true, 'Yes'),
  _Opt(false, 'No', negative: true),
];

const List<_Opt<bool>> _noYes = [
  _Opt(false, 'No'),
  _Opt(true, 'Yes', negative: true),
];

class VerifyEmploymentScreen extends ConsumerStatefulWidget {
  const VerifyEmploymentScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<VerifyEmploymentScreen> createState() => _VerifyEmploymentScreenState();
}

class _VerifyEmploymentScreenState extends ConsumerState<VerifyEmploymentScreen> {
  // Text fields
  final _designation = TextEditingController();
  final _department = TextEditingController();
  final _reportingManager = TextEditingController();
  final _employeeCode = TextEditingController();
  final _monthlyInHandSalary = TextEditingController();
  final _yearlyPackage = TextEditingController();
  final _uanNumber = TextEditingController();
  final _pfNumber = TextEditingController();
  final _esiNumber = TextEditingController();
  final _behaviorRemarks = TextEditingController();
  final _disciplinaryDetails = TextEditingController();
  final _feedback = TextEditingController();
  final _verifierName = TextEditingController();
  final _verifierDesignation = TextEditingController();
  final _verifierEmail = TextEditingController();
  final _verifierPhone = TextEditingController();

  // Other form state (web INITIAL_FORM)
  bool _workedHere = true;
  String _joiningDate = '';
  String _exitDate = '';
  String _duration = '';
  String _salaryVerificationStatus = '';
  String _employmentVerificationStatus = '';
  String _performanceRating = '';
  String _recommendation = '';
  bool _disciplinaryIssues = false;
  bool _rehireEligible = true;
  bool _declarationAccepted = false;
  String _supportingDocumentUrl = '';
  String _supportingDocumentName = '';

  bool _uploading = false;
  String _uploadError = '';
  bool _submitting = false;
  String _submitError = '';
  bool _submitted = false;

  List<TextEditingController> get _controllers => [
        _designation,
        _department,
        _reportingManager,
        _employeeCode,
        _monthlyInHandSalary,
        _yearlyPackage,
        _uanNumber,
        _pfNumber,
        _esiNumber,
        _behaviorRemarks,
        _disciplinaryDetails,
        _feedback,
        _verifierName,
        _verifierDesignation,
        _verifierEmail,
        _verifierPhone,
      ];

  @override
  void initState() {
    super.initState();
    ref.listenManual<AsyncValue<Map<String, dynamic>>>(
      _verificationProvider(widget.token),
      (_, next) {
        final info = next.valueOrNull;
        if (info != null) _prefill(info);
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  /// Same pre-fill as the web: what the employee declared, so HR only corrects it.
  void _prefill(Map<String, dynamic> info) {
    void fill(TextEditingController c, Object? value) {
      final v = strOrNull(value);
      if (v != null) c.text = v;
    }

    fill(_designation, info['designation']);
    fill(_employeeCode, info['employeeCode']);
    fill(_department, info['department']);
    fill(_reportingManager, info['reportingManager']);
    fill(_uanNumber, info['uanNumber']);
    fill(_pfNumber, info['pfNumber']);
    fill(_esiNumber, info['esiNumber']);
    fill(_monthlyInHandSalary, info['monthlyInHandSalary']);
    fill(_yearlyPackage, info['yearlyPackage']);

    String dateOf(Object? v) {
      final s = str(v);
      return s.length >= 10 ? s.substring(0, 10) : s;
    }

    final joining = strOrNull(info['joiningDate']);
    final exit = strOrNull(info['exitDate']);
    final duration = strOrNull(info['duration']);
    if (joining != null) _joiningDate = dateOf(joining);
    if (exit != null) _exitDate = dateOf(exit);
    if (duration != null) _duration = duration;
    if (mounted) setState(() {});
  }

  bool get _salaryStatusMissing => _workedHere && _salaryVerificationStatus.isEmpty;
  bool get _decisionMissing => _workedHere && _employmentVerificationStatus.isEmpty;
  bool get _canSubmit => _declarationAccepted && !_salaryStatusMissing && !_decisionMissing && !_submitting;

  /// The web form object, key for key.
  Map<String, dynamic> _payload() => {
        'workedHere': _workedHere,
        'designation': _designation.text,
        'joiningDate': _joiningDate,
        'exitDate': _exitDate,
        'duration': _duration,
        'employeeCode': _employeeCode.text,
        'department': _department.text,
        'reportingManager': _reportingManager.text,
        'uanNumber': _uanNumber.text,
        'pfNumber': _pfNumber.text,
        'esiNumber': _esiNumber.text,
        'monthlyInHandSalary': _monthlyInHandSalary.text,
        'yearlyPackage': _yearlyPackage.text,
        'salaryVerificationStatus': _salaryVerificationStatus,
        'employmentVerificationStatus': _employmentVerificationStatus,
        'performanceRating': _performanceRating,
        'behaviorRemarks': _behaviorRemarks.text,
        'disciplinaryIssues': _disciplinaryIssues,
        'disciplinaryDetails': _disciplinaryDetails.text,
        'recommendation': _recommendation,
        'rehireEligible': _rehireEligible,
        'feedback': _feedback.text,
        'hrRemarks': _feedback.text,
        'supportingDocumentUrl': _supportingDocumentUrl,
        'supportingDocumentName': _supportingDocumentName,
        'verifierName': _verifierName.text,
        'verifierDesignation': _verifierDesignation.text,
        'verifierEmail': _verifierEmail.text,
        'verifierPhone': _verifierPhone.text,
        'declarationAccepted': _declarationAccepted,
      };

  Future<void> _submit() async {
    if (!_canSubmit) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _submitError = '';
    });
    try {
      await ref.read(publicApiProvider).submitEmploymentVerification(widget.token, _payload());
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitted = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = errorMessage(e, 'Could not submit the verification');
      });
    }
  }

  Future<void> _upload() async {
    final file = await pickDocumentWithSheet(context, title: 'Supporting document');
    if (file == null || !mounted) return;
    setState(() {
      _uploading = true;
      _uploadError = '';
    });
    try {
      final res = asMap(await ref.read(publicApiProvider).uploadVerificationDocument(widget.token, file));
      final result = res['data'] is Map ? asMap(res['data']) : res;
      if (!mounted) return;
      setState(() {
        _supportingDocumentUrl = str(result['url']);
        _supportingDocumentName = str(result['originalName'], file.name);
      });
    } catch (e) {
      if (mounted) setState(() => _uploadError = errorMessage(e, 'Upload failed'));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_verificationProvider(widget.token));

    return Scaffold(
      appBar: AppBar(title: const Text('Employment verification')),
      body: SafeArea(
        child: async.when(
          loading: () => const LoadingView(label: 'Loading verification request...'),
          error: (e, _) => ErrorView(
            error: e,
            title: 'Verification link is invalid or expired.',
            onRetry: () => ref.invalidate(_verificationProvider(widget.token)),
          ),
          data: (info) => _submitted ? _buildThanks() : _buildForm(info),
        ),
      ),
    );
  }

  Widget _buildThanks() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: AppColors.successBg, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, size: 34, color: AppColors.success),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Thank you',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.inkStrong),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your employment verification response has been recorded on PagerLook. The requesting '
          'company will review your submission.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.inkBody),
        ),
        const SizedBox(height: 28),
        AppButton(
          label: 'Done',
          variant: AppButtonVariant.outline,
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
      ],
    );
  }

  Widget _buildForm(Map<String, dynamic> info) {
    final employeeName = str(info['employeeName']);
    final requestingCompany = strOrNull(info['requestingCompanyName']);
    final previousCompany = strOrNull(info['previousCompanyName']);
    final positions = asMapList(info['positions']);
    final documents = asMapList(info['documents']);
    final declaredMonthly = strOrNull(info['monthlyInHandSalary']);
    final declaredYearly = strOrNull(info['yearlyPackage']);

    final hint = _submitHint();
    const bold = TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkStrong);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Text('PAGERLOOK', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        Text('Employment Verification', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            children: [
              if (requestingCompany != null) ...[
                TextSpan(text: requestingCompany, style: bold),
                const TextSpan(text: ' has requested verification of '),
              ] else
                const TextSpan(text: 'Please confirm employment details for '),
              TextSpan(text: employeeName, style: bold),
              if (previousCompany != null) ...[
                const TextSpan(text: ' at '),
                TextSpan(text: previousCompany, style: bold),
              ],
              const TextSpan(text: '.'),
            ],
          ),
          style: const TextStyle(fontSize: 14, height: 1.45, color: AppColors.inkBody),
        ),
        const SizedBox(height: 16),

        // ── Employee on record ────────────────────────────────────────────
        AppCard(
          title: 'Employee on record',
          child: Column(
            children: [
              InfoRow(label: 'Name', value: employeeName),
              InfoRow(label: 'PagerLook ID', value: str(info['employeePagerlookId'])),
              InfoRow(label: 'Designation', value: str(info['designation'])),
              InfoRow(label: 'Department', value: str(info['department'])),
              InfoRow(label: 'Duration', value: str(info['duration'])),
              InfoRow(label: 'Reporting manager', value: str(info['reportingManager'])),
              InfoRow(label: 'Monthly in-hand (declared)', value: declaredMonthly == null ? '' : '₹$declaredMonthly'),
              InfoRow(label: 'Yearly package (declared)', value: declaredYearly == null ? '' : '₹$declaredYearly'),
            ],
          ),
        ),

        // ── Career journey ────────────────────────────────────────────────
        if (positions.isNotEmpty) ...[
          const SizedBox(height: 12),
          AppCard(
            title: 'Career journey at your company (${positions.length})',
            subtitle: 'Please confirm this progression is accurate in your response below.',
            child: Column(
              children: [
                for (var i = 0; i < positions.length; i++)
                  _PositionRow(index: i, position: positions[i], isLast: i == positions.length - 1),
              ],
            ),
          ),
        ],

        // ── Employee documents ────────────────────────────────────────────
        if (documents.isNotEmpty) ...[
          const SizedBox(height: 12),
          AppCard(
            title: 'Employee documents (${documents.length})',
            child: Column(
              children: [
                for (final doc in documents)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.description_outlined),
                    title: Text(
                      titleCase(str(doc['documentType'], 'document').replaceAll('_', ' ')),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.inkStrong),
                    ),
                    subtitle: Text(str(doc['originalName']), maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: TextButton(
                      onPressed: () => openExternalUrl(mediaUrl(doc['url'])),
                      child: const Text('View'),
                    ),
                  ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 12),

        // ── The response form ─────────────────────────────────────────────
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Did this person work at your company?',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.inkStrong),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ChoiceButton(
                      label: 'Yes, worked here',
                      selected: _workedHere,
                      onTap: () => setState(() => _workedHere = true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ChoiceButton(
                      label: 'Did not work here',
                      selected: !_workedHere,
                      negative: true,
                      onTap: () => setState(() => _workedHere = false),
                    ),
                  ),
                ],
              ),
              if (_workedHere) ..._workedHereSection(info, declaredMonthly, declaredYearly, employeeName),
              const SizedBox(height: 20),
              AppTextField(
                controller: _feedback,
                label: 'HR remarks / additional comments',
                hint: 'Optional notes',
                maxLines: 4,
                minLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              _buildDocumentPicker(),
            ],
          ),
        ),

        // ── Verifier ──────────────────────────────────────────────────────
        const SizedBox(height: 12),
        AppCard(
          title: 'Verifier details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                controller: _verifierName,
                label: 'Your name',
                hint: 'Full name',
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _verifierDesignation,
                label: 'Your designation',
                hint: 'e.g. HR Manager',
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _verifierEmail,
                label: 'Your email',
                hint: 'you@company.com',
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                validator: (v) => emailValidator(v, required: false),
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _verifierPhone,
                label: 'Your phone',
                hint: 'Optional',
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
              ),
            ],
          ),
        ),

        // ── Declaration & submit ──────────────────────────────────────────
        const SizedBox(height: 12),
        Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.card),
            side: const BorderSide(color: AppColors.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: CheckboxListTile(
            value: _declarationAccepted,
            onChanged: (v) => setState(() => _declarationAccepted = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            title: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'I declare that the information provided above is true and accurate to the best of my '
                        'knowledge, and that I am authorised to verify this employment on behalf of ',
                  ),
                  TextSpan(text: previousCompany ?? 'the company', style: bold),
                  const TextSpan(text: '.'),
                ],
              ),
              style: const TextStyle(fontSize: 13, height: 1.45, color: AppColors.inkBody),
            ),
          ),
        ),
        if (_submitError.isNotEmpty) ...[
          const SizedBox(height: 12),
          InfoBanner(message: _submitError, tone: Tone.danger),
        ],
        const SizedBox(height: 18),
        AppButton(
          label: _submitting ? 'Submitting…' : 'Submit verification',
          loading: _submitting,
          onPressed: _canSubmit ? _submit : null,
        ),
        if (hint != null) ...[
          const SizedBox(height: 8),
          Text(hint.$1, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: hint.$2)),
        ],
        const SizedBox(height: 20),
        const Text(
          'Secure verification powered by PagerLook',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
        ),
      ],
    );
  }

  (String, Color)? _submitHint() {
    if (_decisionMissing) {
      return ('Please mark this employment as Verified or Unverified to submit.', AppColors.warning);
    }
    if (_salaryStatusMissing) {
      return ('Please confirm whether the salary is correct to submit.', AppColors.warning);
    }
    if (!_declarationAccepted) {
      return ('Please accept the declaration to submit.', AppColors.inkFaint);
    }
    return null;
  }

  List<Widget> _workedHereSection(
    Map<String, dynamic> info,
    String? declaredMonthly,
    String? declaredYearly,
    String employeeName,
  ) {
    final decisionNote = switch (_employmentVerificationStatus) {
      'verified' => '✓ This employment will be marked as verified on their PagerLook profile.',
      'unverified' => '✗ This employment will be marked as unverified — the details could not be confirmed.',
      _ => 'Choose Verified or Unverified to complete the verification.',
    };

    return [
      // Employment details
      const _GroupTitle('Employment details'),
      AppTextField(
        controller: _designation,
        label: 'Job title / Designation',
        hint: 'Job title',
        textCapitalization: TextCapitalization.words,
      ),
      const SizedBox(height: 12),
      AppDateField(
        label: 'Joining date',
        value: _joiningDate.isEmpty ? null : _joiningDate,
        onChanged: (v) => setState(() => _joiningDate = v),
      ),
      const SizedBox(height: 12),
      AppDateField(
        label: 'Exit date',
        value: _exitDate.isEmpty ? null : _exitDate,
        onChanged: (v) => setState(() => _exitDate = v),
      ),
      const SizedBox(height: 12),
      AppTextField(
        controller: _department,
        label: 'Department',
        hint: 'Department',
        textCapitalization: TextCapitalization.words,
      ),
      const SizedBox(height: 12),
      AppTextField(
        controller: _reportingManager,
        label: 'Reporting manager',
        hint: 'Manager name',
        textCapitalization: TextCapitalization.words,
      ),
      const SizedBox(height: 12),
      AppTextField(controller: _employeeCode, label: 'Employee ID / Code', hint: 'Company employee code'),

      // Salary
      const _GroupTitle('Salary', hint: 'Confirm the amount, then mark it verified or unverified'),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.brand50,
          borderRadius: BorderRadius.circular(AppRadii.control),
          border: Border.all(color: AppColors.brand100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'EMPLOYEE DECLARED',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: AppColors.brand600),
            ),
            const SizedBox(height: 6),
            Text(
              'Monthly in-hand: ${declaredMonthly == null ? 'Not provided' : '₹$declaredMonthly'}',
              style: const TextStyle(fontSize: 13.5, color: AppColors.inkBody),
            ),
            const SizedBox(height: 2),
            Text(
              'Yearly package: ${declaredYearly == null ? 'Not provided' : '₹$declaredYearly'}',
              style: const TextStyle(fontSize: 13.5, color: AppColors.inkBody),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      AppTextField(
        controller: _monthlyInHandSalary,
        label: 'Monthly in-hand (₹)',
        hint: 'e.g. 45000',
        keyboardType: TextInputType.number,
      ),
      const SizedBox(height: 12),
      AppTextField(
        controller: _yearlyPackage,
        label: 'Yearly package (₹)',
        hint: 'e.g. 1200000',
        keyboardType: TextInputType.number,
      ),
      const SizedBox(height: 14),
      _Choice<String>(
        label: 'Are these salary figures correct?',
        requiredMark: true,
        value: _salaryVerificationStatus,
        options: _verifyOptions,
        onChanged: (v) => setState(() => _salaryVerificationStatus = v),
      ),

      // Statutory IDs
      const _GroupTitle('Statutory IDs', hint: 'Optional — strengthens the verification'),
      AppTextField(
        controller: _uanNumber,
        label: 'UAN (PF)',
        hint: '12 digits',
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)],
      ),
      const SizedBox(height: 12),
      AppTextField(controller: _pfNumber, label: 'PF ID'),
      const SizedBox(height: 12),
      AppTextField(controller: _esiNumber, label: 'ESI No.'),

      // Performance & conduct
      const _GroupTitle('Performance & conduct'),
      AppDropdown<String>(
        label: 'Performance rating',
        hint: 'Select…',
        options: _ratingOptions,
        value: _performanceRating.isEmpty ? null : _performanceRating,
        onChanged: (v) => setState(() => _performanceRating = v ?? ''),
      ),
      const SizedBox(height: 12),
      AppDropdown<String>(
        label: 'Recommendation',
        hint: 'Select…',
        options: _recommendationOptions,
        value: _recommendation.isEmpty ? null : _recommendation,
        onChanged: (v) => setState(() => _recommendation = v ?? ''),
      ),
      const SizedBox(height: 12),
      AppTextField(
        controller: _behaviorRemarks,
        label: 'Behavior / Conduct remarks',
        hint: 'Professionalism, teamwork, conduct…',
        maxLines: 3,
        minLines: 2,
        textCapitalization: TextCapitalization.sentences,
      ),
      const SizedBox(height: 14),
      _Choice<bool>(
        label: 'Any disciplinary issues on record?',
        value: _disciplinaryIssues,
        options: _noYes,
        onChanged: (v) => setState(() => _disciplinaryIssues = v),
      ),
      if (_disciplinaryIssues) ...[
        const SizedBox(height: 8),
        AppTextField(
          controller: _disciplinaryDetails,
          hint: 'Please describe the disciplinary issue(s)',
          maxLines: 3,
          minLines: 2,
          textCapitalization: TextCapitalization.sentences,
        ),
      ],
      const SizedBox(height: 14),
      _Choice<bool>(
        label: 'Eligible for rehire?',
        value: _rehireEligible,
        options: _yesNo,
        onChanged: (v) => setState(() => _rehireEligible = v),
      ),

      // Final verification
      const _GroupTitle('Final verification', hint: 'Your decision on this employment record'),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.brand50,
          borderRadius: BorderRadius.circular(AppRadii.control),
          border: Border.all(color: AppColors.brand100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Choice<String>(
              label: "Do you verify ${employeeName.isEmpty ? 'this person' : employeeName}'s employment?",
              requiredMark: true,
              value: _employmentVerificationStatus,
              options: _verifyOptions,
              onChanged: (v) => setState(() => _employmentVerificationStatus = v),
            ),
            const SizedBox(height: 10),
            Text(decisionNote, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
          ],
        ),
      ),
    ];
  }

  Widget _buildDocumentPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FieldLabel('Supporting document (optional)'),
        if (_supportingDocumentUrl.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(
              color: AppColors.successBg,
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline, size: 18, color: AppColors.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _supportingDocumentName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, color: AppColors.inkStrong),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  onPressed: () => setState(() {
                    _supportingDocumentUrl = '';
                    _supportingDocumentName = '';
                  }),
                  child: const Text('Remove'),
                ),
              ],
            ),
          )
        else
          AppButton(
            label: _uploading ? 'Uploading…' : 'Attach PDF or image',
            icon: Icons.attach_file,
            variant: AppButtonVariant.outline,
            loading: _uploading,
            onPressed: _upload,
          ),
        if (_uploadError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_uploadError, style: const TextStyle(fontSize: 12, color: AppColors.danger)),
          ),
      ],
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.title, {this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const SizedBox(height: 14),
          Text(
            title.toUpperCase(),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.brand600),
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(hint!, style: const TextStyle(fontSize: 12, color: AppColors.inkFaint)),
            ),
        ],
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({required this.label, required this.selected, required this.onTap, this.negative = false});

  final String label;
  final bool selected;
  final bool negative;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = negative ? Tone.danger : Tone.success;
    return Material(
      color: selected ? tone.bg : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
        side: BorderSide(color: selected ? tone.fg : AppColors.line, width: selected ? 1.4 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: selected ? tone.fg : AppColors.inkBody,
            ),
          ),
        ),
      ),
    );
  }
}

/// Two-button choice (web `Choice`).
class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.requiredMark = false,
  });

  final String label;
  final T value;
  final List<_Opt<T>> options;
  final ValueChanged<T> onChanged;
  final bool requiredMark;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(label, requiredMark: requiredMark),
        Row(
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: _ChoiceButton(
                  label: options[i].label,
                  selected: options[i].value == value,
                  negative: options[i].negative,
                  onTap: () => onChanged(options[i].value),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _PositionRow extends StatelessWidget {
  const _PositionRow({required this.index, required this.position, required this.isLast});

  final int index;
  final Map<String, dynamic> position;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final yearly = strOrNull(position['yearlyPackage']);
    final monthly = strOrNull(position['monthlyInHandSalary']);
    final to = asBool(position['isCurrent']) ? 'Present' : str(position['toDate'], '—');
    final line = StringBuffer('${str(position['fromDate'], '—')} → $to');
    if (yearly != null) line.write(' · CTC ₹$yearly');
    if (monthly != null) line.write(' · In-hand ₹$monthly/mo');

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.brand600, shape: BoxShape.circle),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 1, margin: const EdgeInsets.symmetric(vertical: 4), color: AppColors.line),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    str(position['title'], '—'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.inkStrong),
                  ),
                  const SizedBox(height: 2),
                  Text(line.toString(), style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
