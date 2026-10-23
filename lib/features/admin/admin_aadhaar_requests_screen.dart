import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/widgets.dart';
import 'admin_utils.dart';

/// Manual Aadhaar KYC review queue.
final adminAadhaarRequestsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, AdminListQuery>((ref, query) async {
  final data = await ref.watch(adminApiProvider).fetchAadhaarRequests(status: query.status, q: query.q);
  return listFrom(data, const ['requests', 'items']);
});

const _tabs = {
  'pending': 'Pending',
  'approved': 'Approved',
  'rejected': 'Rejected',
  'all': 'All',
};

/// Port of `pages/admin/AdminAadhaarRequests.jsx`.
class AdminAadhaarRequestsScreen extends ConsumerStatefulWidget {
  const AdminAadhaarRequestsScreen({super.key});

  @override
  ConsumerState<AdminAadhaarRequestsScreen> createState() => _AdminAadhaarRequestsScreenState();
}

class _AdminAadhaarRequestsScreenState extends ConsumerState<AdminAadhaarRequestsScreen> {
  String _status = 'pending';
  String _search = '';

  AdminListQuery get _key => (status: _status, q: _search);

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(adminAadhaarRequestsProvider(_key));

    return Scaffold(
      appBar: AppBar(title: const Text('Aadhaar verification')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SearchField(
              hint: 'Search name, email, PagerLook ID...',
              onChanged: (q) => setState(() => _search = q),
            ),
          ),
          FilterChipsBar(
            options: _tabs,
            selected: _status,
            onSelected: (key) => setState(() => _status = key),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(adminAadhaarRequestsProvider(_key).future),
              child: value.when(
                skipLoadingOnRefresh: true,
                skipLoadingOnReload: true,
                loading: () => const LoadingView(label: 'Loading submissions...'),
                error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.invalidate(adminAadhaarRequestsProvider(_key)),
                ),
                data: (requests) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Check the typed details against the uploaded card, then approve or reject.',
                        style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted),
                      ),
                    ),
                    if (requests.isEmpty)
                      EmptyState(
                        title: _status == 'all' ? 'No Aadhaar submissions.' : 'No $_status Aadhaar submissions.',
                        icon: Icons.fingerprint,
                      )
                    else
                      for (final request in requests) ...[
                        _RequestCard(request: request),
                        const SizedBox(height: 12),
                      ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request});

  final Map<String, dynamic> request;

  @override
  Widget build(BuildContext context) {
    final id = idOf(request);
    final employee = request['employee'] is Map ? asMap(request['employee']) : null;
    final contact = strOrNull(employee?['email']) ?? str(employee?['phone']);
    final nameDiffers = employee != null && !asBool(employee['profileNameMatches']);

    void open() => context.push('/admin/aadhaar-requests/$id');

    return AppCard(
      onTap: id.isEmpty ? null : open,
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
                      strOrNull(employee?['name']) ?? 'Unknown',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.inkStrong),
                    ),
                    if (contact.isNotEmpty)
                      Text(
                        contact,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(str(request['status'])),
            ],
          ),
          const SizedBox(height: 8),
          InfoRow(
            label: 'Name on card',
            valueWidget: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  str(request['nameOnAadhaar'], '—'),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.inkStrong),
                ),
                if (nameDiffers)
                  const Text(
                    'Differs from profile name',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.warning),
                  ),
              ],
            ),
          ),
          InfoRow(
            label: 'Aadhaar',
            valueWidget: Text(
              str(request['aadhaarMasked'], '—'),
              textAlign: TextAlign.right,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: AppColors.inkStrong),
            ),
          ),
          InfoRow(label: 'Submitted', value: formatDate(request['submittedAt'])),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: id.isEmpty ? null : open, child: const Text('Review →')),
          ),
        ],
      ),
    );
  }
}
