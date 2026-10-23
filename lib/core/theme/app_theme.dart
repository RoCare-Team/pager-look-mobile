import 'package:flutter/material.dart';

/// Tokens from the web design system (`DESIGN_SYSTEM.md`, "Quiet Infrastructure").
/// Never hard-code a hex in a screen — add a token here.
class AppColors {
  AppColors._();

  // Neutrals
  static const canvas = Color(0xFFFAFAFA);
  static const surface = Color(0xFFFFFFFF);
  static const sidebar = Color(0xFFFCFCFD);
  static const hairline = Color(0xFFECECEF);
  static const line = Color(0xFFE1E1E6);

  // Ink
  static const inkStrong = Color(0xFF09090B);
  static const inkBody = Color(0xFF3F3F46);
  static const inkMuted = Color(0xFF71717A);
  static const inkFaint = Color(0xFFA1A1AA);

  // Brand navy — an accent, not a surface.
  static const brand50 = Color(0xFFEDF0F8);
  static const brand100 = Color(0xFFD6DCEE);
  static const brand500 = Color(0xFF233B8A);
  static const brand600 = Color(0xFF152763); // primary — user-chosen royal navy
  static const brand700 = Color(0xFF101E4D);
  static const brand900 = Color(0xFF0E1D4A);

  // Sky accent — the bright "fintech" blue used for icon tiles and highlights.
  static const sky = Color(0xFF152763);
  static const skyBg = Color(0xFFE8ECF7);
  static const skyDeep = Color(0xFF152763);

  // Icon-tile accents, so grids read as distinct services.
  static const tileBlue = Color(0xFF2563EB);
  static const tileGreen = Color(0xFF059669);
  static const tilePurple = Color(0xFF7C3AED);
  static const tileOrange = Color(0xFFEA580C);
  static const tilePink = Color(0xFFDB2777);
  static const tileTeal = Color(0xFF0891B2);
  static const tileIndigo = Color(0xFF4F46E5);
  static const tileAmber = Color(0xFFD97706);

  // Semantic
  static const success = Color(0xFF059669);
  static const successBg = Color(0xFFECFDF5);
  static const warning = Color(0xFFD97706);
  static const warningBg = Color(0xFFFFFBEB);
  static const danger = Color(0xFFDC2626);
  static const dangerBg = Color(0xFFFEF2F2);
  static const info = Color(0xFF2747B2);
  static const infoBg = Color(0xFFEFF3FC);

  // Score bands, low → high (credit-score style gauge).
  static const scoreHighRisk = Color(0xFFF87171);
  static const scoreNeedsWork = Color(0xFFFB923C);
  static const scoreFair = Color(0xFFFBBF24);
  static const scoreGood = Color(0xFFA3E635);
  static const scoreExcellent = Color(0xFF4ADE80);
  static const scoreElite = Color(0xFF22C55E);
}

class AppRadii {
  AppRadii._();
  static const card = 12.0;
  static const control = 10.0;
}

/// Semantic tone used by badges, banners and stat tiles.
enum Tone { neutral, brand, success, warning, danger, info }

extension ToneColors on Tone {
  Color get fg => switch (this) {
        Tone.neutral => AppColors.inkBody,
        Tone.brand => AppColors.brand600,
        Tone.success => AppColors.success,
        Tone.warning => AppColors.warning,
        Tone.danger => AppColors.danger,
        Tone.info => AppColors.info,
      };

  Color get bg => switch (this) {
        Tone.neutral => const Color(0xFFF4F4F5),
        Tone.brand => AppColors.brand50,
        Tone.success => AppColors.successBg,
        Tone.warning => AppColors.warningBg,
        Tone.danger => AppColors.dangerBg,
        Tone.info => AppColors.infoBg,
      };
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand600,
      primary: AppColors.brand600,
      onPrimary: Colors.white,
      secondary: AppColors.brand500,
      error: AppColors.danger,
      surface: AppColors.surface,
      onSurface: AppColors.inkStrong,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final text = base.textTheme.apply(bodyColor: AppColors.inkBody, displayColor: AppColors.inkStrong);

    final controlShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control));
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: c, width: w),
        );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.canvas,
      textTheme: text.copyWith(
        headlineSmall:
            text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3, color: AppColors.inkStrong),
        titleLarge:
            text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2, color: AppColors.inkStrong),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.inkStrong),
        titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: AppColors.inkStrong),
        bodyMedium: text.bodyMedium?.copyWith(color: AppColors.inkBody, height: 1.45),
        bodySmall: text.bodySmall?.copyWith(color: AppColors.inkMuted),
        labelSmall:
            text.labelSmall?.copyWith(color: AppColors.inkFaint, letterSpacing: 0.6, fontWeight: FontWeight.w600),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.inkStrong,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle:
            TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.inkStrong, letterSpacing: -0.2),
        shape: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: const BorderSide(color: AppColors.hairline),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.hairline, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: const TextStyle(color: AppColors.inkFaint),
        labelStyle: const TextStyle(color: AppColors.inkMuted),
        border: border(AppColors.line),
        enabledBorder: border(AppColors.line),
        focusedBorder: border(AppColors.brand600, 1.5),
        errorBorder: border(AppColors.danger),
        focusedErrorBorder: border(AppColors.danger, 1.5),
        disabledBorder: border(AppColors.hairline),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brand600,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.brand100,
          disabledForegroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          shape: controlShape,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.inkStrong,
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: AppColors.line),
          shape: controlShape,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.brand600,
          shape: controlShape,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.brand50,
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: const TextStyle(color: AppColors.inkBody, fontWeight: FontWeight.w500),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.skyBg,
        elevation: 0,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? AppColors.brand600 : AppColors.inkFaint,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 26,
            color: states.contains(WidgetState.selected) ? AppColors.sky : AppColors.inkFaint,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.card)),
      ),
      listTileTheme: const ListTileThemeData(iconColor: AppColors.inkMuted),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.brand600),
    );
  }
}
