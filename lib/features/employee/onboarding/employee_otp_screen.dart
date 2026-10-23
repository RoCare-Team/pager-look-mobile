import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/config/env.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/api/auth_api.dart';
import 'widgets/journey.dart';

/// Web `OtpInput.DEFAULT_OTP_LENGTH` — the send response normally overrides it.
const int _defaultOtpLength = 4;
const int _defaultResendSeconds = 30;

/// Port of `pages/employee/EmployeeOtp.jsx` (plus the Google option from
/// `GoogleSignInButton.jsx`).
class EmployeeOtpScreen extends ConsumerStatefulWidget {
  const EmployeeOtpScreen({super.key, this.fromJoin = false});

  final bool fromJoin;

  @override
  ConsumerState<EmployeeOtpScreen> createState() => _EmployeeOtpScreenState();
}

class _EmployeeOtpScreenState extends ConsumerState<EmployeeOtpScreen> {
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _otpCtrl = TextEditingController();

  String _countryCode = '+91';
  bool _otpSent = false;
  String _sentTo = '';
  int _otpLength = _defaultOtpLength;
  int _resendSeconds = 0;
  Timer? _timer;

  /// Set by a 429 — blocks "Send OTP" until the backend's cooldown ends.
  bool _rateLimited = false;

  bool _sending = false;
  bool _verifying = false;
  bool _googleBusy = false;
  String? _error;

  /// The last code auto-submitted, so the same digits never fire twice.
  String _autoSubmitted = '';

  String get _phoneDigits => _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
  bool get _isPhoneValid => _phoneDigits.length >= 10;
  String get _fullPhone => normalizePhone(_countryCode, _phoneCtrl.text);
  bool get _busy => _sending || _verifying || _googleBusy;

