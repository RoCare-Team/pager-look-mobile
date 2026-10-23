import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/home_routes.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';

/// `GET /employee/settings` — `{ notificationsEnabled, publicProfileEnabled, language, veriworkId }`.
final employeeSettingsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return asMap(await ref.watch(employeeApiProvider).fetchSettings());
});

const Map<String, String> _languages = {
  'en-US': 'English (US)',
  'en-IN': 'English (India)',
  'hi-IN': 'Hindi',
};

/// PATCH body exactly as the web builds it in `EmployeeSettings.jsx`.
Map<String, dynamic> buildSettingsPatch(
  Map<String, dynamic> settings, {
  bool? notificationsEnabled,
  bool? publicProfileEnabled,
  String? language,
}) {
  return {
    'notificationsEnabled': notificationsEnabled ?? (settings['notificationsEnabled'] == null ? true : asBool(settings['notificationsEnabled'])),
    'publicProfileEnabled': publicProfileEnabled ?? (settings['publicProfileEnabled'] == null ? true : asBool(settings['publicProfileEnabled'])),
    'language': language ?? str(settings['language'], 'en-US'),
  };
}

/// Account tab — port of `EmployeeSettings.jsx`, plus the sidebar links the
/// web shows on wide screens.
class EmployeeSettingsScreen extends ConsumerStatefulWidget {
  const EmployeeSettingsScreen({super.key});

  @override
  ConsumerState<EmployeeSettingsScreen> createState() => _EmployeeSettingsScreenState();
}

