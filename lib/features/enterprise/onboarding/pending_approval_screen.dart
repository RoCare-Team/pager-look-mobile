import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/home_routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/api/enterprise_api.dart';
import 'onboarding_shared.dart';

/// `GET /enterprise/application/status` →
/// `{ status, rejectionReason, documentReviews, rejectedDocuments, canResubmit, unreadMessages }`.
final _applicationStatusProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return asMap(await ref.watch(enterpriseApiProvider).fetchApplicationStatus());
});

/// `GET /enterprise/application/messages` → `{ messages: [...] }`.
final _applicationMessagesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data = asMap(await ref.watch(enterpriseApiProvider).fetchApplicationMessages());
  return asMapList(data['messages']);
});

/// How often the screen re-checks the application while it is visible.
const Duration _pollInterval = Duration(seconds: 30);

/// Port of `pages/enterprise/PendingApproval.jsx`. Polls the application while
/// open (the web relies on a manual refresh) and moves the user on as soon as
/// the compliance team approves or rejects.
class PendingApprovalScreen extends ConsumerStatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  ConsumerState<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends ConsumerState<PendingApprovalScreen> with WidgetsBindingObserver {
  Timer? _poll;
  bool _foreground = true;
  bool _leaving = false;
  bool _sending = false;
  bool _resubmitting = false;
  bool _signingOut = false;
  final Set<String> _uploading = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(_pollInterval, (_) {
      if (_foreground && mounted && !_leaving) _refresh();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final nowForeground = state == AppLifecycleState.resumed;
    if (nowForeground && !_foreground && mounted && !_leaving) _refresh();
    _foreground = nowForeground;
  }

  void _refresh() {
    ref.invalidate(_applicationStatusProvider);
    ref.invalidate(_applicationMessagesProvider);
  }

  Future<void> _pullToRefresh() async {
    _refresh();
    try {
      await ref.read(_applicationStatusProvider.future);
    } catch (_) {
      // Shown inline.
    }
  }

  /// Approved / rejected → store the new status and leave for the right home.
  Future<void> _handleStatus(Map<String, dynamic> application) async {
    if (_leaving) return;
    final status = str(application['status']);
    final auth = ref.read(authProvider);
    if (status == 'approved') {
      _leaving = true;
      await auth.updateCompany(
        {'approvalStatus': 'approved', 'isVerified': true, 'onboardingComplete': true},
        merge: true,
      );
    } else if (status == 'rejected') {
      _leaving = true;
      await auth.updateCompany(
        {
          'approvalStatus': 'rejected',
          'isVerified': false,
          'rejectionReason': str(application['rejectionReason']),
        },
        merge: true,
      );
    } else {
      return;
    }
    if (!mounted) return;
    context.go(enterpriseHomeRoute(ref.read(authProvider).company));
  }

  Future<bool> _send(String text) async {
    setState(() => _sending = true);
    try {
      await ref.read(enterpriseApiProvider).postApplicationMessage(text);
      ref.invalidate(_applicationMessagesProvider);
      return true;
    } catch (e) {
      showErrorToast(e, 'Could not send message');
      return false;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _resubmit() async {
    setState(() => _resubmitting = true);
    try {
      final data = asMap(await ref.read(enterpriseApiProvider).resubmitApplication());
      final status = strOrNull(data['status']);
      if (status != null) {
        await ref.read(authProvider).updateCompany({'approvalStatus': status}, merge: true);
      }
      showToast('Application resubmitted for review', type: ToastType.success);
      _refresh();
    } catch (e) {
      showErrorToast(e, 'Could not resubmit');
    } finally {
      if (mounted) setState(() => _resubmitting = false);
    }
  }

  Future<void> _reupload(String documentKey) async {
    final file = await pickDocumentWithSheet(context, title: 'Re-upload ${onboardingDocLabel(documentKey)}');
    if (file == null || !mounted) return;
    setState(() => _uploading.add(documentKey));
    try {
      await ref.read(enterpriseApiProvider).uploadOnboardingDocument(enterpriseDocType(documentKey), file);
      showToast('${onboardingDocLabel(documentKey)} re-uploaded', type: ToastType.success);
      ref.invalidate(_applicationStatusProvider);
    } catch (e) {
      showErrorToast(e, 'Upload failed');
    } finally {
      if (mounted) setState(() => _uploading.remove(documentKey));
    }
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    _leaving = true;
    await ref.read(authProvider).logout();
    if (!mounted) return;
    context.go('/enterprise/login');
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<Map<String, dynamic>>>(_applicationStatusProvider, (_, next) {
      final app = next.valueOrNull;
      if (app != null) _handleStatus(app);
    });

    final auth = ref.watch(authProvider);
    final statusAsync = ref.watch(_applicationStatusProvider);
    final messagesAsync = ref.watch(_applicationMessagesProvider);

    final application = statusAsync.valueOrNull ?? const <String, dynamic>{};
    final rejected = asMapList(application['rejectedDocuments']);
    final needsChanges = str(application['status']) == 'changes_requested';
    final name = strOrNull(auth.company?['companyLegalName']) ?? strOrNull(auth.company?['name']) ?? 'Your company';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(needsChanges ? 'Changes Requested' : 'Application Under Review'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _leaving ? null : _refresh,
          ),
        ],
      ),
      body: StickyActionLayout(
        body: RefreshIndicator(
          onRefresh: _pullToRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Text(
                needsChanges
                    ? 'Our compliance team needs a document corrected before they can approve you.'
                    : 'Your enterprise registration has been submitted to our compliance team.',
                style: const TextStyle(fontSize: 14, color: AppColors.inkMuted, height: 1.45),
              ),
              const SizedBox(height: 16),
              if (statusAsync.isLoading && !statusAsync.hasValue)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (statusAsync.hasError && !statusAsync.hasValue)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: InfoBanner(
                    tone: Tone.danger,
                    title: "Couldn't load your application status",
                    message: errorMessage(statusAsync.error),
                    action: AppButton(
                      label: 'Try again',
                      variant: AppButtonVariant.outline,
                      compact: true,
                      expand: false,
                      onPressed: _refresh,
                    ),
                  ),
                ),
              _StatusHero(name: name, needsChanges: needsChanges),
              if (rejected.isNotEmpty) ...[
                const SizedBox(height: 16),
                AppCard(
                  title: 'Documents to fix (${rejected.length})',
                  subtitle: 'Re-upload each one — the rest of your application stays as it is.',
                  child: Column(
                    children: [
                      for (final doc in rejected) ...[
                        _RejectedDocumentCard(
                          label: onboardingDocLabel(str(doc['documentKey'])),
                          reason: str(doc['reason']),
                          uploading: _uploading.contains(str(doc['documentKey'])),
                          onReupload: () => _reupload(str(doc['documentKey'])),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              ],
              if (needsChanges && rejected.isEmpty) ...[
                const SizedBox(height: 16),
                const InfoBanner(
                  tone: Tone.success,
                  message: 'All requested documents have been re-uploaded. Tap "Resubmit for review" below to '
                      'send it back to our team.',
                ),
              ],
              const SizedBox(height: 16),
              MessageThread(
                messages: messagesAsync.valueOrNull ?? const [],
                isLoading: messagesAsync.isLoading && !messagesAsync.hasValue,
                error: messagesAsync.hasError ? messagesAsync.error : null,
                onRetry: () => ref.invalidate(_applicationMessagesProvider),
                isSending: _sending,
                onSend: _send,
                title: 'Questions about your application?',
                subtitle: 'Message our compliance team here — replies show up on this page.',
                placeholder: 'e.g. When will my application be approved?',
              ),
              const SizedBox(height: 16),
              const _ContactLinks(),
            ],
          ),
        ),
        actions: [
          AppButton(
            label: 'Sign Out',
            variant: AppButtonVariant.outline,
            loading: _signingOut,
            onPressed: _signingOut ? null : _signOut,
          ),
          if (needsChanges)
            AppButton(
              label: _resubmitting ? 'Resubmitting…' : 'Resubmit for review',
              loading: _resubmitting,
              onPressed: rejected.isNotEmpty || _resubmitting ? null : _resubmit,
            )
          else
            const AppButton(label: 'Awaiting Admin Approval', onPressed: null),
        ],
      ),
    );
  }
}

class _StatusHero extends StatelessWidget {
  const _StatusHero({required this.name, required this.needsChanges});

  final String name;
  final bool needsChanges;

  @override
  Widget build(BuildContext context) {
    final tone = needsChanges ? Tone.danger : Tone.warning;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: tone.fg.withValues(alpha: 0.18)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tone.bg, AppColors.surface],
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(color: tone.fg.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(needsChanges ? Icons.priority_high : Icons.hourglass_top, size: 32, color: tone.fg),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.inkStrong),
          ),
          const SizedBox(height: 8),
          Text(
            needsChanges
                ? 'Everything else looks good. Re-upload the document(s) below and resubmit — you do not need to '
                    'start over.'
                : 'Your application is under review. Our team will review your documents within 24–48 business '
                    'hours. You will receive an email once your employer dashboard is unlocked.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.inkBody),
          ),
          const SizedBox(height: 18),
          const _ChecklistItem(
            icon: Icons.check,
            color: AppColors.success,
            text: 'Registration submitted',
          ),
          const SizedBox(height: 8),
          _ChecklistItem(
            icon: Icons.circle,
            iconSize: 10,
            color: tone.fg,
            text: needsChanges ? 'Changes requested — action needed' : 'Admin compliance review (24–48 hrs)',
          ),
          const SizedBox(height: 8),
          const _ChecklistItem(
            icon: Icons.circle_outlined,
            iconSize: 12,
            color: AppColors.inkFaint,
            text: 'Dashboard access unlocked',
            muted: true,
          ),
        ],
      ),
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  const _ChecklistItem({
    required this.icon,
    required this.color,
    required this.text,
    this.iconSize = 16,
    this.muted = false,
  });

  final IconData icon;
  final Color color;
  final String text;
  final double iconSize;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: muted ? AppColors.canvas : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          SizedBox(width: 18, child: Icon(icon, size: iconSize, color: color)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13.5, color: muted ? AppColors.inkFaint : AppColors.inkBody),
            ),
          ),
        ],
      ),
    );
  }
}

