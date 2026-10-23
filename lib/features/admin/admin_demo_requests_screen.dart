import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/widgets.dart';
import 'admin_utils.dart';

/// Demo requests filed from the public site.
final adminDemoRequestsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, AdminListQuery>((ref, query) async {
  final data = await ref.watch(adminApiProvider).fetchDemoRequests(status: query.status, q: query.q);
  return listFrom(data, const ['requests', 'items']);
});

const _tabs = {
  'new': 'New',
  'contacted': 'Contacted',
  'scheduled': 'Scheduled',
  'closed': 'Closed',
  'all': 'All',
};

const _statuses = ['new', 'contacted', 'scheduled', 'closed'];

Tone _statusTone(String status) => switch (status) {
      'new' => Tone.warning,
      'contacted' => Tone.info,
      'scheduled' => Tone.brand,
      _ => Tone.neutral,
    };

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Port of `pages/admin/AdminDemoRequests.jsx` — leads someone has to call.
class AdminDemoRequestsScreen extends ConsumerStatefulWidget {
  const AdminDemoRequestsScreen({super.key});

  @override
  ConsumerState<AdminDemoRequestsScreen> createState() => _AdminDemoRequestsScreenState();
}

class _AdminDemoRequestsScreenState extends ConsumerState<AdminDemoRequestsScreen> {
  String _status = 'new';
  String _search = '';
  String? _expandedId;
  String? _savingId;

  AdminListQuery get _key => (status: _status, q: _search);

  /// Move a lead along, or leave an internal note on it.
  Future<bool> _update(String id, Map<String, dynamic> body, String successMessage) async {
    setState(() => _savingId = id);
    try {
      await ref.read(adminApiProvider).updateDemoRequest(id, body);
      ref.invalidate(adminDemoRequestsProvider);
      showToast(successMessage, type: ToastType.success);
      return true;
    } catch (e) {
      showErrorToast(e, 'Could not update the demo request');
      return false;
    } finally {
      if (mounted) setState(() => _savingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(adminDemoRequestsProvider(_key));

    return Scaffold(
      appBar: AppBar(title: const Text('Demo requests')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SearchField(
              hint: 'Search name, email, phone, company...',
              onChanged: (q) => setState(() => _search = q),
            ),
          ),
          FilterChipsBar(
            options: _tabs,
            selected: _status,
            onSelected: (key) => setState(() => _status = key),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(adminDemoRequestsProvider(_key).future),
              child: value.when(
                skipLoadingOnRefresh: true,
                skipLoadingOnReload: true,
                loading: () => const LoadingView(label: 'Loading demo requests...'),
                error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.invalidate(adminDemoRequestsProvider(_key)),
                ),
                data: (requests) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Leads from the website\'s "Book a demo" form. Call them, then move the lead along.',
                        style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted),
                      ),
                    ),
                    if (requests.isEmpty)
                      EmptyState(
                        title: _status == 'all' ? 'No demo requests yet.' : 'No $_status demo requests yet.',
                        icon: Icons.campaign_outlined,
                      )
                    else
                      for (final request in requests) ...[
                        _DemoRequestCard(
                          key: ValueKey('demo-${idOf(request)}'),
                          request: request,
                          expanded: _expandedId == idOf(request),
                          saving: _savingId == idOf(request),
                          onToggle: () => setState(() {
                            final id = idOf(request);
                            _expandedId = _expandedId == id ? null : id;
                          }),
                          onStatus: (status) => _update(idOf(request), {'status': status}, 'Status updated'),
                          onSaveNotes: (notes) => _update(idOf(request), {'notes': notes}, 'Note saved'),
                        ),
                        const SizedBox(height: 12),
                      ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoRequestCard extends StatelessWidget {
  const _DemoRequestCard({
    super.key,
    required this.request,
    required this.expanded,
    required this.saving,
    required this.onToggle,
    required this.onStatus,
    required this.onSaveNotes,
  });

  final Map<String, dynamic> request;
  final bool expanded;
  final bool saving;
  final VoidCallback onToggle;
  final Future<bool> Function(String status) onStatus;
  final Future<bool> Function(String notes) onSaveNotes;

  @override
  Widget build(BuildContext context) {
    final status = str(request['status'], 'new');
    final phone = str(request['phone']);
    final email = str(request['email']);
    final teamSize = strOrNull(request['teamSize']);
    final handledBy = strOrNull(pick(request, 'handledBy.email'));
    final message = strOrNull(request['message']);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  str(request['name'], '—'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.inkStrong),
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(status, tone: _statusTone(status), label: _capitalize(status)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${strOrNull(request['company']) ?? 'No company given'}${teamSize != null ? ' · $teamSize people' : ''}',
            style: const TextStyle(fontSize: 13.5, color: AppColors.inkBody),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (phone.isNotEmpty)
                InkWell(
                  onTap: () => openExternalUrl('tel:$phone'),
                  child: Text(
                    phone,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.brand600),
                  ),
                ),
              if (phone.isNotEmpty && email.isNotEmpty)
                const Text('·', style: TextStyle(color: AppColors.inkFaint)),
              if (email.isNotEmpty)
                InkWell(
                  onTap: () => openExternalUrl('mailto:$email'),
                  child: Text(email, style: const TextStyle(fontSize: 13.5, color: AppColors.inkMuted)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Received ${formatDate(request['createdAt'])}${handledBy != null ? ' · last updated by $handledBy' : ''}',
            style: const TextStyle(fontSize: 12, color: AppColors.inkFaint),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _StatusPicker(status: status, saving: saving, onChanged: onStatus)),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  label: expanded ? 'Hide' : 'Details',
                  compact: true,
                  variant: AppButtonVariant.outline,
                  icon: expanded ? Icons.expand_less : Icons.expand_more,
                  onPressed: onToggle,
                ),
              ),
            ],
          ),
          if (expanded) ...[
            const SizedBox(height: 14),
            const Divider(),
            const SizedBox(height: 12),
            const Text(
              'WHAT THEY ASKED FOR',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: AppColors.inkFaint),
            ),
            const SizedBox(height: 4),
            Text(
              message ?? '— nothing written —',
              style: const TextStyle(fontSize: 13.5, color: AppColors.inkBody, height: 1.45),
            ),
            const SizedBox(height: 14),
            const Text(
              'INTERNAL NOTES',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: AppColors.inkFaint),
            ),
            const SizedBox(height: 6),
            _NotesEditor(notes: str(request['notes']), saving: saving, onSave: onSaveNotes),
          ],
        ],
      ),
    );
  }
}

