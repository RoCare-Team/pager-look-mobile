import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/config/env.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/widgets.dart';

/// Public verified resume (`/u/:slug`) — port of `pages/public/PublicProfile.jsx`
/// + `components/public/PublicResume.jsx`, with the "Get Full Profile Access"
/// request form (`PublicFullAccessModal.jsx`) as a bottom sheet.
final _publicProfileProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, slug) async {
  final res = await ref.watch(publicApiProvider).fetchPublicProfile(slug);
  return asMap(res);
});

/// Score scale used by the web gauge (`employeeScoreUtils.js`).
const int _scoreMin = 300;
const int _scoreMax = 1000;

class PublicProfileScreen extends ConsumerStatefulWidget {
  const PublicProfileScreen({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends ConsumerState<PublicProfileScreen> {
  bool _accessSent = false;

  String _profileLink(Map<String, dynamic>? data) =>
      strOrNull(data?['publicProfileUrl']) ?? '${Env.appOrigin}/u/${Uri.encodeComponent(widget.slug)}';

  Future<void> _openAccessSheet(Map<String, dynamic> data) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AccessRequestSheet(slug: widget.slug, employeeName: str(data['name'], 'this professional')),
    );
    if (sent == true && mounted) setState(() => _accessSent = true);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_publicProfileProvider(widget.slug));
    final data = async.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verified profile'),
        actions: [
          if (data != null)
            IconButton(
              tooltip: 'Share profile link',
              icon: const Icon(Icons.share_outlined),
              onPressed: () => Share.share(_profileLink(data)),
            ),
        ],
      ),
      body: SafeArea(
        child: async.when(
          skipLoadingOnRefresh: true,
          loading: () => const LoadingView(label: 'Loading profile...'),
          error: (e, _) => _NotFound(
            error: e,
            onRetry: () => ref.invalidate(_publicProfileProvider(widget.slug)),
          ),
          data: (profile) => RefreshIndicator(
            onRefresh: () => ref.refresh(_publicProfileProvider(widget.slug).future),
            child: _buildBody(profile),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(Map<String, dynamic> data) {
    final name = str(data['name'], 'Professional');
    final veriworkId = str(data['veriworkId']);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (_accessSent) ...[
          InfoBanner(
            tone: Tone.success,
            message: 'Access request sent. $name will review your request and approve if appropriate.',
          ),
          const SizedBox(height: 14),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const StatusBadge(null, label: 'Verified on PagerLook', tone: Tone.success, icon: Icons.verified_user_outlined),
            if (veriworkId.isNotEmpty)
              Text('Public profile · $veriworkId', style: const TextStyle(fontSize: 12, color: AppColors.inkFaint)),
          ],
        ),
        const SizedBox(height: 14),
        _ResumeCard(profile: data),
        const SizedBox(height: 14),
        _ProtectedCard(
          emailMasked: str(data['emailMasked'], '••••@••••.com'),
          phoneMasked: str(data['phoneMasked'], '+91••••••••••'),
          onRequest: () => _openAccessSheet(data),
        ),
        const SizedBox(height: 14),
        _AtAGlance(profile: data),
        const SizedBox(height: 14),
        AppButton(
          label: 'Download resume PDF (opens web)',
          icon: Icons.download_outlined,
          variant: AppButtonVariant.outline,
          onPressed: () => openExternalUrl(_profileLink(data)),
        ),
        const SizedBox(height: 14),
        const InfoBanner(
          message: 'This resume is auto-generated from a PagerLook verified profile. Download the PDF for '
              'sharing, or request full access for hiring and background verification.',
        ),
      ],
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isNetwork = error is ApiException && (error as ApiException).isNetwork;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        const Center(child: BrandLogo(height: 32)),
        const SizedBox(height: 28),
        Text(
          isNetwork ? "Couldn't load this profile" : 'Profile not found',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.inkStrong),
        ),
        const SizedBox(height: 8),
        Text(
          errorMessage(error, 'This public profile does not exist or is not shared yet.'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.inkMuted),
        ),
        const SizedBox(height: 24),
        AppButton(label: 'Try again', icon: Icons.refresh, variant: AppButtonVariant.outline, onPressed: onRetry),
        const SizedBox(height: 10),
        AppButton(label: 'Go to PagerLook', onPressed: () => context.go('/')),
      ],
    );
  }
}

