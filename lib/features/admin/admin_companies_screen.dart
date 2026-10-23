import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import 'admin_utils.dart';

/// Companies for a status tab (`all` → no filter), normalised like the web's
/// `fetchAdminCompanies`.
final adminCompaniesProvider =
    FutureProvider.autoDispose.family<List<AdminCompanyListItem>, String>((ref, status) async {
  final data = await ref.watch(adminApiProvider).fetchCompanies(status == 'all' ? null : status);
  return normalizeCompanyList(data);
});

const _tabs = {
  'submitted': 'Pending',
  'approved': 'Approved',
  'rejected': 'Rejected',
  'all': 'All',
};

class _TabConfig {
  const _TabConfig(this.title, this.subtitle, this.empty);
  final String title;
  final String subtitle;
  final String empty;
}

const _tabConfig = {
  'submitted': _TabConfig('Pending Review', 'Companies awaiting admin approval', 'No companies pending review'),
  'approved': _TabConfig('Approved Companies', 'Companies with dashboard access', 'No approved companies yet'),
  'rejected': _TabConfig('Rejected Applications', 'Companies that were not approved', 'No rejected applications'),
  'all': _TabConfig('All Companies', 'Every registered enterprise application', 'No companies found'),
};

/// Port of `pages/admin/AdminCompanies.jsx`. The status tab lives in the URL
/// (`/admin/companies?status=approved`), as the web's tab links do.
class AdminCompaniesScreen extends ConsumerWidget {
  const AdminCompaniesScreen({super.key, this.initialStatus = 'submitted'});

  final String initialStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = initialStatus.isEmpty ? 'all' : initialStatus;
    final config = _tabConfig[status] ?? _tabConfig['all']!;
    final value = ref.watch(adminCompaniesProvider(status));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Companies'),
        actions: [
          IconButton(
            tooltip: 'Refresh list',
            icon: value.isLoading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: value.isLoading ? null : () => ref.invalidate(adminCompaniesProvider(status)),
          ),
        ],
      ),
      body: Column(
        children: [
          FilterChipsBar(
            options: _tabs,
            selected: status,
            onSelected: (key) => context.go(key == 'submitted' ? '/admin/companies' : '/admin/companies?status=$key'),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(adminCompaniesProvider(status).future),
              child: value.when(
                skipLoadingOnRefresh: true,
                skipLoadingOnReload: true,
                loading: () => const LoadingView(label: 'Loading companies...'),
                error: (e, _) => ErrorView(
                  error: e,
                  title: 'Could not load companies',
                  onRetry: () => ref.invalidate(adminCompaniesProvider(status)),
                ),
                data: (list) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    PageIntro(title: config.title, subtitle: config.subtitle),
                    if (list.isEmpty && status == 'submitted') ...[
                      const InfoBanner(
                        tone: Tone.warning,
                        message:
                            'No pending companies. Enterprise must complete onboarding and click Submit for Review.',
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (list.isEmpty)
                      EmptyState(title: config.empty, icon: Icons.business_outlined)
                    else
                      for (final item in list) ...[
                        _CompanyCard(item: item),
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

class _CompanyCard extends StatelessWidget {
  const _CompanyCard({required this.item});

  final AdminCompanyListItem item;

  @override
  Widget build(BuildContext context) {
    void open() => context.push('/admin/companies/${item.id}');

    return AppCard(
      onTap: item.id.isEmpty ? null : open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAvatar(name: item.name, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.inkStrong),
                    ),
                    if (item.workEmail.isNotEmpty)
                      Text(
                        item.workEmail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(item.status, tone: companyStatusTone(item.status)),
            ],
          ),
          const SizedBox(height: 8),
          InfoRow(label: 'Industry', value: item.industry),
          InfoRow(
            label: 'Contact',
            value: item.phone.isEmpty ? item.contact : '${item.contact}\n${item.phone}',
          ),
          InfoRow(label: 'Admin email', value: item.adminEmail),
          InfoRow(label: 'Submitted', value: formatDate(item.submittedAt)),
          const SizedBox(height: 8),
          AppButton(
            label: 'View',
            compact: true,
            variant: AppButtonVariant.secondary,
            onPressed: item.id.isEmpty ? null : open,
          ),
        ],
      ),
    );
  }
}
