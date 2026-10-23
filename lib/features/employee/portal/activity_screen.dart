import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import 'employee_access_consent_screen.dart';
import 'employee_invitations_screen.dart';
import 'employee_portal_utils.dart';

/// `GET /employee/activity?filter=` — `{ pendingRequests, recentUpdates, items }`.
final employeeActivityProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, filter) async {
  return asMap(await ref.watch(employeeApiProvider).fetchActivity(filter));
});

const Map<String, String> _tabs = {'all': 'All', 'requests': 'Requests', 'updates': 'Updates'};

/// Activity tab — port of `Activity.jsx`: pending invitations, access
/// requests and activity requests, plus recent updates.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  String _tab = 'all';
  String? _busyKey;

  Future<void> _refresh() async {
    ref.invalidate(employeeActivityProvider(_tab));
    ref.invalidate(employeeInvitationsProvider);
    ref.invalidate(employeeAccessRequestsProvider);
    await Future.wait([
      ref.read(employeeActivityProvider(_tab).future),
      ref.read(employeeInvitationsProvider.future),
      ref.read(employeeAccessRequestsProvider.future),
    ]);
  }

  Future<void> _run(String key, Future<void> Function() action) async {
    if (_busyKey != null || !mounted) return;
    setState(() => _busyKey = key);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<bool> _confirmReject(String title, String message) => showConfirmDialog(
        context,
        title: title,
        message: message,
        confirmLabel: 'Reject',
        destructive: true,
      );

  void _acceptInvitation(String id) => _run('inv-$id', () async {
        try {
          await ref.read(employeeApiProvider).acceptInvitation(id);
          showToast('Invitation accepted', type: ToastType.success);
          ref.invalidate(employeeInvitationsProvider);
          try {
            await ref.read(authProvider).refreshEmployeeProfile();
          } catch (_) {
            // Accepted — the profile catches up on next load.
          }
        } catch (e) {
          showErrorToast(e, 'Failed to accept');
        }
      });

  Future<void> _rejectInvitation(String id, String company) async {
    if (!await _confirmReject('Reject invitation?', 'You will not be added to $company.')) return;
    await _run('inv-$id', () async {
      try {
        await ref.read(employeeApiProvider).rejectInvitation(id);
        showToast('Invitation rejected', type: ToastType.success);
        ref.invalidate(employeeInvitationsProvider);
      } catch (e) {
        showErrorToast(e, 'Failed to reject');
      }
    });
  }

  void _approveAccess(String id) => _run('acc-$id', () async {
        try {
          await ref.read(employeeApiProvider).approveAccessRequest(id);
          showToast('Access approved', type: ToastType.success);
          ref.invalidate(employeeAccessRequestsProvider);
        } catch (e) {
          showErrorToast(e, 'Failed to approve');
        }
      });

  Future<void> _rejectAccess(String id, String company) async {
    if (!await _confirmReject('Reject access request?', '$company will not get access to your profile.')) return;
    await _run('acc-$id', () async {
      try {
        await ref.read(employeeApiProvider).rejectAccessRequest(id);
        showToast('Access rejected', type: ToastType.success);
        ref.invalidate(employeeAccessRequestsProvider);
      } catch (e) {
        showErrorToast(e, 'Failed to reject');
      }
    });
  }

  void _updateActivity(String id, String status) => _run('act-$id', () async {
        try {
          await ref.read(employeeApiProvider).updateActivity(id, status);
          ref.invalidate(employeeActivityProvider);
          // Activity approvals sync to the linked access request server-side.
          ref.invalidate(employeeAccessRequestsProvider);
        } catch (e) {
          showErrorToast(e, 'Failed to update request');
        }
      });

  @override
  Widget build(BuildContext context) {
    final activityAsync = ref.watch(employeeActivityProvider(_tab));
    final invAsync = ref.watch(employeeInvitationsProvider);
    final accessAsync = ref.watch(employeeAccessRequestsProvider);

    final loading = (activityAsync.isLoading && !activityAsync.hasValue) ||
        (invAsync.isLoading && !invAsync.hasValue) ||
        (accessAsync.isLoading && !accessAsync.hasValue);

    Widget content;
    if (loading) {
      content = const LoadingView(label: 'Loading activity...');
    } else {
      final error = activityAsync.error ?? invAsync.error ?? accessAsync.error;
      final activity = activityAsync.valueOrNull ?? const <String, dynamic>{};
      final pendingInvitations =
          (invAsync.valueOrNull ?? const <Map<String, dynamic>>[]).where((i) => str(i['status']) == 'pending').toList();
      final pendingAccess = (accessAsync.valueOrNull ?? const <Map<String, dynamic>>[])
          .where((r) => str(r['status']) == 'pending')
          .toList();
      final requests =
          asMapList(activity['pendingRequests']).where((i) => str(i['status']) == 'pending').toList();
      final updates = asMapList(activity['recentUpdates']);
      final hasPending = pendingInvitations.isNotEmpty || pendingAccess.isNotEmpty || requests.isNotEmpty;
      final busy = _busyKey != null;

      content = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (error != null) ...[
            const SizedBox(height: 8),
            InfoBanner(tone: Tone.danger, message: errorMessage(error)),
          ],
          if (_tab == 'all' || _tab == 'requests') ...[
            SectionHeader(
              'Pending Requests',
              action: PopupMenuButton<String>(
                tooltip: 'See all',
                icon: const Icon(Icons.more_horiz, color: AppColors.inkMuted),
                onSelected: (path) => context.push(path),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: '/employee/invitations', child: Text('All invitations')),
                  PopupMenuItem(value: '/employee/access-requests', child: Text('All access requests')),
                ],
              ),
            ),
            for (final inv in pendingInvitations)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _RequestCard(
                  eyebrow: 'Company Invitation',
                  eyebrowColor: AppColors.brand600,
                  title: str(inv['companyName'], 'A company'),
                  lines: [
                    [str(inv['department']), str(inv['designation'])].where((s) => s.isNotEmpty).join(' · '),
                  ],
                  badge: invitationStatusStyle(str(inv['status'])),
                  rejectLabel: 'Reject',
                  approveLabel: 'Accept',
                  busy: busy,
                  loading: _busyKey == 'inv-${invitationIdOf(inv)}',
                  onReject: () => _rejectInvitation(invitationIdOf(inv), str(inv['companyName'], 'this company')),
                  onApprove: () => _acceptInvitation(invitationIdOf(inv)),
                ),
              ),
            for (final req in pendingAccess)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _RequestCard(
                  eyebrow: 'Access Request',
                  eyebrowColor: AppColors.info,
                  title: str(req['companyName'], 'A company'),
                  lines: [
                    formatRequestType(strOrNull(req['requestType'])),
                    formatAccessDate(req['requestedAt'] ?? req['createdAt']),
                  ],
                  badge: accessRequestStatusStyle(str(req['status'])),
                  rejectLabel: 'Reject',
                  approveLabel: 'Approve',
                  busy: busy,
                  loading: _busyKey == 'acc-${idOf(req)}',
                  onReject: () => _rejectAccess(idOf(req), str(req['companyName'], 'This company')),
                  onApprove: () => _approveAccess(idOf(req)),
                ),
              ),
            for (final item in requests)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ActivityCard(
                  item: item,
                  busy: busy,
                  loading: _busyKey == 'act-${idOf(item)}',
                  onApprove: () => _updateActivity(idOf(item), 'approved'),
                  onDeny: () => _updateActivity(idOf(item), 'denied'),
                ),
              ),
            if (!hasPending)
              const AppCard(
                child: Text(
                  'No pending requests',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.inkMuted),
                ),
              ),
          ],
          if (_tab == 'all' || _tab == 'updates') ...[
            const SectionHeader('Recent Updates'),
            if (updates.isEmpty)
              const AppCard(
                child: Text(
                  'No recent updates',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.inkMuted),
                ),
              )
            else
              for (final item in updates)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ActivityCard(item: item, busy: busy),
                ),
          ],
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: Column(
        children: [
          FilterChipsBar(
            options: _tabs,
            selected: _tab,
            onSelected: (v) => setState(() => _tab = v),
          ),
          Expanded(child: RefreshIndicator(onRefresh: _refresh, child: content)),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.eyebrow,
    required this.eyebrowColor,
    required this.title,
    required this.lines,
    required this.badge,
    required this.rejectLabel,
    required this.approveLabel,
    required this.busy,
    required this.loading,
    required this.onReject,
    required this.onApprove,
  });

  final String eyebrow;
  final Color eyebrowColor;
  final String title;
  final List<String> lines;
  final StatusStyle badge;
  final String rejectLabel;
  final String approveLabel;
  final bool busy;
  final bool loading;
  final VoidCallback onReject;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    final visible = lines.where((l) => l.isNotEmpty && l != '—').toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow(eyebrow, color: eyebrowColor),
                    const SizedBox(height: 4),
                    Text(title,
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.inkStrong)),
                    for (var i = 0; i < visible.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          visible[i],
                          style: TextStyle(
                            fontSize: i == 0 ? 13.5 : 12,
                            color: i == 0 ? AppColors.inkBody : AppColors.inkFaint,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(null, label: badge.label, tone: badge.tone),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: rejectLabel,
                  variant: AppButtonVariant.outline,
                  onPressed: busy ? null : onReject,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: AppButton(label: approveLabel, loading: loading, onPressed: busy ? null : onApprove)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Web `ActivityRequestCard.jsx`.
class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.item, required this.busy, this.loading = false, this.onApprove, this.onDeny});

  final Map<String, dynamic> item;
  final bool busy;
  final bool loading;
  final VoidCallback? onApprove;
  final VoidCallback? onDeny;

  @override
  Widget build(BuildContext context) {
    final company = strOrNull(item['company']);
    final title = company ?? str(item['title']);
    final message = strOrNull(item['message']);
    final avatarSource = title.length > 2 ? title.substring(0, 2) : title;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.hairline, shape: BoxShape.circle),
                child: Text(
                  avatarSource,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkMuted),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkStrong),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(formatDate(item['createdAt']),
                            style: const TextStyle(fontSize: 11.5, color: AppColors.inkFaint)),
                      ],
                    ),
                    if (message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(message, style: const TextStyle(fontSize: 13.5, color: AppColors.inkBody)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (onApprove != null && onDeny != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AppButton(label: 'Deny', variant: AppButtonVariant.outline, onPressed: busy ? null : onDeny),
                ),
                const SizedBox(width: 10),
                Expanded(child: AppButton(label: 'Approve', loading: loading, onPressed: busy ? null : onApprove)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
