import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/upload.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import 'employee_portal_utils.dart';
import 'employee_score_screen.dart';
import 'job_history_screen.dart';

/// Web `addExperienceConstants.js`.
const List<String> _employmentTypes = ['Full-time', 'Part-time', 'Contract', 'Internship', 'Freelance'];

class _DocSlot {
  const _DocSlot(this.id, this.title, this.icon);
  final String id;
  final String title;
  final IconData icon;
}

const List<_DocSlot> _experienceDocuments = [
  _DocSlot('offer_letter', 'Offer Letter', Icons.description_outlined),
  _DocSlot('salary_slip', 'Recent Salary Slip', Icons.receipt_long_outlined),
  _DocSlot('experience_letter', 'Experience Letter', Icons.assignment_outlined),
  _DocSlot('relieving_letter', 'Relieving Letter', Icons.badge_outlined),
  _DocSlot('pf_statement', 'PF / UAN Statement', Icons.description_outlined),
  _DocSlot('form_16', 'Form 16 (Tax)', Icons.receipt_long_outlined),
];

const int _baseHrSlots = 2;
const int _maxHrContacts = 6;
const int _maxPositions = 15;

/// A role held at this company (one per promotion).
class _Position {
  _Position(VoidCallback onChange) {
    for (final c in [title, yearlyPackage, monthly]) {
      c.addListener(onChange);
    }
  }

  final title = TextEditingController();
  final yearlyPackage = TextEditingController();
  final monthly = TextEditingController();
  String? fromDate;
  String? toDate;
  bool isCurrent = false;

  void dispose() {
    title.dispose();
    yearlyPackage.dispose();
    monthly.dispose();
  }
}

/// Port of `AddExperience.jsx` — creates the job, uploads any documents, then
/// opens its verification page.
class AddExperienceScreen extends ConsumerStatefulWidget {
  const AddExperienceScreen({super.key});

  @override
  ConsumerState<AddExperienceScreen> createState() => _AddExperienceScreenState();
}

class _AddExperienceScreenState extends ConsumerState<AddExperienceScreen> {
  final _company = TextEditingController();
  final _role = TextEditingController();
  final _department = TextEditingController();
  final _workLocation = TextEditingController();
  final _employeeCode = TextEditingController();
  final _yearlyPackage = TextEditingController();
  final _monthly = TextEditingController();
  final _uan = TextEditingController();
  final _pf = TextEditingController();
  final _esi = TextEditingController();
  final _companyEmail = TextEditingController();
  final _description = TextEditingController();

  String _employmentType = 'Full-time';
  String? _joiningDate;
  String? _exitDate;
  bool _isPresent = false;
  final List<_Position> _positions = [];
  List<String> _hrContacts = List.filled(_baseHrSlots, '');
  final Map<String, PickedDoc> _documents = {};
  bool _submitting = false;
  String? _error;

  List<TextEditingController> get _controllers => [
        _company,
        _role,
        _department,
        _workLocation,
        _employeeCode,
        _yearlyPackage,
        _monthly,
        _uan,
        _pf,
        _esi,
        _companyEmail,
        _description,
      ];

  @override
  void initState() {
    super.initState();
    for (final c in [_company, _role, _uan, _companyEmail]) {
      c.addListener(_onChanged);
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final p in _positions) {
      p.dispose();
    }
    super.dispose();
  }

  bool get _uanValid => _uan.text.isEmpty || _uan.text.length == 12;

  bool get _datesValid =>
      _exitDate == null || _joiningDate == null || _exitDate!.compareTo(_joiningDate!) >= 0;

  bool get _isValid =>
      _company.text.trim().isNotEmpty &&
      _role.text.trim().isNotEmpty &&
      _joiningDate != null &&
      (_isPresent || _exitDate != null) &&
      _companyEmail.text.trim().isNotEmpty &&
      _uanValid &&
      _datesValid;

  List<Map<String, dynamic>> get _cleanPositions => _positions
      .map((p) => <String, dynamic>{
            'title': p.title.text.trim(),
            'fromDate': p.fromDate ?? '',
            'toDate': p.isCurrent ? '' : (p.toDate ?? ''),
            'isCurrent': p.isCurrent,
            'yearlyPackage': p.yearlyPackage.text.trim(),
            'monthlyInHandSalary': p.monthly.text.trim(),
          })
      .where((p) => (p['title'] as String).isNotEmpty)
      .toList();

