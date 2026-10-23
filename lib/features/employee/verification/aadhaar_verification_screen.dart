import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/upload.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/widgets.dart';
import '../onboarding/widgets/journey.dart';
import 'digilocker_webview.dart';
import 'verification_providers.dart';

const Map<String, String> _fieldLabels = {'name': 'Name', 'dob': 'Date of birth', 'gender': 'Gender'};

const Map<String, String> _genderOptions = {
  'male': 'Male',
  'female': 'Female',
  'other': 'Other',
  'prefer_not_to_say': 'Prefer not to say',
};

/// Port of `pages/employee/AadhaarVerification.jsx`.
///
/// DigiLocker e-KYC is the primary path (as on the web). The manual card upload
/// (`POST /employee/verification/aadhaar`) is offered as a fallback — the
/// backend only accepts it when DigiLocker isn't configured.
class AadhaarVerificationScreen extends ConsumerStatefulWidget {
  const AadhaarVerificationScreen({super.key, this.status, this.message});

  /// One-shot DigiLocker callback result: `success` | `mismatch` | `failed`.
  final String? status;
  final String? message;

  @override
  ConsumerState<AadhaarVerificationScreen> createState() => _AadhaarVerificationScreenState();
}

class _AadhaarVerificationScreenState extends ConsumerState<AadhaarVerificationScreen> {
  late final AppLifecycleListener _lifecycle;
  Timer? _poll;
  bool _awaitingDigiLocker = false;
  bool _connecting = false;
  bool _showManual = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    if (widget.status != null || widget.message != null) {
      // The callback changed verification state server-side — pull it fresh.
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshAll());
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _poll?.cancel();
    super.dispose();
  }

  void _onResume() {
    if (!_awaitingDigiLocker) return;
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    if (!mounted) return;
    final auth = ref.read(authProvider);
    invalidateVerification(ref);
    try {
      await auth.refreshEmployeeProfile();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _pullRefresh() async {
    final auth = ref.read(authProvider);
    try {
      await auth.refreshEmployeeProfile();
    } catch (_) {}
    if (!mounted) return;
    ref.invalidate(verificationStatusProvider);
    final _ = await ref.refresh(aadhaarSubmissionProvider.future);
  }

  /// Legacy manual submissions are decided by an admin out of band — poll while pending.
  void _syncPolling(Map<String, dynamic>? submission) {
    final pending = str(submission?['status']) == 'pending';
    if (pending && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 20), (_) {
        if (mounted) ref.invalidate(aadhaarSubmissionProvider);
      });
    } else if (!pending && _poll != null) {
      _poll?.cancel();
      _poll = null;
    }
  }

  /// The DigiLocker result lands server-side during the redirect; mirror it
  /// into the stored profile so the step bar and the face-match gate see it.
  void _mirrorDigiLocker(Map<String, dynamic>? submission) {
    final auth = ref.read(authProvider);
    final profile = auth.profile;
    if (profile == null || submission == null || str(submission['method']) != 'digilocker') return;
    final verified = str(submission['status']) == 'approved';
    final used = asBool(profile['digilockerUsed']);
    if (asBool(profile['aadhaarVerified']) == verified && (!verified || used)) return;
    auth.updateProfile({...profile, 'aadhaarVerified': verified, 'digilockerUsed': verified || used});
  }

  Future<void> _connect() async {
    if (_connecting) return;
    final api = ref.read(employeeApiProvider);
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final data = asMap(await api.startDigiLockerConnect('aadhaar'));
      final url = strOrNull(data['authorizationUrl']);
      if (url == null) throw ApiException('Could not start DigiLocker');
      if (!mounted) return;
      final result = await openDigiLockerInApp(context, url);
      if (!mounted || result == null) return;
      // Show the outcome on this screen, in the app — never the website.
      invalidateVerification(ref);
      context.replace(Uri(path: '/employee/verification/aadhaar', query: result.query).toString());
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not start DigiLocker'));
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<Map<String, dynamic>>>(aadhaarSubmissionProvider, (_, next) {
      final value = next.valueOrNull;
      _syncPolling(value);
      _mirrorDigiLocker(value);
    });

    final submissionAsync = ref.watch(aadhaarSubmissionProvider);
    final profile = ref.watch(authProvider).profile;

    return Scaffold(
      appBar: AppBar(title: const Text('Aadhaar verification')),
      body: AsyncValueView<Map<String, dynamic>>(
        value: submissionAsync,
        loadingLabel: 'Loading your Aadhaar status...',
        onRetry: () => ref.invalidate(aadhaarSubmissionProvider),
        data: (submission) => RefreshIndicator(
          onRefresh: _pullRefresh,
          child: _buildBody(submission, profile),
        ),
      ),
    );
  }

  Widget _buildBody(Map<String, dynamic> submission, Map<String, dynamic>? profile) {
    final status = str(submission['status'], 'not_submitted');
    final method = str(submission['method']);
    // Aadhaar is matched against the saved profile, so it has to exist first.
    final profileIncomplete = profile?['profileSetupComplete'] == false;
    // A DigiLocker mismatch is resolved in place — no new login needed.
    final canVerify = !profileIncomplete &&
        (status == 'not_submitted' || (status == 'rejected' && method != 'digilocker'));

    final subtitle = switch (status) {
      'not_submitted' => 'Identity check 1 of 2 — verify instantly with DigiLocker',
      'pending' => 'Identity check 1 of 2 — your Aadhaar is with our verification team',
      'approved' => 'Identity check 1 of 2 — verified',
      'rejected' => 'Identity check 1 of 2 — details did not match Aadhaar',
      _ => 'Identity check 1 of 2',
    };

    final children = <Widget>[
      JourneyStepCard(child: JourneyStepBar(currentStep: 'identity', completed: completedJourneySteps(profile))),
      const SizedBox(height: 16),
      PageIntro(title: 'Aadhaar verification', subtitle: subtitle),
      if (_error != null) InfoBanner(tone: Tone.danger, message: _error!),
      if (widget.status == 'failed')
        InfoBanner(
          tone: Tone.danger,
          title: 'DigiLocker verification did not complete',
          message: widget.message ?? 'Please try again.',
        ),
      if (_awaitingDigiLocker)
        InfoBanner(
          tone: Tone.info,
          title: 'Finish in DigiLocker',
          message: "Sign in to DigiLocker and allow access, then come back to the app — we'll refresh your status automatically.",
          action: TextButton.icon(
            onPressed: () {
              setState(() => _awaitingDigiLocker = false);
              _refreshAll();
            },
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text("I'm done — refresh status"),
          ),
        ),
      if (profileIncomplete) ...[
        const InfoBanner(
          tone: Tone.warning,
          title: 'Finish your basic details first',
          message: 'Your name, date of birth and gender are matched against Aadhaar, so they need to be on '
              'record before this check can run.',
        ),
        AppButton(label: 'Complete profile setup', onPressed: () => context.push('/employee/profile-setup')),
      ],
      if (!profileIncomplete && status == 'pending')
        const InfoBanner(
          tone: Tone.warning,
          title: 'Under review by the PagerLook team',
          message: 'Your earlier card upload is being reviewed. You can also verify instantly with DigiLocker '
              'once that review is finished.',
        ),
      if (method == 'manual' && (status == 'pending' || status == 'rejected')) _ManualSubmissionCard(submission: submission),
      if (status == 'approved') ...[
        const InfoBanner(
          tone: Tone.success,
          title: 'Aadhaar verified',
          message: 'Your profile details match your Aadhaar. Next, we match your live selfie against your '
              'Aadhaar photo.',
        ),
        if (method == 'digilocker') _MatchReport(submission: submission),
        AppButton(
          label: 'Continue to face match',
          icon: Icons.face,
          onPressed: () => context.push('/employee/verification/biometric'),
        ),
      ],
      if (status == 'rejected') ...[
        InfoBanner(
          tone: Tone.danger,
          title: 'Details did not match your Aadhaar',
          message: strOrNull(submission['rejectionReason']) ?? 'Update your profile to match Aadhaar and verify again.',
        ),
        if (method == 'digilocker') ...[
          _MatchReport(submission: submission),
          _ResolveMismatch(submission: submission),
        ],
      ],
      if (canVerify) ...[
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const InfoBanner(
                icon: Icons.lock_outline,
                message: 'You will sign in to DigiLocker and allow PagerLook to read your e-Aadhaar. We match '
                    'the name, date of birth and gender on Aadhaar with your profile. Your full Aadhaar '
                    'number is never shared with us — only the last 4 digits.',
              ),
              const SizedBox(height: 14),
              AppButton(
                label: _connecting ? 'Connecting to DigiLocker...' : 'Verify with DigiLocker',
                icon: Icons.account_balance_outlined,
                loading: _connecting,
                onPressed: _connecting ? null : _connect,
              ),
            ],
          ),
        ),
        if (!_showManual)
          AppButton(
            label: 'Upload Aadhaar card instead',
            icon: Icons.upload_file,
            variant: AppButtonVariant.ghost,
            onPressed: () => setState(() => _showManual = true),
          )
        else
          _ManualAadhaarForm(
            profile: profile,
            onCancel: () => setState(() => _showManual = false),
            onSubmitted: () => setState(() => _showManual = false),
          ),
      ],
    ];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(16),
      children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i < children.length - 1 && children[i] is! SizedBox) const SizedBox(height: 14),
        ],
        const SecurityNote('Bank-Grade Security Protocol'),
      ],
    );
  }
}

