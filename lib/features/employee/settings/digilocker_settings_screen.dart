import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import '../verification/digilocker_webview.dart';

final _digiLockerProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return asMap(await ref.watch(employeeApiProvider).fetchDigiLockerConnection());
});

/// Port of `DigiLockerSettings.jsx`. The OAuth round-trip happens in the
/// browser; when the user comes back to the app the connection is refetched.
/// [status]/[message] come from the backend callback's redirect
/// (`?status=success|failed&message=…`) when the link opens the app.
class DigiLockerSettingsScreen extends ConsumerStatefulWidget {
  const DigiLockerSettingsScreen({super.key, this.status, this.message});

  final String? status;
  final String? message;

  @override
  ConsumerState<DigiLockerSettingsScreen> createState() => _DigiLockerSettingsScreenState();
}

class _DigiLockerSettingsScreenState extends ConsumerState<DigiLockerSettingsScreen> {
  late final AppLifecycleListener _lifecycle;
  bool _connecting = false;
  bool _disconnecting = false;
  bool _awaitingReturn = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _onResume() async {
    if (!mounted) return;
    ref.invalidate(_digiLockerProvider);
    if (_awaitingReturn) {
      _awaitingReturn = false;
      try {
        // DigiLocker usage feeds the score — keep the session profile fresh.
        await ref.read(authProvider).refreshEmployeeProfile();
      } catch (_) {
        // Non-critical.
      }
    }
  }

  Future<void> _connect() async {
    setState(() => _connecting = true);
    try {
      final res = asMap(await ref.read(employeeApiProvider).startDigiLockerConnect('settings'));
      final url = strOrNull(res['authorizationUrl']);
      if (url == null) {
        showToast('Could not start DigiLocker', type: ToastType.error);
        return;
      }
      if (!mounted) return;
      final result = await openDigiLockerInApp(context, url);
      if (result == null) return;
      final failed = result.queryParameters['status'] != 'success';
      showToast(
        failed ? (result.queryParameters['message'] ?? 'DigiLocker connection failed') : 'DigiLocker connected',
        type: failed ? ToastType.error : ToastType.success,
      );
      _awaitingReturn = true;
      await _onResume();
    } catch (e) {
      showErrorToast(e, 'Could not start DigiLocker');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _disconnect() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Disconnect DigiLocker?',
      message: 'Your DigiLocker account will be unlinked from PagerLook. You can connect it again any time.',
      confirmLabel: 'Disconnect',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _disconnecting = true);
    try {
      await ref.read(employeeApiProvider).disconnectDigiLocker();
      ref.invalidate(_digiLockerProvider);
      showToast('DigiLocker disconnected', type: ToastType.success);
    } catch (e) {
      showErrorToast(e, 'Could not disconnect DigiLocker');
    } finally {
      if (mounted) setState(() => _disconnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connAsync = ref.watch(_digiLockerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('DigiLocker')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(_digiLockerProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            const PageIntro(
              title: 'DigiLocker',
              subtitle: 'Link your DigiLocker account to share government-issued documents',
            ),
            if (widget.status == 'success') ...[
              const InfoBanner(tone: Tone.success, message: 'DigiLocker connected successfully.'),
              const SizedBox(height: 12),
            ],
            if (widget.status == 'failed') ...[
              InfoBanner(
                tone: Tone.danger,
                message: '${widget.message ?? 'DigiLocker authentication failed'}. Please try again.',
              ),
              const SizedBox(height: 12),
            ],
            AppCard(
              child: connAsync.when(
                skipLoadingOnRefresh: true,
                skipLoadingOnReload: true,
                loading: () => const LoadingView(),
                error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(_digiLockerProvider)),
                data: (connection) => asBool(connection['connected'])
                    ? _connected(connection)
                    : _notConnected(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _connected(Map<String, dynamic> connection) {
    final identity = asMap(connection['identity']);
    final name = strOrNull(identity['name']);
    final dob = strOrNull(identity['dob']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const StatusBadge(null, label: 'Connected', tone: Tone.success, icon: Icons.check),
            if (connection['connectedAt'] != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'since ${formatDate(connection['connectedAt'])}',
                  style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
                ),
              ),
            ],
          ],
        ),
        if (name != null) ...[
          const SizedBox(height: 12),
          InfoRow(label: 'Name', value: name),
          if (dob != null) InfoRow(label: 'Date of birth', value: dob),
          InfoRow(label: 'Aadhaar linked', value: asBool(identity['eaadhaarLinked']) ? 'Yes' : 'No'),
        ],
        const SizedBox(height: 16),
        AppButton(
          label: 'Disconnect',
          variant: AppButtonVariant.outline,
          icon: Icons.link_off,
          loading: _disconnecting,
          onPressed: _disconnect,
        ),
      ],
    );
  }

  Widget _notConnected() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          "You'll be taken to DigiLocker to sign in and give consent, then brought back here.",
          style: TextStyle(fontSize: 13.5, color: AppColors.inkBody),
        ),
        const SizedBox(height: 16),
        AppButton(
          label: _connecting ? 'Connecting to DigiLocker...' : 'Verify with DigiLocker',
          icon: Icons.cloud_outlined,
          loading: _connecting,
          onPressed: _connect,
        ),
      ],
    );
  }
}