class _ResumeSection extends StatelessWidget {
  const _ResumeSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 4),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.brand600, width: 2))),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: AppColors.brand600,
              ),
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.profile});

  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final name = str(profile['name'], 'Professional');
    final meta = [profile['company'], profile['currentCity'], profile['totalExperience']]
        .map(strOrNull)
        .whereType<String>()
        .join(' · ');
    final score = asInt(profile['employeeScore']);
    final ratingLabel = str(asMap(profile['scoreRating'])['label']);
    final tags = asMapList(profile['verificationTags']);
    final skills = asList(profile['skills']).map(strOrNull).whereType<String>().toList();
    final jobs = asMapList(profile['jobs']);

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAvatar(name: name, imageUrl: strOrNull(profile['photoUrl']), size: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.inkStrong),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      str(profile['role'], 'Professional'),
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.brand600),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(meta, style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.card),
              color: AppColors.brand50,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PAGERLOOK SCORE',
                        style: TextStyle(
                          fontSize: 10.5,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkMuted,
                        ),
                      ),
                      if (ratingLabel.isNotEmpty)
                        Text(
                          ratingLabel,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkBody),
                        ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: ((score - _scoreMin) / (_scoreMax - _scoreMin)).clamp(0, 1).toDouble(),
                          minHeight: 5,
                          backgroundColor: AppColors.brand100,
                          color: AppColors.brand600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '$score',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brand600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          if (tags.isNotEmpty)
            _ResumeSection(
              title: 'Verification',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in tags)
                    StatusBadge(null, label: '✓ ${str(tag['label'])}', tone: Tone.success),
                ],
              ),
            ),
          if (skills.isNotEmpty)
            _ResumeSection(
              title: 'Skills',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final skill in skills)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.canvas,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Text(skill, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.inkBody)),
                    ),
                ],
              ),
            ),
          _ResumeSection(
            title: 'Experience',
            child: jobs.isEmpty
                ? const Text('No employment history listed.', style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < jobs.length; i++) ...[
                        if (i > 0) const SizedBox(height: 14),
                        _JobEntry(job: jobs[i]),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 10),
          Text(
            'PagerLook ID: ${str(profile['veriworkId'], '—')}',
            style: const TextStyle(fontSize: 11, color: AppColors.inkFaint),
          ),
          const SizedBox(height: 2),
          Text(
            'Verified professional profile · ${asInt(profile['verifiedJobsCount'])}/${asInt(profile['totalJobsCount'])} roles verified',
            style: const TextStyle(fontSize: 11, color: AppColors.inkFaint),
          ),
        ],
      ),
    );
  }
}

class _JobEntry extends StatelessWidget {
  const _JobEntry({required this.job});

  final Map<String, dynamic> job;

  @override
  Widget build(BuildContext context) {
    final tagLabel = strOrNull(asMap(job['verificationTag'])['label']);
    final subline = [strOrNull(job['employmentType']), tagLabel].whereType<String>().join(' · ');
    final description = strOrNull(job['description']);

    return Container(
      padding: const EdgeInsets.only(left: 12),
      decoration: const BoxDecoration(border: Border(left: BorderSide(color: AppColors.line, width: 2))),
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
                      str(job['title'], '—'),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.inkStrong),
                    ),
                    Text(str(job['company']), style: const TextStyle(fontSize: 13.5, color: AppColors.inkBody)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(null, label: str(job['duration'], '—'), tone: Tone.neutral),
            ],
          ),
          if (subline.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(subline, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
          ],
          if (description != null) ...[
            const SizedBox(height: 6),
            Text(description, style: const TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.inkBody)),
          ],
        ],
      ),
    );
  }
}

class _ProtectedCard extends StatelessWidget {
  const _ProtectedCard({required this.emailMasked, required this.phoneMasked, required this.onRequest});