// ── Match report ────────────────────────────────────────────────────────────

/// Profile vs e-Aadhaar, field by field — the standard KYC match report.
class _MatchReport extends StatelessWidget {
  const _MatchReport({required this.submission});

  final Map<String, dynamic> submission;

  @override
  Widget build(BuildContext context) {
    final checks = asMapList(submission['checks']);
    return AppCard(
      title: 'Aadhaar details (from UIDAI via DigiLocker)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow(label: 'Aadhaar number', value: str(submission['aadhaarMasked'])),
          InfoRow(label: 'Checked on', value: formatDate(submission['reviewedAt'])),
          if (checks.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Divider(),
            for (final c in checks) _CheckRow(check: c),
          ],
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check});

  final Map<String, dynamic> check;

  @override
  Widget build(BuildContext context) {
    final matched = asBool(check['matched']);
    final field = str(check['field']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _fieldLabels[field] ?? field,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.inkStrong),
                ),
              ),
              StatusBadge(
                matched ? 'valid' : 'mismatch',
                label: matched ? 'Valid' : 'Mismatch',
                tone: matched ? Tone.success : Tone.danger,
              ),
            ],
          ),
          const SizedBox(height: 4),
          InfoRow(label: 'Your profile', value: str(check['expected'], '—')),
          InfoRow(label: 'Aadhaar', value: str(check['actual'], '—')),
        ],
      ),
    );
  }
}

