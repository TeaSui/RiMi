import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'tokens.dart';

/// Light theme grounded in the RiMi "Warm & Premium" tokens.
abstract final class AppTheme {
  static ThemeData get light {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: RM.brand,
      onPrimary: Colors.white,
      primaryContainer: RM.brandSoft,
      onPrimaryContainer: RM.brandDeep,
      secondary: RM.gold,
      onSecondary: Colors.white,
      secondaryContainer: RM.goldSoft,
      onSecondaryContainer: RM.ink,
      surface: RM.card,
      onSurface: RM.ink,
      error: RM.danger,
      onError: Colors.white,
      outline: RM.line,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: RM.cream,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      textTheme: GoogleFonts.beVietnamProTextTheme(base.textTheme).copyWith(
        displayLarge: RMType.display(size: 40, letterSpacing: -1),
        displayMedium: RMType.display(size: 32),
        displaySmall: RMType.display(size: 24),
        headlineMedium: RMType.display(size: 22),
      ),
      dividerTheme: const DividerThemeData(
        color: RM.line,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: RM.ink,
        contentTextStyle: RMType.body(
          size: 13.5,
          weight: FontWeight.w600,
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 100),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: RM.cream,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
    );
  }
}

/// Drop-in toast that matches the prototype's ink pill (icon + message).
void rmToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1900),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_rounded, color: RM.gold, size: 18),
            const SizedBox(width: 9),
            Flexible(child: Text(message)),
          ],
        ),
      ),
    );
}
