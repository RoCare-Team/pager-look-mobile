import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/visuals.dart';

/// Shown while the stored session is restored (web: the `booting` loader).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandLogo(height: 44),
            SizedBox(height: 28),
            SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
          ],
        ),
      ),
    );
  }
}