class _ManualSubmissionCard extends StatelessWidget {
  const _ManualSubmissionCard({required this.submission});

  final Map<String, dynamic> submission;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: 'Your card upload',
      action: StatusBadge(str(submission['status'])),
      child: Column(
        children: [
          InfoRow(label: 'Aadhaar number', value: str(submission['aadhaarMasked'])),
          InfoRow(label: 'Name on Aadhaar', value: str(submission['nameOnAadhaar'])),
          InfoRow(label: 'Submitted on', value: formatDate(submission['submittedAt'])),
        ],
      ),
    );
  }
}

// ── Mismatch resolution ─────────────────────────────────────────────────────

/// The employee picks which values to continue with:
///  A. Aadhaar's values (copied onto the profile → verified immediately), or
///  B. their own, edited — every save is re-matched against the Aadhaar data.
class _ResolveMismatch extends ConsumerStatefulWidget {
  const _ResolveMismatch({required this.submission});

  final Map<String, dynamic> submission;

  @override
  ConsumerState<_ResolveMismatch> createState() => _ResolveMismatchState();
}

class _ResolveMismatchState extends ConsumerState<_ResolveMismatch> {
  bool _applying = false;
  String? _error;

  Future<void> _applyAadhaar() async {
    if (_applying) return;
    final api = ref.read(employeeApiProvider);
    final auth = ref.read(authProvider);
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      final data = asMap(await api.applyAadhaarDetails());
      await auth.updateProfile({...?auth.profile, ...asMap(data['profile'])});
      if (!mounted) return;
      invalidateVerification(ref);
      showToast('Your profile now uses your Aadhaar details', type: ToastType.success);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not update your details'));
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _editOwn() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const _EditDetailsSheet(),
    );
    if (saved == true && mounted) invalidateVerification(ref);
  }

  @override
  Widget build(BuildContext context) {
    final failed = asMapList(widget.submission['checks']).where((c) => !asBool(c['matched'])).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          InfoBanner(tone: Tone.danger, message: _error!),
          const SizedBox(height: 12),
        ],
        AppCard(
          title: 'Continue with Aadhaar details',
          subtitle: 'Recommended — verified instantly',
          borderColor: AppColors.brand100,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final c in failed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${_fieldLabels[str(c['field'])] ?? str(c['field'])}: ',
                          style: const TextStyle(color: AppColors.inkMuted),
                        ),
                        TextSpan(
                          text: str(c['expected'], '—'),
                          style: const TextStyle(decoration: TextDecoration.lineThrough, color: AppColors.inkFaint),
                        ),
                        const TextSpan(text: '  →  '),
                        TextSpan(
                          text: str(c['actual'], '—'),
                          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkStrong),
                        ),
                      ],
                    ),
                    style: const TextStyle(fontSize: 13.5),
                  ),
                ),
              const SizedBox(height: 8),
              AppButton(
                label: _applying ? 'Updating...' : 'Use Aadhaar details',
                loading: _applying,
                onPressed: _applying ? null : _applyAadhaar,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          title: 'Continue with my details',
          subtitle: 'Correct them — they are re-checked against Aadhaar as soon as you save.',
          child: AppButton(
            label: 'Edit my details',
            variant: AppButtonVariant.secondary,
            onPressed: _applying ? null : _editOwn,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Aadhaar stays unverified until your profile matches it. You can also skip this for now and '
          'come back later from the verification hub.',
          style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
        ),
      ],
    );
  }
}

