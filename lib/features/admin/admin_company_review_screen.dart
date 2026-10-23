import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/widgets.dart';
import 'admin_companies_screen.dart' show adminCompaniesProvider;
import 'admin_dashboard_screen.dart' show adminDashboardProvider;
import 'admin_utils.dart';
import 'widgets/image_viewer.dart';
import 'widgets/message_thread.dart';

/// Web: `fetchAdminCompany` → `normalizeAdminCompanyDetail`.
final adminCompanyProvider = FutureProvider.autoDispose.family<AdminCompanyDetail, String>((ref, id) async {
  final data = await ref.watch(adminApiProvider).fetchCompany(id);
  return AdminCompanyDetail.fromJson(data);
});

/// Application message thread (`data.data.messages || data.messages`).
final adminCompanyMessagesProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, id) async {
  final data = asMap(await ref.watch(adminApiProvider).fetchCompanyMessages(id));
  final nested = asMap(data['data']);
  if (nested['messages'] is List) return asMapList(nested['messages']);
  return asMapList(data['messages']);
});

/// Port of `pages/admin/AdminCompanyReview.jsx`.
class AdminCompanyReviewScreen extends ConsumerStatefulWidget {
  const AdminCompanyReviewScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<AdminCompanyReviewScreen> createState() => _AdminCompanyReviewScreenState();
}

class _AdminCompanyReviewScreenState extends ConsumerState<AdminCompanyReviewScreen> {
  bool _docBusy = false;
  bool _reviewBusy = false;

  Future<void> _refresh() async {
    ref.invalidate(adminCompanyMessagesProvider(widget.id));
    final _ = await ref.refresh(adminCompanyProvider(widget.id).future);
  }

  Future<bool> _reviewDocument({required String documentKey, required String status, String? reason}) async {
    setState(() => _docBusy = true);
    try {
      await ref.read(adminApiProvider).reviewCompanyDocument(
            widget.id,
            documentKey: documentKey,
            status: status,
            reason: reason,
          );
      ref.invalidate(adminCompanyProvider(widget.id));
      ref.invalidate(adminCompanyMessagesProvider(widget.id));
      showToast(
        status == 'approved' ? 'Document approved' : 'Sent back to the company for re-upload',
        type: status == 'approved' ? ToastType.success : ToastType.info,
      );
      return true;
    } catch (e) {
      showErrorToast(e, 'Could not review document');
      return false;
    } finally {
      if (mounted) setState(() => _docBusy = false);
    }
  }

  Future<bool> _sendMessage(String text) async {
    try {
      await ref.read(adminApiProvider).postCompanyMessage(widget.id, text);
      ref.invalidate(adminCompanyMessagesProvider(widget.id));
      return true;
    } catch (e) {
      showErrorToast(e, 'Could not send message');
      return false;
    }
  }

  Future<void> _review(String status, [String? reason]) async {
    setState(() => _reviewBusy = true);
    try {
      await ref.read(adminApiProvider).reviewCompany(widget.id, status, reason);
      // Web invalidates every ['admin'] query.
      ref.invalidate(adminCompaniesProvider);
      ref.invalidate(adminDashboardProvider);
      ref.invalidate(adminCompanyProvider(widget.id));
      showToast(
        status == 'approved' ? 'Company approved — dashboard unlocked' : 'Application rejected',
        type: status == 'approved' ? ToastType.success : ToastType.info,
      );
      if (mounted) {
        context.go(status == 'approved' ? '/admin/companies?status=approved' : '/admin/companies?status=rejected');
      }
    } catch (e) {
      showErrorToast(e, 'Action failed');
      if (mounted) setState(() => _reviewBusy = false);
    }
  }

