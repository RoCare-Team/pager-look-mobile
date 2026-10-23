import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/home_routes.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import 'employee_portal_utils.dart';

/// `GET /employee/score` — shared so other screens can invalidate it.
final employeeScoreProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return asMap(await ref.watch(employeeApiProvider).fetchScore());
});

/// Home tab — port of `EmployeeScore.jsx`.
class EmployeeScoreScreen extends ConsumerWidget {
  const EmployeeScoreScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    try {
      await ref.read(authProvider).refreshEmployeeProfile();
    } catch (_) {
      // The score below still refreshes; the cached profile stays usable.
    }
    final _ = await ref.refresh(employeeScoreProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scoreAsync = ref.watch(employeeScoreProvider);
    final profile = ref.watch(authProvider.select((a) => a.profile));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: _pageBg,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.surface, _pageBg, _pageBg],
              stops: [0, 0.22, 0.45],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _TopBar(profile: profile),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => _refresh(ref),
                    child: AsyncValueView<Map<String, dynamic>>(
                      value: scoreAsync,
                      loadingLabel: 'Loading your score...',
                      onRetry: () => ref.invalidate(employeeScoreProvider),
                      data: (data) => _ScoreBody(data: data, profile: profile),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _pageBg = Color(0xFFF3F6FA);

/// App bar: greeting, avatar (with a verified tick), scan and notifications.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.profile});

  final Map<String, dynamic>? profile;

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final name = str(profile?['name']).trim();
    final firstName = name.isEmpty ? 'there' : name.split(RegExp(r'\s+')).first;
    final verified = isPortalUnlocked(profile);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 6),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.go('/employee/settings'),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.brand100, width: 1.5),
                  ),
                  child: AppAvatar(name: name, imageUrl: strOrNull(profile?['photoUrl']), size: 42),
                ),
                if (verified)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.verified_rounded, size: 18, color: AppColors.success),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_greeting, style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                Text(
                  firstName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: AppColors.brand900,
                  ),
                ),
              ],
            ),
          ),
          _CircleIcon(icon: Icons.qr_code_scanner_rounded, tooltip: 'Scan QR', onTap: () => context.push('/scan')),
          _CircleIcon(
            icon: Icons.notifications_none_rounded,
            tooltip: 'Activity',
            onTap: () => context.go('/employee/activity'),
          ),
        ],
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.hairline),
        ),
        child: Icon(icon, color: AppColors.brand600, size: 21),
      ),
    );
  }
}

class _ScoreBody extends StatelessWidget {
  const _ScoreBody({required this.data, required this.profile});

  final Map<String, dynamic> data;
  final Map<String, dynamic>? profile;