  @override
  void dispose() {
    _timer?.cancel();
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  void _startCountdown(int seconds) {
    _timer?.cancel();
    setState(() => _resendSeconds = seconds < 0 ? 0 : seconds);
    if (seconds <= 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        t.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds -= 1);
      }
    });
  }

  Future<void> _sendOtp() async {
    if (!_isPhoneValid || _busy) return;
    if (_rateLimited && _resendSeconds > 0) return;
    FocusScope.of(context).unfocus();
    final authApi = ref.read(authApiProvider);
    final phone = _fullPhone;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final data = asMap(await authApi.sendEmployeeOtp(phone));
      if (!mounted) return;
      _otpCtrl.clear();
      _autoSubmitted = '';
      final length = asInt(data['otpLength']);
      setState(() {
        _otpSent = true;
        _rateLimited = false;
        _sentTo = phone;
        _otpLength = length > 0 ? length : _defaultOtpLength;
      });
      final resend = asInt(data['resendInSeconds']);
      _startCountdown(resend > 0 ? resend : _defaultResendSeconds);
      showToast(strOrNull(data['message']) ?? 'OTP sent to your phone', type: ToastType.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorMessage(e, 'Failed to send OTP'));
      // 429 — the backend tells us how long the cooldown is.
      final retry = e is ApiException ? e.retryAfterSeconds : null;
      if (retry != null && retry > 0) {
        _rateLimited = true;
        _startCountdown(retry);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _onOtpChanged(String value) {
    setState(() {});
    if (value.length == _otpLength) _verify(value);
  }

  Future<void> _verify(String code) async {
    if (!_otpSent || _verifying || code.length != _otpLength) return;
    if (_autoSubmitted == code) return;
    _autoSubmitted = code;

    final router = GoRouter.of(context);
    final auth = ref.read(authProvider);
    final authApi = ref.read(authApiProvider);
    final fromJoin = widget.fromJoin;

    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final data = asMap(await authApi.verifyEmployeeOtp(_sentTo, code));
      await _completeLogin(auth, router, data, fromJoin: fromJoin, message: 'Phone verified successfully');
    } catch (e) {
      // Allow another attempt: clearing lets a re-entered code fire again.
      _autoSubmitted = '';
      if (mounted) setState(() => _error = errorMessage(e, 'Invalid OTP'));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  static Future<void> _completeLogin(
    AuthController auth,
    GoRouter router,
    Map<String, dynamic> data, {
    required bool fromJoin,
    required String message,
  }) async {
    await auth.loginEmployee(data);
    showToast(message, type: ToastType.success);
    if (fromJoin || auth.hasInvitation) {
      router.go('/employee/profile-setup');
      return;
    }
    router.go(strOrNull(data['homeRoute']) ?? '/employee/profile-setup');
  }

  Future<void> _googleSignIn() async {
    if (_busy) return;
    final router = GoRouter.of(context);
    final auth = ref.read(authProvider);
    final authApi = ref.read(authApiProvider);
    final fromJoin = widget.fromJoin;

    setState(() {
      _googleBusy = true;
      _error = null;
    });
    try {
      final google = GoogleSignIn(serverClientId: Env.googleServerClientId, scopes: const ['email']);
      // Always show the account chooser instead of silently reusing the last account.
      try {
        await google.signOut();
      } catch (_) {}
      final account = await google.signIn();
      if (account == null) return; // cancelled
      final idToken = (await account.authentication).idToken;
      if (idToken == null || idToken.isEmpty) {
        showToast('Google sign-in was cancelled or failed', type: ToastType.error);
        return;
      }
      final data = asMap(await authApi.loginEmployeeGoogle(idToken));
      await _completeLogin(auth, router, data, fromJoin: fromJoin, message: 'Signed in with Google');
    } on PlatformException catch (e) {
      if (e.code != 'sign_in_canceled') {
        showToast('Google sign-in was cancelled or failed', type: ToastType.error);
      }
    } catch (e) {
      showErrorToast(e, 'Google sign-in failed');
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  void _changeNumber() {
    _otpCtrl.clear();
    _autoSubmitted = '';
    setState(() {
      _otpSent = false;
      _error = null;
    });
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final showGoogle = Env.googleServerClientId.isNotEmpty;
    final overlayLabel = _googleBusy
        ? 'Signing in with Google...'
        : (_otpSent ? 'Verifying OTP...' : 'Sending OTP...');

    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/');
      },
      child: Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: _back),
        title: const BrandLogo(height: 26),
      ),
      body: BusyOverlay(
        busy: _busy,
        label: overlayLabel,
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              const PageIntro(
                title: 'Phone OTP Sign In',
                subtitle: 'Enter your mobile number to receive a verification code.',
              ),
              if (_error != null) ...[
                InfoBanner(message: _error!, tone: Tone.danger),
                const SizedBox(height: 16),
              ],
              if (_otpSent) ..._buildOtpSection() else ..._buildPhoneSection(),
              if (showGoogle) ...[
                const SizedBox(height: 24),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or', style: TextStyle(color: AppColors.inkFaint, fontSize: 13)),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),
                AppButton(
                  label: 'Continue with Google',
                  icon: Icons.login,
                  variant: AppButtonVariant.outline,
                  loading: _googleBusy,
                  onPressed: _busy ? null : _googleSignIn,
                ),
              ],
              const SizedBox(height: 28),
              Center(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('Employer? ', style: TextStyle(color: AppColors.inkMuted, fontSize: 14)),
                    InkWell(
                      onTap: _busy ? null : () => context.go('/enterprise/login'),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          'Enterprise Portal',
                          style: TextStyle(color: AppColors.brand600, fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SecurityNote('Aadhaar Encrypted & Secure'),
            ],
          ),
        ),
      ),
    ),
    );
  }

  List<Widget> _buildPhoneSection() {
    final cooling = _rateLimited && _resendSeconds > 0;
    return [
      PhoneField(
        controller: _phoneCtrl,
        countryCode: _countryCode,
        enabled: !_busy,
        onCountryCodeChanged: (code) => setState(() => _countryCode = code),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 20),
      AppButton(
        label: _sending ? 'Sending...' : (cooling ? 'Send OTP (${_resendSeconds}s)' : 'Send OTP'),
        loading: _sending,
        onPressed: (_busy || !_isPhoneValid || cooling) ? null : _sendOtp,
      ),
    ];
  }

  List<Widget> _buildOtpSection() {
    return [
      AppCard(
        color: AppColors.brand50,
        borderColor: AppColors.brand100,
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'OTP SENT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: AppColors.brand600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      text: 'Code sent to ',
                      children: [
                        TextSpan(text: _sentTo, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                    style: const TextStyle(fontSize: 14, color: AppColors.inkBody),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: _busy ? null : _changeNumber, child: const Text('Change')),
          ],
        ),
      ),
      const SizedBox(height: 18),
      OtpInput(
        key: ValueKey('otp-$_otpLength-$_sentTo'),
        length: _otpLength,
        controller: _otpCtrl,
        enabled: !_busy,
        onChanged: _onOtpChanged,
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          const Expanded(
            child: Text("Didn't receive code?", style: TextStyle(color: AppColors.inkMuted, fontSize: 13.5)),
          ),
          if (_resendSeconds > 0)
            Text(
              'Resend in ${_resendSeconds}s',
              style: const TextStyle(color: AppColors.inkFaint, fontWeight: FontWeight.w600, fontSize: 13.5),
            )
          else
            TextButton(onPressed: _busy ? null : _sendOtp, child: const Text('Resend OTP')),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        _verifying ? 'Verifying…' : 'Enter the $_otpLength-digit code — it verifies automatically.',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
      ),
      // Manual retry if the auto-verify failed (e.g. network) with all digits in.
      if (!_verifying && _error != null && _otpCtrl.text.length == _otpLength) ...[
        const SizedBox(height: 14),
        AppButton(
          label: 'Verify OTP',
          onPressed: _busy
              ? null
              : () {
                  _autoSubmitted = '';
                  _verify(_otpCtrl.text);
                },
        ),
      ],
    ];
  }
}
