import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/json.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/widgets.dart';
import 'portal_providers.dart';

/// Bottom-sheet ports of the web team modals: SendAccessRequestModal,
/// RemoveAccessConfirmModal, AssignEmployeeModal and InviteEmployeeModal
/// (VerificationRequestModal lives in widgets_b). Each resolves `true` on success
/// (the caller then invalidates its providers, like the web `onSuccess`).

Future<bool> _showSheet(BuildContext context, Widget child) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => child,
  );
  return result ?? false;
}

/// Scrollable sheet body that stays above the keyboard.
class SheetFrame extends StatelessWidget {
  const SheetFrame({super.key, required this.title, this.subtitle, required this.children});

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.inkStrong)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: const TextStyle(fontSize: 13.5, color: AppColors.inkMuted, height: 1.4)),
            ],
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Cancel + primary button row used at the bottom of every sheet.
class SheetActions extends StatelessWidget {
  const SheetActions({
    super.key,
    required this.confirmLabel,
    required this.onConfirm,
    required this.busy,
    this.danger = false,
    this.cancelLabel = 'Cancel',
  });

  final String confirmLabel;
  final VoidCallback? onConfirm;
  final bool busy;
  final bool danger;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AppButton(
            label: cancelLabel,
            variant: AppButtonVariant.outline,
            onPressed: busy ? null : () => Navigator.of(context).pop(false),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AppButton(
            label: confirmLabel,
            variant: danger ? AppButtonVariant.danger : AppButtonVariant.primary,
            loading: busy,
            onPressed: onConfirm,
          ),
        ),
      ],
    );
  }
}

// ── Send access request ────────────────────────────────────────────────────

const _fallbackRequestTypes = [
  {'value': 'profile_access', 'label': 'Profile Access', 'description': 'View basic profile and employment history'},
  {
    'value': 'background_check',
    'label': 'Background Check',
    'description': 'Access vault documents for background verification',
  },
  {
    'value': 'verification_data',
    'label': 'Verification Data',
    'description': 'View trust score breakdown and verification status',
  },
  {
    'value': 'full_profile_access',
    'label': 'Get Full Profile Access',
    'description': 'Complete access to profile, documents, and verification data',
  },
];

Future<bool> showSendAccessRequestSheet(
  BuildContext context, {
  required String employeeId,
  required String employeeName,
  String defaultRequestType = 'full_profile_access',
}) =>
    _showSheet(
      context,
      _SendAccessRequestSheet(employeeId: employeeId, employeeName: employeeName, defaultRequestType: defaultRequestType),
    );

class _SendAccessRequestSheet extends ConsumerStatefulWidget {
  const _SendAccessRequestSheet({required this.employeeId, required this.employeeName, required this.defaultRequestType});

  final String employeeId;
  final String employeeName;
  final String defaultRequestType;

  @override
  ConsumerState<_SendAccessRequestSheet> createState() => _SendAccessRequestSheetState();
}

