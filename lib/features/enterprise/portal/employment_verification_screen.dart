import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/company_permissions.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import 'widgets_b/sheet_body.dart';
import 'widgets_b/verification_sheets.dart';

final _outgoingProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data = await ref.watch(enterpriseApiProvider).fetchVerificationOutgoing();
  return listFrom(data, const ['requests', 'items']);
});

final _incomingProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data = await ref.watch(enterpriseApiProvider).fetchVerificationIncoming();
  return listFrom(data, const ['requests', 'items']);
});

/// Email delivery badge — web `EMAIL_DELIVERY`.
const Map<String, (String, Tone)> _emailDelivery = {
  'sent': ('Email sent', Tone.success),
  'mock': ('Not sent — configure SMTP', Tone.warning),
  'failed': ('Send failed — retry', Tone.danger),
  'not_sent': ('Email pending', Tone.neutral),
};

/// Port of `pages/enterprise/EmploymentVerification.jsx` — outgoing and
/// incoming employment verification requests.
class EmploymentVerificationScreen extends ConsumerStatefulWidget {
  const EmploymentVerificationScreen({super.key});

  @override
  ConsumerState<EmploymentVerificationScreen> createState() => _EmploymentVerificationScreenState();
}

class _EmploymentVerificationScreenState extends ConsumerState<EmploymentVerificationScreen> {
  String _tab = 'outgoing';

  /// Id of the request whose approve/reject/resend is in flight (web `actionPending`).
  String? _busyId;

  void _invalidate() {
    ref.invalidate(_outgoingProvider);
    ref.invalidate(_incomingProvider);
  }

  Future<void> _refresh() async {
    try {
      await Future.wait([ref.refresh(_outgoingProvider.future), ref.refresh(_incomingProvider.future)]);
    } catch (_) {
      // Shown inline by the error banner.
    }
  }

  Future<void> _openSheet(Widget sheet) async {
    final result = await showAppSheet<bool>(context, builder: (_) => sheet);
    if (result == true) _invalidate();
  }