  @override
  Widget build(BuildContext context) {
    final unlocked = isPortalUnlocked(profile);
    final hasScore = data.isNotEmpty && data['employeeScore'] != null;

    final score = asNum(data['employeeScore']) ?? scoreMin;
    final rating = scoreRatingFor(score);
    final tags = asMapList(data['verificationTags']);
    final factors = asMapList(data['factors']);
    final missing = missingJourneySteps(profile);
    final endorsements = asMap(data['endorsements']);

    void gated(String path, {bool replaceTab = false}) {
      if (!unlocked) {
        showToast('Complete Aadhaar verification to unlock');
        return;
      }
      replaceTab ? context.go(path) : context.push(path);
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        _ScoreCard(
          score: hasScore ? score : null,
          minScore: asInt(data['minScore'], scoreMin),
          maxScore: asInt(data['maxScore'], scoreMax),
          rating: rating,
          trustPoints: data['trustPoints'] == null ? null : asInt(data['trustPoints']),
          maxTrustPoints: asInt(data['maxTrustPoints'], 1000),
          ranking: strOrNull(data['percentile']),
          endorsementCount: asInt(endorsements['count'], asInt(profile?['endorsements'])),
          tags: tags.map((t) => str(t['label'])).where((l) => l.isNotEmpty).toList(),
          onShare: () => gated('/employee/professional-id'),
          onAddJob: () => context.push('/employee/job-history/add'),
        ),
        if (!unlocked) ...[const SizedBox(height: 14), _LockedBanner()],
        if (missing.isNotEmpty) ...[
          const SizedBox(height: 14),
          _BoostBanner(
            title: 'Add ${missing.first.title}',
            points: missing.fold<int>(0, (sum, s) => sum + s.points),
            onTap: () => context.push(missing.first.path),
          ),
        ],
        const SizedBox(height: 16),
        IconGridSection(
          title: 'My Profile',
          actions: [
            GridAction(
              icon: Icons.badge_outlined,
              label: 'Professional ID',
              locked: !unlocked,
              onTap: () => gated('/employee/professional-id'),
            ),
            GridAction(
              icon: Icons.verified_user_outlined,
              label: 'Verify Identity',
              onTap: () => context.push('/employee/verification'),
            ),
            GridAction(
              icon: Icons.edit_outlined,
              label: 'Edit Profile',
              onTap: () => context.push('/employee/profile-setup'),
            ),
            GridAction(
              icon: Icons.thumb_up_alt_outlined,
              label: 'Endorse',
              onTap: () => showEndorseColleagueSheet(context),
            ),
          ],
        ),
        const SizedBox(height: 14),
        IconGridSection(
          title: 'Jobs & Documents',
          actions: [
            GridAction(
              icon: Icons.add_business_outlined,
              label: 'Add Job',
              onTap: () => context.push('/employee/job-history/add'),
            ),
            GridAction(
              icon: Icons.work_history_outlined,
              label: 'Job History',
              locked: !unlocked,
              onTap: () => gated('/employee/job-history', replaceTab: true),
            ),
            GridAction(
              icon: Icons.folder_copy_outlined,
              label: 'Document Vault',
              locked: !unlocked,
              onTap: () => gated('/employee/vault', replaceTab: true),
            ),
            GridAction(
              icon: Icons.history_outlined,
              label: 'Activity',
              locked: !unlocked,
              onTap: () => gated('/employee/activity', replaceTab: true),
            ),
          ],
        ),
        const SizedBox(height: 14),
        IconGridSection(
          title: 'Requests & Settings',
          actions: [
            GridAction(
              icon: Icons.mail_outline_rounded,
              label: 'Invitations',
              onTap: () => context.push('/employee/invitations'),
            ),
            GridAction(
              icon: Icons.key_outlined,
              label: 'Access & Consent',
              onTap: () => context.push('/employee/access-requests'),
            ),
            GridAction(
              icon: Icons.cloud_sync_outlined,
              label: 'DigiLocker',
              onTap: () => context.push('/employee/settings/digilocker'),
            ),
            GridAction(
              icon: Icons.support_agent_outlined,
              label: 'Help & Support',
              onTap: () => context.push('/employee/settings/support'),
            ),
          ],
        ),
        if (hasScore && factors.isNotEmpty) ...[
          const SizedBox(height: 14),
          _BreakdownCard(factors: factors),
        ],
      ],
    );
  }
}

/// The hero card: semicircle gauge, rating, three stats and the main actions.
class _ScoreCard extends StatelessWidget {
  const _ScoreCard({
    required this.score,
    required this.minScore,
    required this.maxScore,
    required this.rating,
    required this.trustPoints,
    required this.maxTrustPoints,
    required this.ranking,
    required this.endorsementCount,
    required this.tags,
    required this.onShare,
    required this.onAddJob,
  });

  final num? score;
  final int minScore;
  final int maxScore;
  final ScoreRating rating;
  final int? trustPoints;
  final int maxTrustPoints;
  final String? ranking;
  final int endorsementCount;
  final List<String> tags;
  final VoidCallback onShare;
  final VoidCallback onAddJob;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.hairline),
        boxShadow: const [BoxShadow(color: Color(0x120E1D4A), blurRadius: 20, offset: Offset(0, 6))],
      ),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'PagerLook Score',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.inkStrong),
            ),
          ),
          const SizedBox(height: 14),
          // The needle sweeps up from the minimum and settles on the score;
          // the number counts up alongside it. Plays once per screen open.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1800),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) {
              final shown = score == null ? null : minScore + (score! - minScore) * t;
              // The number counts up from 0 while the needle sweeps from the left end.
              final counted = score == null ? null : score! * t;
              return Column(
                children: [
                  SizedBox(
                    width: 260,
                    height: 140,
                    child: CustomPaint(
                      painter: _GaugePainter(shown, minScore: minScore, maxScore: maxScore),
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    child: Row(
                      children: [
                        Text('$minScore', style: const TextStyle(fontSize: 11, color: AppColors.inkFaint)),
                        const Spacer(),
                        Text('$maxScore', style: const TextStyle(fontSize: 11, color: AppColors.inkFaint)),
                      ],
                    ),
                  ),
                  Text(
                    counted == null ? '—' : '${counted.round()}',
                    style: const TextStyle(
                      fontSize: 46,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      color: AppColors.brand900,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (score == null)
                    const Text('Verify to get scored', style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted))
                  else
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: rating.label,
                            style: TextStyle(fontWeight: FontWeight.w700, color: rating.tone.fg),
                          ),
                          TextSpan(text: '  ·  out of $maxScore'),
                        ],
                      ),
                      style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.hairline),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  _Stat(
                    value: trustPoints == null ? '—' : '$trustPoints',
                    label: 'Trust points',
                    caption: trustPoints == null ? null : 'of $maxTrustPoints',
                  ),
                  const VerticalDivider(width: 1, thickness: 1, color: AppColors.hairline),
                  _Stat(value: _shortRanking(ranking), label: 'Ranking'),
                  const VerticalDivider(width: 1, thickness: 1, color: AppColors.hairline),
                  _Stat(value: '$endorsementCount', label: 'Endorsements'),
                ],
              ),
            ),
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (final t in tags)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.successBg, borderRadius: BorderRadius.circular(999)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.verified_rounded, size: 14, color: AppColors.success),
                        const SizedBox(width: 4),
                        Text(
                          t,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.success),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: AppButton(label: 'Share ID', icon: Icons.ios_share_rounded, compact: true, onPressed: onShare),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppButton(
                  label: 'Add Job',
                  icon: Icons.add_rounded,
                  compact: true,
                  variant: AppButtonVariant.outline,
                  onPressed: onAddJob,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The backend sends either a real ranking ("Top 40%") or a placeholder
/// sentence ("Building your ranking") — only the former fits a stat tile.
String _shortRanking(String? ranking) {
  if (ranking == null) return '—';
  return RegExp(r'\d').hasMatch(ranking) && ranking.length <= 12 ? ranking : 'New';
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.caption});

  final String value;
  final String label;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          children: [
            Text.rich(
              TextSpan(
                text: value,
                children: [
                  if (caption != null)
                    TextSpan(
                      text: ' $caption',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: AppColors.inkMuted),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.brand600),
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.inkMuted)),
          ],
        ),
      ),
    );
  }
}