class _SendAccessRequestSheetState extends ConsumerState<_SendAccessRequestSheet> {
  late String _requestType = widget.defaultRequestType;
  final _message = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final message = _message.text.trim();
    try {
      await ref.read(enterpriseApiProvider).createAccessRequest({
        'employeeId': widget.employeeId,
        'requestType': _requestType,
        if (message.isNotEmpty) 'message': message,
      });
      showToast('Access request sent. Waiting for employee consent.', type: ToastType.success);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (e.status == 409) {
        showToast('Pending request already exists', type: ToastType.error);
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      showErrorToast(e, 'Failed to send request');
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      showErrorToast(e, 'Failed to send request');
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final typesAsync = ref.watch(accessRequestTypesProvider);
    final fetched = asMapList(typesAsync.valueOrNull);
    final options = fetched.isNotEmpty ? fetched : _fallbackRequestTypes.map(asMap).toList();
    final optionMap = <String, String>{
      for (final o in options)
        str(o['value']): '${str(o['label'])}${str(o['value']) == 'full_profile_access' ? ' ★ All access' : ''}',
    };
    // Web: fall back to the preferred/first type when the current one isn't offered.
    var current = _requestType;
    if (!optionMap.containsKey(current) && optionMap.isNotEmpty) {
      current = optionMap.containsKey(widget.defaultRequestType) ? widget.defaultRequestType : optionMap.keys.first;
    }
    final selected = options.where((o) => str(o['value']) == current).firstOrNull;
    final description = strOrNull(selected?['description']);

    return SheetFrame(
      title: 'Request Access',
      subtitle: "Request access to ${widget.employeeName}'s data.",
      children: [
        AppDropdown<String>(
          label: 'Request Type',
          options: optionMap,
          value: current,
          enabled: !_busy && !typesAsync.isLoading,
          onChanged: (v) {
            if (v != null) setState(() => _requestType = v);
          },
        ),
        const SizedBox(height: 8),
        if (current == 'full_profile_access')
          const Row(
            children: [
              StatusBadge('recommended', label: 'RECOMMENDED', tone: Tone.brand),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Unlocks profile, documents, and verification in one request.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.brand600),
                ),
              ),
            ],
          )
        else if (description != null)
          Text(description, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
        const SizedBox(height: 16),
        AppTextField(
          controller: _message,
          label: 'Message (optional)',
          hint: 'Add a note for the employee...',
          maxLines: 3,
          enabled: !_busy,
        ),
        const SizedBox(height: 20),
        SheetActions(
          confirmLabel: 'Send Request',
          busy: _busy,
          onConfirm: _busy || typesAsync.isLoading
              ? null
              : () {
                  _requestType = current;
                  _submit();
                },
        ),
      ],
    );
  }
}

// ── Remove access ──────────────────────────────────────────────────────────

Future<bool> showRemoveAccessSheet(BuildContext context, {required String employeeId, required String employeeName}) =>
    _showSheet(context, _RemoveAccessSheet(employeeId: employeeId, employeeName: employeeName));

class _RemoveAccessSheet extends ConsumerStatefulWidget {
  const _RemoveAccessSheet({required this.employeeId, required this.employeeName});

  final String employeeId;
  final String employeeName;

  @override
  ConsumerState<_RemoveAccessSheet> createState() => _RemoveAccessSheetState();
}

class _RemoveAccessSheetState extends ConsumerState<_RemoveAccessSheet> {
  bool _busy = false;

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await ref.read(enterpriseApiProvider).revokeEmployeeAccess(widget.employeeId, {});
      showToast('Access removed successfully', type: ToastType.success);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      showErrorToast(e, 'Failed to remove access');
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      title: 'Remove access to ${widget.employeeName}?',
      subtitle: 'Employee will need to approve again if you request access later.',
      children: [
        SheetActions(
          confirmLabel: 'Remove Access',
          danger: true,
          busy: _busy,
          onConfirm: _busy || widget.employeeId.isEmpty ? null : _submit,
        ),
      ],
    );
  }
}

// ── Assign department ──────────────────────────────────────────────────────

Future<bool> showAssignEmployeeSheet(
  BuildContext context, {
  required String employeeId,
  required String employeeName,
  String? department,
  String? designation,
}) =>
    _showSheet(
      context,
      _AssignEmployeeSheet(
        employeeId: employeeId,
        employeeName: employeeName,
        department: department ?? '',
        designation: designation ?? '',
      ),
    );

class _AssignEmployeeSheet extends ConsumerStatefulWidget {
  const _AssignEmployeeSheet({
    required this.employeeId,
    required this.employeeName,
    required this.department,
    required this.designation,
  });

  final String employeeId;
  final String employeeName;
  final String department;
  final String designation;

  @override
  ConsumerState<_AssignEmployeeSheet> createState() => _AssignEmployeeSheetState();
}

