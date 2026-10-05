import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Screen Guardian design system.
///
/// Brand direction: "calm guardian, playful kid". A deep teal primary carries
/// trust for parents, warm coral / amber accents keep it friendly for
/// children, and a warm off-white canvas with white cards replaces the
/// default Material tonal surfaces.
///
/// Every colour used by the app should come from [ColorScheme] or the
/// [GuardianColors] extension so screens never hard-code hex values.
class AppTheme {
  AppTheme._();

  static const String fontFamily = 'Nunito';

  // Brand palette --------------------------------------------------------
  static const Color teal = Color(0xFF0B7B7A);
  static const Color tealDark = Color(0xFF075756);
  static const Color tealLight = Color(0xFF5CC8C4);
  static const Color coral = Color(0xFFFF7A5C);
  static const Color amber = Color(0xFFF5B532);
  static const Color ink = Color(0xFF1B2430);
  static const Color inkSoft = Color(0xFF5B6470);
  static const Color cream = Color(0xFFF7F4EF);

  static ThemeData get light => _build(_lightScheme, _lightExtras);
  static ThemeData get dark => _build(_darkScheme, _darkExtras);

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: teal,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFCDEFEA),
    onPrimaryContainer: Color(0xFF03302F),
    secondary: coral,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFFFE1D8),
    onSecondaryContainer: Color(0xFF4A1A0E),
    tertiary: amber,
    onTertiary: Color(0xFF3A2700),
    tertiaryContainer: Color(0xFFFFECBF),
    onTertiaryContainer: Color(0xFF3A2700),
    error: Color(0xFFD93F3F),
    onError: Colors.white,
    errorContainer: Color(0xFFFFDCD9),
    onErrorContainer: Color(0xFF5A0F0F),
    surface: cream,
    onSurface: ink,
    onSurfaceVariant: inkSoft,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Color(0xFFF1EDE6),
    surfaceContainer: Color(0xFFEBE6DE),
    surfaceContainerHigh: Color(0xFFE4DED5),
    surfaceContainerHighest: Color(0xFFDDD6CC),
    surfaceDim: Color(0xFFE6E2DB),
    surfaceBright: Colors.white,
    inverseSurface: ink,
    onInverseSurface: Color(0xFFF2F4F7),
    inversePrimary: tealLight,
    outline: Color(0xFFA7ADB6),
    outlineVariant: Color(0xFFE3DED5),
    shadow: Color(0xFF1B2430),
    scrim: Color(0xFF0B1118),
  );

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: tealLight,
    onPrimary: Color(0xFF003736),
    primaryContainer: Color(0xFF0B4F4E),
    onPrimaryContainer: Color(0xFFBDEEEA),
    secondary: Color(0xFFFF9D86),
    onSecondary: Color(0xFF4A1A0E),
    secondaryContainer: Color(0xFF6B2A1B),
    onSecondaryContainer: Color(0xFFFFE1D8),
    tertiary: Color(0xFFFFC85C),
    onTertiary: Color(0xFF3A2700),
    tertiaryContainer: Color(0xFF5C4000),
    onTertiaryContainer: Color(0xFFFFECBF),
    error: Color(0xFFFF7B7B),
    onError: Color(0xFF4A0A0A),
    errorContainer: Color(0xFF7A1F1F),
    onErrorContainer: Color(0xFFFFDCD9),
    surface: Color(0xFF0F1720),
    onSurface: Color(0xFFEEF1F5),
    onSurfaceVariant: Color(0xFFA9B2BE),
    surfaceContainerLowest: Color(0xFF0A1016),
    surfaceContainerLow: Color(0xFF16202B),
    surfaceContainer: Color(0xFF1C2733),
    surfaceContainerHigh: Color(0xFF232F3C),
    surfaceContainerHighest: Color(0xFF2B3846),
    surfaceDim: Color(0xFF0F1720),
    surfaceBright: Color(0xFF2B3846),
    inverseSurface: Color(0xFFEEF1F5),
    onInverseSurface: ink,
    inversePrimary: teal,
    outline: Color(0xFF6D7784),
    outlineVariant: Color(0xFF2E3A48),
    shadow: Colors.black,
    scrim: Colors.black,
  );

  static const GuardianColors _lightExtras = GuardianColors(
    card: Colors.white,
    cardBorder: Color(0xFFE3DED5),
    success: Color(0xFF2E9E6B),
    onSuccess: Colors.white,
    successContainer: Color(0xFFD7F3E4),
    onSuccessContainer: Color(0xFF0B3D25),
    heroTop: ink,
    heroBottom: Color(0xFF2A3A4F),
    onHero: Colors.white,
  );

  static const GuardianColors _darkExtras = GuardianColors(
    card: Color(0xFF16202B),
    cardBorder: Color(0xFF2E3A48),
    success: Color(0xFF5FD39A),
    onSuccess: Color(0xFF00391F),
    successContainer: Color(0xFF14503A),
    onSuccessContainer: Color(0xFFD7F3E4),
    heroTop: Color(0xFF0A1016),
    heroBottom: Color(0xFF1C2733),
    onHero: Colors.white,
  );

  static ThemeData _build(ColorScheme scheme, GuardianColors extras) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
    );
    final text = _textTheme(base.textTheme, scheme.onSurface);

    RoundedRectangleBorder radius(double r) =>
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));

    return base.copyWith(
      textTheme: text,
      extensions: <ThemeExtension<dynamic>>[extras],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: scheme.onSurface, size: 24),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: extras.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: extras.cardBorder),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: radius(16),
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: text.titleMedium,
        subtitleTextStyle:
            text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: radius(16),
          textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: radius(16),
          side: BorderSide(color: scheme.outlineVariant, width: 1.5),
          foregroundColor: scheme.onSurface,
          textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: radius(12),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: radius(14),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        shape: radius(18),
        extendedTextStyle:
            text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: extras.card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        labelStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: extras.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: extras.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: radius(12),
        side: BorderSide(color: extras.cardBorder),
        backgroundColor: extras.card,
        selectedColor: scheme.primaryContainer,
        labelStyle: text.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        showCheckmark: false,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: scheme.outlineVariant,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: extras.card,
        surfaceTintColor: Colors.transparent,
        shape: radius(24),
        titleTextStyle: text.titleLarge,
        contentTextStyle:
            text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: radius(14),
        backgroundColor: scheme.inverseSurface,
        contentTextStyle:
            text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 8,
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHigh,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
        valueIndicatorColor: scheme.inverseSurface,
        valueIndicatorTextStyle:
            text.labelLarge?.copyWith(color: scheme.onInverseSurface),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : scheme.outline),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.surfaceContainerHighest),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: radius(6),
        side: BorderSide(color: scheme.outline, width: 1.5),
      ),
      dividerTheme: DividerThemeData(
        color: extras.cardBorder,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHigh,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: scheme.secondary,
        textColor: scheme.onSecondary,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base, Color color) {
    TextStyle s(double size, FontWeight weight,
            {double? height, double letterSpacing = 0}) =>
        TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          fontWeight: weight,
          height: height,
          letterSpacing: letterSpacing,
          color: color,
        );
    return TextTheme(
      displayLarge: s(56, FontWeight.w800, height: 1.05, letterSpacing: -1),
      displayMedium: s(44, FontWeight.w800, height: 1.05, letterSpacing: -0.8),
      displaySmall: s(36, FontWeight.w800, height: 1.1, letterSpacing: -0.5),
      headlineLarge: s(32, FontWeight.w800, height: 1.15, letterSpacing: -0.4),
      headlineMedium: s(28, FontWeight.w800, height: 1.2, letterSpacing: -0.3),
      headlineSmall: s(24, FontWeight.w800, height: 1.25, letterSpacing: -0.2),
      titleLarge: s(20, FontWeight.w800, height: 1.3),
      titleMedium: s(16, FontWeight.w700, height: 1.35),
      titleSmall: s(14, FontWeight.w700, height: 1.35),
      bodyLarge: s(16, FontWeight.w400, height: 1.5),
      bodyMedium: s(14, FontWeight.w400, height: 1.5),
      bodySmall: s(12, FontWeight.w400, height: 1.45),
      labelLarge: s(14, FontWeight.w700, height: 1.3, letterSpacing: 0.1),
      labelMedium: s(12, FontWeight.w700, height: 1.3, letterSpacing: 0.4),
      labelSmall: s(11, FontWeight.w700, height: 1.3, letterSpacing: 0.5),
    );
  }
}

