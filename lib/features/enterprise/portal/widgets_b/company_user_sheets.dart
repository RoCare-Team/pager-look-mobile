import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/json.dart';
import '../../../../core/widgets/widgets.dart';
import 'sheet_body.dart';

/// One entry of the role dropdown: a preset the actor may assign, or a custom role.
class RoleOption {
  const RoleOption({required this.value, required this.label, this.description = '', this.isCustom = false});

  /// Preset key (`hr_manager`) or custom role id.
  final String value;
  final String label;
  final String description;
  final bool isCustom;
}

/// Preset → `{ companyRole }`, custom → `{ companyRoleId }` (web `roleBody`).
Map<String, dynamic> roleBody(String value, List<String> presetKeys) =>
    presetKeys.contains(value) ? {'companyRole': value} : {'companyRoleId': value};

// ─────────────────────────────────────────────────────────────────────────────
// AddCompanyUserModal
// ─────────────────────────────────────────────────────────────────────────────

/// Create a staff login directly, or email an invite. [onChanged] fires after
/// the account/invite exists (the sheet stays open to show credentials).
class AddCompanyUserSheet extends ConsumerStatefulWidget {
  const AddCompanyUserSheet({
    super.key,
    required this.roleOptions,
    required this.presetKeys,
    required this.onChanged,
  });

  final List<RoleOption> roleOptions;
  final List<String> presetKeys;
  final VoidCallback onChanged;

  @override
  ConsumerState<AddCompanyUserSheet> createState() => _AddCompanyUserSheetState();
}

