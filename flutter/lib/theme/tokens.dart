import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// RiMi design tokens — "Warm & Premium" concept.
/// Mirrors `RM` in the design source (tokens.jsx) 1:1.
abstract final class RM {
  // Brand
  static const brand = Color(0xFFE0552B); // saffron-terracotta — primary
  static const brandDeep = Color(0xFFB23C19);
  static const brandSoft = Color(0xFFFBE7DC); // tinted fill
  static const gold = Color(0xFFEBA13A); // amber accent / premium highlight
  static const goldSoft = Color(0xFFFBEFD6);
  static const herb = Color(0xFF3E8E5A); // fresh green — online / success
  static const herbSoft = Color(0xFFE2F0E6);

  // Ink / text
  static const ink = Color(0xFF2B211B); // warm espresso text
  static const ink70 = Color(0xFF5C5048);
  static const muted = Color(0xFF8C7F73);
  static const faint = Color(0xFFB8ADA1);

  // Surfaces
  static const line = Color(0xFFECE3D7); // hairline
  static const cream = Color(0xFFFBF6EF); // app background
  static const card = Color(0xFFFFFFFF);
  static const cardAlt = Color(0xFFFFFCF7);

  // Semantic
  static const danger = Color(0xFFD2453B);
  static const dangerSoft = Color(0xFFFBE3E1);
  static const info = Color(0xFF3E73C4);

  // Avatar tints — [foreground, background]
  static const List<List<Color>> avatarTints = [
    [Color(0xFFE0552B), Color(0xFFFBE7DC)],
    [Color(0xFF3E8E5A), Color(0xFFE2F0E6)],
    [Color(0xFFEBA13A), Color(0xFFFBEFD6)],
    [Color(0xFF3E73C4), Color(0xFFE1ECF8)],
    [Color(0xFF9B59B6), Color(0xFFF0E5F6)],
  ];

  // Food placeholder duotone tints — [light, deep]
  static const List<List<Color>> foodTints = [
    [Color(0xFFF4C77A), Color(0xFFE0552B)],
    [Color(0xFFF2A65A), Color(0xFFC23B1A)],
    [Color(0xFFE9B872), Color(0xFFB6552A)],
    [Color(0xFFF6D08A), Color(0xFFD98236)],
    [Color(0xFFE8A06A), Color(0xFFA8431F)],
    [Color(0xFFF1B96B), Color(0xFFC76A2A)],
  ];

  // Tier (CRM)
  static const tierVip = Color(0xFF9B59B6);
  static const tierVipSoft = Color(0xFFF0E5F6);

  // Helper: flatten an opacity onto a colour (cheap alpha tint).
  static Color a(Color c, double opacity) => c.withValues(alpha: opacity);
}

/// Display font — Bricolage Grotesque. Heading/body — Be Vietnam Pro.
abstract final class RMType {
  static TextStyle display({
    double size = 24,
    FontWeight weight = FontWeight.w800,
    Color color = RM.ink,
    double? letterSpacing,
    double? height,
  }) =>
      GoogleFonts.bricolageGrotesque(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  static TextStyle body({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color color = RM.ink,
    double? letterSpacing,
    double height = 1.5,
  }) =>
      GoogleFonts.beVietnamPro(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );
}

/// Vietnamese đồng formatter — e.g. 148000 -> "148.000 ₫".
String vnd(num n) {
  final s = n.round().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return '${buf.toString()}\u202F₫';
}