/// Credit-score style gauge: one soft-coloured segment per [scoreBands]
/// entry, sized by its range, with a needle and marker at the score.
class _GaugePainter extends CustomPainter {
  _GaugePainter(this.score, {required this.minScore, required this.maxScore});

  final num? score;
  final int minScore;
  final int maxScore;

  double _fraction(num value) {
    final span = maxScore - minScore;
    return span <= 0 ? 0 : ((value - minScore) / span).clamp(0.0, 1.0).toDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    const gap = 0.035; // radians between segments
    final radius = size.width / 2 - stroke / 2 - 6;
    final center = Offset(size.width / 2, size.height - 12);
    final rect = Rect.fromCircle(center: center, radius: radius);
    Offset pointAt(double fraction, [double? r]) {
      final angle = math.pi + math.pi * fraction;
      final d = r ?? radius;
      return Offset(center.dx + d * math.cos(angle), center.dy + d * math.sin(angle));
    }

    for (var i = 0; i < scoreBands.length; i++) {
      final band = scoreBands[i];
      final isLast = i == scoreBands.length - 1;
      final start = _fraction(band.min == scoreBands.first.min ? minScore : band.min);
      final end = isLast ? 1.0 : _fraction(band.max + 1);
      if (end <= start) continue;
      final paint = Paint()
        ..color = band.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke;
      canvas.drawArc(rect, math.pi + math.pi * start, math.pi * (end - start) - (isLast ? 0 : gap), false, paint);
      // Round only the two outer ends of the whole arc.
      if (i == 0) canvas.drawCircle(pointAt(0), stroke / 2, Paint()..color = band.color);
      if (isLast) canvas.drawCircle(pointAt(1), stroke / 2, Paint()..color = band.color);
    }

    final value = score;
    if (value == null) return;
    final fraction = _fraction(value);

    // Needle from the hub towards the arc, like a watch hand.
    canvas.drawLine(
      center,
      pointAt(fraction, radius - stroke - 12),
      Paint()
        ..color = AppColors.brand900
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(center, 7, Paint()..color = AppColors.brand900);

    final knob = pointAt(fraction);
    canvas.drawCircle(knob, stroke / 2 + 5, Paint()..color = const Color(0x260E1D4A));
    canvas.drawCircle(knob, stroke / 2 + 4, Paint()..color = Colors.white);
    canvas.drawCircle(knob, stroke / 2 - 1, Paint()..color = scoreBandFor(value).color);
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.score != score || old.minScore != minScore || old.maxScore != maxScore;
}

/// Promo-style strip nudging the next optional step.
class _BoostBanner extends StatelessWidget {
  const _BoostBanner({required this.title, required this.points, required this.onTap});

  final String title;
  final int points;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF7E8),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFFDE3B4)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: const Color(0xFFFFE8BF), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.bolt_rounded, color: Color(0xFFB45309), size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.inkStrong),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Earn up to +$points points on your score',
                      style: const TextStyle(fontSize: 12, color: AppColors.inkBody),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(color: AppColors.brand50, borderRadius: BorderRadius.circular(999)),
                child: const Text(
                  'Add now',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brand600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return InfoBanner(
      tone: Tone.warning,
      icon: Icons.lock_outline,
      title: 'Verify your Aadhaar',
      message: 'Unlocks Jobs, Vault, Activity and your Professional ID.',
      action: AppButton(
        label: 'Verify now',
        compact: true,
        expand: false,
        onPressed: () => context.push('/employee/verification'),
      ),
    );
  }
}