/// Status control (web `<select>`), disabled while this lead is saving.
class _StatusPicker extends StatelessWidget {
  const _StatusPicker({required this.status, required this.saving, required this.onChanged});

  final String status;
  final bool saving;
  final Future<bool> Function(String status) onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      enabled: !saving,
      initialValue: status,
      tooltip: 'Change status',
      onSelected: (value) {
        if (value != status) onChanged(value);
      },
      itemBuilder: (_) => [
        for (final s in _statuses) PopupMenuItem<String>(value: s, child: Text(_capitalize(s))),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.control),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _capitalize(status),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: saving ? AppColors.inkFaint : AppColors.inkBody,
                ),
              ),
            ),
            if (saving)
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            else
              const Icon(Icons.arrow_drop_down, color: AppColors.inkMuted),
          ],
        ),
      ),
    );
  }
}

class _NotesEditor extends StatefulWidget {
  const _NotesEditor({required this.notes, required this.saving, required this.onSave});

  final String notes;
  final bool saving;
  final Future<bool> Function(String notes) onSave;

  @override
  State<_NotesEditor> createState() => _NotesEditorState();
}

class _NotesEditorState extends State<_NotesEditor> {
  late final TextEditingController _controller = TextEditingController(text: widget.notes);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dirty = _controller.text != widget.notes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          minLines: 2,
          maxLines: 6,
          maxLength: 2000,
          enabled: !widget.saving,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Call notes — who you spoke to, what was agreed…',
            counterText: '',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        AppButton(
          label: widget.saving ? 'Saving…' : 'Save note',
          compact: true,
          variant: AppButtonVariant.outline,
          loading: widget.saving,
          onPressed: !dirty || widget.saving ? null : () => widget.onSave(_controller.text),
        ),
      ],
    );
  }
}
