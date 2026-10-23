import 'dart:convert';
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
import '../../../core/widgets/widgets.dart';
import '../../../data/api/auth_api.dart';
import 'widgets/journey.dart';

/// Web: `API.EMPLOYEE.PROFILE_SETUP` — multipart, called via `lib/employeeProfile.setupProfile`.
/// Not exposed by `EmployeeApi`, so it is called on the client directly.
const String _profileSetupPath = '/employee/profile/setup';

const Map<String, String> _genderOptions = {
  'male': 'Male',
  'female': 'Female',
  'other': 'Other',
  'prefer_not_to_say': 'Prefer not to say',
};

const Map<String, String> _experienceOptions = {
  '0-1 years': '0-1 years',
  '1-3 years': '1-3 years',
  '3-5 years': '3-5 years',
  '5-8 years': '5-8 years',
  '8-12 years': '8-12 years',
  '12+ years': '12+ years',
};

const Map<String, String> _streamOptions = {
  '': 'Select stream (optional)',
  'Science': 'Science',
  'Commerce': 'Commerce',
  'Arts': 'Arts',
  'Vocational': 'Vocational',
};

/// Score per completed education level — mirrors scoreService.
const int _eduPoints = 15;

class _WizardStep {
  const _WizardStep(this.id, this.optional);
  final String id;
  final bool optional;
}

const List<_WizardStep> _steps = [
  _WizardStep('profile', false),
  _WizardStep('education', true),
  _WizardStep('identity', true),
];

const Map<String, List<String>> _eduFields = {
  'class10': ['board', 'school', 'passingYear', 'percentage'],
  'class12': ['board', 'school', 'stream', 'passingYear', 'percentage'],
  'graduation': ['degree', 'college', 'university', 'passingYear', 'percentage'],
};

/// Fields that must be filled (≥ 2 chars) for a level to count as complete.
const Map<String, List<String>> _eduRequired = {
  'class10': ['board', 'school'],
  'class12': ['board', 'school'],
  'graduation': ['degree', 'college'],
};

/// Optional steps the user deliberately jumped over. The web keeps this in
/// sessionStorage; on mobile it lives for the app session.
final List<String> _skippedStepsMemory = <String>[];

