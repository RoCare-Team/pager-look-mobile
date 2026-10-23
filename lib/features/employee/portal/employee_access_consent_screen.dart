import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import 'activity_screen.dart';
import 'employee_portal_utils.dart';

/// `GET /employee/access-requests` → `{ requests }` or a bare list.
final employeeAccessRequestsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return listFrom(await ref.watch(employeeApiProvider).fetchAccessRequests(), const ['requests']);
});

/// `GET /employee/verification/requests` → `{ requests }` (or nested in `data`).
final employeeVerificationRequestsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ref.watch(employeeApiProvider).fetchVerificationRequests();
  final direct = listFrom(res, const ['requests']);
  if (direct.isNotEmpty) return direct;
  return listFrom(pick(res, 'data'), const ['requests']);
});

bool _isConsentPending(Map<String, dynamic> r) =>
    str(r['rawStatus']) == 'pending_employee_consent' || str(r['status']) == 'pending_employee_consent';

/// Port of `EmployeeAccessConsent.jsx` — profile access requests plus
/// verification-consent requests from a current employer.
class EmployeeAccessConsentScreen extends ConsumerStatefulWidget {
  const EmployeeAccessConsentScreen({super.key});

  @override
  ConsumerState<EmployeeAccessConsentScreen> createState() => _EmployeeAccessConsentScreenState();
}

class _EmployeeAccessConsentScreenState extends ConsumerState<EmployeeAccessConsentScreen> {
  String? _busyAccessId;
  String? _busyConsentId;

  Future<void> _refresh() async {
    ref.invalidate(employeeAccessRequestsProvider);
    ref.invalidate(employeeVerificationRequestsProvider);
    await Future.wait([
      ref.read(employeeAccessRequestsProvider.future),
      ref.read(employeeVerificationRequestsProvider.future),
    ]);
  }

  Future<void> _approveAccess(String id) async {
    setState(() => _busyAccessId = id);
    try {
      await ref.read(employeeApiProvider).approveAccessRequest(id);
      showToast('Access request approved', type: ToastType.success);
      ref.invalidate(employeeAccessRequestsProvider);
    } catch (e) {
      showErrorToast(e, 'Failed to approve request');
    } finally {
      if (mounted) setState(() => _busyAccessId = null);
    }
  }

  Future<void> _rejectAccess(String id, {required bool wasApproved, required String company}) async {
    final ok = await showConfirmDialog(
      context,
      title: wasApproved ? 'Remove access?' : 'Reject request?',
      message: wasApproved
          ? '$company will no longer be able to view your profile.'
          : '$company will not get access to your profile.',
      confirmLabel: wasApproved ? 'Remove access' : 'Reject',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busyAccessId = id);
    try {
      await ref.read(employeeApiProvider).rejectAccessRequest(id);
      showToast(wasApproved ? 'Access removed' : 'Access request rejected', type: ToastType.success);
      ref.invalidate(employeeAccessRequestsProvider);
    } catch (e) {
      showErrorToast(e, 'Failed to update request');
    } finally {
      if (mounted) setState(() => _busyAccessId = null);
    }
  }

  Future<void> _approveConsent(String id) async {
    setState(() => _busyConsentId = id);
    try {
      final res = asMap(await ref.read(employeeApiProvider).approveVerificationConsent(id));
      final msg = strOrNull(pick(res, 'data.message')) ??
          strOrNull(res['message']) ??
          'Consent granted — previous company HR will review';
      showToast(msg, type: ToastType.success);
      ref.invalidate(employeeVerificationRequestsProvider);
      ref.invalidate(employeeActivityProvider);
    } catch (e) {
      showErrorToast(e, 'Failed to approve');
    } finally {
      if (mounted) setState(() => _busyConsentId = null);
    }
  }

