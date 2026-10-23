import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import 'employee_portal_utils.dart';

/// `GET /employee/invitations` → `{ invitations }` or a bare list.
final employeeInvitationsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return listFrom(await ref.watch(employeeApiProvider).fetchInvitations(), const ['invitations']);
});

String invitationIdOf(Map<String, dynamic> inv) => str(inv['invitationId'] ?? inv['_id'] ?? inv['id']);

/// Port of `EmployeeInvitations.jsx`.
class EmployeeInvitationsScreen extends ConsumerStatefulWidget {
  const EmployeeInvitationsScreen({super.key});

  @override
  ConsumerState<EmployeeInvitationsScreen> createState() => _EmployeeInvitationsScreenState();
}

class _EmployeeInvitationsScreenState extends ConsumerState<EmployeeInvitationsScreen> {
  String? _busyId;

  Future<void> _accept(Map<String, dynamic> inv) async {
    final id = invitationIdOf(inv);
    final company = str(inv['companyName'], 'the company');
    final ok = await showConfirmDialog(
      context,
      title: 'Join $company?',
      message: '$company will add you to their workforce and can see your verified PagerLook profile.',
      confirmLabel: 'Accept & Join',
    );
    if (!ok || !mounted) return;
    setState(() => _busyId = id);
    try {
      final result = asMap(await ref.read(employeeApiProvider).acceptInvitation(id));
      showToast('You joined ${str(result['companyName'], company)}', type: ToastType.success);
      ref.invalidate(employeeInvitationsProvider);
      try {
        await ref.read(authProvider).refreshEmployeeProfile();
      } catch (_) {
        // The invitation was accepted; the profile refreshes on next load.
      }
      if (mounted) context.go('/employee/score');
    } catch (e) {
      showErrorToast(e, 'Failed to accept invitation');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _reject(Map<String, dynamic> inv) async {
    final id = invitationIdOf(inv);
    final ok = await showConfirmDialog(
      context,
      title: 'Decline invitation?',
      message: 'You will not be added to ${str(inv['companyName'], 'this company')}.',
      confirmLabel: 'Decline',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busyId = id);
    try {
      await ref.read(employeeApiProvider).rejectInvitation(id);
      showToast('Invitation declined', type: ToastType.success);
      ref.invalidate(employeeInvitationsProvider);
    } catch (e) {
      showErrorToast(e, 'Failed to decline invitation');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invAsync = ref.watch(employeeInvitationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Invitations')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(employeeInvitationsProvider.future),
        child: AsyncValueView<List<Map<String, dynamic>>>(
          value: invAsync,
          loadingLabel: 'Loading invitations...',
          onRetry: () => ref.invalidate(employeeInvitationsProvider),
          data: (invitations) {
            final pending = invitations.where((i) => str(i['status']) == 'pending').toList();
            final past = invitations.where((i) => str(i['status']) != 'pending').toList();

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                const PageIntro(
                  title: 'Company invitations',
                  subtitle: 'Companies inviting you to join their workforce',
                ),
                if (invitations.isEmpty)
                  const EmptyState(
                    icon: Icons.mail_outline,
                    title: 'No invitations yet',
                    message: 'When a company invites you, it will appear here.',
                  ),
                if (pending.isNotEmpty) ...[
                  SectionHeader(
                    pending.length > 1 ? 'Pending (${pending.length})' : 'Pending',
                    padding: const EdgeInsets.only(bottom: 10),
                  ),
                  for (final inv in pending)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InvitationCard(
                        invitation: inv,
                        busy: _busyId != null,
                        loading: _busyId == invitationIdOf(inv),
                        onAccept: () => _accept(inv),
                        onReject: () => _reject(inv),
                      ),
                    ),
                ],
                if (past.isNotEmpty) ...[
                  const SectionHeader('Earlier'),
                  for (final inv in past)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InvitationCard(invitation: inv, busy: _busyId != null),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Invitation card (web `InvitationCard`).
class InvitationCard extends StatelessWidget {
  const InvitationCard({
    super.key,
    required this.invitation,
    required this.busy,
    this.loading = false,
    this.onAccept,
    this.onReject,
  });

  final Map<String, dynamic> invitation;
  final bool busy;
  final bool loading;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final inv = invitation;
    final status = str(inv['status']);
    final style = invitationStatusStyle(status);
    final canAct = status == 'pending' && onAccept != null && onReject != null;
    final company = str(inv['companyName'], 'A company');
    final meta = [str(inv['companyIndustry']), str(inv['companyCity'])].where((s) => s.isNotEmpty).join(' · ');
    final designation = strOrNull(inv['designation']);
    final department = strOrNull(inv['department']);

    final String pastNote;
    if (status == 'accepted') {
      pastNote = 'You joined $company${inv['respondedAt'] != null ? ' on ${formatDate(inv['respondedAt'])}' : ''}.';
    } else if (status == 'rejected') {
      pastNote = 'You declined this invitation.';
    } else {
      pastNote = 'This invitation is no longer active.';
    }

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppColors.canvas,
              border: Border(bottom: BorderSide(color: AppColors.hairline)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: AppColors.brand50,
                  ),
                  child: const Icon(Icons.apartment, color: AppColors.brand600),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        company,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: AppColors.inkStrong),
                      ),
                      if (meta.isNotEmpty)
                        Text(meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusBadge(status, label: style.label, tone: style.tone),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.infoBg,
                    borderRadius: BorderRadius.circular(AppRadii.control),
                  ),
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(fontSize: 13.5, color: AppColors.inkBody, height: 1.4),
                      children: [
                        TextSpan(text: company, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const TextSpan(text: ' wants to add you to their workforce'),
                        if (designation != null) ...[
                          const TextSpan(text: ' as '),
                          TextSpan(text: designation, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                        if (department != null) ...[
                          const TextSpan(text: ' in '),
                          TextSpan(text: department, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (designation != null) TagChip(designation),
                    if (department != null) TagChip(department),
                    if (inv['invitedAt'] != null) TagChip('Invited ${formatDate(inv['invitedAt'])}'),
                  ],
                ),
                const SizedBox(height: 14),
                if (canAct)
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: 'Decline',
                          variant: AppButtonVariant.outline,
                          onPressed: busy ? null : onReject,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppButton(
                          label: 'Accept & Join',
                          loading: loading,
                          onPressed: busy ? null : onAccept,
                        ),
                      ),
                    ],
                  )
                else
                  Text(pastNote, style: const TextStyle(fontSize: 12, color: AppColors.inkFaint)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