  Future<void> _reject() async {
    final reason = await showTextInputDialog(
      context,
      title: 'Reject Application',
      message: 'Provide a reason so the company can resubmit.',
      hint: 'e.g. GST certificate is unclear, please re-upload...',
      confirmLabel: 'Confirm Reject',
      maxLines: 4,
      destructive: true,
    );
    if (!mounted || reason == null || reason.trim().isEmpty) return;
    await _review('rejected', reason.trim());
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(adminCompanyProvider(widget.id));
    final app = value.valueOrNull;
    final canReview = app != null && (app.status == 'submitted' || app.status == 'pending');

    return Scaffold(
      appBar: AppBar(title: const Text('Company review')),
      bottomNavigationBar: canReview
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.hairline)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Reject',
                        variant: AppButtonVariant.outline,
                        icon: Icons.close,
                        onPressed: _reviewBusy ? null : _reject,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppButton(
                        label: _reviewBusy ? 'Processing...' : 'Approve Company',
                        loading: _reviewBusy,
                        onPressed: _reviewBusy
                            ? null
                            : () async {
                                // A stray tap on a phone must not unlock a company.
                                final ok = await showConfirmDialog(
                                  context,
                                  title: 'Approve this company?',
                                  message: 'Their enterprise dashboard is unlocked immediately.',
                                  confirmLabel: 'Approve',
                                );
                                if (ok && mounted) await _review('approved');
                              },
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: value.when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          loading: () => const LoadingView(label: 'Loading company details...'),
          error: (e, _) => ErrorView(
            error: e,
            title: 'Company not found',
            onRetry: () => ref.invalidate(adminCompanyProvider(widget.id)),
          ),
          data: (app) => _buildBody(app, canReview),
        ),
      ),
    );
  }

  Widget _buildBody(AdminCompanyDetail app, bool canReview) {
    final company = app.company;
    final admin = app.admin;
    final onboarding = app.onboarding;
    final companyType = strOrNull(company['companyType']) ?? 'private_limited';
    final docDefs = getDocumentsForCompanyType(companyType);
    final documents = app.documents;
    final reviews = app.documentReviews;

    final address = [
      company['locality'],
      company['city'],
      company['state'],
      company['pincode'],
      company['country'],
    ].map(strOrNull).whereType<String>().join(', ');

    final uploaded = documents.entries.where((e) => strOrNull(e.value) != null).toList();

    // Documents defined for the company type, then any other uploaded keys.
    final docTiles = <Widget>[];
    for (final doc in docDefs) {
      // Stored key can differ from the UI id (taxCertificate -> tax).
      final storedKey = strOrNull(documents[doc.id]) != null
          ? doc.id
          : (doc.id == 'taxCertificate' ? 'tax' : doc.id);
      final url = strOrNull(documents[storedKey]);
      if (url == null) continue;
      docTiles.add(_DocumentTile(
        key: ValueKey('doc-$storedKey'),
        label: doc.title,
        url: url,
        documentKey: storedKey,
        review: asMap(reviews[storedKey]),
        canReview: canReview,
        busy: _docBusy,
        onReview: _reviewDocument,
      ));
    }
    for (final entry in uploaded) {
      final key = entry.key;
      final known = docDefs.any((d) => d.id == key || (key == 'tax' && d.id == 'taxCertificate'));
      if (known) continue;
      docTiles.add(_DocumentTile(
        key: ValueKey('doc-$key'),
        label: companyDocLabels[key] ?? key,
        url: str(entry.value),
        documentKey: key,
        review: asMap(reviews[key]),
        canReview: canReview,
        busy: _docBusy,
        onReview: _reviewDocument,
      ));
    }

    final messagesValue = ref.watch(adminCompanyMessagesProvider(widget.id));
    final rejectionReason = app.rejectionReason;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strOrNull(company['name']) ?? str(company['companyLegalName'], '—'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Submitted ${formatDate(strOrNull(onboarding['submittedAt']) ?? app.submittedAt)}',
                    style: const TextStyle(fontSize: 13.5, color: AppColors.inkMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            StatusBadge(
              app.status,
              tone: app.status == 'approved'
                  ? Tone.success
                  : (app.status == 'rejected' ? Tone.danger : Tone.warning),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppCard(
          title: 'Company Information',
          child: Column(
            children: [
              InfoRow(label: 'Company Type', value: getCompanyTypeLabel(companyType)),
              InfoRow(label: 'Legal Name', value: strOrNull(company['name']) ?? str(company['companyLegalName'])),
              InfoRow(label: 'Industry', value: str(company['industry'])),
              InfoRow(label: 'Company Size', value: str(company['companySize'])),
              InfoRow(label: 'Work Email', value: str(company['workEmail'])),
              InfoRow(label: 'Contact Person', value: str(company['contactName'])),
              InfoRow(label: 'Phone', value: str(company['phone'])),
              InfoRow(label: 'Address', value: address),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          title: 'Registration & Admin',
          child: Column(
            children: [
              InfoRow(label: 'Admin Email', value: str(admin['email'])),
              InfoRow(label: getRegistrationLabel(companyType), value: str(company['brn'])),
              InfoRow(label: 'GSTIN / Tax ID', value: str(company['taxId'])),
              InfoRow(label: 'Onboarding Status', value: strOrNull(onboarding['status']) ?? app.status),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          title: 'Uploaded Documents',
          subtitle: 'Reject a single document to send just that one back — the rest of the application stays as it is.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final tile in docTiles) ...[tile, const SizedBox(height: 10)],
              if (uploaded.isEmpty)
                const Text('No documents uploaded', style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        MessageThread(
          messages: messagesValue.valueOrNull ?? const [],
          viewerRole: 'admin',
          isLoading: messagesValue.isLoading && !messagesValue.hasValue,
          onSend: _sendMessage,
          title: 'Messages with this company',
          subtitle: 'They see these replies on their application status page.',
          placeholder: 'Reply to the company…',
        ),
        if (rejectionReason != null) ...[
          const SizedBox(height: 12),
          InfoBanner(tone: Tone.danger, title: 'Rejection Reason', message: rejectionReason),
        ],
      ],
    );
  }
}

/// One uploaded document with its own verdict (web `DocumentLink`).
class _DocumentTile extends StatefulWidget {
  const _DocumentTile({
    super.key,
    required this.label,
    required this.url,
    required this.documentKey,
    required this.review,
    required this.canReview,
    required this.busy,
    required this.onReview,
  });

  final String label;
  final String url;
  final String documentKey;
  final Map<String, dynamic> review;
  final bool canReview;
  final bool busy;
  final Future<bool> Function({required String documentKey, required String status, String? reason}) onReview;

  @override
  State<_DocumentTile> createState() => _DocumentTileState();
}

class _DocumentTileState extends State<_DocumentTile> {
  bool _rejecting = false;
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _view() {
    final href = mediaUrl(widget.url);
    if (href != null && isImagePath(widget.url)) {
      showImageViewer(context, href, title: widget.label);
    } else {
      openExternalUrl(href);
    }
  }

  Future<void> _sendBack() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) return;
    final ok = await widget.onReview(documentKey: widget.documentKey, status: 'rejected', reason: reason);
    if (ok && mounted) {
      setState(() {
        _rejecting = false;
        _reason.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.url.split('/').last;
    final status = strOrNull(widget.review['status']) ?? 'pending';
    final tone = switch (status) {
      'approved' => Tone.success,
      'rejected' => Tone.danger,
      _ => Tone.neutral,
    };
    final rejectReason = strOrNull(widget.review['reason']);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.label,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.inkStrong)),
                    const SizedBox(height: 2),
                    Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(status, tone: tone),
              TextButton(onPressed: _view, child: const Text('View')),
            ],
          ),
          if (status == 'rejected' && rejectReason != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: AppColors.dangerBg, borderRadius: BorderRadius.circular(8)),
              child: Text('Sent back: $rejectReason', style: const TextStyle(fontSize: 12, color: AppColors.danger)),
            ),
          if (widget.canReview) ...[
            const SizedBox(height: 10),
            if (_rejecting) ...[
              TextField(
                controller: _reason,
                autofocus: true,
                enabled: !widget.busy,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: "What's wrong with this document?"),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Send back',
                      compact: true,
                      variant: AppButtonVariant.danger,
                      loading: widget.busy,
                      onPressed: widget.busy || _reason.text.trim().isEmpty ? null : _sendBack,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppButton(
                      label: 'Cancel',
                      compact: true,
                      variant: AppButtonVariant.outline,
                      onPressed: () => setState(() => _rejecting = false),
                    ),
                  ),
                ],
              ),
            ] else
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: status == 'approved' ? 'Approved' : 'Approve doc',
                      compact: true,
                      icon: Icons.check,
                      onPressed: widget.busy || status == 'approved'
                          ? null
                          : () => widget.onReview(documentKey: widget.documentKey, status: 'approved'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppButton(
                      label: 'Reject doc',
                      compact: true,
                      variant: AppButtonVariant.outline,
                      onPressed: widget.busy ? null : () => setState(() => _rejecting = true),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
