import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/widgets.dart';

/// Web `getScoreRating` (employeeScoreUtils.js) — label + tone for a PagerLook score.
class ScoreRatingInfo {
  const ScoreRatingInfo(this.label, this.tone);
  final String label;
  final Tone tone;
}

ScoreRatingInfo scoreRating(num score) {
  if (score >= 951) return const ScoreRatingInfo('Elite Trust', Tone.brand);
  if (score >= 851) return const ScoreRatingInfo('Excellent', Tone.success);
  if (score >= 751) return const ScoreRatingInfo('Good', Tone.info);
  if (score >= 601) return const ScoreRatingInfo('Fair', Tone.warning);
  if (score >= 451) return const ScoreRatingInfo('Needs Improvement', Tone.warning);
  return const ScoreRatingInfo('High Risk', Tone.danger);
}

/// Score tile shown on candidate cards (web `CandidateRequestCard` score box).
class ScoreChip extends StatelessWidget {
  const ScoreChip({super.key, required this.score});

  final num score;

  @override
  Widget build(BuildContext context) {
    final rating = scoreRating(score);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: rating.tone.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: rating.tone.fg.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${score.round()}',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: rating.tone.fg),
          ),
          const Text(
            'PAGERLOOK SCORE',
            style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: AppColors.inkFaint),
          ),
        ],
      ),
    );
  }
}

/// Prev / page x of y / Next — web `enterprise/Pagination.jsx`.
class PaginationBar extends StatelessWidget {
  const PaginationBar({
    super.key,
    required this.page,
    required this.totalPages,
    this.total = 0,
    required this.onPageChange,
  });

  final int page;
  final int totalPages;
  final int total;
  final ValueChanged<int> onPageChange;

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          AppButton(
            label: 'Prev',
            icon: Icons.chevron_left,
            variant: AppButtonVariant.outline,
            compact: true,
            expand: false,
            onPressed: page <= 1 ? null : () => onPageChange(page - 1),
          ),
          Expanded(
            child: Text(
              total > 0 ? 'Page $page of $totalPages · $total total' : 'Page $page of $totalPages',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
            ),
          ),
          AppButton(
            label: 'Next',
            icon: Icons.chevron_right,
            variant: AppButtonVariant.outline,
            compact: true,
            expand: false,
            onPressed: page >= totalPages ? null : () => onPageChange(page + 1),
          ),
        ],
      ),
    );
  }
}
