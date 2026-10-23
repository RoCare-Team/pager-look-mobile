import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';

/// Port of `components/common/MessageThread.jsx` — the conversation attached
/// to an onboarding application. [viewerRole] decides which bubbles are "mine".
class MessageThread extends StatefulWidget {
  const MessageThread({
    super.key,
    required this.messages,
    required this.onSend,
    this.viewerRole = 'company',
    this.isLoading = false,
    this.title = 'Messages',
    this.subtitle,
    this.placeholder = 'Write a message…',
  });

  final List<Map<String, dynamic>> messages;

  /// Sends the text; resolves true on success so the input can be cleared.
  final Future<bool> Function(String text) onSend;
  final String viewerRole;
  final bool isLoading;
  final String title;
  final String? subtitle;
  final String placeholder;

  @override
  State<MessageThread> createState() => _MessageThreadState();
}

class _MessageThreadState extends State<MessageThread> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final ok = await widget.onSend(text);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (ok) _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxBubble = MediaQuery.sizeOf(context).width * 0.72;

    Widget body;
    if (widget.isLoading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Loading…', style: TextStyle(fontSize: 13, color: AppColors.inkFaint)),
      );
    } else if (widget.messages.isEmpty) {
      body = Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(AppRadii.control)),
        child: const Text(
          'No messages yet. Ask a question and our team will reply here.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: widget.messages.map((m) {
          final text = str(m['body']);
          if (asBool(m['isSystem'])) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '$text · ${formatDate(m['createdAt'])}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.inkFaint),
              ),
            );
          }
          final mine = str(m['authorRole']) == widget.viewerRole;
          final docKey = str(m['documentKey']);
          final fg = mine ? Colors.white : AppColors.inkStrong;
          final faint = mine ? Colors.white.withValues(alpha: 0.7) : AppColors.inkMuted;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxBubble),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: mine ? AppColors.brand600 : Tone.neutral.bg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!mine)
                        Text(
                          str(m['authorName']).toUpperCase(),
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: faint),
                        ),
                      if (docKey.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('Re: $docKey',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: faint)),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(text, style: TextStyle(fontSize: 14, color: fg, height: 1.35)),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(formatDate(m['createdAt']), style: TextStyle(fontSize: 10, color: faint)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      );
    }

    return AppCard(
      title: widget.title,
      subtitle: widget.subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          body,
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  enabled: !_sending,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(hintText: widget.placeholder),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: AppButton(
                  label: _sending ? 'Sending…' : 'Send',
                  loading: _sending,
                  compact: true,
                  onPressed: _controller.text.trim().isEmpty ? null : _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
