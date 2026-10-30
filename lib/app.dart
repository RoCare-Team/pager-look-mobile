import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/platform/app_lock.dart';
import 'core/providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/feedback.dart';

class VeriWorkApp extends ConsumerWidget {
  const VeriWorkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    // The refresh token was rejected — the guards already moved the user to a
    // login screen; tell them why.
    ref.listen(authProvider.select((a) => a.sessionExpired), (previous, expired) {
      if (expired && previous != true) {
        showToast('Your session has expired. Please sign in again.', type: ToastType.error);
      }
    });

    return MaterialApp.router(
      title: 'PagerLook',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      themeMode: ThemeMode.light,
      scaffoldMessengerKey: rootMessengerKey,
      routerConfig: router,
      builder: (context, child) {
        // Respect the user's text size, within limits that keep layouts intact.
        final media = MediaQuery.of(context);
        final scaler = media.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.3);
        return MediaQuery(
          data: media.copyWith(textScaler: scaler),
          child: GestureDetector(
            // Tap outside a field to dismiss the keyboard.
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            behavior: HitTestBehavior.translucent,
            // iOS: Face ID / Touch ID lock screen over the app when enabled.
            child: AppLockGate(child: child ?? const SizedBox.shrink()),
          ),
        );
      },
    );
  }
}
