import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';
import 'ios_native.dart';

/// Face ID / Touch ID app lock (iOS only). When on, a signed-in session asks
/// for the owner's face, fingerprint or passcode on launch and after the app
/// has been in the background for [relockAfter].
class AppLockController extends ChangeNotifier {
  AppLockController({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock));

  static const _enabledKey = 'veriwork_app_lock';
  static const relockAfter = Duration(seconds: 30);

  final FlutterSecureStorage _storage;

  bool enabled = false;
  bool locked = false;

  /// `faceID`, `touchID`, or null (passcode only).
  String? biometry;
  bool _authenticating = false;
  DateTime? _backgroundedAt;

  bool get available => IosNative.isSupported;

  String get label => switch (biometry) {
        'faceID' => 'Face ID',
        'touchID' => 'Touch ID',
        _ => 'Passcode',
      };

  IconData get icon => biometry == 'touchID' ? Icons.fingerprint : Icons.face_outlined;

  Future<void> load() async {
    if (!available) return;
    biometry = await IosNative.biometryType();
    try {
      enabled = await _storage.read(key: _enabledKey) == 'true';
    } catch (_) {
      enabled = false;
    }
    locked = enabled;
    notifyListeners();
  }

  /// Turning the lock on or off needs the owner to authenticate first.
  Future<bool> setEnabled(bool value) async {
    final ok = await _authenticate(value ? 'Turn on $label lock for PagerLook' : 'Turn off $label lock');
    if (!ok) return false;
    enabled = value;
    await _storage.write(key: _enabledKey, value: value.toString());
    notifyListeners();
    return true;
  }

  Future<void> unlock() async {
    if (!locked) return;
    if (await _authenticate('Unlock PagerLook')) {
      locked = false;
      notifyListeners();
    }
  }

  /// Signed out: nothing to protect, so drop any pending lock.
  void clearLock() {
    if (!locked) return;
    locked = false;
    notifyListeners();
  }

  void didEnterBackground() => _backgroundedAt ??= DateTime.now();

  void didResume() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (enabled && since != null && DateTime.now().difference(since) >= relockAfter) {
      locked = true;
      notifyListeners();
    }
  }

  Future<bool> _authenticate(String reason) async {
    if (_authenticating) return false;
    _authenticating = true;
    try {
      return await IosNative.authenticate(reason);
    } finally {
      _authenticating = false;
    }
  }
}

final appLockProvider = ChangeNotifierProvider<AppLockController>((ref) => AppLockController());

/// Wraps the app (in `MaterialApp.builder`) and covers it with the lock screen
/// while the lock is active for a signed-in user.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> with WidgetsBindingObserver {
  bool _prompted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(appLockProvider).load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = ref.read(appLockProvider);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        lock.didEnterBackground();
      case AppLifecycleState.resumed:
        lock.didResume();
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    final signedIn = ref.watch(authProvider.select((a) => !a.booting && a.isAuthenticated));
    ref.listen(authProvider.select((a) => a.isAuthenticated), (was, now) {
      if (was == true && !now) lock.clearLock();
    });

    final show = lock.available && lock.locked && signedIn;
    if (!show) {
      _prompted = false;
    } else if (!_prompted) {
      // Ask straight away, like other banking/ID apps; the button retries.
      _prompted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => lock.unlock());
    }

    return Stack(
      children: [
        widget.child,
        if (show) Positioned.fill(child: _LockScreen(lock: lock)),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.lock});

  final AppLockController lock;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              const BrandLogo(height: 44),
              const SizedBox(height: 32),
              Icon(lock.icon, size: 56, color: AppColors.brand600),
              const SizedBox(height: 16),
              const Text(
                'PagerLook is locked',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.inkStrong),
              ),
              const SizedBox(height: 8),
              Text(
                'Use ${lock.label} to open your verified profile and documents.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.inkMuted),
              ),
              const Spacer(),
              AppButton(label: 'Unlock with ${lock.label}', icon: lock.icon, onPressed: lock.unlock),
            ],
          ),
        ),
      ),
    );
  }
}

/// Settings row that turns the lock on/off. Only add it where [IosNative.isSupported].
class AppLockTile extends ConsumerStatefulWidget {
  const AppLockTile({super.key});

  @override
  ConsumerState<AppLockTile> createState() => _AppLockTileState();
}

class _AppLockTileState extends ConsumerState<AppLockTile> {
  bool _busy = false;

  Future<void> _toggle(bool value) async {
    final lock = ref.read(appLockProvider);
    setState(() => _busy = true);
    final ok = await lock.setEnabled(value);
    if (mounted) setState(() => _busy = false);
    if (ok) {
      showToast(value ? '${lock.label} lock turned on' : '${lock.label} lock turned off', type: ToastType.success);
    } else {
      showToast('Could not verify it\'s you — ${lock.label} lock unchanged', type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    return MenuTile(
      icon: lock.icon,
      title: '${lock.label} lock',
      subtitle: 'Ask for ${lock.label} when PagerLook opens',
      trailing: Switch(value: lock.enabled, onChanged: _busy ? null : _toggle),
    );
  }
}
