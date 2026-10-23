import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import 'widgets/journey.dart';

/// `GET /public/employee-invitation/:token` — the web reads `data.invitation || data`.
final _employeeInvitationProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, token) async {
  final data = asMap(await ref.watch(publicApiProvider).fetchEmployeeInvitation(token));
  return data['invitation'] is Map ? asMap(data['invitation']) : data;
});

/// Pull the token out of whatever the user pasted: a full invite link
/// (`…/employee/join?token=…`) or the bare token.
String parseInvitationToken(String input) {
  final text = input.trim();
  if (text.isEmpty) return '';
  final uri = Uri.tryParse(text);
  if (uri != null) {
    final fromQuery = uri.queryParameters['token'];
    if (fromQuery != null && fromQuery.trim().isNotEmpty) return fromQuery.trim();
  }
  final match = RegExp(r'token=([^&\s#]+)').firstMatch(text);
  if (match != null) return Uri.decodeComponent(match.group(1)!);
  if (uri != null && uri.hasScheme && uri.pathSegments.isNotEmpty) return uri.pathSegments.last;
  return text;
}

/// Port of `pages/employee/EmployeeJoin.jsx`.
class EmployeeJoinScreen extends ConsumerStatefulWidget {
  const EmployeeJoinScreen({super.key, this.token = ''});

  final String token;

  @override
  ConsumerState<EmployeeJoinScreen> createState() => _EmployeeJoinScreenState();
}

class _EmployeeJoinScreenState extends ConsumerState<EmployeeJoinScreen> {
  late String _token = widget.token.trim();
  final TextEditingController _linkCtrl = TextEditingController();
  bool _continuing = false;

  @override
  void dispose() {
    _linkCtrl.dispose();
    super.dispose();
  }

  void _openPasted() {
    final token = parseInvitationToken(_linkCtrl.text);
    if (token.isEmpty) {
      showToast('Paste your invitation link or code', type: ToastType.error);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _token = token);
  }

  Future<void> _continue(Map<String, dynamic> invitation) async {
    if (_continuing) return;
    final auth = ref.read(authProvider);
    final router = GoRouter.of(context);
    setState(() => _continuing = true);
    try {
      // Carry everything the company already filled in, so profile setup can
      // pre-fill it instead of asking the invitee to type it again.
      await auth.setInvitation({
        'token': _token,
        'email': str(invitation['employeeEmail'] ?? invitation['email']),
        'companyName': str(invitation['companyName']),
        'name': str(invitation['employeeName']),
        'phone': str(invitation['employeeMobile']),
        'department': str(invitation['department']),
        'designation': str(invitation['designation']),
      });
      router.push('/employee/otp?from=join');
    } catch (e) {
      showErrorToast(e);
    } finally {
      if (mounted) setState(() => _continuing = false);
    }
  }

  Future<String?> _readClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      return (text == null || text.isEmpty) ? null : text;
    } catch (_) {
      return null;
    }
  }

  void _goHome() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: _goHome),
        title: const Text('Join your team'),
      ),
      body: _token.isEmpty ? _buildPasteView() : _buildInvitationView(),
    );
  }

  Widget _buildPasteView() {
    return ListView(
      padding: const EdgeInsets.all(20),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (widget.token.trim().isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: InfoBanner(
              tone: Tone.danger,
              message: 'Invalid invitation link — missing token.',
            ),
          ),
        const PageIntro(
          title: 'Open your invitation',
          subtitle: 'Paste the invitation link from your email (or just the code in it) to see who invited you.',
        ),
        AppTextField(
          controller: _linkCtrl,
          label: 'Invitation link or code',
          hint: 'https://…/employee/join?token=…',
          prefixIcon: Icons.link,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _openPasted(),
          suffix: IconButton(
            tooltip: 'Paste',
            icon: const Icon(Icons.content_paste, size: 20),
            onPressed: () async {
              final clip = await _readClipboard();
              if (clip != null && mounted) {
                _linkCtrl.text = clip;
                setState(() {});
              }
            },
          ),
        ),
        const SizedBox(height: 16),
        AppButton(label: 'Open invitation', icon: Icons.mail_outline, onPressed: _openPasted),
        const SizedBox(height: 12),
        AppButton(label: 'Go to employee home', variant: AppButtonVariant.ghost, onPressed: () => context.go('/employee/otp')),
      ],
    );
  }

  Widget _buildInvitationView() {
    final async = ref.watch(_employeeInvitationProvider(_token));
    return async.when(
      loading: () => const LoadingView(label: 'Loading invitation...'),
      error: (e, _) => _buildErrorView(e),
      data: (invitation) {
        if (invitation.isEmpty) return _buildErrorView(null);
        return _buildDetails(invitation);
      },
    );
  }

  Widget _buildErrorView(Object? error) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 24),
        EmptyState(
          icon: Icons.link_off,
          title: 'Invitation unavailable',
          message: error == null ? 'Invitation not found or expired.' : errorMessage(error, 'Invitation not found or expired.'),
        ),
        AppButton(
          label: 'Try again',
          icon: Icons.refresh,
          variant: AppButtonVariant.outline,
          onPressed: () => ref.invalidate(_employeeInvitationProvider(_token)),
        ),
        const SizedBox(height: 10),
        AppButton(
          label: 'Use a different link',
          variant: AppButtonVariant.ghost,
          onPressed: () => setState(() {
            _linkCtrl.clear();
            _token = '';
          }),
        ),
        AppButton(label: 'Go to employee home', variant: AppButtonVariant.ghost, onPressed: () => context.go('/employee/otp')),
      ],
    );
  }

  Widget _buildDetails(Map<String, dynamic> invitation) {
    final companyName = strOrNull(invitation['companyName']) ?? 'a company';
    final email = strOrNull(invitation['employeeEmail'] ?? invitation['email']);
    final requiresRegistration = invitation['requiresRegistration'] != false;

    return RefreshIndicator(
      onRefresh: () => ref.refresh(_employeeInvitationProvider(_token).future),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'WORKFORCE INVITATION',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.brand600),
          ),
          const SizedBox(height: 6),
          Text(
            "You're invited by $companyName",
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 18),
          AppCard(
            child: Column(
              children: [
                InfoRow(label: 'Department', value: str(invitation['department'])),
                InfoRow(label: 'Role', value: str(invitation['designation'])),
                if (email != null) InfoRow(label: 'Email', value: email),
              ],
            ),
          ),
          if (requiresRegistration) ...[
            const SizedBox(height: 16),
            const Text(
              "Create your PagerLook account to join the team. You'll be added automatically after profile setup.",
              style: TextStyle(fontSize: 14, color: AppColors.inkBody, height: 1.45),
            ),
          ],
          const SizedBox(height: 24),
          AppButton(
            label: 'Continue with OTP',
            loading: _continuing,
            onPressed: _continuing ? null : () => _continue(invitation),
          ),
          const SizedBox(height: 8),
          AppButton(
            label: 'Back to home',
            variant: AppButtonVariant.ghost,
            onPressed: _continuing ? null : () => context.go('/'),
          ),
          const SecurityNote('Your invitation is private to you'),
        ],
      ),
    );
  }
}