class _AddCompanyUserSheetState extends ConsumerState<AddCompanyUserSheet> {
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  String _mode = 'direct';
  late String _roleValue = widget.roleOptions.isEmpty ? '' : widget.roleOptions.first.value;
  String _error = '';
  bool _busy = false;
  Map<String, String>? _created;
  Map<String, dynamic>? _invite;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = '');
    if (_roleValue.isEmpty) {
      setState(() => _error = 'Select a role');
      return;
    }
    final email = _email.text.trim();
    // Trimmed on purpose: this password is read off the screen and handed over.
    final password = _password.text.trim();
    final api = ref.read(enterpriseApiProvider);

    if (_mode == 'direct') {
      if (password.length < 8) {
        setState(() => _error = 'Password must be at least 8 characters');
        return;
      }
      setState(() => _busy = true);
      try {
        final data = asMap(await api.createCompanyUser({
          'email': email,
          'password': password,
          ...roleBody(_roleValue, widget.presetKeys),
        }));
        if (!mounted) return;
        setState(() {
          _created = {'email': email, 'password': password, 'roleLabel': str(data['roleLabel'])};
          _busy = false;
        });
        showToast('Account created', type: ToastType.success);
        widget.onChanged();
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = errorMessage(e, 'Could not create the account');
            _busy = false;
          });
        }
      }
    } else {
      setState(() => _busy = true);
      try {
        final data = asMap(await api.inviteCompanyUser({
          'email': email,
          'name': _name.text.trim(),
          ...roleBody(_roleValue, widget.presetKeys),
        }));
        if (!mounted) return;
        setState(() {
          _invite = data;
          _busy = false;
        });
        final sent = asBool(data['emailSent']);
        showToast(str(data['message'], 'Invite sent'), type: sent ? ToastType.success : ToastType.info);
        widget.onChanged();
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = errorMessage(e, 'Could not send the invite');
            _busy = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final created = _created;
    final invite = _invite;

    if (created != null) {
      return SheetBody(
        title: 'Add team member',
        actions: [
          SheetButtonRow(children: [
            AppButton(
              label: 'Copy credentials',
              variant: AppButtonVariant.secondary,
              onPressed: () =>
                  copyToClipboard('Email: ${created['email']}\nPassword: ${created['password']}', message: 'Copied!'),
            ),
            AppButton(label: 'Done', onPressed: () => Navigator.of(context).pop()),
          ]),
        ],
        children: [
          const InfoBanner(
            tone: Tone.success,
            title: 'Account ready',
            message: 'Share these credentials. They can sign in at the employer login right away.',
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              children: [
                InfoRow(label: 'Email', value: created['email']),
                InfoRow(
                  label: 'Password',
                  valueWidget: SelectableText(
                    created['password'] ?? '',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600),
                  ),
                ),
                InfoRow(label: 'Role', value: created['roleLabel']),
              ],
            ),
          ),
        ],
      );
    }

    if (invite != null) {
      final link = str(invite['inviteLink']);
      final sent = asBool(invite['emailSent']);
      return SheetBody(
        title: 'Add team member',
        actions: [AppButton(label: 'Done', onPressed: () => Navigator.of(context).pop())],
        children: [
          InfoBanner(
            tone: Tone.info,
            title: 'Invite created for ${str(invite['email'], _email.text.trim())}',
            message: sent
                ? 'We emailed them a link to set their password.'
                : 'Email not sent — share this link so they can set their password.',
          ),
          if (link.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(AppRadii.control),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(link, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  ),
                  TextButton(onPressed: () => copyToClipboard(link, message: 'Copied!'), child: const Text('Copy')),
                ],
              ),
            ),
          ],
        ],
      );
    }

    RoleOption? selected;
    for (final r in widget.roleOptions) {
      if (r.value == _roleValue) selected = r;
    }

    return SheetBody(
      title: 'Add team member',
      actions: [
        SheetButtonRow(children: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.outline,
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
          ),
          AppButton(
            label: _busy ? 'Working…' : (_mode == 'direct' ? 'Create account' : 'Send invite'),
            loading: _busy,
            onPressed: _busy || _email.text.trim().isEmpty ? null : _submit,
          ),
        ]),
      ],
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'direct', label: Text('Set password')),
            ButtonSegment(value: 'invite', label: Text('Email invite')),
          ],
          selected: {_mode},
          showSelectedIcon: false,
          onSelectionChanged: _busy
              ? null
              : (s) => setState(() {
                    _mode = s.first;
                    _error = '';
                  }),
        ),
        const SizedBox(height: 8),
        Text(
          _mode == 'direct'
              ? 'You set the password and hand it over — works without any email setup.'
              : 'They get a link and choose their own password. Needs SMTP configured.',
          style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _email,
          label: 'Work Email',
          requiredMark: true,
          hint: 'name@yourcompany.com',
          helper: 'This is their login ID',
          keyboardType: TextInputType.emailAddress,
          enabled: !_busy,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        if (_mode == 'invite')
          AppTextField(controller: _name, label: 'Name', hint: 'Optional', enabled: !_busy)
        else
          AppTextField(
            controller: _password,
            label: 'Password',
            requiredMark: true,
            hint: 'At least 8 characters',
            helper: 'Visible on purpose — this is what you hand over',
            keyboardType: TextInputType.visiblePassword,
            enabled: !_busy,
          ),
        const SizedBox(height: 14),
        AppDropdown<String>(
          label: 'Role',
          options: {
            for (final r in widget.roleOptions) r.value: r.isCustom ? '${r.label} (custom)' : r.label,
          },
          value: _roleValue.isEmpty ? null : _roleValue,
          enabled: !_busy,
          onChanged: (v) => setState(() => _roleValue = v ?? ''),
        ),
        if ((selected?.description ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(selected!.description, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
          ),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error, style: const TextStyle(fontSize: 12.5, color: AppColors.danger, fontWeight: FontWeight.w500)),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RoleBuilderModal
// ─────────────────────────────────────────────────────────────────────────────

const _levels = {'none': 'No access', 'view': 'View only', 'manage': 'Manage'};

/// Create or edit a custom role. Pops `true` on success.
class RoleBuilderSheet extends ConsumerStatefulWidget {
  const RoleBuilderSheet({super.key, required this.modules, this.role});

  /// `[{ id, label }]` from `GET /company/roles`.
  final List<Map<String, dynamic>> modules;

  /// Present = edit mode.
  final Map<String, dynamic>? role;

  @override
  ConsumerState<RoleBuilderSheet> createState() => _RoleBuilderSheetState();
}

class _RoleBuilderSheetState extends ConsumerState<RoleBuilderSheet> {
  late final _name = TextEditingController(text: str(widget.role?['name']));
  late final _description = TextEditingController(text: str(widget.role?['description']));
  late final Map<String, String> _permissions = {
    for (final m in widget.modules)
      str(m['id']): str(asMap(widget.role?['permissions'])[str(m['id'])], 'none'),
  };
  bool _saving = false;

  bool get _isEdit => widget.role != null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final body = {
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'permissions': Map<String, String>.from(_permissions),
    };
    final api = ref.read(enterpriseApiProvider);
    try {
      if (_isEdit) {
        await api.updateCompanyRole(idOf(widget.role), body);
      } else {
        await api.createCompanyRole(body);
      }
      showToast(_isEdit ? 'Role updated' : 'Role created', type: ToastType.success);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      showErrorToast(e, 'Could not save the role');
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final granted = _permissions.values.where((l) => l != 'none').length;
    return SheetBody(
      title: _isEdit ? 'Edit role' : 'Create a role',
      subtitle: 'Name the role, then choose exactly what it can do. Anything set to “No access” '
          'won’t even appear in their menu.',
      actions: [
        SheetButtonRow(children: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.outline,
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
          ),
          AppButton(
            label: _saving ? 'Saving…' : (_isEdit ? 'Save changes' : 'Create role'),
            loading: _saving,
            onPressed: _saving || _name.text.trim().length < 2 ? null : _submit,
          ),
        ]),
      ],
      children: [
        AppTextField(
          controller: _name,
          label: 'Role name',
          requiredMark: true,
          hint: 'e.g. HR Executive',
          enabled: !_saving,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        AppTextField(controller: _description, label: 'Description', hint: 'Optional', enabled: !_saving),
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(
              child: Text('Permissions', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkStrong)),
            ),
            Text(
              '$granted of ${widget.modules.length} modules granted',
              style: const TextStyle(fontSize: 12, color: AppColors.inkFaint),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final m in widget.modules)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  str(m['label'], str(m['id'])),
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.inkBody),
                ),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: [
                    for (final e in _levels.entries)
                      ButtonSegment<String>(value: e.key, label: Text(e.value, style: const TextStyle(fontSize: 12))),
                  ],
                  selected: {_permissions[str(m['id'])] ?? 'none'},
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  onSelectionChanged: _saving
                      ? null
                      : (s) => setState(() => _permissions[str(m['id'])] = s.first),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