/// All score categories in one card; tap a row to see what earns its points.
class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.factors});

  final List<Map<String, dynamic>> factors;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x0F0E1D4A), blurRadius: 16, offset: Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 16, 18, 6),
            child: Text(
              'Score Breakdown',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.brand900),
            ),
          ),
          for (var i = 0; i < factors.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 18, endIndent: 18),
            _FactorTile(factor: factors[i]),
          ],
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

/// One score category — expandable to show which items earn points.
class _FactorTile extends StatefulWidget {
  const _FactorTile({required this.factor});

  final Map<String, dynamic> factor;

  @override
  State<_FactorTile> createState() => _FactorTileState();
}

class _FactorTileState extends State<_FactorTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.factor;
    final points = asNum(f['points']) ?? 0;
    final max = asNum(f['max']) ?? 0;
    final items = asMapList(f['items']);
    final tip = strOrNull(f['tip']);
    final done = max > 0 && points >= max;

    return InkWell(
      onTap: items.isEmpty ? null : () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    str(f['label']),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.inkStrong),
                  ),
                ),
                Text.rich(
                  TextSpan(
                    text: '${points.round()}',
                    style: TextStyle(color: done ? AppColors.success : AppColors.brand600),
                    children: [
                      TextSpan(text: ' / ${max.round()}', style: const TextStyle(color: AppColors.inkFaint)),
                    ],
                  ),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
                if (items.isNotEmpty)
                  Icon(
                    _open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    size: 22,
                    color: AppColors.inkFaint,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: max <= 0 ? 0 : (points / max).clamp(0, 1).toDouble(),
                minHeight: 6,
                backgroundColor: AppColors.skyBg,
                color: done ? AppColors.success : AppColors.brand600,
              ),
            ),
            if (tip != null && !done)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(tip, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
              ),
            if (_open && items.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final it in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        asBool(it['done']) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        size: 16,
                        color: asBool(it['done']) ? AppColors.success : AppColors.inkFaint,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          str(it['label']),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: asBool(it['done']) ? AppColors.inkBody : AppColors.inkFaint,
                          ),
                        ),
                      ),
                      Text(
                        '${asInt(it['points'])}/${asInt(it['max'])}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: asBool(it['done']) ? AppColors.success : AppColors.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Endorse a colleague (web `EndorseColleagueModal.jsx`) ─────────────────

const Map<String, String> _relationships = {
  'colleague': 'Colleague',
  'manager': 'Manager',
  'hr': 'HR',
  'other': 'Other',
};

Future<void> showEndorseColleagueSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _EndorseSheet(),
  );
}

class _EndorseSheet extends ConsumerStatefulWidget {
  const _EndorseSheet();

  @override
  ConsumerState<_EndorseSheet> createState() => _EndorseSheetState();
}

class _EndorseSheetState extends ConsumerState<_EndorseSheet> {
  final _idController = TextEditingController();
  final _messageController = TextEditingController();
  String _relationship = 'colleague';
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _idController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _idController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      final message = _messageController.text.trim();
      await ref.read(employeeApiProvider).createEndorsement({
        'veriworkId': _idController.text.trim(),
        'relationship': _relationship,
        if (message.isNotEmpty) 'message': message,
      });
      showToast('Endorsement sent successfully', type: ToastType.success);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      showErrorToast(e, 'Failed to send endorsement');
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Endorse a colleague', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text('Enter their PagerLook ID to endorse them.', style: TextStyle(color: AppColors.inkMuted)),
            const SizedBox(height: 18),
            AppTextField(
              controller: _idController,
              label: 'PagerLook ID',
              hint: 'e.g. VW-ABC123',
              enabled: !_sending,
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 14),
            AppDropdown<String>(
              label: 'Relationship',
              options: _relationships,
              value: _relationship,
              enabled: !_sending,
              onChanged: (v) => setState(() => _relationship = v ?? 'colleague'),
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _messageController,
              label: 'Message (optional)',
              hint: 'Why are you endorsing them?',
              maxLines: 3,
              enabled: !_sending,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.outline,
                    onPressed: _sending ? null : () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    label: 'Send Endorsement',
                    loading: _sending,
                    onPressed: _idController.text.trim().isEmpty ? null : _send,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