class _EditDetailsSheet extends ConsumerStatefulWidget {
  const _EditDetailsSheet();

  @override
  ConsumerState<_EditDetailsSheet> createState() => _EditDetailsSheetState();
}

class _EditDetailsSheetState extends ConsumerState<_EditDetailsSheet> {
  late final TextEditingController _nameCtrl;
  String _dob = '';
  String _gender = '';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(authProvider).profile;
    _nameCtrl = TextEditingController(text: str(profile?['name']));
    final dob = str(profile?['dateOfBirth']);
    _dob = dob.length > 10 ? dob.substring(0, 10) : dob;
    final gender = str(profile?['gender']);
    _gender = _genderOptions.containsKey(gender) ? gender : '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_nameCtrl.text.trim().length < 2) {
      setState(() => _error = 'Enter your full name');
      return;
    }
    final api = ref.read(employeeApiProvider);
    final auth = ref.read(authProvider);
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final data = asMap(await api.updateProfile({
        'name': _nameCtrl.text.trim(),
        if (_dob.isNotEmpty) 'dateOfBirth': _dob,
        if (_gender.isNotEmpty) 'gender': _gender,
      }));
      await auth.updateProfile({...?auth.profile, ...data});
      showToast('Details saved — re-checked against Aadhaar', type: ToastType.success);
      navigator.pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Could not save your details'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Continue with my details',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.inkStrong),
              ),
              const SizedBox(height: 4),
              const Text(
                'Correct them below — they are re-checked against Aadhaar as soon as you save.',
                style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
              ),
              const SizedBox(height: 16),
              if (_error != null) ...[
                InfoBanner(tone: Tone.danger, message: _error!),
                const SizedBox(height: 12),
              ],
              AppTextField(
                controller: _nameCtrl,
                label: 'Full name',
                enabled: !_saving,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 14),
              AppDateField(
                label: 'Date of birth',
                value: _dob.isEmpty ? null : _dob,
                enabled: !_saving,
                lastDate: DateTime.now(),
                onChanged: (v) => setState(() => _dob = v),
              ),
              const SizedBox(height: 14),
              AppDropdown<String>(
                label: 'Gender',
                hint: 'Select gender',
                options: _genderOptions,
                value: _gender.isEmpty ? null : _gender,
                enabled: !_saving,
                onChanged: (v) => setState(() => _gender = v ?? ''),
              ),
              const SizedBox(height: 20),
              AppButton(
                label: _saving ? 'Saving...' : 'Save & re-check',
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
              const SizedBox(height: 8),
              AppButton(
                label: 'Cancel',
                variant: AppButtonVariant.ghost,
                onPressed: _saving ? null : () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Manual card upload (fallback) ───────────────────────────────────────────

/// Groups the number as printed on the card: `1234 5678 9012`.
class _AadhaarFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 12) digits = digits.substring(0, 12);
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

class _ManualAadhaarForm extends ConsumerStatefulWidget {
  const _ManualAadhaarForm({required this.profile, required this.onCancel, required this.onSubmitted});

  final Map<String, dynamic>? profile;
  final VoidCallback onCancel;
  final VoidCallback onSubmitted;

  @override
  ConsumerState<_ManualAadhaarForm> createState() => _ManualAadhaarFormState();
}

class _ManualAadhaarFormState extends ConsumerState<_ManualAadhaarForm> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _numberCtrl = TextEditingController();
  late final TextEditingController _nameCtrl = TextEditingController(text: str(widget.profile?['name']));
  final TextEditingController _addressCtrl = TextEditingController();
  late String _dob = _initialDob();
  String _gender = '';
  PickedDoc? _front;
  PickedDoc? _back;
  bool _consent = false;
  bool _submitting = false;
  bool _attempted = false;

  String _initialDob() {
    final dob = str(widget.profile?['dateOfBirth']);
    return dob.length > 10 ? dob.substring(0, 10) : dob;
  }

  @override
  void initState() {
    super.initState();
    final gender = str(widget.profile?['gender']);
    if (const ['male', 'female', 'other'].contains(gender)) _gender = gender;
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick(bool front) async {
    final picked = await pickDocumentWithSheet(
      context,
      imagesOnly: true,
      maxBytes: maxPhotoBytes,
      title: front ? 'Aadhaar card — front' : 'Aadhaar card — back',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (front) {
        _front = picked;
      } else {
        _back = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _attempted = true);
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;
    if (_front == null || _back == null) {
      showToast('Upload both sides of your Aadhaar card', type: ToastType.error);
      return;
    }
    if (!_consent) {
      showToast('You must consent before submitting your Aadhaar', type: ToastType.error);
      return;
    }
    final api = ref.read(employeeApiProvider);
    setState(() => _submitting = true);
    try {
      await api.submitAadhaar(
        aadhaarNumber: _numberCtrl.text.replaceAll(RegExp(r'\D'), ''),
        nameOnAadhaar: _nameCtrl.text.trim(),
        dobOnAadhaar: _dob,
        genderOnAadhaar: _gender,
        addressOnAadhaar: _addressCtrl.text.trim(),
        frontImage: _front!,
        backImage: _back!,
      );
      if (!mounted) return;
      showToast('Aadhaar submitted for review', type: ToastType.success);
      invalidateVerification(ref);
      widget.onSubmitted();
    } catch (e) {
      showErrorToast(e, 'Could not submit your Aadhaar');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !_submitting;
    return AppCard(
      title: 'Upload your Aadhaar card',
      subtitle: 'Our verification team reviews the card and your typed details. Nothing is marked verified until approved.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              controller: _numberCtrl,
              label: 'Aadhaar number',
              requiredMark: true,
              hint: '1234 5678 9012',
              prefixIcon: Icons.credit_card,
              keyboardType: TextInputType.number,
              inputFormatters: [_AadhaarFormatter()],
              enabled: enabled,
              validator: aadhaarValidator,
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _nameCtrl,
              label: 'Name as on Aadhaar',
              requiredMark: true,
              enabled: enabled,
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v ?? '').trim().length < 2 ? 'Name as printed on the Aadhaar card is required' : null,
            ),
            const SizedBox(height: 14),
            AppDateField(
              label: 'Date of birth on Aadhaar',
              value: _dob.isEmpty ? null : _dob,
              enabled: enabled,
              lastDate: DateTime.now(),
              onChanged: (v) => setState(() => _dob = v),
            ),
            const SizedBox(height: 14),
            AppDropdown<String>(
              label: 'Gender on Aadhaar',
              hint: 'Select gender',
              options: const {'male': 'Male', 'female': 'Female', 'other': 'Other'},
              value: _gender.isEmpty ? null : _gender,
              enabled: enabled,
              onChanged: (v) => setState(() => _gender = v ?? ''),
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _addressCtrl,
              label: 'Address on Aadhaar',
              maxLines: 3,
              minLines: 2,
              maxLength: 400,
              enabled: enabled,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            _CardImageTile(
              label: 'Front side',
              hint: 'Photo, name, DOB and number',
              file: _front,
              enabled: enabled,
              error: _attempted && _front == null ? 'Front image of the Aadhaar card is required' : null,
              onTap: () => _pick(true),
            ),
            const SizedBox(height: 14),
            _CardImageTile(
              label: 'Back side',
              hint: 'Address side',
              file: _back,
              enabled: enabled,
              error: _attempted && _back == null ? 'Back image of the Aadhaar card is required' : null,
              onTap: () => _pick(false),
            ),
            const SizedBox(height: 10),
            CheckboxListTile(
              value: _consent,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: enabled ? (v) => setState(() => _consent = v ?? false) : null,
              title: const Text(
                'I consent to PagerLook verifying my identity using my Aadhaar card.',
                style: TextStyle(fontSize: 13, color: AppColors.inkBody),
              ),
              subtitle: _attempted && !_consent
                  ? const Text('Consent is required', style: TextStyle(fontSize: 12, color: AppColors.danger))
                  : null,
            ),
            const SizedBox(height: 8),
            AppButton(
              label: _submitting ? 'Submitting...' : 'Submit for review',
              loading: _submitting,
              onPressed: _submitting ? null : _submit,
            ),
            const SizedBox(height: 6),
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.ghost,
              onPressed: _submitting ? null : widget.onCancel,
            ),
          ],
        ),
      ),
    );
  }
}

