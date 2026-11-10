import 'package:flutter/material.dart';

/// Design tokens copied from the macOS app (Sources/App/Theme.swift).
class AppColors {
  static const accent = Color(0xFF3D5AFE);
  static const accentBright = Color(0xFF5B78FF);
  static const accentSoft = Color(0xFFA7B4F5);
  static const accentDeep = Color(0xFF1B2E8F);

  static const gold = Color(0xFFF5C04A);
  static const green = Color(0xFF35D07F);
  static const red = Color(0xFFF0555A);

  static const darkBg = Color(0xFF0A0B10);
  static const darkSidebar = Color(0xFF08090E);
  static const darkElevated = Color(0xFF11131B);
  static const darkCard = Color(0xFF14161F);
  static const darkStroke = Color(0xFF232736);
  static const darkSeparator = Color(0xFF1A1D27);
  static const darkText = Color(0xFFF2F3F7);
  static const darkTextSecondary = Color(0xFF9BA0B4);
  static const darkTextTertiary = Color(0xFF6D7286);

  static const lightBg = Color(0xFFF6F7FB);
  static const lightSidebar = Color(0xFFEDEFF6);
  static const lightElevated = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightStroke = Color(0xFFD6DAE7);
  static const lightSeparator = Color(0xFFE2E5EF);
  static const lightText = Color(0xFF12141C);
  static const lightTextSecondary = Color(0xFF5C6275);
  static const lightTextTertiary = Color(0xFF878DA1);
}

class AppRadii {
  static const small = 8.0;
  static const normal = 14.0;
  static const large = 22.0;
}

class AppTheme {
  static const String fontFamily = 'Vazirmatn';

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: Colors.white,
      secondary: AppColors.accentBright,
      onSecondary: Colors.white,
      surface: AppColors.darkCard,
      onSurface: AppColors.darkText,
      error: AppColors.red,
      onError: Colors.white,
      outline: AppColors.darkStroke,
    );
    return _base(
      scheme,
      scaffold: AppColors.darkBg,
      card: AppColors.darkCard,
      elevated: AppColors.darkElevated,
      stroke: AppColors.darkStroke,
      text: AppColors.darkText,
      secondaryText: AppColors.darkTextSecondary,
      tertiaryText: AppColors.darkTextTertiary,
    );
  }

  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: AppColors.accent,
      onPrimary: Colors.white,
      secondary: AppColors.accentDeep,
      onSecondary: Colors.white,
      surface: AppColors.lightCard,
      onSurface: AppColors.lightText,
      error: AppColors.red,
      onError: Colors.white,
      outline: AppColors.lightStroke,
    );
    return _base(
      scheme,
      scaffold: AppColors.lightBg,
      card: AppColors.lightCard,
      elevated: AppColors.lightElevated,
      stroke: AppColors.lightStroke,
      text: AppColors.lightText,
      secondaryText: AppColors.lightTextSecondary,
      tertiaryText: AppColors.lightTextTertiary,
    );
  }

  static ThemeData _base(
    ColorScheme scheme, {
    required Color scaffold,
    required Color card,
    required Color elevated,
    required Color stroke,
    required Color text,
    required Color secondaryText,
    required Color tertiaryText,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      fontFamily: fontFamily,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    TextStyle style(double size, FontWeight weight, Color color) => TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: 1.55,
        );

    return base.copyWith(
      canvasColor: scaffold,
      cardColor: card,
      dividerColor: stroke,
      iconTheme: IconThemeData(color: secondaryText, size: 20),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: style(18, FontWeight.w700, text),
        iconTheme: IconThemeData(color: secondaryText),
      ),
      textTheme: TextTheme(
        displayLarge: style(34, FontWeight.w800, text),
        headlineMedium: style(24, FontWeight.w700, text),
        titleLarge: style(19, FontWeight.w700, text),
        titleMedium: style(16, FontWeight.w600, text),
        titleSmall: style(14, FontWeight.w600, text),
        bodyLarge: style(15, FontWeight.w400, text),
        bodyMedium: style(13.5, FontWeight.w400, text),
        bodySmall: style(12, FontWeight.w400, secondaryText),
        labelLarge: style(13.5, FontWeight.w600, text),
        labelMedium: style(12, FontWeight.w500, secondaryText),
        labelSmall: style(11, FontWeight.w400, tertiaryText),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        hintStyle: style(13.5, FontWeight.w400, tertiaryText),
        prefixIconColor: secondaryText,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.normal),
          borderSide: BorderSide(color: stroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.normal),
          borderSide: BorderSide(color: stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.normal),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: elevated,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.accent.withValues(alpha: 0.18),
        labelTextStyle: WidgetStatePropertyAll(
          style(11, FontWeight.w500, secondaryText),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.accentBright
                : secondaryText,
            size: 22,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          textStyle: style(14, FontWeight.w700, Colors.white),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.normal),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: stroke),
          textStyle: style(13.5, FontWeight.w600, text),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.normal),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: card,
        selectedColor: AppColors.accent,
        side: BorderSide(color: stroke),
        labelStyle: style(12.5, FontWeight.w500, secondaryText),
        secondaryLabelStyle: style(12.5, FontWeight.w600, Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: AppColors.accent,
        inactiveTrackColor: stroke,
        thumbColor: AppColors.accentBright,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: elevated,
        contentTextStyle: style(13, FontWeight.w400, text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.normal),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: elevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.large),
        ),
        titleTextStyle: style(17, FontWeight.w700, text),
        contentTextStyle: style(13.5, FontWeight.w400, text),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: elevated,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dividerTheme: DividerThemeData(color: stroke, thickness: 1),
    );
  }
}

/// Extra semantic colors that Material does not carry.
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.card,
    required this.elevated,
    required this.stroke,
    required this.textSecondary,
    required this.textTertiary,
    required this.sidebar,
  });

  final Color card;
  final Color elevated;
  final Color stroke;
  final Color textSecondary;
  final Color textTertiary;
  final Color sidebar;

  @override
  AppPalette copyWith({
    Color? card,
    Color? elevated,
    Color? stroke,
    Color? textSecondary,
    Color? textTertiary,
    Color? sidebar,
  }) =>
      AppPalette(
        card: card ?? this.card,
        elevated: elevated ?? this.elevated,
        stroke: stroke ?? this.stroke,
        textSecondary: textSecondary ?? this.textSecondary,
        textTertiary: textTertiary ?? this.textTertiary,
        sidebar: sidebar ?? this.sidebar,
      );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      card: Color.lerp(card, other.card, t)!,
      elevated: Color.lerp(elevated, other.elevated, t)!,
      stroke: Color.lerp(stroke, other.stroke, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
    );
  }

  static const dark = AppPalette(
    card: AppColors.darkCard,
    elevated: AppColors.darkElevated,
    stroke: AppColors.darkStroke,
    textSecondary: AppColors.darkTextSecondary,
    textTertiary: AppColors.darkTextTertiary,
    sidebar: AppColors.darkSidebar,
  );

  static const light = AppPalette(
    card: AppColors.lightCard,
    elevated: AppColors.lightElevated,
    stroke: AppColors.lightStroke,
    textSecondary: AppColors.lightTextSecondary,
    textTertiary: AppColors.lightTextTertiary,
    sidebar: AppColors.lightSidebar,
  );
}

extension AppThemeContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;

  Color get textSecondary => palette.textSecondary;

  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
