import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/home_routes.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';

/// Latest application outcome — used to show the current rejection reason and
/// to notice if the application was re-opened since the session was stored.
final _rejectedStatusProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return asMap(await ref.watch(enterpriseApiProvider).fetchApplicationStatus());
});

/// Port of `pages/enterprise/ApplicationRejected.jsx`. "Resubmit Documents"
/// sends the user back through the document + review steps, exactly like the
/// web (the backend's `/application/resubmit` only applies to
/// `changes_requested`, which the pending-approval screen handles).
class ApplicationRejectedScreen extends ConsumerStatefulWidget {
  const ApplicationRejectedScreen({super.key});

  @override
  ConsumerState<ApplicationRejectedScreen> createState() => _ApplicationRejectedScreenState();
}

class _ApplicationRejectedScreenState extends ConsumerState<ApplicationRejectedScreen> {
  bool _signingOut = false;
  bool _leaving = false;

  Future<void> _handleStatus(Map<String, dynamic> application) async {
    if (_leaving) return;
    final status = str(application['status']);
    final auth = ref.read(authProvider);
    if (status == 'rejected') {
      final reason = strOrNull(application['rejectionReason']);
      if (reason != null && reason != str(auth.company?['rejectionReason'])) {
        await auth.updateCompany({'rejectionReason': reason}, merge: true);
      }
      return;
    }
    if (status == 'changes_requested') {
      // Handled (re-upload + resubmit) on the pending-approval screen.
      _leaving = true;
      if (mounted) context.go('/enterprise/pending-approval');
      return;
    }
    if (status == 'approved' || status == 'submitted' || status == 'pending') {
      _leaving = true;
      await auth.updateCompany(
        {
          'approvalStatus': status,
          if (status == 'approved') 'isVerified': true,
        },
        merge: true,
      );
      if (mounted) context.go(enterpriseHomeRoute(ref.read(authProvider).company));
    }
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    _leaving = true;
    await ref.read(authProvider).logout();
    if (!mounted) return;
    context.go('/enterprise/login');
  }

  void _resubmit() => context.go('/enterprise/verify');

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<Map<String, dynamic>>>(_rejectedStatusProvider, (_, next) {
      final app = next.valueOrNull;
      if (app != null) _handleStatus(app);
    });

    final auth = ref.watch(authProvider);
    final statusAsync = ref.watch(_rejectedStatusProvider);
    final company = auth.company;
    final name =
        strOrNull(company?['companyLegalName']) ?? strOrNull(company?['name']) ?? 'Your application';
    final reason = strOrNull(statusAsync.valueOrNull?['rejectionReason']) ??
        strOrNull(company?['rejectionReason']) ??
        strOrNull(company?['rejectionNote']);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Application Not Approved'),
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(_rejectedStatusProvider);
                try {
                  await ref.read(_rejectedStatusProvider.future);
                } catch (_) {
                  // The stored reason is still shown.
                }
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  const Text(
                    'Your enterprise registration could not be verified at this time.',
                    style: TextStyle(fontSize: 14, color: AppColors.inkMuted, height: 1.45),
                  ),
                  const SizedBox(height: 16),
                  if (statusAsync.isLoading && !statusAsync.hasValue)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 28, 18, 22),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadii.card),
                      border: Border.all(color: AppColors.danger.withValues(alpha: 0.18)),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.dangerBg, AppColors.surface],
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 34, color: AppColors.danger),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '$name was not approved',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.inkStrong),
                        ),
                        const SizedBox(height: 14),
                        if (reason != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(AppRadii.control),
                              border: Border.all(color: AppColors.danger.withValues(alpha: 0.18)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'REJECTION REASON',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.6,
                                    color: AppColors.danger,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(reason, style: const TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.inkBody)),
                              ],
                            ),
                          )
                        else
                          const Text(
                            'Please update your documents and resubmit, or contact PagerLook support if you believe '
                            'this was an error.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.inkBody),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.hairline)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Sign Out',
                        variant: AppButtonVariant.outline,
                        loading: _signingOut,
                        onPressed: _signingOut ? null : _signOut,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: AppButton(
                        label: 'Resubmit Documents',
                        onPressed: _signingOut ? null : _resubmit,
                      ),
                    ),
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