/// Extra semantic colours that Material's [ColorScheme] does not model.
@immutable
class GuardianColors extends ThemeExtension<GuardianColors> {
  const GuardianColors({
    required this.card,
    required this.cardBorder,
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.heroTop,
    required this.heroBottom,
    required this.onHero,
  });

  final Color card;
  final Color cardBorder;
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  /// Dark "night sky" gradient used on immersive full-screen states.
  final Color heroTop;
  final Color heroBottom;
  final Color onHero;

  @override
  GuardianColors copyWith({
    Color? card,
    Color? cardBorder,
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? heroTop,
    Color? heroBottom,
    Color? onHero,
  }) =>
      GuardianColors(
        card: card ?? this.card,
        cardBorder: cardBorder ?? this.cardBorder,
        success: success ?? this.success,
        onSuccess: onSuccess ?? this.onSuccess,
        successContainer: successContainer ?? this.successContainer,
        onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
        heroTop: heroTop ?? this.heroTop,
        heroBottom: heroBottom ?? this.heroBottom,
        onHero: onHero ?? this.onHero,
      );

  @override
  GuardianColors lerp(GuardianColors? other, double t) {
    if (other == null) return this;
    return GuardianColors(
      card: Color.lerp(card, other.card, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer:
          Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      heroTop: Color.lerp(heroTop, other.heroTop, t)!,
      heroBottom: Color.lerp(heroBottom, other.heroBottom, t)!,
      onHero: Color.lerp(onHero, other.onHero, t)!,
    );
  }
}

extension GuardianThemeX on BuildContext {
  ColorScheme get scheme => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  GuardianColors get guardian => Theme.of(this).extension<GuardianColors>()!;
}

/// Helpers for deriving readable colours from a profile's accent colour.
extension ProfileColorX on Color {
  /// A darker shade of this colour, used for gradients.
  Color darken([double amount = 0.18]) {
    final hsl = HSLColor.fromColor(this);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  Color lighten([double amount = 0.18]) {
    final hsl = HSLColor.fromColor(this);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  /// White or dark ink, whichever reads better on top of this colour.
  Color get readableForeground =>
      computeLuminance() > 0.45 ? AppTheme.ink : Colors.white;
}