  Future<void> _rejectConsent(String id) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Decline verification?',
      message: 'Your previous employer will not receive this verification request.',
      confirmLabel: 'Decline',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busyConsentId = id);
    try {
      await ref.read(employeeApiProvider).rejectVerificationConsent(id, {});
      showToast('Verification consent declined', type: ToastType.success);
      ref.invalidate(employeeVerificationRequestsProvider);
    } catch (e) {
      showErrorToast(e, 'Failed to decline');
    } finally {
      if (mounted) setState(() => _busyConsentId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accessAsync = ref.watch(employeeAccessRequestsProvider);
    final verificationAsync = ref.watch(employeeVerificationRequestsProvider);

    Widget body;
    if ((accessAsync.isLoading && !accessAsync.hasValue) || (verificationAsync.isLoading && !verificationAsync.hasValue)) {
      body = const LoadingView(label: 'Loading requests...');
    } else if (accessAsync.hasError && !accessAsync.hasValue && verificationAsync.hasError && !verificationAsync.hasValue) {
      body = ErrorView(error: accessAsync.error, onRetry: _refresh);
    } else {
      final accessRequests = accessAsync.valueOrNull ?? const <Map<String, dynamic>>[];
      final consentRequests =
          (verificationAsync.valueOrNull ?? const <Map<String, dynamic>>[]).where(_isConsentPending).toList();
      final error = accessAsync.error ?? verificationAsync.error;
      final hasAny = consentRequests.isNotEmpty || accessRequests.isNotEmpty;

      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          const PageIntro(
            title: 'Access & Consent',
            subtitle: 'Review profile access and verification consent requests from companies',
          ),
          if (error != null) ...[
            InfoBanner(tone: Tone.danger, message: errorMessage(error)),
            const SizedBox(height: 12),
          ],
          if (consentRequests.isNotEmpty) ...[
            const SectionHeader(
              'Verification with previous employer',
              subtitle: 'Your current company wants to verify a past job — approve to send the request to that '
                  "company's HR.",
              padding: EdgeInsets.only(bottom: 10),
            ),
            for (final req in consentRequests)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ConsentCard(
                  request: req,
                  busy: _busyConsentId != null,
                  loadingApprove: _busyConsentId == idOf(req),
                  onApprove: () => _approveConsent(idOf(req)),
                  onReject: () => _rejectConsent(idOf(req)),
                ),
              ),
          ],
          SectionHeader(
            'Profile access requests',
            subtitle: 'Companies requesting access to your profile and documents.',
            padding: consentRequests.isEmpty ? const EdgeInsets.only(bottom: 10) : null,
          ),
          if (accessRequests.isEmpty)
            const AppCard(
              child: Text(
                'No profile access requests',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.inkMuted),
              ),
            )
          else
            for (final req in accessRequests)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _AccessCard(
                  request: req,
                  busy: _busyAccessId != null,
                  loading: _busyAccessId == idOf(req),
                  onApprove: () => _approveAccess(idOf(req)),
                  onReject: (wasApproved) => _rejectAccess(
                    idOf(req),
                    wasApproved: wasApproved,
                    company: str(req['companyName'], 'This company'),
                  ),
                ),
              ),
          if (!hasAny)
            const EmptyState(
              icon: Icons.verified_user_outlined,
              title: 'No pending requests',
              message: 'Access and verification consent requests will appear here.',
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Access & Consent')),
      body: RefreshIndicator(onRefresh: _refresh, child: body),
    );
  }
}


class _AccessCard extends StatelessWidget {
  const _AccessCard({
    required this.request,
    required this.busy,
    required this.loading,
    required this.onApprove,
    required this.onReject,
  });

  final Map<String, dynamic> request;
  final bool busy;
  final bool loading;
  final VoidCallback onApprove;
  final ValueChanged<bool> onReject;

  @override
  Widget build(BuildContext context) {
    final status = str(request['status']);
    final style = accessRequestStatusStyle(status);
    final canAct = status == 'pending';
    final isApproved = status == 'approved';
    final type = str(request['requestType']);
    final typeLabel = strOrNull(request['requestTypeLabel']) ?? formatRequestType(type);
    final isFullProfile = type == 'full_profile_access';
    final message = strOrNull(request['message']);

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
                    Text(
                      str(request['companyName'], 'A company'),
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.inkStrong),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      typeLabel,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: isFullProfile ? FontWeight.w600 : FontWeight.w400,
                        color: isFullProfile ? AppColors.brand600 : AppColors.inkBody,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(status, label: style.label, tone: style.tone),
            ],
          ),
          if (isFullProfile) ...[
            const SizedBox(height: 10),
            const InfoBanner(
              tone: Tone.neutral,
              message: 'This company will see your complete profile, documents, and verification data.',
            ),
          ],
          if (message != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(AppRadii.control)),
              child: Text(message, style: const TextStyle(fontSize: 13, color: AppColors.inkBody)),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Requested ${formatAccessDate(request['requestedAt'] ?? request['createdAt'])}',
            style: const TextStyle(fontSize: 12, color: AppColors.inkFaint),
          ),
          if (canAct) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Reject',
                    variant: AppButtonVariant.outline,
                    onPressed: busy ? null : () => onReject(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(label: 'Approve', loading: loading, onPressed: busy ? null : onApprove),
                ),
              ],
            ),
          ],
          if (isApproved) ...[
            const SizedBox(height: 12),
            AppButton(
              label: 'Remove access',
              variant: AppButtonVariant.outline,
              icon: Icons.remove_circle_outline,
              loading: loading,
              onPressed: busy ? null : () => onReject(true),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConsentCard extends StatelessWidget {
  const _ConsentCard({
    required this.request,
    required this.busy,
    required this.loadingApprove,
    required this.onApprove,
    required this.onReject,
  });

  final Map<String, dynamic> request;
  final bool busy;
  final bool loadingApprove;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final previous = str(request['previousCompanyName'], 'your previous company');
    final requesting = str(request['requestingCompanyName'], 'Your current company');
    final jobTitle = strOrNull(request['jobTitle']);

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
                    const Eyebrow('Verification consent'),
                    const SizedBox(height: 4),
                    Text(
                      previous,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.inkStrong),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const StatusBadge(null, label: 'Awaiting consent', tone: Tone.neutral),
            ],
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 13.5, color: AppColors.inkBody, height: 1.4),
              children: [
                TextSpan(text: '$requesting wants to verify your employment at '),
                TextSpan(text: previous, style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: '${jobTitle == null ? '' : ' ($jobTitle)'} with their HR on PagerLook.'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(AppRadii.control)),
            child: Text(
              'If you approve, $previous will receive a verification request in their dashboard.',
              style: const TextStyle(fontSize: 13, color: AppColors.inkBody),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Requested ${formatAccessDate(request['requestedAt'])}',
            style: const TextStyle(fontSize: 12, color: AppColors.inkFaint),
          ),
          const SizedBox(height: 12),
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
                  label: 'Approve & send to HR',
                  loading: loadingApprove,
                  onPressed: busy ? null : onApprove,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