class _AssignEmployeeSheetState extends ConsumerState<_AssignEmployeeSheet> {
  late final _department = TextEditingController(text: widget.department);
  late final _designation = TextEditingController(text: widget.designation);
  bool _busy = false;

  @override
  void dispose() {
    _department.dispose();
    _designation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await ref.read(enterpriseApiProvider).assignEmployeeOnboarding(widget.employeeId, {
        'department': _department.text.trim(),
        'designation': _designation.text.trim(),
      });
      showToast('Employee assigned to team', type: ToastType.success);
      ref.invalidate(companyTeamProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      showErrorToast(e, 'Assignment failed');
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      title: 'Assign to Team',
      subtitle: '${widget.employeeName} — verified and ready for department assignment.',
      children: [
        AppTextField(
          controller: _department,
          label: 'Department',
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: _designation,
          label: 'Designation',
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 20),
        SheetActions(
          confirmLabel: 'Activate Employee',
          busy: _busy,
          onConfirm: _busy || _department.text.trim().isEmpty ? null : _submit,
        ),
      ],
    );
  }
}

// ── Invite employee ────────────────────────────────────────────────────────

Future<bool> showInviteEmployeeSheet(BuildContext context, {String defaultDepartment = ''}) =>
    _showSheet(context, _InviteEmployeeSheet(defaultDepartment: defaultDepartment));

class _InviteEmployeeSheet extends ConsumerStatefulWidget {
  const _InviteEmployeeSheet({required this.defaultDepartment});

  final String defaultDepartment;

  @override
  ConsumerState<_InviteEmployeeSheet> createState() => _InviteEmployeeSheetState();
}

class _InviteEmployeeSheetState extends ConsumerState<_InviteEmployeeSheet> {
  String _tab = 'search';
  late final _department = TextEditingController(text: widget.defaultDepartment);
  final _designation = TextEditingController();
  Map<String, String> _errors = {};

  // Search mode
  final _search = TextEditingController();
  Timer? _debounce;
  String _debounced = '';
  bool _searching = false;
  bool _searched = false;
  List<Map<String, dynamic>> _results = const [];
  Map<String, dynamic>? _selected;

  // Link mode
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  Map<String, dynamic>? _linkResult;

  bool _busy = false;

  /// Anything created here should refresh the team screens when the sheet closes.
  bool _changed = false;

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_department, _designation, _search, _name, _mobile, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _roleValid => _department.text.trim().isNotEmpty && _designation.text.trim().isNotEmpty;

