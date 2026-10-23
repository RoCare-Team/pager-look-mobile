import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/widgets.dart';
import 'admin_utils.dart';
import 'widgets/hr_contacts_editor.dart';

/// `{ requests, summary }` for a status/search (web reads `data.data || data`).
final adminVerificationRequestsProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, AdminListQuery>((ref, query) async {
  final data = asMap(await ref.watch(adminApiProvider).fetchVerificationRequests(status: query.status, q: query.q));
  return data['data'] is Map ? asMap(data['data']) : data;
});

const _tabs = {
  'open': 'Open',
  'hr_responded': 'HR responded',
  'verified': 'Verified',
  'rejected': 'Rejected',
  'expired': 'Expired',
  'all': 'All',
};

const _emailStatusLabels = {
  'sent': 'Email sent',
  'mock': 'Mock (SMTP not configured)',
  'failed': 'Email failed',
  'not_sent': 'Not sent',
  'not_applicable': '',
};

Tone _statusTone(String raw) => switch (raw) {
      'verified' || 'approved' => Tone.success,
      'hr_responded' => Tone.info,
      'rejected' => Tone.danger,
      'expired' => Tone.neutral,
      _ => Tone.warning,
    };

/// Port of `pages/admin/AdminVerifications.jsx`.
class AdminVerificationsScreen extends ConsumerStatefulWidget {
  const AdminVerificationsScreen({super.key});

  @override
  ConsumerState<AdminVerificationsScreen> createState() => _AdminVerificationsScreenState();
}

class _AdminVerificationsScreenState extends ConsumerState<AdminVerificationsScreen> {
  String _status = 'open';
  String _search = '';
  String? _openResendId;

  AdminListQuery get _key => (status: _status, q: _search);

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(adminVerificationRequestsProvider(_key));

    return Scaffold(
      appBar: AppBar(title: const Text('Employment verifications')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SearchField(
              hint: 'Search employee, company, HR email...',
              onChanged: (q) => setState(() => _search = q),
            ),
          ),
          FilterChipsBar(
            options: _tabs,
            selected: _status,
            onSelected: (key) => setState(() {
              _status = key;
              _openResendId = null;
            }),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(adminVerificationRequestsProvider(_key).future),
              child: value.when(
                skipLoadingOnRefresh: true,
                skipLoadingOnReload: true,
                loading: () => const LoadingView(label: 'Loading verification requests...'),
                error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.invalidate(adminVerificationRequestsProvider(_key)),
                ),
                data: _buildList,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(Map<String, dynamic> payload) {
    final requests = listFrom(payload, const ['requests']);
    final summary = payload['summary'] is Map ? asMap(payload['summary']) : null;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Every verification request on the platform — who sent it, where it went, and whether anyone '
            'replied. Re-send the ones that stalled.',
            style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted),
          ),
        ),
        if (summary != null) ...[
          StatGrid(
            columns: 3,
            children: [
              for (final stat in const [
                ('Total', 'total'),
                ('Open', 'open'),
                ('Verified', 'verified'),
                ('Rejected', 'rejected'),
                ('Expired', 'expired'),
              ])
                StatCard(label: stat.$1, value: formatNumber(summary[stat.$2]), tone: Tone.neutral),
            ],
          ),
          const SizedBox(height: 14),
        ],
        if (requests.isEmpty)
          EmptyState(
            title: _status == 'all'
                ? 'No verification requests.'
                : 'No ${_status.replaceFirst('_', ' ')} verification requests.',
            icon: Icons.fact_check_outlined,
          )
        else
          for (final request in requests) ...[
            _RequestCard(
              key: ValueKey('vr-${idOf(request)}'),
              request: request,
              resendOpen: _openResendId != null && _openResendId == idOf(request),
              onOpenResend: () => setState(() => _openResendId = idOf(request)),
              onCloseResend: () => setState(() => _openResendId = null),
              onResent: () => ref.invalidate(adminVerificationRequestsProvider),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    super.key,
    required this.request,
    required this.resendOpen,
    required this.onOpenResend,
    required this.onCloseResend,
    required this.onResent,
  });

  final Map<String, dynamic> request;
  final bool resendOpen;
  final VoidCallback onOpenResend;
  final VoidCallback onCloseResend;
  final VoidCallback onResent;

