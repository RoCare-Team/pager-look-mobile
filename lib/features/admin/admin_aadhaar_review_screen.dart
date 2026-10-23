import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/widgets.dart';
import 'admin_aadhaar_requests_screen.dart' show adminAadhaarRequestsProvider;
import 'admin_dashboard_screen.dart' show adminDashboardProvider;
import 'widgets/image_viewer.dart';

final adminAadhaarRequestProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  return asMap(await ref.watch(adminApiProvider).fetchAadhaarRequest(id));
});

/// Port of `pages/admin/AdminAadhaarReview.jsx`.
class AdminAadhaarReviewScreen extends ConsumerStatefulWidget {
  const AdminAadhaarReviewScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<AdminAadhaarReviewScreen> createState() => _AdminAadhaarReviewScreenState();
}

class _AdminAadhaarReviewScreenState extends ConsumerState<AdminAadhaarReviewScreen> {
  final _reason = TextEditingController();
  final _notes = TextEditingController();
  String _formError = '';
  bool _submitting = false;

  @override
  void dispose() {
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _decide(String status) async {
    FocusScope.of(context).unfocus();
    if (status == 'rejected' && _reason.text.trim().isEmpty) {
      setState(() => _formError = 'Add a reason so the employee knows what to fix');
      return;
    }
    setState(() {
      _formError = '';
      _submitting = true;
    });
    try {
      await ref.read(adminApiProvider).reviewAadhaarRequest(
            widget.id,
            status: status,
            reason: _reason.text,
            notes: _notes.text,
          );
      ref.invalidate(adminAadhaarRequestProvider(widget.id));
      ref.invalidate(adminAadhaarRequestsProvider);
      ref.invalidate(adminDashboardProvider);
      showToast(
        status == 'approved' ? 'Aadhaar approved' : 'Aadhaar rejected',
        type: status == 'approved' ? ToastType.success : ToastType.info,
      );
      if (mounted) context.go('/admin/aadhaar-requests');
    } catch (e) {
      if (mounted) {
        setState(() {
          _formError = errorMessage(e, 'Could not save the decision');
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(adminAadhaarRequestProvider(widget.id));

    return Scaffold(
      appBar: AppBar(title: const Text('Aadhaar review')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(adminAadhaarRequestProvider(widget.id).future),
        child: value.when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          loading: () => const LoadingView(label: 'Loading submission...'),
          error: (e, _) => ErrorView(
            error: e,
            title: 'Submission not found',
            onRetry: () => ref.invalidate(adminAadhaarRequestProvider(widget.id)),
          ),
          data: _buildBody,
        ),
      ),
    );
  }

  Widget _buildBody(Map<String, dynamic> request) {
    final employee = request['employee'] is Map ? asMap(request['employee']) : null;
    final status = str(request['status'], 'pending');
    final decided = status != 'pending';
    final submissionCount = asInt(request['submissionCount']);
    final faceMatch = asMap(request['faceMatch']);
    final faceVerified = faceMatch['verifiedAt'] != null;
    final selfie = mediaUrl(faceMatch['selfieUrl']);
    final employeeId = employee == null ? '' : idOf(employee);
    final dob = strOrNull(request['dobOnAadhaar']);
    final reviewerEmail = strOrNull(pick(request, 'reviewedBy.email'));

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strOrNull(employee?['name']) ?? 'Unknown employee', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                '${str(employee?['email'], '—')} · ${str(employee?['phone'], '—')}',
                style: const TextStyle(fontSize: 13.5, color: AppColors.inkMuted),
              ),
              if (strOrNull(employee?['veriworkId']) != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    str(employee?['veriworkId']),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColors.inkFaint),
                  ),
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusBadge(status),
                  if (submissionCount > 1)
                    StatusBadge('attempt', tone: Tone.neutral, label: 'Attempt $submissionCount'),
                ],
              ),
              if (employeeId.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => context.push('/admin/employees/$employeeId'),
                    child: const Text('Full profile →'),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          title: 'Card images',
          subtitle: 'Confirm the number and name below appear exactly like this on the card.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminImageTile(label: 'Front', path: strOrNull(request['frontImageUrl'])),
              const SizedBox(height: 14),
              AdminImageTile(label: 'Back', path: strOrNull(request['backImageUrl'])),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          title: 'Declared details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InfoRow(
                label: 'Aadhaar number',
                valueWidget: Text(
                  str(request['aadhaarNumber'], '—'),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5, color: AppColors.inkStrong),
                ),
              ),
              _FlagRow(
                label: 'Name on card',
                value: str(request['nameOnAadhaar']),
                flag: employee != null && !asBool(employee['profileNameMatches']) ? 'differs from profile' : null,
              ),
              _FlagRow(
                label: 'Date of birth',
                value: dob ?? '',
                flag: employee != null && dob != null && !asBool(employee['profileDobMatches'])
                    ? 'differs from profile'
                    : null,
              ),
              InfoRow(label: 'Gender', value: str(request['genderOnAadhaar'])),
              InfoRow(label: 'Address', value: str(request['addressOnAadhaar'])),
              InfoRow(label: 'Consent given', value: asBool(request['consentAccepted']) ? 'Yes' : 'No'),
              InfoRow(label: 'Submitted', value: formatDate(request['submittedAt'])),
              InfoRow(label: 'Profile name', value: str(employee?['name'])),
              InfoRow(label: 'Profile date of birth', value: str(employee?['dateOfBirth'])),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          title: 'Face match',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InfoRow(
                label: 'Result',
                value: faceVerified
                    ? 'Matched at ${str(faceMatch['similarity'], '0')}% (needed ${str(faceMatch['threshold'], '0')}%)'
                    : 'Not run yet',
              ),
              InfoRow(label: 'Provider', value: str(faceMatch['provider'])),
              InfoRow(
                label: 'Liveness',
                value: faceVerified ? (asBool(faceMatch['livenessPassed']) ? 'Passed' : 'Failed') : '',
              ),
              InfoRow(label: 'Attempts', value: '${asInt(faceMatch['attempts'])}'),
              if (selfie != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () => showImageViewer(context, selfie, title: 'Verified selfie'),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.card),
                      child: Image.network(
                        selfie,
                        width: 128,
                        height: 128,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 128,
                          height: 128,
                          color: AppColors.canvas,
                          child: const Icon(Icons.broken_image_outlined, color: AppColors.inkFaint),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          title: 'Decision',
          child: decided
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${status == 'approved' ? 'Approved' : 'Rejected'} on ${formatDate(request['reviewedAt'])}'
                      '${reviewerEmail != null ? ' by $reviewerEmail' : ''}.',
                      style: const TextStyle(fontSize: 14, color: AppColors.inkBody),
                    ),
                    if (strOrNull(request['rejectionReason']) != null) ...[
                      const SizedBox(height: 10),
                      InfoBanner(tone: Tone.danger, message: str(request['rejectionReason'])),
                    ],
                    if (strOrNull(request['reviewNotes']) != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Internal note: ${str(request['reviewNotes'])}',
                        style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
                      ),
                    ],
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_formError.isNotEmpty) ...[
                      InfoBanner(tone: Tone.danger, message: _formError),
                      const SizedBox(height: 12),
                    ],
                    AppTextField(
                      controller: _reason,
                      label: 'Rejection reason',
                      hint: 'Shown to the employee — e.g. back image is blurry, number does not match the card',
                      maxLines: 3,
                      minLines: 3,
                      maxLength: 500,
                      enabled: !_submitting,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _notes,
                      label: 'Internal note (optional)',
                      hint: 'Only visible to admins',
                      maxLines: 3,
                      minLines: 3,
                      maxLength: 1000,
                      enabled: !_submitting,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 16),
                    AppButton(
                      label: _submitting ? 'Saving...' : 'Approve Aadhaar',
                      loading: _submitting,
                      icon: Icons.check,
                      onPressed: _submitting ? null : () => _decide('approved'),
                    ),
                    const SizedBox(height: 10),
                    AppButton(
                      label: 'Reject',
                      variant: AppButtonVariant.danger,
                      onPressed: _submitting ? null : () => _decide('rejected'),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Approving marks the employee Aadhaar-verified and unlocks the face match against the photo on this card.',
                      style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Detail row with an amber "differs from profile" flag (web `DetailRow flag`).
class _FlagRow extends StatelessWidget {
  const _FlagRow({required this.label, required this.value, this.flag});

  final String label;
  final String value;
  final String? flag;

  @override
  Widget build(BuildContext context) {
    return InfoRow(
      label: label,
      valueWidget: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: value.isEmpty ? '—' : value),
            if (flag != null)
              TextSpan(
                text: '  $flag',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.warning),
              ),
          ],
        ),
        textAlign: TextAlign.right,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.inkStrong),
      ),
    );
  }
}