  final String emailMasked;
  final String phoneMasked;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: 'Full contact & documents',
      subtitle: 'Contact details, documents, and complete verification data require employee consent.',
      action: const Icon(Icons.lock_outline, color: AppColors.brand600),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow(label: 'Email', value: emailMasked),
          InfoRow(label: 'Phone', value: phoneMasked),
          const InfoRow(label: 'Document vault', value: 'Offer letters, payslips, ID proofs'),
          const InfoRow(label: 'Background check data', value: 'Verification records & audit trail'),
          const SizedBox(height: 12),
          AppButton(label: 'Get Full Profile Access', icon: Icons.lock_open_outlined, onPressed: onRequest),
        ],
      ),
    );
  }
}

class _AtAGlance extends StatelessWidget {
  const _AtAGlance({required this.profile});

  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final company = strOrNull(profile['company']);
    final experience = strOrNull(profile['totalExperience']);
    final city = strOrNull(profile['currentCity']);
    return AppCard(
      title: 'At a glance',
      child: Column(
        children: [
          InfoRow(label: 'Role', value: str(profile['role'])),
          if (company != null) InfoRow(label: 'Company', value: company),
          if (experience != null) InfoRow(label: 'Experience', value: experience),
          if (city != null) InfoRow(label: 'Location', value: city),
          InfoRow(
            label: 'Verified roles',
            value: '${asInt(profile['verifiedJobsCount'])} / ${asInt(profile['totalJobsCount'])}',
          ),
        ],
      ),
    );
  }
}

/// Port of `PublicFullAccessModal.jsx`. Pops `true` once the request is sent.
class _AccessRequestSheet extends ConsumerStatefulWidget {
  const _AccessRequestSheet({required this.slug, required this.employeeName});

  final String slug;
  final String employeeName;

  @override
  ConsumerState<_AccessRequestSheet> createState() => _AccessRequestSheetState();
}

class _AccessRequestSheetState extends ConsumerState<_AccessRequestSheet> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _reason = TextEditingController();
  bool _pending = false;
  String _error = '';

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _reason.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _name.text.trim().length >= 2 && _email.text.trim().contains('@') && _reason.text.trim().length >= 10;

  void _changed(String _) => setState(() => _error = '');

  Future<void> _submit() async {
    if (!_canSubmit || _pending) return;
    setState(() => _pending = true);
    try {
      await ref.read(publicApiProvider).requestPublicProfileAccess(widget.slug, {
        'requesterName': _name.text,
        'requesterEmail': _email.text,
        'reason': _reason.text,
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pending = false;
        _error = e is ApiException && e.status == 409
            ? 'You already have a pending request for this profile.'
            : errorMessage(e, 'Failed to send request');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Get Full Profile Access',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.inkStrong),
              ),
              const SizedBox(height: 4),
              Text(
                "Request complete access to ${widget.employeeName}'s verified profile, contact details, and documents.",
                style: const TextStyle(fontSize: 13.5, color: AppColors.inkMuted),
              ),
              const SizedBox(height: 18),
              AppTextField(
                controller: _name,
                label: 'Your name',
                hint: 'Alex Rivera',
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                enabled: !_pending,
                onChanged: _changed,
              ),
              const SizedBox(height: 14),
              AppTextField(
                controller: _email,
                label: 'Work email',
                hint: 'hr@company.com',
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                enabled: !_pending,
                onChanged: _changed,
              ),
              const SizedBox(height: 14),
              AppTextField(
                controller: _reason,
                label: 'Why do you need profile access?',
                hint: 'e.g. We are hiring for a Senior Developer role and need to verify employment history before interview.',
                helper: 'Minimum 10 characters. ${widget.employeeName} will review and approve.',
                maxLines: 4,
                minLines: 3,
                textCapitalization: TextCapitalization.sentences,
                enabled: !_pending,
                onChanged: _changed,
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 14),
                InfoBanner(message: _error, tone: Tone.danger),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Cancel',
                      variant: AppButtonVariant.outline,
                      onPressed: _pending ? null : () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppButton(
                      label: _pending ? 'Sending...' : 'Send request',
                      loading: _pending,
                      onPressed: _canSubmit ? _submit : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