  Future<List<Map<String, dynamic>>> _searchCompanies(String q) async =>
      listFrom(await ref.read(employeeApiProvider).fetchCompanySuggestions(q));

  Future<List<Map<String, dynamic>>> _searchRoles(String q) async =>
      listFrom(await ref.read(employeeApiProvider).fetchRoleSuggestions(q));

  Future<void> _pickDoc(_DocSlot slot) async {
    final file = await pickDocumentWithSheet(context, title: slot.title);
    if (file == null || !mounted) return;
    setState(() => _documents[slot.id] = file);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_isValid || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final api = ref.read(employeeApiProvider);
    final hr = cleanContacts(_hrContacts);
    try {
      final job = asMap(await api.createJob({
        'title': _role.text.trim(),
        'company': _company.text.trim(),
        'employmentType': _employmentType,
        'department': _department.text.trim(),
        'workLocation': _workLocation.text.trim(),
        'employeeCode': _employeeCode.text.trim(),
        'joiningDate': _joiningDate ?? '',
        'exitDate': _isPresent ? '' : (_exitDate ?? ''),
        'isPresent': _isPresent,
        'uanNumber': _uan.text.trim(),
        'pfNumber': _pf.text.trim(),
        'esiNumber': _esi.text.trim(),
        'yearlyPackage': _yearlyPackage.text.trim(),
        'monthlyInHandSalary': _monthly.text.trim(),
        'positions': _cleanPositions,
        'companyEmail': _companyEmail.text.trim(),
        'hrContacts': hr,
        'hrEmail': hr.isNotEmpty ? hr[0] : '',
        'managerEmail': hr.length > 1 ? hr[1] : '',
        'description': _description.text.trim(),
      }));
      final jobId = idOf(job);
      for (final entry in _documents.entries) {
        await api.uploadJobDocument(jobId, entry.value, documentType: entry.key);
      }
      ref.invalidate(employeeJobsProvider);
      ref.invalidate(employeeScoreProvider);
      try {
        await ref.read(authProvider).refreshEmployeeProfile();
      } catch (_) {
        // Non-critical — the job was saved.
      }
      if (!mounted) return;
      showToast('Employment added', type: ToastType.success);
      if (jobId.isNotEmpty) {
        context.pushReplacement('/employee/jobs/$jobId/verify');
      } else {
        context.pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = errorMessage(e, 'Failed to add job');
      });
      showErrorToast(e, 'Failed to add job');
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  Widget _section(String title, {String? subtitle, required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppCard(
        title: title,
        subtitle: subtitle,
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

  @override
  Widget build(BuildContext context) {
    final disabled = _submitting;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Employment Details')),
      body: BusyOverlay(
        busy: _submitting,
        label: 'Saving employment...',
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              const PageIntro(
                title: 'Add Employment Details',
                subtitle: 'Complete employment and statutory details for verification',
              ),
              if (_error != null) ...[
                InfoBanner(tone: Tone.danger, message: _error!),
                const SizedBox(height: 16),
              ],

              _section('Company & Role', children: [
                AsyncAutocompleteField<Map<String, dynamic>>(
                  controller: _company,
                  label: 'Company Name',
                  requiredMark: true,
                  hint: 'e.g. Tata Consultancy Services',
                  enabled: !disabled,
                  search: _searchCompanies,
                  displayString: (o) => str(o['name']),
                  subtitle: (o) {
                    final meta = [str(o['industry']), str(o['city'])].where((s) => s.isNotEmpty).join(' · ');
                    return meta.isEmpty ? null : meta;
                  },
                ),
                AsyncAutocompleteField<Map<String, dynamic>>(
                  controller: _role,
                  label: 'Role / Designation',
                  requiredMark: true,
                  hint: 'e.g. Senior Software Engineer',
                  enabled: !disabled,
                  search: _searchRoles,
                  displayString: (o) => str(o['name']),
                ),
                AppDropdown<String>(
                  label: 'Employment Type',
                  options: {for (final t in _employmentTypes) t: t},
                  value: _employmentType,
                  enabled: !disabled,
                  onChanged: (v) => setState(() => _employmentType = v ?? 'Full-time'),
                ),
                AppTextField(
                  controller: _department,
                  label: 'Department',
                  hint: 'e.g. Engineering',
                  enabled: !disabled,
                  textCapitalization: TextCapitalization.words,
                ),
                AppTextField(
                  controller: _workLocation,
                  label: 'Work Location',
                  hint: 'e.g. Mumbai, Maharashtra',
                  enabled: !disabled,
                  textCapitalization: TextCapitalization.words,
                ),
                AppTextField(
                  controller: _employeeCode,
                  label: 'Employee ID / Code',
                  hint: 'Company employee number',
                  enabled: !disabled,
                ),
                AppTextField(
                  controller: _yearlyPackage,
                  label: 'Yearly Package (CTC)',
                  hint: 'e.g. 1200000',
                  helper: 'Annual cost to company',
                  prefixIcon: Icons.payments_outlined,
                  keyboardType: TextInputType.number,
                  enabled: !disabled,
                ),
                AppTextField(
                  controller: _monthly,
                  label: 'Monthly In-Hand',
                  hint: 'e.g. 45000',
                  helper: 'Monthly take-home — HR confirms this during verification',
                  prefixText: '₹ ',
                  keyboardType: TextInputType.number,
                  enabled: !disabled,
                ),
              ]),

              _section('Employment Timeline', children: [
                AppDateField(
                  label: 'Joining Date',
                  requiredMark: true,
                  value: _joiningDate,
                  enabled: !disabled,
                  lastDate: DateTime.now(),
                  onChanged: (v) => setState(() => _joiningDate = v),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppDateField(
                      label: 'Exit Date',
                      requiredMark: !_isPresent,
                      value: _isPresent ? null : _exitDate,
                      enabled: !disabled && !_isPresent,
                      onChanged: (v) => setState(() => _exitDate = v),
                    ),
                    if (!_datesValid)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'Exit date cannot be before joining date',
                          style: TextStyle(fontSize: 12, color: AppColors.danger),
                        ),
                      ),
                    CheckboxListTile(
                      value: _isPresent,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Currently working here'),
                      onChanged: disabled
                          ? null
                          : (v) => setState(() {
                                _isPresent = v ?? false;
                                if (_isPresent) _exitDate = null;
                              }),
                    ),
                  ],
                ),
              ]),

              _section(
                'Career Journey at this Company',
                subtitle: 'Optional — add each role you held here. E.g. joined as Software Engineer, '
                    'then promoted to Senior Software Engineer.',
                children: [
                  if (_positions.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.canvas,
                        borderRadius: BorderRadius.circular(AppRadii.control),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: const Text(
                        'No roles added yet. Add one for each promotion or title change.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
                      ),
                    ),
                  for (var i = 0; i < _positions.length; i++) _positionCard(i, disabled),
                  if (_positions.length < _maxPositions)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: disabled ? null : () => setState(() => _positions.add(_Position(_onChanged))),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add role / promotion'),
                      ),
                    ),
                ],
              ),

              _section(
                'PF, ESI & Statutory Details',
                subtitle: 'Provident Fund and ESI details strengthen employment verification',
                children: [
                  AppTextField(
                    controller: _uan,
                    label: 'UAN (PF)',
                    hint: '12-digit Universal Account Number',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)],
                    validator: (_) => _uanValid ? null : 'UAN must be exactly 12 digits',
                    enabled: !disabled,
                  ),
                  AppTextField(
                    controller: _pf,
                    label: 'PF Member ID',
                    hint: 'EPF member / PF account number',
                    enabled: !disabled,
                  ),
                  AppTextField(
                    controller: _esi,
                    label: 'ESI / ESIC Number',
                    hint: 'Employee State Insurance number',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(17)],
                    enabled: !disabled,
                  ),
                ],
              ),

              _section(
                'Verification Contacts',
                subtitle: 'We email your verification request to these HR contacts.',
                children: [
                  AppTextField(
                    controller: _companyEmail,
                    label: 'Company Email',
                    requiredMark: true,
                    hint: 'yourname@company.com',
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: Icons.alternate_email,
                    enabled: !disabled,
                  ),
                  HrContactsEditor(
                    initial: _hrContacts,
                    minRows: _baseHrSlots,
                    max: _maxHrContacts,
                    enabled: !disabled,
                    showLimitNote: false,
                    addLabel: 'Add HR contact',
                    rowLabel: (i) => 'HR Contact ${i + 1}',
                    placeholder: (i) => 'hr${i + 1}@company.com',
                    onChanged: (list) => _hrContacts = list,
                  ),
                ],
              ),

              _section(
                'Supporting Documents',
                subtitle: 'Upload offer letter, salary slip, PF statement, Form 16, or relieving letter '
                    'to increase trust score',
                children: [
                  for (final slot in _experienceDocuments) _docRow(slot, disabled),
                ],
              ),

              _section('Work Description', children: [
                AppTextField(
                  controller: _description,
                  label: 'Key Responsibilities',
                  hint: 'Briefly describe your role and impact...',
                  maxLines: 5,
                  minLines: 4,
                  maxLength: 2000,
                  enabled: !disabled,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ]),

              AppButton(
                label: _submitting ? 'Saving...' : 'Save & Verify Employment',
                loading: _submitting,
                onPressed: _isValid ? _submit : null,
              ),
              if (!_isValid)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Company, role, joining date, exit date (or current job) and company email are required.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _positionCard(int index, bool disabled) {
    final p = _positions[index];
    return Container(
      key: ObjectKey(p),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TagChip('Role ${index + 1}', tone: Tone.brand),
              const Spacer(),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: disabled
                    ? null
                    : () {
                        final removed = _positions.removeAt(index);
                        setState(() {});
                        WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
                      },
                child: const Text('Remove'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          AppTextField(
            controller: p.title,
            label: 'Role / Designation',
            hint: 'e.g. Software Engineer',
            prefixIcon: Icons.work_outline,
            enabled: !disabled,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: p.yearlyPackage,
            label: 'Yearly Package (CTC)',
            hint: 'e.g. 900000',
            keyboardType: TextInputType.number,
            enabled: !disabled,
          ),
          const SizedBox(height: 12),
          AppDateField(
            label: 'From',
            value: p.fromDate,
            enabled: !disabled,
            onChanged: (v) => setState(() => p.fromDate = v),
          ),
          const SizedBox(height: 12),
          AppDateField(
            label: 'To',
            value: p.isCurrent ? null : p.toDate,
            enabled: !disabled && !p.isCurrent,
            onChanged: (v) => setState(() => p.toDate = v),
          ),
          CheckboxListTile(
            value: p.isCurrent,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('This is my current role'),
            onChanged: disabled
                ? null
                : (v) => setState(() {
                      p.isCurrent = v ?? false;
                      if (p.isCurrent) p.toDate = null;
                    }),
          ),
          AppTextField(
            controller: p.monthly,
            label: 'Monthly In-Hand',
            hint: 'e.g. 45000',
            prefixText: '₹ ',
            keyboardType: TextInputType.number,
            enabled: !disabled,
          ),
        ],
      ),
    );
  }

  Widget _docRow(_DocSlot slot, bool disabled) {
    final file = _documents[slot.id];
    final uploaded = file != null;
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
        side: const BorderSide(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: disabled ? null : () => _pickDoc(slot),
        leading: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(color: AppColors.brand50, borderRadius: BorderRadius.circular(10)),
          child: Icon(slot.icon, size: 20, color: AppColors.brand600),
        ),
        title: Text(slot.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(
          file != null ? '${file.name} · ${file.sizeLabel}' : 'Not uploaded',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: uploaded ? AppColors.success : AppColors.inkFaint,
            fontWeight: uploaded ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
        trailing: uploaded
            ? IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.close, size: 20),
                onPressed: disabled ? null : () => setState(() => _documents.remove(slot.id)),
              )
            : const Icon(Icons.add_circle_outline, color: AppColors.brand600),
      ),
    );
  }
}