/// One side of the Aadhaar card, with a live preview so the employee can see
/// it's readable before submitting (web `AadhaarImagePicker`).
class _CardImageTile extends StatelessWidget {
  const _CardImageTile({
    required this.label,
    required this.hint,
    required this.file,
    required this.enabled,
    required this.onTap,
    this.error,
  });

  final String label;
  final String hint;
  final PickedDoc? file;
  final bool enabled;
  final VoidCallback onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final hasImage = file != null;
    final borderColor = error != null ? AppColors.danger : (hasImage ? AppColors.success : AppColors.line);
    final bg = error != null ? AppColors.dangerBg : (hasImage ? AppColors.successBg : AppColors.canvas);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(label, requiredMark: true),
        AspectRatio(
          aspectRatio: 8 / 5,
          child: Material(
            color: bg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.card),
              side: BorderSide(color: borderColor, width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? onTap : null,
              child: hasImage
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(file!.path), fit: BoxFit.contain),
                        if (enabled)
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.inkStrong.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'Change',
                                style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                      ],
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.file_upload, size: 28, color: AppColors.inkFaint),
                          const SizedBox(height: 6),
                          const Text(
                            'Tap to upload',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.inkBody),
                          ),
                          const SizedBox(height: 2),
                          Text(hint, style: const TextStyle(fontSize: 12, color: AppColors.inkFaint)),
                        ],
                      ),
                    ),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(error!, style: const TextStyle(fontSize: 12, color: AppColors.danger)),
          ),
      ],
    );
  }
}
