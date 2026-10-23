import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import '../onboarding/widgets/journey.dart';
import 'verification_providers.dart';

/// Points per sub-item — Identity's 200 is split across its two checks.
const Map<String, int> _itemPoints = {'profile': 100, 'education': 45, 'aadhaar': 100, 'face': 100};
const int _totalPoints = 345;

/// Port of `pages/employee/IdentityVerification.jsx` — the verification hub.
class IdentityVerificationScreen extends ConsumerWidget {
  const IdentityVerificationScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    final auth = ref.read(authProvider);
    try {
      await auth.refreshEmployeeProfile();
    } catch (_) {}
    final _ = await ref.refresh(verificationStatusProvider.future);
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(context, title: 'Log out?', confirmLabel: 'Log out', destructive: true);
    if (!ok || !context.mounted) return;
    final router = GoRouter.of(context);
    await ref.read(authProvider).logout();
    router.go('/employee/otp');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(verificationStatusProvider);
    final profile = ref.watch(authProvider).profile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Identity Verification'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) {
              if (v == 'logout') _logout(context, ref);
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'logout', child: Text('Log out'))],
          ),
        ],
      ),
      body: AsyncValueView<Map<String, dynamic>>(
        value: statusAsync,
        loadingLabel: 'Loading verification...',
        onRetry: () => ref.invalidate(verificationStatusProvider),
        data: (status) => RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: _buildBody(context, ref, status, profile),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> status,
    Map<String, dynamic>? profile,
  ) {
    // Detail screens are pushed, so this hub stays mounted — refresh on return.
    Future<void> open(String to) async {
      await context.push(to);
      if (context.mounted) ref.invalidate(verificationStatusProvider);
    }

    final currentStep = str(status['currentStep'], 'profile');
    final profileIncomplete =
        status['profileSetupComplete'] == false || (currentStep == 'profile' && !asBool(status['isComplete']));

    if (profileIncomplete) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const JourneyStepCard(child: JourneyStepBar(currentStep: 'profile')),
          const SizedBox(height: 16),
          const PageIntro(title: 'Complete your profile first'),
          const SizedBox(height: 8),
          AppButton(label: 'Create Your Profile', onPressed: () => context.go('/employee/profile-setup')),
          const SecurityNote('Bank-Grade Security Protocol'),
        ],
      );
    }

    final merged = {...?profile, ...status};
    final educationDone = hasAnyEducation(merged);
    final aadhaarDone = status.containsKey('aadhaarVerified') && status['aadhaarVerified'] != null
        ? asBool(status['aadhaarVerified'])
        : asBool(profile?['aadhaarVerified']);
    final biometricDone = status.containsKey('biometricVerified') && status['biometricVerified'] != null
        ? asBool(status['biometricVerified'])
        : asBool(profile?['biometricVerified']);

    final items = <_Item>[
      const _Item(
          'profile', 'Basic details', 'Name, role, contact and location', true, '/employee/profile-setup', 'Edit'),
      _Item('education', 'Education', '10th, 12th and graduation', educationDone,
          '/employee/profile-setup?step=education', 'Add'),
      _Item('aadhaar', 'Aadhaar verification', 'Secure e-KYC via DigiLocker or OTP', aadhaarDone,
          '/employee/verification/aadhaar', 'Verify'),
      _Item('face', 'Face verification', 'A quick liveness selfie matched to your ID', biometricDone,
          '/employee/verification/biometric', 'Verify'),
    ];

    final earned = items.fold<int>(0, (sum, it) => sum + (it.done ? _itemPoints[it.key]! : 0));
    final percent = ((earned / _totalPoints) * 100).round();
    final pending = items.where((it) => !it.done).toList();
    final allDone = pending.isEmpty;
    final completed = completedJourneySteps(merged);

    final name = strOrNull(profile?['name']) ?? 'Your account';
    final veriworkId = str(profile?['veriworkId']);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        JourneyStepCard(child: JourneyStepBar(currentStep: 'identity', completed: completed)),
        const SizedBox(height: 16),
        ProgressSummaryCard(
          progress: percent / 100,
          centerLabel: '$percent%',
          title: allDone ? 'All steps complete' : '${pending.length} step${pending.length > 1 ? 's' : ''} left',
          caption: veriworkId.isEmpty ? name : '$name · $veriworkId',
        ),
        const SectionHeader('Steps'),
        for (final it in items) ...[
          _ItemTile(item: it, points: _itemPoints[it.key]!, onOpen: () => open(it.to)),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        AppButton(
          label: allDone ? 'View your score' : 'Do this later',
          variant: allDone ? AppButtonVariant.primary : AppButtonVariant.secondary,
          onPressed: () => context.go('/employee/score'),
        ),
        const SecurityNote('Bank-Grade Security Protocol'),
      ],
    );
  }
}

class _Item {
  const _Item(this.key, this.title, this.desc, this.done, this.to, this.cta);
  final String key;
  final String title;
  final String desc;
  final bool done;
  final String to;
  final String cta;
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.points, required this.onOpen});

  final _Item item;
  final int points;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: item.done ? AppColors.successBg : AppColors.canvas,
              shape: BoxShape.circle,
              border: Border.all(color: item.done ? Colors.transparent : AppColors.line),
            ),
            child: item.done ? const Icon(Icons.check_rounded, size: 20, color: AppColors.success) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.inkStrong),
                ),
                const SizedBox(height: 2),
                Text(
                  item.desc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (item.done)
            const Text('Done', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.success))
          else
            AppButton(
              label: '${item.cta} · +$points',
              variant: AppButtonVariant.secondary,
              compact: true,
              expand: false,
              onPressed: onOpen,
            ),
        ],
      ),
    );
  }
}
