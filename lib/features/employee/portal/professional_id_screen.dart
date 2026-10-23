import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/home_routes.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import 'employee_portal_utils.dart';

final _professionalIdProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return asMap(await ref.watch(employeeApiProvider).fetchProfessionalId());
});

/// Port of `ProfessionalId.jsx` + `ProfessionalIdCard.jsx`. On mobile the
/// public profile link is shared (and shown as a QR) instead of printed.
class ProfessionalIdScreen extends ConsumerWidget {
  const ProfessionalIdScreen({super.key});

  void _share(String url, String name) {
    if (url.isEmpty) {
      showToast('Public profile link is not available yet', type: ToastType.error);
      return;
    }
    Share.share(
      name.isEmpty ? url : '$name — verified PagerLook profile: $url',
      subject: 'My PagerLook Professional ID',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlocked = isPortalUnlocked(ref.watch(authProvider.select((a) => a.profile)));
    final idAsync = ref.watch(_professionalIdProvider);
    final loaded = idAsync.valueOrNull;
    final url = loaded == null ? '' : buildPublicProfileUrl(loaded);

    if (!unlocked) {
      return Scaffold(
        appBar: AppBar(title: const Text('Professional ID')),
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Complete Aadhaar verification to unlock',
          message: 'Your Professional ID becomes available once your identity is verified.',
          action: AppButton(
            label: 'Go to verification',
            expand: false,
            onPressed: () => context.push('/employee/verification'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Professional ID'),
        actions: [
          if (url.isNotEmpty)
            IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.ios_share),
              onPressed: () => _share(url, str(loaded?['name'])),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(_professionalIdProvider.future),
        child: AsyncValueView<Map<String, dynamic>>(
          value: idAsync,
          loadingLabel: 'Loading professional ID...',
          onRetry: () => ref.invalidate(_professionalIdProvider),
          data: (data) {
            if (data.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  EmptyState(
                    icon: Icons.badge_outlined,
                    title: 'No profile data found',
                    message: 'Complete your profile to generate your Professional ID.',
                  ),
                ],
              );
            }
            return _Body(data: data, url: url, onShare: () => _share(url, str(data['name'])));
          },
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.data, required this.url, required this.onShare});

  final Map<String, dynamic> data;
  final String url;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final veriworkId = strOrNull(data['veriworkId']);
    final identity = publicProfileIdentity(data);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _IdCard(data: data, url: url),
        const SizedBox(height: 16),
        Center(
          child: TextButton.icon(
            onPressed: () => context.push('/employee/profile-setup'),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit Identity Details'),
          ),
        ),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.verified_user_outlined, size: 16, color: AppColors.inkMuted),
            SizedBox(width: 6),
            Text('Cryptographically signed document.', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
          ],
        ),
        if (veriworkId != null) ...[
          const SizedBox(height: 16),
          AppCard(
            color: AppColors.warningBg,
            borderColor: AppColors.warning.withValues(alpha: 0.2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Eyebrow('Your PagerLook ID', color: AppColors.warning),
                const SizedBox(height: 4),
                SelectableText(
                  veriworkId,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.inkStrong),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Share this ID so colleagues and managers can endorse you on PagerLook Score.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkBody),
                ),
                const SizedBox(height: 8),
                AppButton(
                  label: 'Copy PagerLook ID',
                  icon: Icons.copy,
                  variant: AppButtonVariant.ghost,
                  expand: false,
                  compact: true,
                  onPressed: () => copyToClipboard(veriworkId, message: 'PagerLook ID copied'),
                ),
              ],
            ),
          ),
        ],
        if (url.isNotEmpty) ...[
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Public Profile Link', style: TextStyle(fontSize: 12, color: AppColors.inkFaint)),
                const SizedBox(height: 4),
                Text(
                  url,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.brand600),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Copy',
                        icon: Icons.link,
                        variant: AppButtonVariant.outline,
                        compact: true,
                        onPressed: () => copyToClipboard(url, message: 'Link copied!'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppButton(
                        label: 'Open',
                        icon: Icons.open_in_new,
                        variant: AppButtonVariant.outline,
                        compact: true,
                        onPressed: () => context.push('/u/${Uri.encodeComponent(identity)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppButton(
                        label: 'Share',
                        icon: Icons.ios_share,
                        compact: true,
                        onPressed: onShare,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        AppButton(
          label: 'View Job History',
          icon: Icons.work_outline,
          onPressed: () => context.go('/employee/job-history'),
        ),
      ],
    );
  }
}

/// The navy ID card (web `ProfessionalIdCard.jsx`) with a QR of the public link.
class _IdCard extends StatelessWidget {
  const _IdCard({required this.data, required this.url});

  final Map<String, dynamic> data;
  final String url;

  @override
  Widget build(BuildContext context) {
    final name = str(data['name']);
    final role = strOrNull(data['role']);
    final company = strOrNull(data['company']);
    final experience = strOrNull(data['experience']);
    final score = data['employeeScore'] ?? data['trustScore'];
    final verifiedJobs = asInt(data['verifiedJobsCount'] ?? data['verifiedJobs']);
    final totalJobs = data['totalJobsCount'];
    final skills = asList(data['skills']).map((s) => str(s)).where((s) => s.isNotEmpty).toList();
    const onDark = AppColors.inkStrong;
    const muted = AppColors.inkMuted;

    Widget stat(String value, String label) => Expanded(
          child: Column(
            children: [
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: onDark)),
              const SizedBox(height: 2),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: muted)),
            ],
          ),
        );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: [
          Container(height: 5, color: AppColors.brand600),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                      child: AppAvatar(name: name, imageUrl: strOrNull(data['photoUrl']), size: 92),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.verified_user, size: 14, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: onDark),
                ),
                if (role != null) ...[
                  const SizedBox(height: 2),
                  Text(role, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: muted)),
                ],
                if (company != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.apartment, size: 14, color: muted),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          experience == null ? company : '$company • $experience',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: muted),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                const Divider(height: 1),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    stat(score == null ? '—' : '${asInt(score)}', 'PagerLook Score'),
                    stat(totalJobs == null ? '$verifiedJobs' : '$verifiedJobs/${asInt(totalJobs)}', 'Verified Jobs'),
                    stat('${asInt(data['endorsements'])}', 'Endorsements'),
                  ],
                ),
                if (skills.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 14),
                  const Text(
                    'CORE PROFICIENCIES',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: muted),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: skills
                        .map(
                          (s) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.brand50,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(s,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.brand600)),
                          ),
                        )
                        .toList(),
                  ),
                ],
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: Column(
                    children: [
                      if (url.isNotEmpty) ...[
                        QrImageView(
                          data: url,
                          version: QrVersions.auto,
                          size: 160,
                          backgroundColor: AppColors.canvas,
                          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: AppColors.brand900),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: AppColors.brand900,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        'ID: ${str(data['veriworkId'], '—')}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.inkStrong),
                      ),
                      const SizedBox(height: 2),
                      const Text('Scan to verify profile', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
