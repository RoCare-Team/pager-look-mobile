import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import 'widgets_a/portal_providers.dart';
import 'widgets_a/team_utils.dart';

const _statusTabs = {'all': 'All', 'pending': 'Pending', 'approved': 'Approved', 'rejected': 'Rejected'};

/// Port of `pages/enterprise/AccessRequests.jsx`.
class AccessRequestsScreen extends ConsumerStatefulWidget {
  const AccessRequestsScreen({super.key, this.initialStatus = 'all'});

  final String initialStatus;

  @override
  ConsumerState<AccessRequestsScreen> createState() => _AccessRequestsScreenState();
}

class _AccessRequestsScreenState extends ConsumerState<AccessRequestsScreen> {
  late String _status = _normalizeTab(widget.initialStatus);
  int _page = 1;

  static String _normalizeTab(String status) {
    final s = status == 'accepted' ? 'approved' : status;
    return _statusTabs.containsKey(s) ? s : 'all';
  }

  AccessRequestsQuery get _query => (status: _status, page: _page);

  @override
  void didUpdateWidget(covariant AccessRequestsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialStatus != widget.initialStatus) {
      _status = _normalizeTab(widget.initialStatus);
      _page = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(companyAccessRequestsProvider(_query));

    return Scaffold(
      appBar: AppBar(title: const Text('Access Requests')),
      body: RefreshIndicator(
        onRefresh: () async {
          try {
            final _ = await ref.refresh(companyAccessRequestsProvider(_query).future);
          } catch (_) {
            // Rendered below.
          }
        },
        child: AsyncValueView<dynamic>(
          value: async,
          loadingLabel: 'Loading access requests...',
          onRetry: () => ref.invalidate(companyAccessRequestsProvider(_query)),
          data: (raw) {
            final data = asMap(raw);
            final summary = asMap(data['summary']);
            final all = asMapList(data['requests']);
            // The backend may return every request regardless of `status`;
            // filter here so the tabs always mean what they say.
            final requests = _status == 'all'
                ? all
                : all.where((r) {
                    final s = str(r['status']) == 'accepted' ? 'approved' : str(r['status']);
                    return s == _status;
                  }).toList();
            final pagination = data['pagination'] is Map ? asMap(data['pagination']) : null;
            final totalPages = asInt(pagination?['totalPages'], 1);

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                const PageIntro(
                  title: 'Access Requests',
                  subtitle: 'Track profile and verification access requests',
                ),
                StatGrid(
                  children: [
                    StatCard(
                      icon: Icons.send_outlined,
                      label: 'Total Requests Sent',
                      value: '${asInt(summary['total'])}',
                      tone: Tone.brand,
                    ),
                    StatCard(
                      icon: Icons.check_circle_outline,
                      label: 'Accepted',
                      value: '${asInt(summary['accepted'] ?? summary['approved'])}',
                      tone: Tone.success,
                    ),
                    StatCard(
                      icon: Icons.schedule,
                      label: 'Pending',
                      value: '${asInt(summary['pending'])}',
                      tone: Tone.warning,
                    ),
                    StatCard(
                      icon: Icons.cancel_outlined,
                      label: 'Rejected',
                      value: '${asInt(summary['rejected'])}',
                      tone: Tone.danger,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilterChipsBar(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  options: _statusTabs,
                  selected: _status,
                  onSelected: (s) => setState(() {
                    _status = s;
                    _page = 1;
                  }),
                ),
                const SizedBox(height: 8),
                if (requests.isEmpty)
                  AppCard(
                    child: EmptyState(
                      icon: Icons.key_outlined,
                      title: 'No access requests yet',
                      message: 'Send a request from Team Management to get started.',
                      action: TextButton(
                        onPressed: () => context.go('/company/team'),
                        child: const Text('Go to Team'),
                      ),
                    ),
                  )
                else
                  ...requests.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _AccessRequestCard(request: r),
                      )),
                if (pagination != null && totalPages > 1) ...[
                  const SizedBox(height: 12),
                  _Pager(
                    page: asInt(pagination['page'], _page),
                    totalPages: totalPages,
                    total: asInt(pagination['total']),
                    onPage: (p) => setState(() => _page = p),
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

class _AccessRequestCard extends StatelessWidget {
  const _AccessRequestCard({required this.request});

  final Map<String, dynamic> request;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = accessRequestStatusStyle(strOrNull(request['status']));
    final employeeId = strOrNull(request['employeeId']);
    final message = strOrNull(request['message']);
    return AppCard(
      onTap: employeeId == null ? null : () => context.push('/company/team/${Uri.encodeComponent(employeeId)}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      str(request['employeeName'] ?? request['name'], '—'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.inkStrong),
                    ),
                    const SizedBox(height: 2),
                    Text(formatRequestType(request['requestType']),
                        style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(strOrNull(request['status']), label: label.toUpperCase(), tone: tone),
            ],
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text('“$message”', style: const TextStyle(fontSize: 12.5, color: AppColors.inkBody)),
          ],
          const SizedBox(height: 10),
          Text(
            formatAccessDate(request['requestedAt'] ?? request['dateRequested'] ?? request['createdAt']),
            style: const TextStyle(fontSize: 12, color: AppColors.inkFaint),
          ),
        ],
      ),
    );
  }
}

/// Web `Pagination` — prev/next with the current page.
class _Pager extends StatelessWidget {
  const _Pager({required this.page, required this.totalPages, required this.total, required this.onPage});

  final int page;
  final int totalPages;
  final int total;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppButton(
          label: 'Prev',
          compact: true,
          expand: false,
          variant: AppButtonVariant.outline,
          onPressed: page <= 1 ? null : () => onPage(page - 1),
        ),
        Expanded(
          child: Text(
            'Page $page of $totalPages${total > 0 ? ' · $total total' : ''}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
          ),
        ),
        AppButton(
          label: 'Next',
          compact: true,
          expand: false,
          variant: AppButtonVariant.outline,
          onPressed: page >= totalPages ? null : () => onPage(page + 1),
        ),
      ],
    );
  }
}