/// A document the admin sent back, with an inline re-upload.
class _RejectedDocumentCard extends StatelessWidget {
  const _RejectedDocumentCard({
    required this.label,
    required this.reason,
    required this.uploading,
    required this.onReupload,
  });

  final String label;
  final String reason;
  final bool uploading;
  final VoidCallback onReupload;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
      ),
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
                    Text(label,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.inkStrong)),
                    if (reason.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(reason, style: const TextStyle(fontSize: 12.5, color: AppColors.danger)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const StatusBadge('rejected', label: 'REJECTED', tone: Tone.danger),
            ],
          ),
          const SizedBox(height: 12),
          AppButton(
            label: uploading ? 'Uploading…' : 'Re-upload this document',
            icon: Icons.upload_file_outlined,
            variant: AppButtonVariant.outline,
            compact: true,
            loading: uploading,
            onPressed: uploading ? null : onReupload,
          ),
        ],
      ),
    );
  }
}

class _ContactLinks extends StatelessWidget {
  const _ContactLinks();

  @override
  Widget build(BuildContext context) {
    Widget link(IconData icon, String label, String url) => TextButton.icon(
          onPressed: () => openExternalUrl(url),
          icon: Icon(icon, size: 16),
          label: Text(label, style: const TextStyle(fontSize: 12.5)),
          style: TextButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 8)),
        );

    return Column(
      children: [
        const Text('Or reach us directly', style: TextStyle(fontSize: 12, color: AppColors.inkFaint)),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            link(Icons.mail_outline, supportEmail, 'mailto:$supportEmail'),
            link(
              Icons.chat_outlined,
              'WhatsApp $supportPhoneDisplay',
              whatsappLink('Hi PagerLook, I have a question about my company application.'),
            ),
            link(Icons.call_outlined, 'Call us', 'tel:$supportPhone'),
          ],
        ),
      ],
    );
  }
}
