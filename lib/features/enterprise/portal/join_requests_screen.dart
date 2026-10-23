import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/company_permissions.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import 'widgets_b/score_and_pagination.dart';

final _joinRequestsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data = await ref.watch(enterpriseApiProvider).fetchJoinRequests();
  return listFrom(data, const ['requests', 'items', 'joinRequests']);
});

/// Port of `pages/enterprise/JoinRequests.jsx`.
class JoinRequestsScreen extends ConsumerStatefulWidget {
  const JoinRequestsScreen({super.key});

  @override
  ConsumerState<JoinRequestsScreen> createState() => _JoinRequestsScreenState();
}

class _JoinRequestsScreenState extends ConsumerState<JoinRequestsScreen> {
  String _tab = 'new';
  String _query = '';

  /// `"<id>:<status>"` while an approve/reject is in flight.
  String? _busy;

  Future<void> _refresh() async {
    try {
      final _ = await ref.refresh(_joinRequestsProvider.future);
    } catch (_) {}
  }

  Future<void> _update(Map<String, dynamic> request, String status) async {
    final id = idOf(request);
    setState(() => _busy = '$id:$status');
    try {
      await ref.read(enterpriseApiProvider).updateJoinRequest(id, status);
      showToast(status == 'approved' ? 'Join request approved' : 'Join request rejected', type: ToastType.success);
      ref.invalidate(_joinRequestsProvider);
    } catch (e) {
      showErrorToast(e, 'Failed to update join request');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_joinRequestsProvider);
    final perms = ref.watch(companyPermissionsProvider).valueOrNull ?? const CompanyPermissions();
    final canManage = !perms.ready || perms.can('join_requests', 'manage');

    return Scaffold(
      appBar: AppBar(title: const Text('Join Requests')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: AsyncValueView<List<Map<String, dynamic>>>(
          value: async,
          loadingLabel: 'Loading join requests...',
          onRetry: () => ref.invalidate(_joinRequestsProvider),
          data: (requests) {
            final pending = requests.where((r) => str(r['status']) == 'pending').toList();
            final history =
                requests.where((r) => const ['approved', 'rejected'].contains(str(r['status']))).toList();
            final q = _query.toLowerCase();
            final isNew = _tab == 'new';
            final filtered = (isNew ? pending : history)
                .where((r) => str(r['name']).toLowerCase().contains(q))
                .toList();

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${pending.length} pending verification',
                        style: const TextStyle(color: AppColors.inkMuted),
                      ),
                    ),
                    const StatusBadge('live', label: 'LIVE', tone: Tone.success),
                  ],
                ),
                FilterChipsBar(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  options: {
                    'new': pending.isEmpty ? 'New' : 'New (${pending.length})',
                    'history': history.isEmpty ? 'History' : 'History (${history.length})',
                  },
                  selected: _tab,
                  onSelected: (v) => setState(() => _tab = v),
                ),
                SearchField(
                  hint: 'Search candidates...',
                  initialValue: _query,
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 14),
                if (filtered.isEmpty)
                  isNew
                      ? const EmptyState(
                          icon: Icons.person_add_alt,
                          title: 'No pending join requests',
                          message: 'All candidates have been reviewed.',
                        )
                      : const EmptyState(icon: Icons.history, title: 'No history yet.')
                else
                  for (final req in filtered)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _CandidateCard(
                        request: req,
                        busyStatus: _busy != null && _busy!.startsWith('${idOf(req)}:')
                            ? _busy!.substring(idOf(req).length + 1)
                            : null,
                        disabled: _busy != null,
                        onApprove: isNew && canManage ? () => _update(req, 'approved') : null,
                        onReject: isNew && canManage ? () => _update(req, 'rejected') : null,
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

/// Web `components/enterprise/CandidateRequestCard.jsx`.
class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.request,
    required this.busyStatus,
    required this.disabled,
    this.onApprove,
    this.onReject,
  });

  final Map<String, dynamic> request;
  final String? busyStatus;
  final bool disabled;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final name = str(r['name']);
    final documents = asList(r['documents']).map((d) => str(d)).where((d) => d.isNotEmpty).toList();
    final status = str(r['status']);

    Widget fact(String label, String value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: AppColors.inkFaint)),
              const SizedBox(height: 2),
              Text(
                value.isEmpty ? '—' : value,
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.inkStrong),
              ),
            ],
          ),
        );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAvatar(name: name, imageUrl: strOrNull(r['photoUrl']), size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.inkStrong),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [str(r['role']), str(r['department'])].where((s) => s.isNotEmpty).join(' • '),
                      style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
                    ),
                    if (status != 'pending' && status.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      StatusBadge(status),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ScoreChip(score: asNum(r['employeeScore'] ?? r['trust']) ?? 0),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(AppRadii.control)),
            child: Row(
              children: [
                fact('Joining Date', str(r['joiningDate'])),
                fact('Salary Band', str(r['salaryBand'])),
              ],
            ),
          ),
          if (documents.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Documents', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.inkFaint)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: documents
                  .map(
                    (d) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Text(d, style: const TextStyle(fontSize: 12, color: AppColors.inkBody)),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (onApprove != null && onReject != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Reject',
                    variant: AppButtonVariant.outline,
                    loading: busyStatus == 'rejected',
                    onPressed: disabled ? null : onReject,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    label: 'Approve',
                    loading: busyStatus == 'approved',
                    onPressed: disabled ? null : onApprove,
                  ),
                ),
              ],
            ),
          ],
          if (status == 'pending' && asDate(r['createdAt']) != null) ...[
            const SizedBox(height: 10),
            Text(
              'Requested ${timeAgo(r['createdAt'])}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
            ),
          ],
        ],
      ),
    );
  }
}