/// Port of `pages/employee/ProfileSetup.jsx` — a 3-step wizard (basic details,
/// education, identity) that saves to `POST /employee/profile/setup`.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key, this.initialStep});

  /// `profile` | `education` | `identity` (web `?step=`).
  final String? initialStep;

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final ScrollController _scroll = ScrollController();

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _roleCtrl = TextEditingController();
  final TextEditingController _companyCtrl = TextEditingController();
  final TextEditingController _cityCtrl = TextEditingController();
  final TextEditingController _currentAddressCtrl = TextEditingController();
  final TextEditingController _permanentAddressCtrl = TextEditingController();
  late final Map<String, Map<String, TextEditingController>> _edu = {
    for (final level in _eduFields.entries)
      level.key: {for (final field in level.value) field: TextEditingController()},
  };

  bool _loading = true;
  bool _saving = false;
  String _countryCode = '+91';
  String _dateOfBirth = '';
  String _gender = '';
  String _totalExperience = '';
  bool _sameAsCurrentAddress = false;
  PickedDoc? _photo;
  String _photoUrl = '';
  bool _aadhaarVerified = false;
  bool _biometricVerified = false;

  late int _step;
  bool _showStep1Errors = false;
  String? _error;
  List<String> _generalErrors = const [];
  Map<String, String> _fieldErrors = const {};

  List<TextEditingController> get _allControllers => [
        _nameCtrl,
        _phoneCtrl,
        _emailCtrl,
        _roleCtrl,
        _companyCtrl,
        _cityCtrl,
        _currentAddressCtrl,
        _permanentAddressCtrl,
        for (final level in _edu.values) ...level.values,
      ];

  @override
  void initState() {
    super.initState();
    final requested = _steps.indexWhere((s) => s.id == widget.initialStep);
    _step = requested >= 0 ? requested : 0;
    for (final c in _allControllers) {
      c.addListener(_onFieldChanged);
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in _allControllers) {
      c.removeListener(_onFieldChanged);
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  // ── Loading ─────────────────────────────────────────────────────────────

  Future<void> _load() async {
    final auth = ref.read(authProvider);
    final api = ref.read(employeeApiProvider);
    Map<String, dynamic> data;
    try {
      data = asMap(await api.fetchProfile());
    } catch (_) {
      final profile = auth.profile ?? const <String, dynamic>{};
      data = {
        ...profile,
        'phone': profile['phone'] ?? auth.user?['phone'],
        'email': profile['email'] ?? auth.user?['email'],
      };
    }
    if (!mounted) return;
    _applyProfile(_withInvitationDefaults(data, auth.invitation));
    setState(() => _loading = false);
  }

  /// Anything the inviting company already entered pre-fills the form — but
  /// only where the saved profile is still blank.
  Map<String, dynamic> _withInvitationDefaults(Map<String, dynamic> data, Map<String, String> invite) {
    final name = strOrNull(data['name']);
    final role = strOrNull(data['role']);
    final hasName = name != null && name != 'New User';
    final hasRole = role != null && role != 'Professional';
    String? inv(String key) => strOrNull(invite[key]);
    return {
      ...data,
      'name': hasName ? name : (inv('name') ?? name),
      'email': strOrNull(data['email']) ?? inv('email') ?? '',
      'phone': strOrNull(data['phone']) ?? inv('phone') ?? '',
      'role': hasRole ? role : (inv('designation') ?? role),
      'company': strOrNull(data['company']) ?? inv('companyName') ?? '',
    };
  }

  /// Web `parseStoredPhone`: split `+<cc><digits>` into code + national number.
  (String, String) _parseStoredPhone(Object? value) {
    final trimmed = str(value).trim();
    if (trimmed.isEmpty) return ('+91', '');
    if (trimmed.startsWith('+')) {
      final codes = [...PhoneField.codes]..sort((a, b) => b.length.compareTo(a.length));
      for (final code in codes) {
        if (trimmed.startsWith(code)) {
          return (code, _tenDigits(trimmed.substring(code.length)));
        }
      }
      final digits = trimmed.replaceAll(RegExp(r'\D'), '');
      return ('+91', _tenDigits(digits.length > 10 ? digits.substring(digits.length - 10) : digits));
    }
    return ('+91', _tenDigits(trimmed));
  }

  String _tenDigits(String v) {
    final digits = v.replaceAll(RegExp(r'\D'), '');
    return digits.length > 10 ? digits.substring(0, 10) : digits;
  }

  void _applyProfile(Map<String, dynamic> data) {
    final (code, phone) = _parseStoredPhone(data['phone']);
    final currentAddress = str(data['currentAddress']);
    final permanentAddress = str(data['permanentAddress']);
    final name = str(data['name']);
    final role = str(data['role']);
    final dob = str(data['dateOfBirth']);

    _nameCtrl.text = name == 'New User' ? '' : name;
    _countryCode = code;
    _phoneCtrl.text = phone;
    _emailCtrl.text = str(data['email']);
    _dateOfBirth = dob.length > 10 ? dob.substring(0, 10) : dob;
    _gender = _genderOptions.containsKey(str(data['gender'])) ? str(data['gender']) : '';
    _roleCtrl.text = role == 'Professional' ? '' : role;
    _companyCtrl.text = str(data['company']);
    final exp = str(data['totalExperience']);
    _totalExperience = _experienceOptions.containsKey(exp) ? exp : '';
    _cityCtrl.text = str(data['currentCity']);
    _currentAddressCtrl.text = currentAddress;
    _permanentAddressCtrl.text = permanentAddress;
    _sameAsCurrentAddress = currentAddress.isNotEmpty &&
        (permanentAddress.isEmpty || permanentAddress.trim() == currentAddress.trim());
    _photoUrl = str(data['photoUrl']);
    _aadhaarVerified = asBool(data['aadhaarVerified']);
    _biometricVerified = asBool(data['biometricVerified']);
    for (final level in _edu.entries) {
      for (final field in level.value.entries) {
        field.value.text = str(pick(data, 'education.${level.key}.${field.key}'));
      }
    }
  }

  // ── Derived state ───────────────────────────────────────────────────────

  String _eduValue(String level, String field) => _edu[level]![field]!.text;

  /// `empty` | `partial` | `complete`
  String _eduLevelState(String level) {
    final touched = _edu[level]!.values.any((c) => c.text.trim().isNotEmpty);
    if (!touched) return 'empty';
    final complete = _eduRequired[level]!.every((k) => _eduValue(level, k).trim().length >= 2);
    return complete ? 'complete' : 'partial';
  }

  Map<String, String> get _eduStates => {for (final level in _eduFields.keys) level: _eduLevelState(level)};

  int get _completedEduLevels => _eduStates.values.where((s) => s == 'complete').length;

  bool get _hasPartialEdu => _eduStates.values.contains('partial');

  String get _phoneDigits => _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');

  /// Step 1 — the only genuinely required information.
  List<String> get _step1Missing => [
        if (_nameCtrl.text.trim().length < 2) 'Full name',
        if (_phoneDigits.length < 10) 'Phone number',
        if (_emailCtrl.text.trim().isEmpty) 'Email',
        if (_dateOfBirth.isEmpty) 'Date of birth',
        if (_gender.isEmpty) 'Gender',
        if (_roleCtrl.text.trim().length < 2) 'Current role',
        if (_companyCtrl.text.trim().isEmpty) 'Current company',
        if (_totalExperience.isEmpty) 'Total experience',
        if (_cityCtrl.text.trim().length < 2) 'Current city',
        if (_currentAddressCtrl.text.trim().length < 5) 'Current address',
        if (!_sameAsCurrentAddress && _permanentAddressCtrl.text.trim().length < 5) 'Permanent address',
      ];

  bool get _isStep1Valid => _step1Missing.isEmpty;

  List<String> get _completedSteps => [
        if (_isStep1Valid) 'profile',
        if (_completedEduLevels > 0 && !_hasPartialEdu) 'education',
        if (_aadhaarVerified && _biometricVerified) 'identity',
      ];

  List<String> get _visibleSkipped {
    final done = _completedSteps;
    return _skippedStepsMemory.where((id) => !done.contains(id)).toList();
  }

  void _markSkipped(String id) {
    if (!_skippedStepsMemory.contains(id)) setState(() => _skippedStepsMemory.add(id));
  }

  void _clearSkipped(String id) {
    if (_skippedStepsMemory.contains(id)) setState(() => _skippedStepsMemory.remove(id));
  }

  // ── Navigation within the wizard ────────────────────────────────────────

  void _scrollTop() {
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  void _goToStep(int index) {
    FocusScope.of(context).unfocus();
    setState(() => _step = index);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTop());
  }

  void _advance() {
    if (_step == _steps.length - 1) {
      _submit();
      return;
    }
    _goToStep(_step + 1);
  }

  /// Filled in = done and no longer skipped; left empty = skipped.
  void _settleOptionalStep(int index) {
    final meta = _steps[index];
    if (!meta.optional) return;
    if (_completedSteps.contains(meta.id)) {
      _clearSkipped(meta.id);
    } else {
      _markSkipped(meta.id);
    }
  }

  void _goNext() {
    if (_step == 0) {
      if (!_isStep1Valid) {
        setState(() => _showStep1Errors = true);
        _scrollTop();
        return;
      }
      setState(() => _showStep1Errors = false);
    }
    if (_step == 1 && _hasPartialEdu) {
      _scrollTop();
      return;
    }
    _settleOptionalStep(_step);
    _advance();
  }

  void _skipStep() {
    final meta = _steps[_step];
    if (!meta.optional) return;
    // Skipping means "none of this", so a half-filled level is cleared.
    if (meta.id == 'education' && _hasPartialEdu) {
      final states = _eduStates;
      for (final entry in states.entries) {
        if (entry.value == 'partial') {
          for (final c in _edu[entry.key]!.values) {
            c.clear();
          }
        }
      }
    }
    _markSkipped(meta.id);
    _advance();
  }

  void _handleStepSelect(String id) {
    final index = _steps.indexWhere((s) => s.id == id);
    if (index < 0 || index == _step) return;
    if (index > 0 && !_isStep1Valid) {
      setState(() => _showStep1Errors = true);
      _goToStep(0);
      return;
    }
    if (_step == 1 && index != 1 && _hasPartialEdu) return;
    if (index > _step) _settleOptionalStep(_step);
    _clearSkipped(id);
    _goToStep(index);
  }

  /// Persist what's filled so far and stay on the current step.
  void _handleSave() {
    if (!_isStep1Valid) {
      setState(() => _showStep1Errors = true);
      _goToStep(0);
      return;
    }
    if (_hasPartialEdu) {
      _goToStep(1);
      return;
    }
    _submit(saveOnly: true);
  }

  void _handleFinish() {
    if (_saving || _loading) return;
    if (!_isStep1Valid) {
      setState(() => _showStep1Errors = true);
      _goToStep(0);
      return;
    }
    if (_hasPartialEdu) {
      _goToStep(1);
      return;
    }
    _submit();
  }

  /// Leave the wizard for one of the identity checks. The server refuses
  /// Aadhaar until the profile is saved, so save first, then go.
  void _startVerification(String to) {
    if (_saving || _loading) return;
    final profile = ref.read(authProvider).profile;
    if (asBool(profile?['profileSetupComplete'])) {
      context.push(to);
      return;
    }
    if (!_isStep1Valid) {
      setState(() => _showStep1Errors = true);
      _goToStep(0);
      return;
    }
    if (_hasPartialEdu) {
      _goToStep(1);
      return;
    }
    _submit(saveOnly: true, nextPath: to);
  }

  // ── Saving ──────────────────────────────────────────────────────────────

  Future<void> _submit({bool saveOnly = false, String? nextPath}) async {
    if (_saving || _loading) return;
    FocusScope.of(context).unfocus();
    final auth = ref.read(authProvider);
    final client = ref.read(apiClientProvider);
    final router = GoRouter.of(context);
    final isEditing = asBool(auth.profile?['profileSetupComplete']);

    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
      _generalErrors = const [];
    });

    try {
      // Only send education if something was actually filled — empty strings
      // would otherwise wipe a level added earlier.
      final eduPayload = {
        for (final level in _edu.entries)
          level.key: {for (final field in level.value.entries) field.key: field.value.text.trim()},
      };
      final anyEducation = eduPayload.values.any((lvl) => lvl.values.any((v) => v.isNotEmpty));
      final invitationToken = auth.invitation['token'] ?? '';

      final form = await buildFormData(
        fields: {
          'name': _nameCtrl.text.trim(),
          'phone': normalizePhone(_countryCode, _phoneCtrl.text),
          'email': _emailCtrl.text.trim(),
          'dateOfBirth': _dateOfBirth,
          'gender': _gender,
          'role': _roleCtrl.text.trim(),
          'company': _companyCtrl.text.trim(),
          'totalExperience': _totalExperience,
          'currentCity': _cityCtrl.text.trim(),
          'currentAddress': _currentAddressCtrl.text.trim(),
          'sameAsCurrentAddress': _sameAsCurrentAddress ? 'true' : 'false',
          if (!_sameAsCurrentAddress) 'permanentAddress': _permanentAddressCtrl.text.trim(),
          if (anyEducation) 'education': jsonEncode(eduPayload),
          if (invitationToken.isNotEmpty) 'invitationToken': invitationToken,
        },
        files: {'photo': _photo},
      );

      final data = asMap(await client.post(_profileSetupPath, body: form));

      // Setup is over — the skip marks were wizard state, not profile state.
      if (!saveOnly && nextPath == null) _skippedStepsMemory.clear();

      final fresh = Map<String, dynamic>.from(data)
        ..remove('nextRoute')
        ..remove('invitationResult');
      final previous = auth.profile ?? const <String, dynamic>{};
      await auth.updateProfile({
        ...previous,
        ...fresh,
        'profileSetupComplete': data['profileSetupComplete'] ?? true,
        'photoUrl': data['photoUrl'] ?? previous['photoUrl'],
      });

      if (mounted) {
        setState(() {
          // The photo is saved — don't upload it again on the next save.
          if (strOrNull(data['photoUrl']) != null) {
            _photoUrl = str(data['photoUrl']);
            _photo = null;
          }
        });
      }

      final autoJoined = asList(pick(data, 'invitationResult.autoJoined'));
      if (autoJoined.isNotEmpty) {
        final entry = autoJoined.first;
        final companyName = entry is String
            ? entry
            : (strOrNull(asMap(entry)['companyName']) ?? strOrNull(asMap(entry)['name']) ?? 'the company');
        await auth.clearInvitation();
        showToast('You have been added to $companyName team!', type: ToastType.success);
        if (nextPath != null) {
          router.push(nextPath);
        } else if (!saveOnly) {
          router.go('/employee/score');
        }
        return;
      }

      if (nextPath != null) {
        router.push(nextPath);
        return;
      }
      if (saveOnly) {
        showToast('Progress saved', type: ToastType.success);
        return;
      }
      // Finishing setup lands on the score — it's the payoff.
      router.go(isEditing ? '/employee/professional-id' : '/employee/score');
    } catch (e) {
      final fieldErrors = <String, String>{};
      final general = <String>[];
      final details = e is ApiException ? e.details : null;
      for (final item in asList(details)) {
        if (item is String) {
          general.add(item);
          continue;
        }
        final map = asMap(item);
        final path = map['path'];
        final field = strOrNull(map['field']) ?? (path is List ? path.join('.') : strOrNull(path));
        final message = strOrNull(map['message']) ?? strOrNull(map['msg']);
        if (field != null && message != null) {
          fieldErrors[field] = message;
        } else if (message != null) {
          general.add(message);
        }
      }
      if (mounted) {
        setState(() {
          _fieldErrors = fieldErrors;
          _generalErrors = general;
          _error = errorMessage(e, 'Failed to save profile');
        });
        _scrollTop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickPhoto() async {
    final picked = await pickDocumentWithSheet(
      context,
      imagesOnly: true,
      maxBytes: maxPhotoBytes,
      title: 'Profile photo',
    );
    if (picked == null || !mounted) return;
    setState(() => _photo = picked);
  }

  Future<void> _logout() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Log out?',
      message: 'Your unsaved changes on this page will be lost.',
      confirmLabel: 'Log out',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final router = GoRouter.of(context);
    await ref.read(authProvider).logout();
    router.go('/employee/otp');
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final isEditing = asBool(auth.profile?['profileSetupComplete']);
    final List<Widget> stepContent = _loading
        ? const <Widget>[]
        : switch (_step) {
            0 => _buildStepProfile(),
            1 => _buildStepEducation(),
            _ => _buildStepIdentity(isEditing: isEditing),
          };

    return PopScope(
      canPop: _step == 0 || _loading,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _handleStepSelect(_steps[_step - 1].id);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEditing ? 'Edit Your Profile' : 'Create Your Profile'),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) {
                if (v == 'logout') _logout();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'logout', child: Text('Log out')),
              ],
            ),
          ],
        ),
        body: _loading
            ? const LoadingView(label: 'Loading profile...')
            : BusyOverlay(
                busy: _saving,
                label: 'Saving profile...',
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        controller: _scroll,
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        children: [
                          _buildProgress(),
                          ..._buildErrors(),
                          const SizedBox(height: 16),
                          ...stepContent,
                          const SecurityNote('Your profile is private & encrypted'),
                        ],
                      ),
                    ),
                    _buildBottomBar(isEditing),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildProgress() {
    final skippedDetails = journeySteps.where((s) => _visibleSkipped.contains(s.id)).toList();
    return JourneyStepCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          JourneyStepBar(
            currentStep: _steps[_step].id,
            completed: _completedSteps,
            skipped: _visibleSkipped,
            onStepSelect: _saving ? null : _handleStepSelect,
          ),
          if (skippedDetails.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 10),
            for (final s in skippedDetails)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  decoration: BoxDecoration(
                    color: AppColors.warningBg,
                    borderRadius: BorderRadius.circular(AppRadii.control),
                    border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${s.label} skipped · +${s.points} pts',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkBody),
                        ),
                      ),
                      TextButton(
                        onPressed: _saving ? null : () => _handleStepSelect(s.id),
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildErrors() {
    final widgets = <Widget>[];
    if (_error != null || _generalErrors.isNotEmpty) {
      final lines = [
        if (_error != null) _error!,
        ..._generalErrors.where((g) => g != _error).map((g) => '• $g'),
      ];
      widgets.addAll([
        const SizedBox(height: 12),
        InfoBanner(tone: Tone.danger, message: lines.join('\n')),
      ]);
    }
    final missing = _step1Missing;
    if (_showStep1Errors && _step == 0 && missing.isNotEmpty) {
      widgets.addAll([
        const SizedBox(height: 12),
        InfoBanner(
          tone: Tone.warning,
          title: 'Still needed to continue:',
          message: missing.map((m) => '• $m').join('\n'),
        ),
      ]);
    }
    return widgets;
  }

  Widget _fieldError(String key) {
    final message = _fieldErrors[key];
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4),
      child: Text(message, style: const TextStyle(fontSize: 12, color: AppColors.danger)),
    );
  }

  Widget _section({required String title, String? description, required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        title: title,
        subtitle: description,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              children[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _withError(Widget field, String key) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [field, _fieldError(key)],
      );

  // Step 1 ─────────────────────────────────────────────────────────────────

  List<Widget> _buildStepProfile() {
    final enabled = !_saving;
    final employeeApi = ref.read(employeeApiProvider);
    return [
      _section(
        title: 'Personal details',
        description: 'Basic identity information for your PagerLook account',
        children: [
          _withError(
            AppTextField(
              controller: _nameCtrl,
              label: 'Full Name',
              requiredMark: true,
              prefixIcon: Icons.person_outline,
              enabled: enabled,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
            ),
            'name',
          ),
          _withError(
            PhoneField(
              controller: _phoneCtrl,
              countryCode: _countryCode,
              label: 'Phone Number',
              enabled: enabled,
              onCountryCodeChanged: (code) => setState(() => _countryCode = code),
            ),
            'phone',
          ),
          _withError(
            AppTextField(
              controller: _emailCtrl,
              label: 'Email',
              requiredMark: true,
              prefixIcon: Icons.alternate_email,
              keyboardType: TextInputType.emailAddress,
              enabled: enabled,
              autofillHints: const [AutofillHints.email],
            ),
            'email',
          ),
          _withError(
            AppDateField(
              label: 'Date of Birth',
              value: _dateOfBirth.isEmpty ? null : _dateOfBirth,
              requiredMark: true,
              enabled: enabled,
              lastDate: DateTime.now(),
              onChanged: (v) => setState(() => _dateOfBirth = v),
            ),
            'dateOfBirth',
          ),
          _withError(
            AppDropdown<String>(
              label: 'Gender',
              requiredMark: true,
              hint: 'Select gender',
              options: _genderOptions,
              value: _gender.isEmpty ? null : _gender,
              enabled: enabled,
              onChanged: (v) => setState(() => _gender = v ?? ''),
            ),
            'gender',
          ),
        ],
      ),
      _section(
        title: 'Work details',
        description: 'Your current role helps employers find and verify you',
        children: [
          _withError(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AsyncAutocompleteField<String>(
                  controller: _roleCtrl,
                  label: 'Current Role',
                  requiredMark: true,
                  hint: 'e.g. Software Engineer',
                  minChars: 1,
                  enabled: enabled,
                  displayString: (s) => s,
                  search: (q) async {
                    final dynamic data = await employeeApi.fetchRoleSuggestions(q);
                    final List<dynamic> raw = asList(data is List ? data : asMap(data)['items']);
                    return raw
                        .map<String>((e) => e is Map ? str(e['name']) : str(e))
                        .where((s) => s.isNotEmpty)
                        .toList();
                  },
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 4, left: 4),
                  child: Text(
                    'Start typing to see role suggestions',
                    style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
                  ),
                ),
              ],
            ),
            'role',
          ),
          // Plain input, no lookup: people work at companies that aren't on PagerLook.
          _withError(
            AppTextField(
              controller: _companyCtrl,
              label: 'Current Company',
              requiredMark: true,
              hint: 'Type any company name, or None',
              helper: 'Not working right now? Just type None',
              prefixIcon: Icons.business_outlined,
              enabled: enabled,
              textCapitalization: TextCapitalization.words,
            ),
            'company',
          ),
          _withError(
            AppDropdown<String>(
              label: 'Total Experience',
              requiredMark: true,
              hint: 'Select experience',
              options: _experienceOptions,
              value: _totalExperience.isEmpty ? null : _totalExperience,
              enabled: enabled,
              onChanged: (v) => setState(() => _totalExperience = v ?? ''),
            ),
            'totalExperience',
          ),
        ],
      ),
      _section(
        title: 'Location',
        description: 'Used for employment verification and your public profile',
        children: [
          _withError(
            AppTextField(
              controller: _cityCtrl,
              label: 'Current City',
              requiredMark: true,
              prefixIcon: Icons.location_city,
              enabled: enabled,
              textCapitalization: TextCapitalization.words,
            ),
            'currentCity',
          ),
          _withError(
            AppTextField(
              controller: _currentAddressCtrl,
              label: 'Current Address',
              requiredMark: true,
              maxLines: 3,
              minLines: 3,
              enabled: enabled,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
            ),
            'currentAddress',
          ),
          Material(
            color: AppColors.canvas,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.control),
              side: const BorderSide(color: AppColors.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: CheckboxListTile(
              value: _sameAsCurrentAddress,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'Permanent address same as current address',
                style: TextStyle(fontSize: 13.5, color: AppColors.inkBody),
              ),
              onChanged: enabled
                  ? (checked) => setState(() {
                        _sameAsCurrentAddress = checked ?? false;
                        if (_sameAsCurrentAddress) _permanentAddressCtrl.clear();
                      })
                  : null,
            ),
          ),
          if (!_sameAsCurrentAddress)
            _withError(
              AppTextField(
                controller: _permanentAddressCtrl,
                label: 'Permanent Address',
                requiredMark: true,
                maxLines: 3,
                minLines: 3,
                enabled: enabled,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
              ),
              'permanentAddress',
            ),
        ],
      ),
      _section(
        title: 'Profile photo',
        description: 'Optional — upload a clear photo for your professional ID',
        children: [_buildPhotoPicker(enabled)],
      ),
    ];
  }

  Widget _buildPhotoPicker(bool enabled) {
    final networkUrl = mediaUrl(_photoUrl);
    final Widget preview;
    if (_photo != null) {
      preview = Image.file(File(_photo!.path), fit: BoxFit.cover);
    } else if (networkUrl != null) {
      preview = Image.network(
        networkUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.person_outline, size: 40, color: AppColors.inkFaint),
        ),
      );
    } else {
      preview = const Center(child: Icon(Icons.person_outline, size: 40, color: AppColors.inkFaint));
    }

    return Row(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: preview,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppButton(
                label: _photo != null || networkUrl != null ? 'Change photo' : 'Choose photo',
                icon: Icons.photo_camera_outlined,
                variant: AppButtonVariant.secondary,
                compact: true,
                expand: false,
                onPressed: enabled ? _pickPhoto : null,
              ),
              const SizedBox(height: 6),
              const Text('JPEG, PNG or WebP · Max 5MB', style: TextStyle(fontSize: 12, color: AppColors.inkFaint)),
              _fieldError('photo'),
            ],
          ),
        ),
      ],
    );
  }

  // Step 2 ─────────────────────────────────────────────────────────────────

  List<Widget> _buildStepEducation() {
    final completed = _completedEduLevels;
    return [
      _section(
        title: 'Education',
        description: 'Optional · +$_eduPoints pts per level · $completed/3 added',
        children: [
          if (_hasPartialEdu)
            const InfoBanner(
              tone: Tone.danger,
              message: 'Finish or clear the half-filled level.',
            ),
        ],
      ),
      _eduLevelCard(
        title: 'Class 10th',
        subtitle: 'Secondary school',
        level: 'class10',
        children: [
          _eduField('class10', 'board', 'Board', hint: 'e.g. CBSE, ICSE, State Board', required: true),
          _eduField('class10', 'school', 'School Name', hint: 'School name', required: true),
          _eduYearPercentRow('class10', percentHint: 'e.g. 85.5'),
        ],
      ),
      _eduLevelCard(
        title: 'Class 12th',
        subtitle: 'Higher secondary',
        level: 'class12',
        children: [
          _eduField('class12', 'board', 'Board', hint: 'e.g. CBSE, ICSE, State Board', required: true),
          _eduField('class12', 'school', 'School Name', hint: 'School name', required: true),
          AppDropdown<String>(
            label: 'Stream',
            options: _streamOptions,
            value: _streamOptions.containsKey(_eduValue('class12', 'stream')) ? _eduValue('class12', 'stream') : '',
            enabled: !_saving,
            onChanged: (v) => _edu['class12']!['stream']!.text = v ?? '',
          ),
          _eduYearPercentRow('class12', percentHint: 'e.g. 78'),
        ],
      ),
      _eduLevelCard(
        title: 'Graduation',
        subtitle: 'Undergraduate degree',
        level: 'graduation',
        children: [
          _eduField('graduation', 'degree', 'Degree', hint: 'e.g. B.Tech, B.Com, B.A', required: true),
          _eduField('graduation', 'college', 'College Name', hint: 'College name', required: true),
          _eduField('graduation', 'university', 'University', hint: 'University name (optional)'),
          _eduYearPercentRow('graduation', percentLabel: 'Percentage / CGPA', percentHint: 'e.g. 8.2 CGPA', numericPercent: false),
        ],
      ),
    ];
  }

  Widget _eduLevelCard({
    required String title,
    required String subtitle,
    required String level,
    required List<Widget> children,
  }) {
    final state = _eduLevelState(level);
    final Widget? badge = switch (state) {
      'complete' => const StatusBadge('complete', label: 'Complete', tone: Tone.success),
      'partial' => const StatusBadge('partial', label: 'Incomplete', tone: Tone.danger),
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        title: title,
        subtitle: subtitle,
        action: badge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              children[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _eduField(
    String level,
    String field,
    String label, {
    String? hint,
    bool required = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
  }) {
    return _withError(
      AppTextField(
        controller: _edu[level]![field],
        label: label,
        hint: hint,
        requiredMark: required,
        enabled: !_saving,
        keyboardType: keyboardType,
        inputFormatters: formatters,
        textCapitalization: keyboardType == null ? TextCapitalization.words : TextCapitalization.none,
      ),
      'education.$level.$field',
    );
  }

  Widget _eduYearPercentRow(
    String level, {
    String percentLabel = 'Percentage',
    required String percentHint,
    bool numericPercent = true,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _eduField(
            level,
            'passingYear',
            'Passing Year',
            hint: 'YYYY',
            required: true,
            keyboardType: TextInputType.number,
            formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _eduField(
            level,
            'percentage',
            percentLabel,
            hint: percentHint,
            keyboardType: numericPercent ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          ),
        ),
      ],
    );
  }

  // Step 3 ─────────────────────────────────────────────────────────────────

  List<Widget> _buildStepIdentity({required bool isEditing}) {
    final checks = [
      (
        key: 'aadhaar',
        title: 'Aadhaar verification',
        desc: 'Secure e-KYC via DigiLocker or OTP.',
        done: _aadhaarVerified,
        to: '/employee/verification/aadhaar',
        icon: Icons.credit_card,
      ),
      (
        key: 'face',
        title: 'Face verification',
        desc: 'A quick liveness selfie matched to your ID.',
        done: _biometricVerified,
        to: '/employee/verification/biometric',
        icon: Icons.face,
      ),
    ];

    return [
      _section(
        title: 'Identity verification',
        description: 'Optional · +200 pts',
        children: [
          for (final c in checks)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(c.icon, size: 22, color: AppColors.brand600),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          c.title,
                          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.inkStrong),
                        ),
                      ),
                      if (c.done) const StatusBadge('done', label: 'Done', tone: Tone.success),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(c.desc, style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                  const SizedBox(height: 12),
                  AppButton(
                    label: c.done ? 'Verified' : 'Verify ${c.key == 'aadhaar' ? 'Aadhaar' : 'face'}',
                    icon: c.done ? Icons.check_circle_outline : null,
                    onPressed: (c.done || _saving) ? null : () => _startVerification(c.to),
                  ),
                ],
              ),
            ),
        ],
      ),
    ];
  }

  Widget _buildBottomBar(bool isEditing) {
    final meta = _steps[_step];
    final isLast = _step == _steps.length - 1;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (_step > 0) ...[
                    Expanded(
                      child: AppButton(
                        label: 'Back',
                        variant: AppButtonVariant.outline,
                        compact: true,
                        onPressed: _saving ? null : () => _handleStepSelect(_steps[_step - 1].id),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (meta.optional) ...[
                    Expanded(
                      child: AppButton(
                        label: isLast ? 'Skip & finish' : 'Skip step',
                        variant: AppButtonVariant.outline,
                        compact: true,
                        onPressed: _saving ? null : _skipStep,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: AppButton(
                      label: 'Save',
                      variant: AppButtonVariant.outline,
                      compact: true,
                      onPressed: _saving ? null : _handleSave,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (!isLast)
                AppButton(label: 'Continue', onPressed: _saving ? null : _goNext)
              else
                AppButton(
                  label: _saving ? 'Saving...' : (isEditing ? 'Save Changes' : 'Finish setup'),
                  loading: _saving,
                  onPressed: _saving ? null : _handleFinish,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
