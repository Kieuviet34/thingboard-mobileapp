import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class TbTextStyles {
  static final titleLarge = GoogleFonts.roboto(
    fontWeight: FontWeight.w500,
    fontSize: 28,
    height: 1.28,
    letterSpacing: 0.25,
  );

  static final titleMedium = GoogleFonts.roboto(
    fontWeight: FontWeight.w500,
    fontSize: 24,
    height: 1.33,
    letterSpacing: 0,
  );

  static final titleSmall = GoogleFonts.roboto(
    fontWeight: FontWeight.w500,
    fontSize: 20,
    height: 1.2,
    letterSpacing: 0.01,
  );

  static final titleXs = GoogleFonts.roboto(
    fontWeight: FontWeight.w500,
    fontSize: 18,
    height: 1.33,
    letterSpacing: 0.15,
  );

  static final bodyLarge = GoogleFonts.roboto(
    fontWeight: FontWeight.w400,
    fontSize: 16,
    height: 1.5,
    letterSpacing: 0.15,
  );

  static final bodyMedium = GoogleFonts.roboto(
    fontWeight: FontWeight.w400,
    fontSize: 14,
    height: 1.43,
    letterSpacing: 0.2,
  );

  static final bodySmall = GoogleFonts.roboto(
    fontWeight: FontWeight.w400,
    fontSize: 12,
    height: 1.33,
    letterSpacing: 0.4,
  );

  static final bodyRegular = GoogleFonts.roboto(
    fontWeight: FontWeight.w400,
    fontSize: 17,
    height: 1.5,
    letterSpacing: -0.41,
  );

  static final labelLarge = GoogleFonts.roboto(
    fontWeight: FontWeight.w500,
    fontSize: 16,
    height: 1.5,
    letterSpacing: 0.25,
  );

  static final labelMedium = GoogleFonts.roboto(
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 1.43,
    letterSpacing: 0.25,
  );

  static final labelSmall = GoogleFonts.roboto(
    fontWeight: FontWeight.w400,
    fontSize: 12,
    height: 1.33,
    letterSpacing: 0.4,
  );

  static final titleSmallSb = GoogleFonts.roboto(
    fontWeight: FontWeight.w600,
    fontSize: 20,
    height: 1.2,
    letterSpacing: 0.01,
  );

  static final caption = GoogleFonts.roboto(
    fontWeight: FontWeight.w400,
    fontSize: 11,
    height: 1.45,
    letterSpacing: 0.25,
  );

  static final button = GoogleFonts.roboto(
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 1.43,
    letterSpacing: 0.25,
  );
}
