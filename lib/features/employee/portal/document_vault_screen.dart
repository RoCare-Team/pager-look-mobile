import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';

final _vaultProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return asMap(await ref.watch(employeeApiProvider).fetchVault());
});

class _CategoryMeta {
  const _CategoryMeta(this.label, this.icon, this.tone);
  final String label;
  final IconData icon;
  final Tone tone;
}

/// Web `VAULT_CATEGORY_META` (+ the icons of `VaultCategoryCard.jsx`).
const Map<String, _CategoryMeta> _categoryMeta = {
  'identity': _CategoryMeta('Identity', Icons.badge_outlined, Tone.info),
  'education': _CategoryMeta('Education', Icons.school_outlined, Tone.brand),
  'experience': _CategoryMeta('Experience', Icons.work_outline, Tone.success),
  'financial': _CategoryMeta('Financial', Icons.account_balance_wallet_outlined, Tone.warning),
};

class _Category {
  const _Category(this.id, this.label, this.files);
  final String id;
  final String label;
  final int files;

  _CategoryMeta get meta => _categoryMeta[id] ?? _CategoryMeta(label, Icons.folder_outlined, Tone.neutral);
}

/// Web `formatSize`.
String _formatSize(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Vault tab — port of `DocumentVault.jsx`.
class DocumentVaultScreen extends ConsumerStatefulWidget {
  const DocumentVaultScreen({super.key});

  @override
  ConsumerState<DocumentVaultScreen> createState() => _DocumentVaultScreenState();
}

class _DocumentVaultScreenState extends ConsumerState<DocumentVaultScreen> {
  bool _uploading = false;

  List<_Category> _categories(Map<String, dynamic> data, List<Map<String, dynamic>> items) {
    final fromApi = asMapList(data['categories']);
    if (fromApi.isNotEmpty) {
      return fromApi.map((c) {
        final id = str(c['id'] ?? c['category']);
        return _Category(id, str(c['label'], _categoryMeta[id]?.label ?? id), asInt(c['count'] ?? c['files']));
      }).toList();
    }
    return _categoryMeta.entries
        .map((e) => _Category(e.key, e.value.label, items.where((d) => str(d['category']) == e.key).length))
        .toList();
  }

  Future<void> _startUpload(List<_Category> categories, String initial) async {
    if (_uploading) return;
    final category = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => _CategorySheet(categories: categories, initial: initial),
    );
    if (category == null || !mounted) return;
    final label = categories.firstWhere((c) => c.id == category, orElse: () => _Category(category, category, 0)).label;
    final file = await pickDocumentWithSheet(context, title: 'Upload to $label');
    if (file == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      await ref.read(employeeApiProvider).uploadVaultDocument(
            category: category,
            name: file.name,
            file: file,
            size: _formatSize(file.size),
          );
      showToast('Document uploaded', type: ToastType.success);
      ref.invalidate(_vaultProvider);
    } catch (e) {
      showErrorToast(e, 'Upload failed');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vaultAsync = ref.watch(_vaultProvider);
    final loaded = vaultAsync.valueOrNull;
    final loadedItems = loaded == null ? const <Map<String, dynamic>>[] : asMapList(loaded['items']);
    final loadedCategories = loaded == null ? const <_Category>[] : _categories(loaded, loadedItems);

    return Scaffold(
      appBar: AppBar(title: const Text('Document Vault')),
      floatingActionButton: loaded == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _uploading ? null : () => _startUpload(loadedCategories, 'identity'),
              icon: _uploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.add),
              label: Text(_uploading ? 'Uploading...' : 'Upload File'),
              backgroundColor: AppColors.brand600,
              foregroundColor: Colors.white,
            ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(_vaultProvider.future),
        child: AsyncValueView<Map<String, dynamic>>(
          value: vaultAsync,
          loadingLabel: 'Loading vault...',
          onRetry: () => ref.invalidate(_vaultProvider),
          data: (data) {
            final items = asMapList(data['items']);
            final categories = _categories(data, items);
            final recentSource = data['recentDocuments'] is List ? asMapList(data['recentDocuments']) : items;
            final recent = [...recentSource]..sort((a, b) {
                final da = asDate(a['createdAt']) ?? DateTime(1970);
                final db = asDate(b['createdAt']) ?? DateTime(1970);
                return db.compareTo(da);
              });
            final recentDocs = recent.take(5).toList();
            final totalDocs = asInt(pick(data, 'summary.totalDocuments'), items.length);
            final verifiedCount = asInt(
              pick(data, 'summary.verifiedCount'),
              items.where((d) => str(d['status']) == 'verified').length,
            );
            final storagePercent = totalDocs > 0 ? ((totalDocs / 20) * 100).round().clamp(0, 100).toInt() : 0;

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                const PageIntro(
                  title: 'Your documents',
                  subtitle: 'Securely store and manage your verified documents',
                ),
                _StorageHero(total: totalDocs, verified: verifiedCount, percent: storagePercent),
                const SectionHeader('Categories'),
                StatGrid(
                  children: categories
                      .map((c) => _CategoryCard(
                            category: c,
                            onTap: _uploading ? null : () => _startUpload(categories, c.id),
                          ))
                      .toList(),
                ),
                const SectionHeader('Recent Documents'),
                if (recentDocs.isEmpty)
                  const AppCard(
                    child: Text(
                      'No documents uploaded yet',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.inkMuted),
                    ),
                  )
                else
                  for (final doc in recentDocs)
                    Padding(padding: const EdgeInsets.only(bottom: 10), child: _DocTile(doc: doc)),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: () => context.push('/employee/job-history/add'),
                    child: const Text('Upload experience documents →'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StorageHero extends StatelessWidget {
  const _StorageHero({required this.total, required this.verified, required this.percent});

  final int total;
  final int verified;
  final int percent;

  @override
  Widget build(BuildContext context) {
    return ProgressSummaryCard(
      progress: percent / 100,
      centerLabel: '$percent%',
      title: '$total document${total == 1 ? '' : 's'}',
      caption: '$verified verified · Encrypted & secure',
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, this.onTap});

  final _Category category;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final meta = category.meta;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: meta.tone.bg, borderRadius: BorderRadius.circular(12)),
            child: Icon(meta.icon, color: meta.tone.fg),
          ),
          const SizedBox(height: 12),
          Text(category.label, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkStrong)),
          const SizedBox(height: 2),
          Text('${category.files} Files', style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
          const SizedBox(height: 12),
          Container(
            height: 4,
            decoration: BoxDecoration(color: meta.tone.fg, borderRadius: BorderRadius.circular(99)),
          ),
        ],
      ),
    );
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({required this.doc});

  final Map<String, dynamic> doc;

  @override
  Widget build(BuildContext context) {
    final verified = str(doc['status']) == 'verified';
    final sizeOrCategory = strOrNull(doc['size']) ?? humanize(doc['category']);
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.brand50, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.description_outlined, color: AppColors.brand600, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  str(doc['name'], 'Document'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkStrong),
                ),
                const SizedBox(height: 2),
                Text(
                  '$sizeOrCategory • ${formatDate(doc['createdAt'])}',
                  style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusBadge(null, label: verified ? 'Verified' : 'Pending', tone: verified ? Tone.success : Tone.warning),
        ],
      ),
    );
  }
}

/// Bottom sheet: choose the category, then continue to the file picker.
class _CategorySheet extends StatefulWidget {
  const _CategorySheet({required this.categories, required this.initial});

  final List<_Category> categories;
  final String initial;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  late String _selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Upload a document', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text('Choose a category for this file.', style: TextStyle(color: AppColors.inkMuted)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.categories
                  .map(
                    (c) => ChoiceChip(
                      avatar: Icon(c.meta.icon, size: 18),
                      label: Text(c.label),
                      selected: _selected == c.id,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _selected = c.id),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 20),
            AppButton(
              label: 'Choose file',
              icon: Icons.upload_file,
              onPressed: () => Navigator.of(context).pop(_selected),
            ),
          ],
        ),
      ),
    );
  }
}
