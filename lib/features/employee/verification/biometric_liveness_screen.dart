import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/upload.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import '../onboarding/widgets/journey.dart';
import 'face_scan_camera.dart';
import 'verification_providers.dart';

/// Port of `pages/employee/BiometricLiveness.jsx`. One guided camera session
/// ([openFaceScan]) captures the straight / left / right frames, then the
/// match runs straight away — the `center` frame is matched against Aadhaar.
class BiometricLivenessScreen extends ConsumerStatefulWidget {
  const BiometricLivenessScreen({super.key});

  @override
  ConsumerState<BiometricLivenessScreen> createState() => _BiometricLivenessScreenState();
}

class _BiometricLivenessScreenState extends ConsumerState<BiometricLivenessScreen> {
  bool _matching = false;
  String? _error;
  Map<String, dynamic>? _result;

  Future<void> _scan() async {
    if (_matching) return;
    final frames = await openFaceScan(context);
    if (frames == null || !mounted) return;
    for (final frame in frames.values) {
      final invalid = validateImage(frame, maxBytes: maxPhotoBytes);
      if (invalid != null) {
        setState(() => _error = invalid);
        return;
      }
    }
    await _runMatch(frames);
  }

  Future<void> _runMatch(Map<String, PickedDoc> frames) async {
    final selfie = frames['center'];
    final left = frames['left'];
    final right = frames['right'];
    if (_matching || selfie == null || left == null || right == null) return;

    final api = ref.read(employeeApiProvider);
    final auth = ref.read(authProvider);
    setState(() {
      _matching = true;
      _error = null;
    });
    try {
      final data = asMap(await api.verifyBiometric(selfie, [left, right]));
      final profile = auth.profile;
      if (profile != null) {
        await auth.updateProfile({
          ...profile,
          'biometricVerified': true,
          'photoUrl': strOrNull(profile['photoUrl']) ?? data['photoUrl'],
          'isVerified': true,
        });
      }
      if (!mounted) return;
      setState(() => _result = data);
      showToast(strOrNull(data['message']) ?? 'Face matched', type: ToastType.success);
      invalidateVerification(ref);
      try {
        await auth.refreshEmployeeProfile();
      } catch (_) {}
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Face match failed'));
    } finally {
      if (mounted) setState(() => _matching = false);
    }
  }

  Future<void> _refresh() async {
    final auth = ref.read(authProvider);
    try {
      await auth.refreshEmployeeProfile();
    } catch (_) {}
    if (!mounted) return;
    final _ = await ref.refresh(aadhaarSubmissionProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final aadhaarAsync = ref.watch(aadhaarSubmissionProvider);
    final profile = ref.watch(authProvider).profile;

    return Scaffold(
      appBar: AppBar(title: const Text('Face match')),
      body: AsyncValueView<Map<String, dynamic>>(
        value: aadhaarAsync,
        loadingLabel: 'Checking your Aadhaar status...',
        onRetry: () => ref.invalidate(aadhaarSubmissionProvider),
        data: (aadhaar) => BusyOverlay(
          busy: _matching,
          label: 'Matching your face...',
          child: _buildBody(aadhaar, profile),
        ),
      ),
    );
  }

  Widget _buildBody(Map<String, dynamic> aadhaar, Map<String, dynamic>? profile) {
    final aadhaarApproved = str(aadhaar['status']) == 'approved';
    final alreadyVerified = asBool(profile?['biometricVerified']);
    final showCapture = aadhaarApproved && _result == null && !alreadyVerified;

    final List<Widget> content;
    if (!aadhaarApproved) {
      content = [
        InfoBanner(
          tone: Tone.warning,
          title: 'Verify Aadhaar first',
          message: str(aadhaar['status']) == 'pending'
              ? 'Face match unlocks once your Aadhaar is approved.'
              : 'Face match needs an approved Aadhaar.',
          action: TextButton(
            onPressed: () => context.push('/employee/verification/aadhaar'),
            child: const Text('Go to Aadhaar →'),
          ),
        ),
      ];
    } else if (_result != null) {
      content = [_buildResult(_result!), const SizedBox(height: 16), _scoreButton()];
    } else if (alreadyVerified) {
      content = [
        const InfoBanner(
          tone: Tone.success,
          icon: Icons.verified_user,
          title: 'Face match complete',
          message: 'Your face is matched to your Aadhaar.',
        ),
        const SizedBox(height: 16),
        _scoreButton(),
      ];
    } else {
      content = _buildScanIntro();
    }

    final list = RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          JourneyStepCard(child: JourneyStepBar(currentStep: 'identity', completed: completedJourneySteps(profile))),
          const SizedBox(height: 16),
          ...content,
        ],
      ),
    );

    if (!showCapture) return list;

    return Column(
      children: [
        Expanded(child: list),
        Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.hairline)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: AppButton(
                label: _error != null ? 'Scan again' : 'Start face scan',
                icon: Icons.photo_camera_outlined,
                loading: _matching,
                onPressed: _matching ? null : _scan,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _scoreButton() => AppButton(label: 'See your score', onPressed: () => context.go('/employee/score'));

  Widget _buildResult(Map<String, dynamic> result) {
    final captureOnly = str(result['provider']) == 'capture';
    return InfoBanner(
      tone: Tone.success,
      icon: Icons.verified_user,
      title: captureOnly ? 'Face captured' : 'Face matched',
      message: captureOnly
          ? 'Your face check is complete.'
          : '${str(result['similarity'], '0')}% match with your Aadhaar photo',
    );
  }

  /// The pre-scan screen: one illustration, one line, the three moves.
  List<Widget> _buildScanIntro() {
    return [
      if (_error != null) ...[
        InfoBanner(tone: Tone.danger, message: _error!),
        const SizedBox(height: 8),
      ],
      const SizedBox(height: 24),
      Center(
        child: Container(
          width: 120,
          height: 120,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.skyBg),
          child: const Icon(Icons.face_retouching_natural, size: 60, color: AppColors.brand600),
        ),
      ),
      const SizedBox(height: 24),
      const Text(
        'Quick face scan',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.brand900),
      ),
      const SizedBox(height: 8),
      const Text(
        'Takes about 10 seconds',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14.5, color: AppColors.inkMuted),
      ),
      const SizedBox(height: 28),
      const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _MoveChip(icon: Icons.face_outlined, label: 'Straight'),
          SizedBox(width: 10),
          _MoveChip(icon: Icons.arrow_back_rounded, label: 'Left'),
          SizedBox(width: 10),
          _MoveChip(icon: Icons.arrow_forward_rounded, label: 'Right'),
        ],
      ),
    ];
  }
}

class _MoveChip extends StatelessWidget {
  const _MoveChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Icon(icon, size: 24, color: AppColors.brand600),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkStrong)),
        ],
      ),
    );
  }
}
