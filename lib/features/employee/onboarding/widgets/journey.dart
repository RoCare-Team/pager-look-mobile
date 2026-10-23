import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/json.dart';

/// Port of the web's `utils/employeeJourney.js` + `VerificationStepBar.jsx`.
///
/// Three steps. Only the first is required; the other two are optional and each
/// carries score. Identity is ONE step containing two checks (Aadhaar + Face).
class JourneyStep {
  const JourneyStep({
    required this.id,
    required this.label,
    required this.title,
    required this.description,
    required this.required,
    required this.points,
    required this.path,
  });

  final String id;
  final String label;
  final String title;
  final String description;
  final bool required;
  final int points;
  final String path;
}

const List<JourneyStep> journeySteps = [
  JourneyStep(
    id: 'profile',
    label: 'Basic details',
    title: 'Your details',
    description: 'Name, role and contact details',
    required: true,
    points: 100,
    path: '/employee/profile-setup',
  ),
  JourneyStep(
    id: 'education',
    label: 'Education',
    title: 'Education',
    description: '10th, 12th and graduation',
    required: false,
    points: 45,
    path: '/employee/profile-setup?step=education',
  ),
  JourneyStep(
    id: 'identity',
    label: 'Identity',
    title: 'Aadhaar & Face',
    description: 'Aadhaar e-KYC and a live face check',
    required: false,
    points: 200,
    path: '/employee/verification',
  ),
];

/// True once at least one education level is fully filled.
bool hasAnyEducation(Map<String, dynamic>? profile) {
  final edu = asMap(profile?['education']);
  bool filled(String level, String a, String b) =>
      strOrNull(pick(edu, '$level.$a')) != null && strOrNull(pick(edu, '$level.$b')) != null;
  return filled('class10', 'board', 'school') ||
      filled('class12', 'board', 'school') ||
      filled('graduation', 'degree', 'college');
}

/// Which journey steps a profile has actually finished.
List<String> completedJourneySteps(Map<String, dynamic>? profile) {
  if (profile == null) return const [];
  return [
    if (asBool(profile['profileSetupComplete'])) 'profile',
    if (hasAnyEducation(profile)) 'education',
    if (asBool(profile['aadhaarVerified']) && asBool(profile['biometricVerified'])) 'identity',
  ];
}

enum _StepState { done, current, skipped, upcoming }

/// The one progress bar for the whole employee journey. Every step reads as
/// exactly one of: done, current, skipped, upcoming. Completion always wins.
class JourneyStepBar extends StatelessWidget {
  const JourneyStepBar({
    super.key,
    required this.currentStep,
    this.completed = const [],
    this.skipped = const [],
    this.onStepSelect,
  });

  final String currentStep;
  final List<String> completed;
  final List<String> skipped;
  final ValueChanged<String>? onStepSelect;

  _StepState _stateOf(JourneyStep step) {
    if (completed.contains(step.id) || currentStep == 'complete') return _StepState.done;
    if (step.id == currentStep) return _StepState.current;
    if (skipped.contains(step.id)) return _StepState.skipped;
    return _StepState.upcoming;
  }

  String _caption(JourneyStep step, _StepState state) => switch (state) {
        _StepState.done => 'Done',
        _StepState.skipped => 'Skipped',
        _StepState.current => 'In progress',
        _StepState.upcoming => step.required ? 'Required' : '+${step.points} pts',
      };

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < journeySteps.length; i++) {
      final step = journeySteps[i];
      final state = _stateOf(step);
      children.add(Expanded(child: _buildStep(step, i, state)));
      if (i < journeySteps.length - 1) {
        final connectorColor = switch (state) {
          _StepState.done => AppColors.success,
          _StepState.skipped => AppColors.warning.withValues(alpha: 0.5),
          _ => AppColors.line,
        };
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 17),
            child: Container(
              width: 20,
              height: 2,
              decoration: BoxDecoration(color: connectorColor, borderRadius: BorderRadius.circular(2)),
            ),
          ),
        );
      }
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _buildStep(JourneyStep step, int index, _StepState state) {
    final (Color bg, Color fg, Color border) = switch (state) {
      _StepState.done => (AppColors.success, Colors.white, AppColors.success),
      _StepState.current => (AppColors.brand600, Colors.white, AppColors.brand100),
      _StepState.skipped => (AppColors.warningBg, AppColors.warning, AppColors.warning),
      _StepState.upcoming => (AppColors.hairline, AppColors.inkFaint, AppColors.line),
    };
    final labelColor = switch (state) {
      _StepState.done => AppColors.success,
      _StepState.current => AppColors.brand600,
      _StepState.skipped => AppColors.warning,
      _StepState.upcoming => AppColors.inkFaint,
    };

    final Widget glyph = switch (state) {
      _StepState.done => Icon(Icons.check, size: 18, color: fg),
      _StepState.skipped => Icon(Icons.fast_forward, size: 16, color: fg),
      _ => Text('${index + 1}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
    };

    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: Border.all(color: border, width: state == _StepState.current ? 3 : 1.5),
            ),
            child: glyph,
          ),
          const SizedBox(height: 6),
          Text(
            step.label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: labelColor),
          ),
          const SizedBox(height: 2),
          Text(
            _caption(step, state).toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: state == _StepState.skipped ? AppColors.warning : AppColors.inkFaint,
            ),
          ),
        ],
      ),
    );

    final select = onStepSelect;
    if (select == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.control),
      onTap: () => select(step.id),
      child: content,
    );
  }
}

/// White card holding the step bar — used at the top of every journey screen.
class JourneyStepCard extends StatelessWidget {
  const JourneyStepCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.hairline),
      ),
      child: child,
    );
  }
}

/// Small "lock + text" footer the web shows under every journey page.
class SecurityNote extends StatelessWidget {
  const SecurityNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.verified_user, size: 15, color: AppColors.inkFaint),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.inkFaint, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
