import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/widgets.dart';
import 'admin_employees_screen.dart' show adminEmployeesProvider;
import 'admin_utils.dart';
import 'widgets/delete_employee_dialog.dart';
import 'widgets/image_viewer.dart';

/// Web: `fetchAdminEmployee` → `normalizeAdminEmployee` (null → not found).
final adminEmployeeProvider = FutureProvider.autoDispose.family<AdminEmployee?, String>((ref, id) async {
  final data = await ref.watch(adminApiProvider).fetchEmployee(id);
  return AdminEmployee.fromJson(data);
});

/// Port of `pages/admin/AdminEmployeeDetail.jsx`.
class AdminEmployeeDetailScreen extends ConsumerStatefulWidget {
  const AdminEmployeeDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<AdminEmployeeDetailScreen> createState() => _AdminEmployeeDetailScreenState();
}

class _AdminEmployeeDetailScreenState extends ConsumerState<AdminEmployeeDetailScreen> {
  bool _statusBusy = false;
  bool _deleteBusy = false;

  Future<void> _toggleActive(AdminEmployee employee) async {
    final next = !employee.isActive;
    if (!next) {
      final ok = await showConfirmDialog(
        context,
        title: 'Deactivate this employee?',
        message: 'They are signed out and blocked from logging in. Their verification records are kept, '
            'and you can restore them at any time.',
        confirmLabel: 'Deactivate',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _statusBusy = true);
    try {
      await ref.read(adminApiProvider).setEmployeeStatus(widget.id, next);
      ref.invalidate(adminEmployeeProvider(widget.id));
      ref.invalidate(adminEmployeesProvider);
      showToast(
        next ? 'Employee reactivated' : 'Employee deactivated — they can no longer log in',
        type: next ? ToastType.success : ToastType.info,
      );
    } catch (e) {
      showErrorToast(e, 'Could not update the employee');
    } finally {
      if (mounted) setState(() => _statusBusy = false);
    }
  }

  Future<void> _delete(AdminEmployee employee) async {
    final deleted = await showDeleteEmployeeDialog(
      context,
      name: employee.name,
      veriworkId: employee.veriworkId,
      onConfirm: (confirm) async {
        if (mounted) setState(() => _deleteBusy = true);
        try {
          await ref.read(adminApiProvider).deleteEmployee(widget.id, confirm);
          ref.invalidate(adminEmployeesProvider);
          showToast('Employee permanently deleted', type: ToastType.success);
          return true;
        } catch (e) {
          showErrorToast(e, 'Could not delete the employee');
          return false;
        } finally {
          if (mounted) setState(() => _deleteBusy = false);
        }
      },
    );
    // The record this screen renders no longer exists — leave before it refetches a 404.
    if (deleted && mounted) context.go('/admin/employees');
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(adminEmployeeProvider(widget.id));

    return Scaffold(
      appBar: AppBar(title: const Text('Employee')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(adminEmployeeProvider(widget.id).future),
        child: value.when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          loading: () => const LoadingView(label: 'Loading employee...'),
          error: (e, _) => ErrorView(
            error: e,
            onRetry: () => ref.invalidate(adminEmployeeProvider(widget.id)),
          ),
          data: (employee) => employee == null
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    EmptyState(
                      title: 'Employee not found',
                      icon: Icons.person_off_outlined,
                      action: AppButton(
                        label: 'Back to employees',
                        expand: false,
                        variant: AppButtonVariant.outline,
                        onPressed: () => context.go('/admin/employees'),
                      ),
                    ),
                  ],
                )
              : _buildBody(employee),
        ),
      ),
    );
  }

  Widget _buildBody(AdminEmployee employee) {
    final busy = _statusBusy || _deleteBusy;
    final photo = mediaUrl(employee.photoUrl);
    final kyc = employee.aadhaarKyc;
    final education = employee.education;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: photo == null ? null : () => showImageViewer(context, photo, title: employee.name),
                    child: AppAvatar(name: employee.name, imageUrl: employee.photoUrl, size: 72),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(employee.name, style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                          '${employee.role} · ${employee.company}',
                          style: const TextStyle(fontSize: 13.5, color: AppColors.inkMuted),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          employee.veriworkId,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColors.inkFaint),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  StatusBadge('score', tone: Tone.brand, label: 'Score ${employee.employeeScore}'),
                  if (!employee.isActive) const StatusBadge('deactivated', tone: Tone.neutral, label: 'Deactivated'),
                  if (employee.isVerified) const StatusBadge('verified', tone: Tone.success, label: 'Verified'),
                  if (employee.profileSetupComplete)
                    const StatusBadge('complete', tone: Tone.info, label: 'Profile Complete'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          title: 'Account actions',
          color: AppColors.dangerBg,
          borderColor: AppColors.danger.withValues(alpha: 0.15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                employee.isActive
                    ? 'Deactivating blocks login and ends their sessions immediately, but keeps every verification record companies rely on. Deleting erases the account and all of it — permanently.'
                    : 'This account is deactivated and cannot log in. Restore it to give access back, or delete it permanently to erase everything the platform holds.',
                style: const TextStyle(fontSize: 13.5, color: AppColors.inkBody, height: 1.4),
              ),
              const SizedBox(height: 12),
              AppButton(
                label: _statusBusy
                    ? 'Saving…'
                    : (employee.isActive ? 'Deactivate account' : 'Restore account'),
                variant: AppButtonVariant.secondary,
                loading: _statusBusy,
                onPressed: busy ? null : () => _toggleActive(employee),
              ),
              const SizedBox(height: 8),
              AppButton(
                label: 'Delete permanently',
                variant: AppButtonVariant.danger,
                icon: Icons.delete_outline,
                onPressed: busy ? null : () => _delete(employee),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          title: 'Contact & Identity',
          child: Column(
            children: [
              InfoRow(label: 'Email', value: employee.email),
              InfoRow(label: 'Phone', value: employee.phone),
              InfoRow(label: 'Date of Birth', value: employee.dateOfBirth),
              InfoRow(label: 'Gender', value: employee.gender),
              InfoRow(label: 'City', value: employee.currentCity),
              InfoRow(label: 'Auth Provider', value: employee.authProvider),
              InfoRow(label: 'Joined', value: formatDate(employee.createdAt)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          title: 'Work & Verification',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InfoRow(label: 'Current Role', value: employee.role),
              InfoRow(label: 'Current Company', value: employee.company),
              InfoRow(label: 'Linked Companies', value: employee.linkedCompanyLabel),
              InfoRow(label: 'Total Experience', value: employee.totalExperience),
              InfoRow(label: 'Aadhaar Verified', value: employee.aadhaarVerified ? 'Yes' : 'No'),
              InfoRow(label: 'Biometric Verified', value: employee.biometricVerified ? 'Yes' : 'No'),
              InfoRow(label: 'DigiLocker Used', value: employee.digilockerUsed ? 'Yes' : 'No'),
              InfoRow(label: 'Endorsements', value: '${employee.endorsements}'),
              if (kyc != null) ...[
                const SizedBox(height: 12),
                _AadhaarKycBlock(kyc: kyc),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          title: 'Address',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AddressBlock(label: 'Current Address', value: employee.currentAddress),
              const SizedBox(height: 10),
              _AddressBlock(label: 'Permanent Address', value: employee.permanentAddress),
            ],
          ),
        ),
        if (education != null) ...[
          const SizedBox(height: 12),
          AppCard(
            title: 'Education',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _EducationBlock(
                  title: 'Class 10th',
                  rows: [
                    ('Board', pick(education, 'class10.board')),
                    ('School', pick(education, 'class10.school')),
                    ('Year', pick(education, 'class10.passingYear')),
                    ('Percentage', pick(education, 'class10.percentage')),
                  ],
                ),
                const SizedBox(height: 10),
                _EducationBlock(
                  title: 'Class 12th',
                  rows: [
                    ('Board', pick(education, 'class12.board')),
                    ('School', pick(education, 'class12.school')),
                    ('Stream', pick(education, 'class12.stream')),
                    ('Year', pick(education, 'class12.passingYear')),
                    ('Percentage', pick(education, 'class12.percentage')),
                  ],
                ),
                const SizedBox(height: 10),
                _EducationBlock(
                  title: 'Graduation',
                  rows: [
                    ('Degree', pick(education, 'graduation.degree')),
                    ('College', pick(education, 'graduation.college')),
                    ('University', pick(education, 'graduation.university')),
                    ('Year', pick(education, 'graduation.passingYear')),
                    ('Percentage', pick(education, 'graduation.percentage')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _AadhaarKycBlock extends StatelessWidget {
  const _AadhaarKycBlock({required this.kyc});

  final Map<String, dynamic> kyc;

  @override
  Widget build(BuildContext context) {
    final id = idOf(kyc);
    final reason = strOrNull(kyc['rejectionReason']);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Aadhaar KYC',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.inkStrong)),
              ),
              if (id.isNotEmpty)
                TextButton(
                  onPressed: () => context.push('/admin/aadhaar-requests/$id'),
                  child: const Text('Review →'),
                ),
            ],
          ),
          InfoRow(
            label: 'Status',
            valueWidget: Align(alignment: Alignment.centerRight, child: StatusBadge(str(kyc['status']))),
          ),
          InfoRow(
            label: 'Number',
            valueWidget: Text(
              str(kyc['aadhaarMasked'], '—'),
              textAlign: TextAlign.right,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: AppColors.inkStrong),
            ),
          ),
          InfoRow(label: 'Submitted', value: formatDate(kyc['submittedAt'])),
          InfoRow(
            label: 'Face match',
            value: asBool(kyc['faceMatchMatched'])
                ? 'Matched (${str(kyc['faceMatchSimilarity'], '0')}%)'
                : 'Not matched',
          ),
          if (reason != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(reason, style: const TextStyle(fontSize: 12, color: AppColors.danger)),
            ),
        ],
      ),
    );
  }
}

class _AddressBlock extends StatelessWidget {
  const _AddressBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(AppRadii.control)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 6),
          Text(value.isEmpty ? '—' : value, style: const TextStyle(fontSize: 13.5, color: AppColors.inkStrong)),
        ],
      ),
    );
  }
}

class _EducationBlock extends StatelessWidget {
  const _EducationBlock({required this.title, required this.rows});

  final String title;
  final List<(String, Object?)> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.inkStrong)),
          const SizedBox(height: 4),
          for (final (label, value) in rows) InfoRow(label: label, value: str(value)),
        ],
      ),
    );
  }
}
