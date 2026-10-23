import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_exception.dart';
import '../theme/app_theme.dart';
import 'app_button.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
            if (label != null) ...[
              const SizedBox(height: 14),
              Text(label!, style: const TextStyle(color: AppColors.inkMuted)),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry, this.title = "Couldn't load this"});

  final Object? error;
  final VoidCallback? onRetry;
  final String title;

  @override
  Widget build(BuildContext context) {
    final forbidden = error is ApiException && (error as ApiException).isForbidden;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(forbidden ? Icons.lock_outline : Icons.cloud_off_outlined, size: 40, color: AppColors.inkFaint),
            const SizedBox(height: 12),
            Text(
              forbidden ? "You don't have access" : title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.inkStrong),
            ),
            const SizedBox(height: 6),
            Text(
              errorMessage(error),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.inkMuted),
            ),
            if (onRetry != null && !forbidden) ...[
              const SizedBox(height: 16),
              AppButton(
                label: 'Try again',
                icon: Icons.refresh,
                variant: AppButtonVariant.outline,
                expand: false,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.message, this.icon = Icons.inbox_outlined, this.action});

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(color: AppColors.brand50, shape: BoxShape.circle),
              child: Icon(icon, size: 26, color: AppColors.brand600),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: AppColors.inkStrong),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.inkMuted)),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Renders an [AsyncValue] with consistent loading / error / data states.
///
/// Keeps showing previous data while refreshing, so pull-to-refresh doesn't
/// flash a spinner over content.
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    super.key,
    required this.value,
    required this.data,
    this.onRetry,
    this.loadingLabel,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;
  final String? loadingLabel;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      data: data,
      loading: () => LoadingView(label: loadingLabel),
      error: (e, _) => ErrorView(error: e, onRetry: onRetry),
    );
  }
}

/// Full-screen translucent blocker shown during a mutation.
class BusyOverlay extends StatelessWidget {
  const BusyOverlay({super.key, required this.busy, required this.child, this.label});

  final bool busy;
  final Widget child;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (busy)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.white.withValues(alpha: 0.7),
              child: LoadingView(label: label),
            ),
          ),
      ],
    );
  }
}
