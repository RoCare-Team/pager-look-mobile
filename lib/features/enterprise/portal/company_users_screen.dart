import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/company_permissions.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import 'widgets_b/company_user_sheets.dart';
import 'widgets_b/sheet_body.dart';

final _companyUsersProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return asMap(await ref.watch(enterpriseApiProvider).fetchCompanyUsers());
});

final _rolesProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return asMap(await ref.watch(enterpriseApiProvider).fetchRoles());
});

const _presetTones = {
  'owner': Tone.brand,
  'admin': Tone.info,
  'hr_manager': Tone.success,
  'recruiter': Tone.warning,
  'viewer': Tone.neutral,
};

Widget _roleBadge(String roleKey, String label, {bool isCustom = false}) => StatusBadge(
      roleKey,
      label: (label.isEmpty ? roleKey : label).toUpperCase(),
      tone: isCustom ? Tone.brand : (_presetTones[roleKey] ?? Tone.neutral),
    );

/// Port of `pages/enterprise/CompanyUsers.jsx` — staff logins, invites and roles.
class CompanyUsersScreen extends ConsumerStatefulWidget {
  const CompanyUsersScreen({super.key});

  @override
  ConsumerState<CompanyUsersScreen> createState() => _CompanyUsersScreenState();
}

class _CompanyUsersScreenState extends ConsumerState<CompanyUsersScreen> {
  /// `"<kind>:<id>"` while a row action is in flight.
  String? _busy;

  void _invalidate() {
    ref.invalidate(_companyUsersProvider);
    ref.invalidate(_rolesProvider);
    ref.invalidate(companyPermissionsProvider);
  }

  Future<void> _refresh() async {
    try {
      await Future.wait([ref.refresh(_companyUsersProvider.future), ref.refresh(_rolesProvider.future)]);
    } catch (_) {}
  }

