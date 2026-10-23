import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/widgets.dart';
import 'scan_routing.dart';

/// The page a scanned company QR lands on (`/join/:code`) — port of
/// `pages/public/QrJoin.jsx`. Same fields as the employer's "Invite Employee"
/// form; the candidate fills them in themselves.
///
/// On submit: already on PagerLook → an invitation waits in their portal;
/// new → the backend returns a `joinLink` and we go straight to registration.
final _qrJoinInfoProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, code) async {
  final res = asMap(await ref.watch(publicApiProvider).fetchQrJoinInfo(code));
  return res['data'] is Map ? asMap(res['data']) : res;
});

class QrJoinScreen extends ConsumerStatefulWidget {
  const QrJoinScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<QrJoinScreen> createState() => _QrJoinScreenState();
}

class _QrJoinScreenState extends ConsumerState<QrJoinScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _department = TextEditingController();
  final _role = TextEditingController();

  bool _pending = false;
  String _error = '';
  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();
    // The QR can carry a role/department — prefill so the candidate types less.
    ref.listenManual<AsyncValue<Map<String, dynamic>>>(
      _qrJoinInfoProvider(widget.code),
      (_, next) {
        final info = next.valueOrNull;
        if (info == null) return;
        if (_role.text.isEmpty) _role.text = str(info['designation']);
        if (_department.text.isEmpty) _department.text = str(info['department']);
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _department.dispose();
    _role.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_pending) return;
    FocusScope.of(context).unfocus();
    setState(() => _error = '');
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Please enter your full name');
      return;
    }
    if (_phone.text.replaceAll(RegExp(r'\D'), '').length < 10) {
      setState(() => _error = 'Please enter a valid 10-digit mobile number');
      return;
    }

    setState(() => _pending = true);
    try {
      final res = asMap(await ref.read(publicApiProvider).submitQrJoinRequest(widget.code, {
        'name': _name.text,
        'phone': _phone.text,
        'email': _email.text,
        'role': _role.text,
        'department': _department.text,
      }));
      final payload = res['data'] is Map ? asMap(res['data']) : res;
      if (!mounted) return;

      // New to PagerLook — hand them straight to profile setup.
      final joinLink = strOrNull(payload['joinLink']);
      if (joinLink != null) {
        final route = routeForScannedValue(joinLink);
        if (route != null) {
          context.go(route);
        } else {
          await openExternalUrl(joinLink);
          if (mounted) setState(() => _pending = false);
        }
        return;
      }
      setState(() {
        _pending = false;
        _result = payload;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pending = false;
        _error = errorMessage(e, 'Could not send your request');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_qrJoinInfoProvider(widget.code));

    return Scaffold(
      appBar: AppBar(title: const Text('Join a company')),
      body: SafeArea(
        child: async.when(
          loading: () => const LoadingView(label: 'Loading...'),
          error: (e, _) => ErrorView(
            error: e,
            title: 'This QR code is invalid or no longer active.',
            onRetry: () => ref.invalidate(_qrJoinInfoProvider(widget.code)),
          ),
          data: (info) => _result != null ? _buildSuccess(_result!) : _buildForm(info),
        ),
      ),
    );
  }

  /// Only reached by people who already have a PagerLook profile.
  Widget _buildSuccess(Map<String, dynamic> result) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: AppColors.successBg, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, size: 34, color: AppColors.success),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          "You're invited",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.inkStrong),
        ),
        const SizedBox(height: 8),
        Text(
          str(result['message']),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.inkBody),
        ),
        const SizedBox(height: 28),
        AppButton(label: 'Open my invitations', onPressed: () => context.go('/employee/invitations')),
      ],
    );
  }

  Widget _buildForm(Map<String, dynamic> info) {
    final companyName = str(info['companyName'], 'this company');
    final label = strOrNull(info['label']);
    final designation = strOrNull(info['designation']);
    final department = strOrNull(info['department']);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        const Center(child: BrandLogo(height: 30)),
        const SizedBox(height: 20),
        AppCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (label != null)
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    color: AppColors.inkFaint,
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                'Join $companyName',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.inkStrong),
              ),
              const SizedBox(height: 6),
              Text(
                "Fill in your details to request joining $companyName. Already on PagerLook? We'll match you by "
                "your mobile number — otherwise we'll set up your profile next.",
                style: const TextStyle(fontSize: 13.5, height: 1.45, color: AppColors.inkBody),
              ),
              if (designation != null || department != null) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (designation != null) StatusBadge(null, label: designation, tone: Tone.neutral),
                    if (department != null) StatusBadge(null, label: department, tone: Tone.neutral),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              AppTextField(
                controller: _name,
                label: 'Full Name',
                requiredMark: true,
                hint: 'Your full name',
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                enabled: !_pending,
              ),
              const SizedBox(height: 14),
              AppTextField(
                controller: _phone,
                label: 'Mobile Number',
                requiredMark: true,
                hint: '10-digit mobile number',
                helper: 'We use this to find your existing PagerLook profile',
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.telephoneNumber],
                enabled: !_pending,
              ),
              const SizedBox(height: 14),
              AppTextField(
                controller: _email,
                label: 'Email',
                hint: 'Optional',
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                enabled: !_pending,
              ),
              const SizedBox(height: 14),
              AppTextField(
                controller: _department,
                label: 'Department',
                hint: 'Optional',
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                enabled: !_pending,
              ),
              const SizedBox(height: 14),
              AppTextField(
                controller: _role,
                label: 'Designation',
                hint: 'e.g. Software Engineer',
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                enabled: !_pending,
                onSubmitted: (_) => _submit(),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_error, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: AppColors.danger)),
              ],
              const SizedBox(height: 18),
              AppButton(
                label: _pending ? 'Submitting…' : 'Continue',
                loading: _pending,
                onPressed: _submit,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Center(
          child: Text.rich(
            TextSpan(
              text: 'Powered by ',
              children: [
                TextSpan(
                  text: 'PagerLook',
                  style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.brand600),
                ),
              ],
            ),
            style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
          ),
        ),
      ],
    );
  }
}
