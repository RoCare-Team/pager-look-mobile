import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/app_lock.dart';
import '../../../core/platform/ios_native.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import 'employee_settings_screen.dart';

/// Port of `PrivacySecurity.jsx`.
///
/// The web page's consent toggles, 2FA button and session list are local
/// placeholders with no backend behind them, so this screen only offers the
/// controls that are real: consent requests, public-profile visibility (the
/// settings API), DigiLocker and signing this device out.
class PrivacySecurityScreen extends ConsumerStatefulWidget {
  const PrivacySecurityScreen({super.key});

  @override
  ConsumerState<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends ConsumerState<PrivacySecurityScreen> {
  bool _saving = false;

  Future<void> _setPublicProfile(Map<String, dynamic> settings, bool value) async {
    setState(() => _saving = true);
    try {
      await ref.read(employeeApiProvider).updateSettings(buildSettingsPatch(settings, publicProfileEnabled: value));
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
      title: 'Log out of this device?',
      message: 'You will need to verify your mobile number again to sign in.',
      confirmLabel: 'Log out',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await ref.read(authProvider).logout();
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(employeeSettingsProvider);
    final user = ref.watch(authProvider.select((a) => a.user));
    final phone = strOrNull(user?['phone']);
    final email = strOrNull(user?['email']);

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & Security')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(employeeSettingsProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            const PageIntro(
              title: 'Privacy & Security',
              subtitle: 'Control who can access your credentials',
            ),
            MenuSection(
              title: 'Consent Control',
              children: [
                MenuTile(
                  icon: Icons.key_outlined,
                  title: 'Recruiter Access',
                  subtitle: 'Companies must request approval to view your full profile. Review requests here.',
                  onTap: () => context.push('/employee/access-requests'),
                ),
                settingsAsync.when(
                  skipLoadingOnRefresh: true,
                  skipLoadingOnReload: true,
                  data: (settings) {
                    final enabled =
                        settings['publicProfileEnabled'] == null ? true : asBool(settings['publicProfileEnabled']);
                    return MenuTile(
                      icon: Icons.public,
                      title: 'Public Profile Visibility',
                      subtitle: enabled
                          ? 'Anyone with your link or QR can view your verified profile'
                          : 'Your public profile link is hidden',
                      trailing: Switch(
                        value: enabled,
                        onChanged: _saving ? null : (v) => _setPublicProfile(settings, v),
                      ),
                    );
                  },
                  loading: () => const MenuTile(
                    icon: Icons.public,
                    title: 'Public Profile Visibility',
                    trailing: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  error: (e, _) => MenuTile(
                    icon: Icons.public,
                    title: 'Public Profile Visibility',
                    subtitle: "Couldn't load — tap to retry",
                    onTap: () => ref.invalidate(employeeSettingsProvider),
                  ),
                ),
                MenuTile(
                  icon: Icons.cloud_outlined,
                  title: 'DigiLocker',
                  subtitle: 'Manage your linked government documents',
                  onTap: () => context.push('/employee/settings/digilocker'),
                ),
              ],
            ),
            MenuSection(
              title: 'Security Settings',
              children: [
                MenuTile(
                  icon: Icons.verified_user_outlined,
                  title: 'Secure sign-in',
                  subtitle: phone == null
                      ? 'You sign in with a one-time code sent to your mobile number, or with Google'
                      : 'You sign in with a one-time code sent to $phone, or with Google',
                ),
                MenuTile(
                  icon: Icons.fingerprint,
                  title: 'Identity verification',
                  subtitle: 'Aadhaar and face match',
                  onTap: () => context.push('/employee/verification'),
                ),
                if (IosNative.isSupported) const AppLockTile(),
              ],
            ),
            MenuSection(
              title: 'Active Sessions',
              children: [
                MenuTile(
                  icon: Icons.smartphone,
                  title: 'This device',
                  subtitle: email ?? phone ?? 'Signed in',
                  trailing: const StatusBadge(null, label: 'Current', tone: Tone.success),
                ),
                MenuTile(
                  icon: Icons.logout,
                  title: 'Log out of this device',
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