  Future<void> _run(String key, Future<void> Function() action) async {
    setState(() => _busy = key);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _changeRole(Map<String, dynamic> user, String value, List<String> presetKeys) =>
      _run('role:${idOf(user)}', () async {
        try {
          await ref.read(enterpriseApiProvider).updateCompanyUserRole(idOf(user), roleBody(value, presetKeys));
          showToast('Role updated', type: ToastType.success);
          _invalidate();
        } catch (e) {
          showErrorToast(e, 'Failed to update role');
        }
      });

  Future<void> _resetPassword(Map<String, dynamic> user) async {
    final email = str(user['email']);
    final entered = await showTextInputDialog(
      context,
      title: 'Reset password',
      message: 'Set a new password for $email (min 8 characters)',
      label: 'New password',
      confirmLabel: 'Set password',
      maxLines: 1,
      keyboardType: TextInputType.visiblePassword,
    );
    if (entered == null) return;
    // Trimmed: the password is read off the screen and handed over.
    final password = entered.trim();
    if (password.length < 8) {
      showToast('Password must be at least 8 characters', type: ToastType.error);
      return;
    }
    await _run('password:${idOf(user)}', () async {
      try {
        final data = asMap(await ref.read(enterpriseApiProvider).resetCompanyUserPassword(idOf(user), password));
        showToast(str(data['message'], 'Password updated'), type: ToastType.success);
        if (mounted) await _showNewPassword(email, password);
      } catch (e) {
        showErrorToast(e, 'Failed to reset password');
      }
    });
  }

  Future<void> _showNewPassword(String email, String password) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Password updated', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New password for $email:'),
            const SizedBox(height: 8),
            SelectableText(password, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => copyToClipboard('Email: $email\nPassword: $password'),
            child: const Text('Copy'),
          ),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Done')),
        ],
      ),
    );
  }

  Future<void> _remove(Map<String, dynamic> user) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Remove user?',
      message: '${str(user['email'])} will lose access to your company workspace.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok) return;
    await _run('remove:${idOf(user)}', () async {
      try {
        await ref.read(enterpriseApiProvider).removeCompanyUser(idOf(user));
        showToast('User removed', type: ToastType.success);
        _invalidate();
      } catch (e) {
        showErrorToast(e, 'Failed to remove user');
      }
    });
  }

  Future<void> _revoke(Map<String, dynamic> invite) => _run('revoke:${idOf(invite)}', () async {
        try {
          await ref.read(enterpriseApiProvider).revokeCompanyUserInvite(idOf(invite));
          showToast('Invite revoked', type: ToastType.success);
          _invalidate();
        } catch (e) {
          showErrorToast(e, 'Failed to revoke invite');
        }
      });

  Future<void> _deleteRole(Map<String, dynamic> role) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete role?',
      message: 'Delete the "${str(role['name'])}" role?',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    await _run('deleteRole:${idOf(role)}', () async {
      try {
        await ref.read(enterpriseApiProvider).deleteCompanyRole(idOf(role));
        showToast('Role deleted', type: ToastType.success);
        _invalidate();
      } catch (e) {
        showErrorToast(e, 'Failed to delete role');
      }
    });
  }

  Future<void> _openRoleBuilder(List<Map<String, dynamic>> modules, [Map<String, dynamic>? role]) async {
    final saved = await showAppSheet<bool>(context, builder: (_) => RoleBuilderSheet(modules: modules, role: role));
    if (saved == true) _invalidate();
  }

  Future<void> _openAddUser(List<RoleOption> roleOptions, List<String> presetKeys) {
    return showAppSheet<void>(
      context,
      builder: (_) => AddCompanyUserSheet(roleOptions: roleOptions, presetKeys: presetKeys, onChanged: _invalidate),
    );
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(_companyUsersProvider);
    final rolesAsync = ref.watch(_rolesProvider);
    final perms = ref.watch(companyPermissionsProvider).valueOrNull ?? const CompanyPermissions();
    // Web: `can('company_users', 'manage')` — power-granting, so hidden until known.
    final canManage = perms.can('company_users', 'manage');

    return Scaffold(
      appBar: AppBar(title: const Text('Company Users')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: AsyncValueView<Map<String, dynamic>>(
          value: usersAsync,
          loadingLabel: 'Loading company users...',
          onRetry: _invalidate,
          data: (payload) {
            final rolesPayload = rolesAsync.valueOrNull ?? const <String, dynamic>{};
            final users = asMapList(payload['users']);
            final invites = asMapList(payload['pendingInvites']);
            final assignablePresets = asList(payload['assignableRoles']).map((e) => str(e)).toList();
            final modules = asMapList(rolesPayload['modules']);
            final presetRoles = asMapList(rolesPayload['presetRoles']);
            final customRoles = asMapList(rolesPayload['customRoles']);
            final presetKeys = presetRoles.map((r) => str(r['key'])).toList();

            final roleOptions = <RoleOption>[
              for (final r in presetRoles.where((r) => assignablePresets.contains(str(r['key']))))
                RoleOption(value: str(r['key']), label: str(r['label']), description: str(r['description'])),
              for (final r in customRoles)
                RoleOption(value: idOf(r), label: str(r['name']), description: str(r['description']), isCustom: true),
            ];
            final busy = _busy != null;

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                const Text(
                  'Create roles, decide what each can access, and give your staff a login.',
                  style: TextStyle(color: AppColors.inkMuted, height: 1.45),
                ),
                if (canManage) ...[
                  const SizedBox(height: 14),
                  SheetButtonRow(children: [
                    AppButton(
                      label: 'Create role',
                      variant: AppButtonVariant.outline,
                      onPressed: rolesAsync.hasValue ? () => _openRoleBuilder(modules) : null,
                    ),
                    AppButton(
                      label: 'Add member',
                      icon: Icons.add,
                      onPressed: () => _openAddUser(roleOptions, presetKeys),
                    ),
                  ]),
                ],

                // Members
                const SectionHeader('Members'),
                if (users.isEmpty)
                  const EmptyState(icon: Icons.people_outline, title: 'No company users yet')
                else
                  for (final u in users)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MemberCard(
                        user: u,
                        canManage: canManage,
                        busy: busy,
                        busyKey: _busy,
                        roleOptions: roleOptions,
                        onRoleChanged: (v) => _changeRole(u, v, presetKeys),
                        onResetPassword: () => _resetPassword(u),
                        onRemove: () => _remove(u),
                      ),
                    ),

                // Pending invites
                if (invites.isNotEmpty) ...[
                  const SectionHeader('Pending invites'),
                  for (final inv in invites)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppCard(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    str(inv['email']),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkStrong),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Invited ${formatDate(inv['invitedAt'])} · expires ${formatDate(inv['expiresAt'])}',
                                    style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                                  ),
                                  const SizedBox(height: 6),
                                  _roleBadge(str(inv['roleKey']), str(inv['roleLabel'])),
                                ],
                              ),
                            ),
                            if (canManage)
                              AppButton(
                                label: 'Revoke',
                                variant: AppButtonVariant.outline,
                                compact: true,
                                expand: false,
                                loading: _busy == 'revoke:${idOf(inv)}',
                                onPressed: busy ? null : () => _revoke(inv),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],

                // Custom roles
                const SectionHeader('Your roles', subtitle: 'Roles you created, with exactly the access you picked.'),
                if (rolesAsync.hasError && !rolesAsync.hasValue)
                  const InfoBanner(tone: Tone.danger, message: 'Could not load roles. Pull to refresh.')
                else if (customRoles.isEmpty)
                  const EmptyState(
                    icon: Icons.shield_outlined,
                    title: 'No custom roles yet',
                    message: 'Create one to grant a very specific set of access.',
                  )
                else
                  for (final role in customRoles)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _roleBadge(idOf(role), str(role['name']), isCustom: true),
                                  ),
                                ),
                                if (canManage) ...[
                                  TextButton(
                                    onPressed: busy ? null : () => _openRoleBuilder(modules, role),
                                    child: const Text('Edit'),
                                  ),
                                  TextButton(
                                    style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                                    onPressed: busy ? null : () => _deleteRole(role),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ],
                            ),
                            if (str(role['description']).isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  str(role['description']),
                                  style: const TextStyle(fontSize: 12.5, color: AppColors.inkBody),
                                ),
                              ),
                            _PermissionSummary(permissions: asMap(role['permissions']), modules: modules),
                          ],
                        ),
                      ),
                    ),

                // Built-in roles
                SectionHeader(
                  'Built-in roles',
                  subtitle: perms.roleLabel.isEmpty
                      ? 'Ready-made presets.'
                      : 'Ready-made presets. Your role: ${perms.roleLabel}',
                ),
                for (final role in presetRoles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _roleBadge(str(role['key']), str(role['label'])),
                          if (str(role['description']).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                str(role['description']),
                                style: const TextStyle(fontSize: 12.5, color: AppColors.inkBody),
                              ),
                            ),
                          _PermissionSummary(permissions: asMap(role['permissions']), modules: modules),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.user,
    required this.canManage,
    required this.busy,
    required this.busyKey,
    required this.roleOptions,
    required this.onRoleChanged,
    required this.onResetPassword,
    required this.onRemove,
  });

  final Map<String, dynamic> user;
  final bool canManage;
  final bool busy;
  final String? busyKey;
  final List<RoleOption> roleOptions;
  final ValueChanged<String> onRoleChanged;
  final VoidCallback onResetPassword;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final id = idOf(user);
    final email = str(user['email']);
    final isYou = asBool(user['isYou']);
    final isOwner = asBool(user['isOwner']);
    final roleKey = str(user['roleKey']);
    final canEditRole = canManage && !isYou && !isOwner;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppAvatar(name: email, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: email),
                        if (isYou)
                          const TextSpan(
                            text: ' (you)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.inkFaint),
                          ),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkStrong),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Added ${strOrNull(user['createdAt']) == null ? '—' : formatDate(user['createdAt'])}',
                      style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
              if (!canEditRole) ...[
                const SizedBox(width: 8),
                _roleBadge(roleKey, str(user['roleLabel']), isCustom: asBool(user['isCustomRole'])),
              ],
            ],
          ),
          if (canEditRole) ...[
            const SizedBox(height: 12),
            AppDropdown<String>(
              options: {for (final r in roleOptions) r.value: r.label},
              value: roleKey.isEmpty ? null : roleKey,
              hint: str(user['roleLabel'], 'Select role'),
              enabled: !busy,
              onChanged: (v) {
                if (v != null && v != roleKey) onRoleChanged(v);
              },
            ),
          ],
          if (canManage && !isYou) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppButton(
                  label: 'Reset password',
                  icon: Icons.lock_reset,
                  variant: AppButtonVariant.outline,
                  compact: true,
                  expand: false,
                  loading: busyKey == 'password:$id',
                  onPressed: busy ? null : onResetPassword,
                ),
                if (!isOwner)
                  AppButton(
                    label: 'Remove',
                    icon: Icons.person_remove_outlined,
                    variant: AppButtonVariant.ghost,
                    compact: true,
                    expand: false,
                    loading: busyKey == 'remove:$id',
                    onPressed: busy ? null : onRemove,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Granted modules as small chips (web `PermissionSummary`).
class _PermissionSummary extends StatelessWidget {
  const _PermissionSummary({required this.permissions, required this.modules});

  final Map<String, dynamic> permissions;
  final List<Map<String, dynamic>> modules;

  @override
  Widget build(BuildContext context) {
    final granted = modules.where((m) {
      final level = str(permissions[str(m['id'])]);
      return level.isNotEmpty && level != 'none';
    }).toList();
    if (granted.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('No access granted yet.', style: TextStyle(fontSize: 12, color: AppColors.inkFaint)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: granted.map((m) {
          final manage = str(permissions[str(m['id'])]) == 'manage';
          final label = str(m['label'], str(m['id']));
          final tone = manage ? Tone.brand : Tone.neutral;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(6)),
            child: Text(
              manage ? label : '$label · view',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: tone.fg),
            ),
          );
        }).toList(),
      ),
    );
  }
}
