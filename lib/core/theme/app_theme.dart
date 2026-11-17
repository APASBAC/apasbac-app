import 'package:flutter/material.dart';

abstract final class AppColors {
  static const cream = Color(0xFFFFF3D4);
  static const red = Color(0xFF8B1A1A);
  static const muted = Color(0xFF78534A);
  static const border = Color(0xFFDCC4AC);
  static const soft = Color(0xFFF3E3C7);
}

ThemeData buildAppTheme() {
  // Todas as funções de cor são definidas aqui. Antes, as que ficavam de fora
  // (surfaceVariant, surfaceTint, *Fixed, surfaceDim...) eram geradas pelo
  // Material 3 a partir do vermelho e apareciam rosadas/lilás no aparelho.
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.red).copyWith(
    primary: AppColors.red,
    onPrimary: AppColors.cream,
    secondary: AppColors.red,
    onSecondary: AppColors.cream,
    tertiary: AppColors.red,
    onTertiary: AppColors.cream,
    primaryContainer: AppColors.soft,
    onPrimaryContainer: AppColors.red,
    secondaryContainer: AppColors.soft,
    onSecondaryContainer: AppColors.red,
    surface: AppColors.cream,
    onSurface: AppColors.red,
    onSurfaceVariant: AppColors.muted,
    surfaceContainerLowest: AppColors.cream,
    surfaceContainerLow: AppColors.cream,
    surfaceContainer: AppColors.soft,
    surfaceContainerHigh: AppColors.soft,
    surfaceContainerHighest: AppColors.soft,
    outline: AppColors.muted,
    outlineVariant: AppColors.border,
    error: AppColors.red,
    onError: AppColors.cream,
    errorContainer: AppColors.soft,
    onErrorContainer: AppColors.red,
    inverseSurface: AppColors.red,
    onInverseSurface: AppColors.cream,
    inversePrimary: AppColors.soft,
    tertiaryContainer: AppColors.soft,
    onTertiaryContainer: AppColors.red,
    surfaceDim: AppColors.soft,
    surfaceBright: AppColors.cream,
    surfaceTint: Colors.transparent,
    primaryFixed: AppColors.soft,
    primaryFixedDim: AppColors.border,
    onPrimaryFixed: AppColors.red,
    onPrimaryFixedVariant: AppColors.red,
    secondaryFixed: AppColors.soft,
    secondaryFixedDim: AppColors.border,
    onSecondaryFixed: AppColors.red,
    onSecondaryFixedVariant: AppColors.red,
    tertiaryFixed: AppColors.soft,
    tertiaryFixedDim: AppColors.border,
    onTertiaryFixed: AppColors.red,
    onTertiaryFixedVariant: AppColors.red,
    // ignore: deprecated_member_use
    surfaceVariant: AppColors.soft,
    // ignore: deprecated_member_use
    background: AppColors.cream,
    // ignore: deprecated_member_use
    onBackground: AppColors.red,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  final button = FilledButton.styleFrom(
    minimumSize: const Size(48, 50),
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.cream,
    textTheme: ThemeData.light()
        .textTheme
        .apply(bodyColor: AppColors.red, displayColor: AppColors.red),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.cream,
      foregroundColor: AppColors.red,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
          color: AppColors.red, fontSize: 20, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: AppColors.cream,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: shape.copyWith(side: const BorderSide(color: AppColors.border)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.cream,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.red, width: 2)),
    ),
    filledButtonTheme: FilledButtonThemeData(style: button),
    elevatedButtonTheme: ElevatedButtonThemeData(
        style: button.copyWith(
      backgroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.disabled)
              ? AppColors.soft
              : AppColors.red),
      foregroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.disabled)
              ? AppColors.muted
              : AppColors.cream),
      elevation: const WidgetStatePropertyAll(0),
    )),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: button.copyWith(
            side: const WidgetStatePropertyAll(
                BorderSide(color: AppColors.border)))),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48))),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
    listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        iconColor: AppColors.red),
    tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.red,
        unselectedLabelColor: AppColors.muted,
        indicatorSize: TabBarIndicatorSize.label),
    snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.red,
        contentTextStyle: TextStyle(color: AppColors.cream),
        actionTextColor: AppColors.cream),
    dialogTheme: DialogThemeData(
        backgroundColor: AppColors.cream,
        surfaceTintColor: Colors.transparent,
        shape: shape),
    bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.cream,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: AppColors.border),
    popupMenuTheme: const PopupMenuThemeData(
        color: AppColors.cream, surfaceTintColor: Colors.transparent),
    chipTheme: ChipThemeData(
        backgroundColor: AppColors.cream,
        selectedColor: AppColors.soft,
        side: const BorderSide(color: AppColors.border),
        labelStyle: const TextStyle(color: AppColors.red),
        checkmarkColor: AppColors.red,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.red, foregroundColor: AppColors.cream),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: AppColors.red),
    navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: AppColors.cream,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.soft),
  );
}