  /// The backend resolves only complete identifiers — full email, PagerLook ID or 10-digit mobile.
  static bool _looksComplete(String q) {
    final digits = q.replaceAll(RegExp(r'\D'), '');
    return (q.contains('@') && q.contains('.')) || q.contains('-') || digits.length >= 10;
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(value));
  }

  Future<void> _runSearch(String raw) async {
    final q = raw;
    if (!mounted) return;
    setState(() {
      _debounced = q;
      _searched = false;
      _results = const [];
    });
    if (!_looksComplete(q) || _selected != null) return;
    setState(() => _searching = true);
    try {
      final data = asMap(await ref.read(enterpriseApiProvider).searchCompanyEmployees(q));
      final inner = data['data'] is Map ? asMap(data['data']) : data;
      final employees = asMapList(inner['employees']);
      if (!mounted || _debounced != q) return;
      setState(() {
        _results = employees;
        _searched = true;
      });
    } catch (e) {
      if (!mounted || _debounced != q) return;
      setState(() {
        _results = const [];
        _searched = true;
      });
    } finally {
      if (mounted && _debounced == q) setState(() => _searching = false);
    }
  }

  bool _validateRole() {
    final next = <String, String>{};
    if (_department.text.trim().isEmpty) next['department'] = 'Department is required';
    if (_designation.text.trim().isEmpty) next['designation'] = 'Designation is required';
    setState(() => _errors = next);
    return next.isEmpty;
  }

  void _handleInviteError(Object e) {
    if (e is ApiException && e.status == 409) {
      showToast(e.message.isNotEmpty ? e.message : 'Pending invitation already exists for this employee',
          type: ToastType.error);
      return;
    }
    showErrorToast(e, 'Failed to send invitation');
  }

  Map<String, dynamic> _unwrap(Object? res) {
    final map = asMap(res);
    return map['data'] is Map ? asMap(map['data']) : map;
  }

  Future<void> _sendToRegistered() async {
    final selected = _selected;
    if (selected == null || !_validateRole()) return;
    setState(() => _busy = true);
    final name = strOrNull(selected['name']) ?? 'Employee';
    try {
      final res = await ref.read(enterpriseApiProvider).inviteEmployee({
        'employeeName': name,
        'employeeUserId': selected['employeeId'],
        if (strOrNull(selected['veriworkId']) != null) 'employeePagerlookId': selected['veriworkId'],
        'department': _department.text.trim(),
        'designation': _designation.text.trim(),
      });
      final data = _unwrap(res);
      final notified = strOrNull(data['notifiedEmail']);
      showToast(
        notified != null
            ? "Invitation sent to $name at $notified. It's also waiting in their portal."
            : "Invitation sent to $name. They'll accept it from their portal.",
        type: ToastType.success,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _handleInviteError(e);
      if (mounted) setState(() => _busy = false);
    }
  }

  void _switchToLinkInvite() {
    final q = _search.text.trim();
    if (q.contains('@')) {
      if (_email.text.isEmpty) _email.text = q.toLowerCase();
    } else {
      final digits = q.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 10 && _mobile.text.isEmpty) _mobile.text = digits.substring(digits.length - 10);
    }
    setState(() {
      _errors = {};
      _tab = 'link';
    });
  }

  Future<void> _generateLink() async {
    final next = <String, String>{};
    if (_name.text.trim().isEmpty) next['employeeName'] = 'Employee name is required';
    if (_mobile.text.trim().isEmpty) {
      next['employeeMobile'] = 'Mobile number is required';
    } else if (_mobile.text.replaceAll(RegExp(r'\D'), '').length < 10) {
      next['employeeMobile'] = 'Enter a valid mobile number';
    }
    if (_department.text.trim().isEmpty) next['department'] = 'Department is required';
    if (_designation.text.trim().isEmpty) next['designation'] = 'Designation is required';
    final emailError = emailValidator(_email.text, required: false);
    if (emailError != null) next['employeeEmail'] = emailError;
    setState(() => _errors = next);
    if (next.isNotEmpty) return;

    setState(() => _busy = true);
    final email = _email.text.trim();
    try {
      final res = await ref.read(enterpriseApiProvider).inviteEmployee({
        'employeeName': _name.text.trim(),
        'employeeMobile': _mobile.text.trim(),
        if (email.isNotEmpty) 'employeeEmail': email,
        'department': _department.text.trim(),
        'designation': _designation.text.trim(),
      });
      final data = _unwrap(res);
      _changed = true;
      if (str(data['caseType']) == 'registered') {
        final notified = strOrNull(data['notifiedEmail']);
        showToast(
          notified != null
              ? 'This person is already on PagerLook — invitation sent to $notified.'
              : 'This person is already on PagerLook — invitation sent to their portal.',
          type: ToastType.success,
        );
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      if (email.isNotEmpty && asBool(data['emailSent']) && !asBool(data['emailMock'])) {
        showToast('Registration link emailed to $email', type: ToastType.success);
      } else {
        showToast('Invite link generated — copy and share it.', type: ToastType.success);
      }
      if (mounted) {
        setState(() {
          _linkResult = data;
          _busy = false;
        });
      }
    } catch (e) {
      _handleInviteError(e);
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _employeeSummary(Map<String, dynamic> emp, {Widget? trailing}) {
    final name = strOrNull(emp['name']) ?? 'Unnamed';
    final roleLine = [str(emp['role']), str(emp['company'])].where((s) => s.isNotEmpty).join(' · ');
    final idLine =
        [str(emp['veriworkId']), str(emp['maskedMobile']), str(emp['maskedEmail'])].where((s) => s.isNotEmpty).join(' · ');
    return Row(
      children: [
        AppAvatar(name: name, imageUrl: strOrNull(emp['photoUrl']), size: 38),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.inkStrong)),
              if (roleLine.isNotEmpty)
                Text(roleLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.inkBody)),
              if (idLine.isNotEmpty)
                Text(idLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _errorText(String? message) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(message, style: const TextStyle(fontSize: 12, color: AppColors.danger)),
        );

  Widget _roleFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: _department,
          label: 'Department',
          requiredMark: true,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
        ),
        _errorText(_errors['department']),
        const SizedBox(height: 14),
        AppTextField(
          controller: _designation,
          label: 'Designation',
          requiredMark: true,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
        ),
        _errorText(_errors['designation']),
      ],
    );
  }

  List<Widget> _searchTab() {
    final selected = _selected;
    if (selected != null) {
      return [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.brand50,
            borderRadius: BorderRadius.circular(AppRadii.control),
            border: Border.all(color: AppColors.brand100),
          ),
          child: _employeeSummary(
            selected,
            trailing: TextButton(
              onPressed: _busy ? null : () => setState(() => _selected = null),
              child: const Text('Change'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _roleFields(),
        const SizedBox(height: 12),
        Text(
          '${strOrNull(selected['name']) ?? 'They'} gets an email and an invitation in their PagerLook portal. '
          'They join your team once they accept.',
          style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
        ),
        const SizedBox(height: 20),
        SheetActions(
          confirmLabel: 'Send Invitation',
          busy: _busy,
          onConfirm: _busy || !_roleValid ? null : _sendToRegistered,
        ),
      ];
    }

    final typed = _search.text.trim();
    final complete = _looksComplete(_debounced);
    final searchedAndEmpty = complete && _searched && !_searching && _results.isEmpty;
    return [
      AppTextField(
        controller: _search,
        label: 'Search by PagerLook ID, mobile or email',
        hint: 'e.g. VW-IEDM-05 or 7740847114',
        prefixIcon: Icons.search,
        autofocus: true,
        onChanged: _onSearchChanged,
      ),
      if (typed.isNotEmpty && !_looksComplete(typed))
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Enter the full mobile number, complete PagerLook ID, or email — we match the exact person, '
            'never a partial name.',
            style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
          ),
        ),
      if (complete && _searching)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Searching…', style: TextStyle(fontSize: 12, color: AppColors.inkFaint)),
        ),
      if (searchedAndEmpty) ...[
        const SizedBox(height: 12),
        InfoBanner(
          tone: Tone.warning,
          title: 'No PagerLook account matches that',
          message: 'Send them a registration link instead — your company name is filled in for them, and they '
              'join your team automatically once they finish signing up.',
          action: AppButton(
            label: 'Send a registration link',
            variant: AppButtonVariant.secondary,
            compact: true,
            expand: false,
            onPressed: _switchToLinkInvite,
          ),
        ),
      ],
      if (_results.isNotEmpty) ...[
        const SizedBox(height: 10),
        ..._results.map((emp) {
          final already = asBool(emp['alreadyInvited']);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Opacity(
              opacity: already ? 0.6 : 1,
              child: AppCard(
                padding: const EdgeInsets.all(12),
                onTap: already ? null : () => setState(() => _selected = emp),
                child: _employeeSummary(
                  emp,
                  trailing: already ? const StatusBadge('invited', label: 'Already invited', tone: Tone.neutral) : null,
                ),
              ),
            ),
          );
        }),
      ],
    ];
  }

  List<Widget> _linkTab() {
    final result = _linkResult;
    final link = strOrNull(result?['registrationLink']);
    if (result != null && link != null) {
      final who = _name.text.trim().isEmpty ? 'the employee' : _name.text.trim();
      final dept = _department.text.trim();
      return [
        InfoBanner(
          tone: Tone.info,
          title: 'Invite link ready${asBool(result['emailMock']) ? ' (dev mode)' : ''}',
          message: 'Share this with $who. Your company name is already filled in on their signup, and they join'
              '${dept.isNotEmpty ? ' $dept' : ' your team'} automatically once setup is done.',
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.control),
            border: Border.all(color: AppColors.line),
          ),
          child: SelectableText(link, style: const TextStyle(fontSize: 12.5, color: AppColors.inkBody)),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Copy',
                icon: Icons.copy,
                variant: AppButtonVariant.secondary,
                onPressed: () => copyToClipboard(link, message: 'Invite link copied'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AppButton(
                label: 'Share',
                icon: Icons.ios_share,
                variant: AppButtonVariant.secondary,
                onPressed: () => Share.share(link),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Invite another',
                variant: AppButtonVariant.outline,
                onPressed: () => setState(() {
                  _linkResult = null;
                  _name.clear();
                  _mobile.clear();
                  _email.clear();
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppButton(label: 'Done', onPressed: () => Navigator.of(context).pop(true)),
            ),
          ],
        ),
      ];
    }

    final canSubmit = !_busy && _roleValid && _name.text.trim().isNotEmpty && _mobile.text.trim().isNotEmpty;
    return [
      AppTextField(
        controller: _name,
        label: 'Employee Name',
        requiredMark: true,
        enabled: !_busy,
        textCapitalization: TextCapitalization.words,
        onChanged: (_) => setState(() {}),
      ),
      _errorText(_errors['employeeName']),
      const SizedBox(height: 14),
      AppTextField(
        controller: _mobile,
        label: 'Employee Mobile',
        hint: '10-digit mobile number',
        requiredMark: true,
        enabled: !_busy,
        keyboardType: TextInputType.phone,
        onChanged: (_) => setState(() {}),
      ),
      _errorText(_errors['employeeMobile']),
      const SizedBox(height: 14),
      AppTextField(
        controller: _email,
        label: 'Employee Email',
        hint: "Optional — we'll also email the link",
        helper: 'Add an email to also send the link to their inbox',
        enabled: !_busy,
        keyboardType: TextInputType.emailAddress,
      ),
      _errorText(_errors['employeeEmail']),
      const SizedBox(height: 14),
      _roleFields(),
      const SizedBox(height: 12),
      const Text(
        'If this mobile or email already has a PagerLook account, we skip the link and send the invitation '
        'straight to their portal instead.',
        style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
      ),
      const SizedBox(height: 20),
      SheetActions(
        confirmLabel: 'Generate invite link',
        busy: _busy,
        onConfirm: canSubmit ? _generateLink : null,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, result) {
        // Swipe-dismiss after a link was generated still refreshes the team.
        if (didPop && result == null && _changed) {
          ref.invalidate(companyTeamProvider);
          ref.invalidate(companyPendingInvitationsProvider);
        }
      },
      child: SheetFrame(
        title: 'Invite Employee',
        subtitle: 'Search a registered employee to invite them directly, or generate a link to share with '
            'someone new.',
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'search', label: Text('Search on PagerLook')),
              ButtonSegment(value: 'link', label: Text('Invite by link')),
            ],
            selected: {_tab},
            showSelectedIcon: false,
            onSelectionChanged: _busy
                ? null
                : (s) => setState(() {
                      _tab = s.first;
                      _errors = {};
                    }),
          ),
          const SizedBox(height: 18),
          ...(_tab == 'search' ? _searchTab() : _linkTab()),
        ],
      ),
    );
  }
}