  Future<void> _reject(Map<String, dynamic> request) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Reject verification?',
      message: 'Reject the employment verification request for ${str(request['employeeName'], 'this employee')}?',
      confirmLabel: 'Reject',
      destructive: true,
    );
    if (!ok) return;
    setState(() => _busyId = idOf(request));
    try {
      await ref.read(enterpriseApiProvider).rejectVerificationRequest(idOf(request));
      showToast('Verification rejected', type: ToastType.success);
      _invalidate();
    } catch (e) {
      showErrorToast(e, 'Failed to reject');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _resend(Map<String, dynamic> request) async {
    setState(() => _busyId = idOf(request));
    try {
      final result = asMap(await ref.read(enterpriseApiProvider).resendVerificationEmail(idOf(request)));
      final status = str(result['emailStatus']);
      showToast(
        str(result['message'], status == 'sent' ? 'Verification email re-sent' : 'Resend attempted'),
        type: status == 'failed' ? ToastType.error : ToastType.success,
      );
      _invalidate();
    } catch (e) {
      showErrorToast(e, 'Failed to resend email');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final outAsync = ref.watch(_outgoingProvider);
    final inAsync = ref.watch(_incomingProvider);
    final perms = ref.watch(companyPermissionsProvider).valueOrNull ?? const CompanyPermissions();
    // The backend guards every action with verification:manage. While the
    // permission map is unknown keep actions visible, as the web page does.
    final canManage = !perms.ready || perms.can('verification', 'manage');

    final loading = (outAsync.isLoading && !outAsync.hasValue) || (inAsync.isLoading && !inAsync.hasValue);

    Widget body;
    if (loading) {
      body = const LoadingView(label: 'Loading verification requests...');
    } else {
      final outgoing = outAsync.valueOrNull ?? const <Map<String, dynamic>>[];
      final incoming = inAsync.valueOrNull ?? const <Map<String, dynamic>>[];
      final error = outAsync.error ?? inAsync.error;
      final isOutgoing = _tab == 'outgoing';
      final list = isOutgoing ? outgoing : incoming;
      final busy = _busyId != null;

      body = Column(
        children: [
          FilterChipsBar(
            options: {
              'outgoing': outgoing.isEmpty ? 'Outgoing' : 'Outgoing (${outgoing.length})',
              'incoming': incoming.isEmpty ? 'Incoming' : 'Incoming (${incoming.length})',
            },
            selected: _tab,
            onSelected: (v) => setState(() => _tab = v),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  if (error != null) ...[
                    InfoBanner(
                      tone: error is ApiException && error.isForbidden ? Tone.warning : Tone.danger,
                      message: errorMessage(error),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SectionHeader(
                    isOutgoing ? 'Outgoing Requests' : 'Incoming Requests',
                    subtitle: isOutgoing
                        ? 'Verification requests your company has sent.'
                        : 'Previous employer verification requests via the platform channel.',
                    padding: const EdgeInsets.only(top: 4, bottom: 12),
                  ),
                  if (list.isEmpty)
                    EmptyState(
                      icon: Icons.verified_outlined,
                      title: isOutgoing ? 'No outgoing verification requests' : 'No incoming verification requests',
                    )
                  else
                    for (final request in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _RequestCard(
                          request: request,
                          busy: busy,
                          busySelf: _busyId == idOf(request),
                          onApprove: !isOutgoing && canManage
                              ? () => _openSheet(IncomingApproveSheet(request: request))
                              : null,
                          onReject: !isOutgoing && canManage ? () => _reject(request) : null,
                          onResendEmail: isOutgoing && canManage ? () => _resend(request) : null,
                          onCompleteEmail:
                              canManage ? () => _openSheet(EmailVerificationCompleteSheet(request: request)) : null,
                          onReviewHr: canManage ? () => _openSheet(HrResponseReviewSheet(request: request)) : null,
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Employment Verification')),
      body: body,
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.busy,
    required this.busySelf,
    this.onApprove,
    this.onReject,
    this.onCompleteEmail,
    this.onReviewHr,
    this.onResendEmail,
  });

  final Map<String, dynamic> request;
  final bool busy;
  final bool busySelf;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onCompleteEmail;
  final VoidCallback? onReviewHr;
  final VoidCallback? onResendEmail;

  @override
  Widget build(BuildContext context) {
    final rawStatus = str(request['rawStatus'] ?? request['status']);
    final channel = str(request['verificationChannel']);
    final isPending = rawStatus == 'pending';
    final isEmailChannel = channel == 'email';
    final isEmailInProcess = isEmailChannel && (rawStatus == 'in_process' || rawStatus == 'in_review');
    final isHrResponded = rawStatus == 'hr_responded';
    final emailStatus = str(request['emailStatus']);
    final showEmailDelivery = isEmailChannel && emailStatus.isNotEmpty && emailStatus != 'not_applicable';
    final delivery = _emailDelivery[emailStatus];

    final (statusLabel, statusTone) = verificationStatusStyle(rawStatus);
    final (channelLabel, channelTone) = verificationChannelStyle(channel);

    final jobTitle = str(request['jobTitle'] ?? request['title']);
    final company = str(request['companyName'] ?? request['company'] ?? request['previousCompanyName']);
    final tagLabel = strOrNull(pick(request, 'verificationTag.label'));

    final actions = <Widget>[
      if (isEmailInProcess && onResendEmail != null)
        AppButton(
          label: 'Resend email',
          variant: AppButtonVariant.outline,
          compact: true,
          expand: false,
          loading: busySelf,
          onPressed: busy ? null : onResendEmail,
        ),
      if (isPending && onApprove != null && onReject != null) ...[
        AppButton(
          label: 'Reject',
          variant: AppButtonVariant.outline,
          compact: true,
          expand: false,
          loading: busySelf,
          onPressed: busy ? null : onReject,
        ),
        AppButton(
          label: 'Approve',
          compact: true,
          expand: false,
          onPressed: busy ? null : onApprove,
        ),
      ],
      if (isEmailInProcess && onCompleteEmail != null)
        AppButton(
          label: 'Complete / Document Verify',
          variant: AppButtonVariant.secondary,
          compact: true,
          expand: false,
          onPressed: busy ? null : onCompleteEmail,
        ),
      if (isHrResponded && onReviewHr != null)
        AppButton(
          label: 'Review HR Response',
          compact: true,
          expand: false,
          onPressed: busy ? null : onReviewHr,
        ),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            str(request['employeeName'], 'Employee'),
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.inkStrong),
          ),
          const SizedBox(height: 3),
          Text(
            [jobTitle, company].where((s) => s.isNotEmpty).join(' · '),
            style: const TextStyle(fontSize: 13.5, color: AppColors.inkBody),
          ),
          if (tagLabel != null) ...[
            const SizedBox(height: 6),
            Text(
              tagLabel,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            formatAccessDate(request['createdAt'] ?? request['requestedAt']),
            style: const TextStyle(fontSize: 12, color: AppColors.inkFaint),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusBadge(channel, label: channelLabel, tone: channelTone),
              StatusBadge(rawStatus, label: statusLabel, tone: statusTone),
              if (showEmailDelivery && delivery != null)
                StatusBadge(emailStatus, label: delivery.$1, tone: delivery.$2),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ],
      ),
    );
  }
}