  @override
  Widget build(BuildContext context) {
    final raw = strOrNull(request['rawStatus']) ?? str(request['status']);
    final requestedBy = asMap(request['requestedBy']);
    final channel = str(request['verificationChannel']);
    final isEmail = channel == 'email';
    final targetCompany = strOrNull(request['targetCompanyName']) ?? str(request['previousCompanyName']);
    final emailLabel = _emailStatusLabels[str(request['emailStatus'])] ?? '';
    final hrContacts = asList(request['hrContacts']).map((c) => str(c)).where((c) => c.isNotEmpty).toList();
    final subtitle = [
      strOrNull(request['jobTitle']),
      strOrNull(request['companyName']) ?? strOrNull(request['previousCompanyName']),
    ].whereType<String>().join(' · ');
    final veriworkId = strOrNull(request['employeeVeriworkId']);
    final lastReminded = request['lastRemindedAt'];

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
                      str(request['employeeName'], '—'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.inkStrong),
                    ),
                    if (veriworkId != null)
                      Text(
                        veriworkId,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColors.inkFaint),
                      ),
                    if (subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusBadge(raw, tone: _statusTone(raw), label: strOrNull(request['statusLabel']) ?? raw),
                  if (request['requestedAt'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        formatDate(request['requestedAt']),
                        style: const TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          InfoRow(
            label: 'Requested by',
            valueWidget: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: str(requestedBy['label'], '—')),
                  TextSpan(
                    text: '  ${str(requestedBy['type']) == 'company' ? 'COMPANY' : 'EMPLOYEE'}',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.inkMuted),
                  ),
                ],
              ),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.inkStrong),
            ),
          ),
          InfoRow(
            label: 'Channel',
            value: channel == 'platform'
                ? 'PagerLook dashboard ($targetCompany)'
                : 'HR email${isEmail && emailLabel.isNotEmpty ? ' — $emailLabel' : ''}',
          ),
          InfoRow(
            label: 'Re-sends',
            value: '${asInt(request['remindersSent'])}'
                '${lastReminded != null ? ' — last ${formatDate(lastReminded)}' : ''}',
          ),
          if (isEmail)
            InfoRow(label: 'HR contacts', value: hrContacts.isEmpty ? 'None on record' : hrContacts.join(', ')),
          const SizedBox(height: 10),
          if (asBool(request['canResend']))
            resendOpen
                ? _ResendPanel(
                    request: request,
                    isEmail: isEmail,
                    initialContacts: hrContacts,
                    onClose: onCloseResend,
                    onResent: onResent,
                  )
                : AppButton(
                    label: 'Resend request',
                    compact: true,
                    variant: AppButtonVariant.secondary,
                    icon: Icons.send_outlined,
                    onPressed: onOpenResend,
                  )
          else
            Text(
              strOrNull(request['resendBlockedReason']) ?? 'This request can no longer be re-sent.',
              style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
            ),
        ],
      ),
    );
  }
}

/// Resend panel for one request. Opens with the addresses already on the
/// record so support can fix a dead mailbox or add the ones HR actually reads.
class _ResendPanel extends ConsumerStatefulWidget {
  const _ResendPanel({
    required this.request,
    required this.isEmail,
    required this.initialContacts,
    required this.onClose,
    required this.onResent,
  });

  final Map<String, dynamic> request;
  final bool isEmail;
  final List<String> initialContacts;
  final VoidCallback onClose;
  final VoidCallback onResent;

  @override
  ConsumerState<_ResendPanel> createState() => _ResendPanelState();
}

class _ResendPanelState extends ConsumerState<_ResendPanel> {
  late List<String> _contacts = widget.initialContacts.isEmpty ? [''] : [...widget.initialContacts];
  bool _sending = false;

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      final res = await ref.read(adminApiProvider).resendVerificationRequest(
            idOf(widget.request),
            hrContacts: widget.isEmail ? cleanContacts(_contacts) : null,
          );
      final result = asMap(res);
      final payload = result['data'] is Map ? asMap(result['data']) : result;
      showToast(strOrNull(payload['message']) ?? 'Verification request re-sent', type: ToastType.success);
      widget.onResent();
      widget.onClose();
    } catch (e) {
      showErrorToast(e, 'Could not re-send the request');
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final requestedBy = asMap(request['requestedBy']);
    final target = strOrNull(request['targetCompanyName']) ?? str(request['previousCompanyName']);
    final from = str(requestedBy['type']) == 'company'
        ? "${strOrNull(requestedBy['companyName']) ?? 'the requesting company'}'s mailbox"
        : "the employee's own mailbox";

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.isEmail) ...[
            HrContactsEditor(
              initialContacts: _contacts,
              onChanged: (next) => _contacts = next,
              enabled: !_sending,
              label: 'HR contacts',
              hint: 'Everyone listed here gets the same secure verification link.',
            ),
            const SizedBox(height: 8),
            Text(
              'Sent from $from, the same as the original request.',
              style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
            ),
          ] else
            Text(
              "This request sits on $target's PagerLook dashboard. Re-sending nudges them there — there is no email to correct.",
              style: const TextStyle(fontSize: 12.5, color: AppColors.inkBody),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: _sending ? 'Sending...' : (widget.isEmail ? 'Resend request' : 'Send reminder'),
                  compact: true,
                  loading: _sending,
                  onPressed: _sending ? null : _send,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  label: 'Cancel',
                  compact: true,
                  variant: AppButtonVariant.secondary,
                  onPressed: _sending ? null : widget.onClose,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
