import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/company_permissions.dart';
import '../../../core/config/env.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';

final _qrCodesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data = await ref.watch(enterpriseApiProvider).fetchQrOnboarding();
  return listFrom(data, const ['qrCodes', 'items']);
});

/// The public join page a scanned code opens. The backend sends `joinLink`
/// (`${FRONTEND_URL}/join/<code>`); fall back to the same shape.
String _joinLink(Map<String, dynamic> qr) =>
    str(qr['joinLink'], '${Env.appOrigin}/join/${str(qr['code'])}');

/// Port of `pages/enterprise/QROnboarding.jsx`.
class QrOnboardingScreen extends ConsumerStatefulWidget {
  const QrOnboardingScreen({super.key});

  @override
  ConsumerState<QrOnboardingScreen> createState() => _QrOnboardingScreenState();
}

class _QrOnboardingScreenState extends ConsumerState<QrOnboardingScreen> {
  final _label = TextEditingController();
  final _department = TextEditingController();
  final _designation = TextEditingController();
  bool _creating = false;

  /// `"<id>:toggle"` / `"<id>:delete"` while a card action is in flight.
  String? _busy;

  @override
  void dispose() {
    _label.dispose();
    _department.dispose();
    _designation.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final _ = await ref.refresh(_qrCodesProvider.future);
    } catch (_) {}
  }

  Future<void> _create() async {
    FocusScope.of(context).unfocus();
    final label = _label.text.trim();
    if (label.isEmpty) return;
    final department = _department.text.trim();
    final designation = _designation.text.trim();
    setState(() => _creating = true);
    try {
      await ref.read(enterpriseApiProvider).createQrOnboarding({
        'label': label,
        if (department.isNotEmpty) 'department': department,
        if (designation.isNotEmpty) 'designation': designation,
      });
      showToast('QR code generated', type: ToastType.success);
      _label.clear();
      _department.clear();
      _designation.clear();
      ref.invalidate(_qrCodesProvider);
    } catch (e) {
      showErrorToast(e, 'Failed to generate QR code');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _toggle(Map<String, dynamic> qr) async {
    final id = idOf(qr);
    setState(() => _busy = '$id:toggle');
    try {
      await ref.read(enterpriseApiProvider).setQrOnboardingActive(id, !asBool(qr['isActive']));
      ref.invalidate(_qrCodesProvider);
    } catch (e) {
      showErrorToast(e, 'Failed to update QR code');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _delete(Map<String, dynamic> qr) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete QR code?',
      message: '"${str(qr['label'])}" will stop working for anyone who scans it.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    final id = idOf(qr);
    setState(() => _busy = '$id:delete');
    try {
      await ref.read(enterpriseApiProvider).deleteQrOnboarding(id);
      showToast('QR code deleted', type: ToastType.success);
      ref.invalidate(_qrCodesProvider);
    } catch (e) {
      showErrorToast(e, 'Failed to delete QR code');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_qrCodesProvider);
    final perms = ref.watch(companyPermissionsProvider).valueOrNull ?? const CompanyPermissions();
    final canManage = !perms.ready || perms.can('qr_onboarding', 'manage');

    return Scaffold(
      appBar: AppBar(title: const Text('QR & Onboarding')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            const Text(
              "Print or share a QR — candidates scan it and fill the same details you'd enter when "
              'inviting them. Track them under Team Management → Pending invitations.',
              style: TextStyle(color: AppColors.inkMuted, height: 1.45),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => context.go('/company/team'),
                child: const Text('Open Team Management'),
              ),
            ),
            if (canManage) ...[
              const SizedBox(height: 4),
              AppCard(
                title: 'Create QR code',
                subtitle: 'Give it a label so you can tell campaigns apart.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppTextField(
                      controller: _label,
                      label: 'Campaign Label',
                      requiredMark: true,
                      hint: 'Campus Hiring 2026',
                      enabled: !_creating,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: _department,
                      label: 'Department',
                      hint: 'Optional',
                      helper: 'Pre-fills for whoever scans this code',
                      enabled: !_creating,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: _designation,
                      label: 'Role / Designation',
                      hint: 'Optional',
                      enabled: !_creating,
                    ),
                    const SizedBox(height: 16),
                    AppButton(
                      label: _creating ? 'Generating…' : 'Generate QR Code',
                      icon: Icons.qr_code_2,
                      loading: _creating,
                      onPressed: _creating || _label.text.trim().isEmpty ? null : _create,
                    ),
                  ],
                ),
              ),
            ],
            AsyncValueView<List<Map<String, dynamic>>>(
              value: async,
              loadingLabel: 'Loading QR codes...',
              onRetry: () => ref.invalidate(_qrCodesProvider),
              data: (qrCodes) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(qrCodes.isEmpty ? 'Your QR codes' : 'Your QR codes (${qrCodes.length})'),
                  if (qrCodes.isEmpty)
                    const EmptyState(
                      icon: Icons.qr_code_2,
                      title: 'No QR codes yet',
                      message: 'Create one and share it at drives, walk-ins or on your careers page.',
                    )
                  else
                    for (final qr in qrCodes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _QrCard(
                          qr: qr,
                          canManage: canManage,
                          disabled: _busy != null,
                          busyAction: _busy != null && _busy!.startsWith('${idOf(qr)}:')
                              ? _busy!.substring(idOf(qr).length + 1)
                              : null,
                          onToggle: () => _toggle(qr),
                          onDelete: () => _delete(qr),
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({
    required this.qr,
    required this.canManage,
    required this.disabled,
    required this.busyAction,
    required this.onToggle,
    required this.onDelete,
  });

  final Map<String, dynamic> qr;
  final bool canManage;
  final bool disabled;
  final String? busyAction;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final label = str(qr['label'], 'QR code');
    final active = asBool(qr['isActive']);
    final link = _joinLink(qr);
    final roleLine = [str(qr['designation']), str(qr['department'])].where((s) => s.isNotEmpty).join(' · ');

    Widget stat(String name, Object? value, Color color) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name.toUpperCase(),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.inkFaint)),
            Text(
              '${asInt(value)}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color),
            ),
          ],
        );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Opacity(
                opacity: active ? 1 : 0.4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadii.control),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: QrImageView(
                    data: link,
                    size: 112,
                    backgroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    eyeStyle: QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: active ? AppColors.brand600 : AppColors.inkMuted,
                    ),
                    dataModuleStyle: QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: active ? AppColors.brand600 : AppColors.inkMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.inkStrong,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        StatusBadge(
                          active ? 'active' : 'paused',
                          label: active ? 'Active' : 'Paused',
                          tone: active ? Tone.success : Tone.neutral,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${roleLine.isEmpty ? 'Any role' : roleLine} · ${formatDate(qr['createdAt'])}',
                      style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        stat('Scans', qr['scans'], AppColors.inkStrong),
                        const SizedBox(width: 20),
                        stat('Invited', qr['joined'], AppColors.brand600),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(AppRadii.control),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    link,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.inkBody),
                  ),
                ),
                TextButton(
                  onPressed: () => copyToClipboard(link, message: 'Link copied'),
                  child: const Text('Copy link'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppButton(
                label: 'Share',
                icon: Icons.ios_share,
                variant: AppButtonVariant.outline,
                compact: true,
                expand: false,
                onPressed: () => Share.share('Join $label on PagerLook: $link', subject: label),
              ),
              if (canManage) ...[
                AppButton(
                  label: active ? 'Pause' : 'Activate',
                  icon: active ? Icons.pause_circle_outline : Icons.play_circle_outline,
                  variant: AppButtonVariant.outline,
                  compact: true,
                  expand: false,
                  loading: busyAction == 'toggle',
                  onPressed: disabled ? null : onToggle,
                ),
                AppButton(
                  label: 'Delete',
                  icon: Icons.delete_outline,
                  variant: AppButtonVariant.ghost,
                  compact: true,
                  expand: false,
                  loading: busyAction == 'delete',
                  onPressed: disabled ? null : onDelete,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