class _EmployeeSettingsScreenState extends ConsumerState<EmployeeSettingsScreen> {
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // The web refetches the profile on this page.
    Future.microtask(_refreshProfile);
  }

  Future<void> _refreshProfile() async {
    try {
      await ref.read(authProvider).refreshEmployeeProfile();
    } catch (_) {
      // Keep showing the cached session profile.
    }
  }

  Future<void> _refresh() async {
    await _refreshProfile();
    final _ = await ref.refresh(employeeSettingsProvider.future);
  }

  Future<void> _patch(Map<String, dynamic> body) async {
    setState(() => _saving = true);
    try {
      await ref.read(employeeApiProvider).updateSettings(body);
      ref.invalidate(employeeSettingsProvider);
      showToast('Settings updated', type: ToastType.success);
    } catch (e) {
      showErrorToast(e, 'Failed to update settings');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Sign out?',
      message: 'You will need to verify your mobile number again to sign in.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await ref.read(authProvider).logout();
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authProvider.select((a) => a.profile));
    final unlocked = isPortalUnlocked(profile);
    final settingsAsync = ref.watch(employeeSettingsProvider);
    final settings = settingsAsync.valueOrNull;

    void gated(String path) {
      if (!unlocked) {
        showToast('Complete Aadhaar verification to unlock');
        return;
      }
      context.push(path);
    }

    final name = str(profile?['name'], 'Your profile');
    final role = strOrNull(profile?['role']);
    final veriworkId = strOrNull(settings?['veriworkId']) ?? strOrNull(profile?['veriworkId']);
    final score = profile?['employeeScore'];

    Widget preferences;
    if (settings == null) {
      preferences = settingsAsync.hasError
          ? AppCard(
              child: ErrorView(
                error: settingsAsync.error,
                title: "Couldn't load preferences",
                onRetry: () => ref.invalidate(employeeSettingsProvider),
              ),
            )
          : const AppCard(child: LoadingView(label: 'Loading settings...'));
    } else {
      final notifications = settings['notificationsEnabled'] == null ? true : asBool(settings['notificationsEnabled']);
      final publicProfile = settings['publicProfileEnabled'] == null ? true : asBool(settings['publicProfileEnabled']);
      final language = str(settings['language'], 'en-US');
      preferences = MenuSection(
        title: 'Preferences',
        children: [
          MenuTile(
            icon: Icons.notifications_none,
            title: 'Notification Settings',
            trailing: Switch(
              value: notifications,
              onChanged: _saving ? null : (v) => _patch(buildSettingsPatch(settings, notificationsEnabled: v)),
            ),
          ),
          MenuTile(
            icon: Icons.language,
            title: 'Language',
            subtitle: 'Preferred app language',
            trailing: DropdownButton<String>(
              value: _languages.containsKey(language) ? language : null,
              underline: const SizedBox.shrink(),
              hint: const Text('Select'),
              items: _languages.entries
                  .map((e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: _saving
                  ? null
                  : (v) {
                      if (v != null && v != language) _patch(buildSettingsPatch(settings, language: v));
                    },
            ),
          ),
          MenuTile(
            icon: Icons.public,
            title: 'Public Profile Visibility',
            trailing: Switch(
              value: publicProfile,
              onChanged: _saving ? null : (v) => _patch(buildSettingsPatch(settings, publicProfileEnabled: v)),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings & Support')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            AppCard(
              onTap: () => context.push('/employee/profile-setup'),
              child: Row(
                children: [
                  Stack(
                    children: [
                      AppAvatar(name: name, imageUrl: strOrNull(profile?['photoUrl']), size: 64),
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.brand600),
                        ),
                        if (role != null)
                          Text(role, style: const TextStyle(fontSize: 13.5, color: AppColors.inkMuted)),
                        if (veriworkId != null)
                          Text(veriworkId, style: const TextStyle(fontSize: 12, color: AppColors.inkFaint)),
                        if (score != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: StatusBadge(
                              null,
                              label: 'PagerLook Score ${asInt(score)}',
                              tone: Tone.success,
                              icon: Icons.verified_user_outlined,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.edit_outlined, color: AppColors.brand600),
                ],
              ),
            ),
            if (!unlocked) ...[
              const SizedBox(height: 12),
              InfoBanner(
                tone: Tone.warning,
                icon: Icons.lock_outline,
                message: 'Complete Aadhaar verification to unlock your Professional ID, Job History, Vault and Activity.',
                action: AppButton(
                  label: 'Continue verification',
                  compact: true,
                  expand: false,
                  onPressed: () => context.push('/employee/verification'),
                ),
              ),
            ],
            MenuSection(
              title: 'Account & Security',
              children: [
                MenuTile(
                  icon: Icons.person_outline,
                  title: 'Personal Information',
                  subtitle: 'Name, Email, Phone',
                  locked: !unlocked,
                  onTap: () => gated('/employee/professional-id'),
                ),
                MenuTile(
                  icon: Icons.mail_outline,
                  title: 'Email & Verification Sending',
                  subtitle: 'SMTP mailbox for self-verification',
                  onTap: () => context.push('/employee/settings/email'),
                ),
                MenuTile(
                  icon: Icons.lock_outline,
                  title: 'Privacy & Security',
                  subtitle: 'Consent, visibility, sessions',
                  onTap: () => context.push('/employee/settings/privacy'),
                ),
                MenuTile(
                  icon: Icons.cloud_outlined,
                  title: 'DigiLocker',
                  subtitle: 'Link government-issued documents',
                  onTap: () => context.push('/employee/settings/digilocker'),
                ),
              ],
            ),
            MenuSection(
              title: 'Profile',
              children: [
                MenuTile(
                  icon: Icons.badge_outlined,
                  title: 'Professional ID',
                  subtitle: 'Your shareable verified ID',
                  locked: !unlocked,
                  onTap: () => gated('/employee/professional-id'),
                ),
                MenuTile(
                  icon: Icons.verified_outlined,
                  title: 'Verification',
                  subtitle: 'Aadhaar and face match',
                  onTap: () => context.push('/employee/verification'),
                ),
                MenuTile(
                  icon: Icons.edit_note,
                  title: 'Edit profile',
                  subtitle: 'Basic details and education',
                  onTap: () => context.push('/employee/profile-setup'),
                ),
              ],
            ),
            MenuSection(
              title: 'Requests',
              children: [
                MenuTile(
                  icon: Icons.mail_outline,
                  title: 'Invitations',
                  subtitle: 'Companies inviting you to join',
                  onTap: () => context.push('/employee/invitations'),
                ),
                MenuTile(
                  icon: Icons.key_outlined,
                  title: 'Access & Consent',
                  subtitle: 'Profile access and verification consent',
                  onTap: () => context.push('/employee/access-requests'),
                ),
              ],
            ),
            preferences,
            MenuSection(
              title: 'Support & Resources',
              children: [
                MenuTile(
                  icon: Icons.support_agent,
                  title: 'Help & Support',
                  subtitle: 'FAQ, live chat, WhatsApp and email',
                  onTap: () => context.push('/employee/settings/support'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            MenuSection(
              children: [
                MenuTile(
                  icon: Icons.logout,
                  title: 'Sign out',
                  destructive: true,
                  onTap: _signOut,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
