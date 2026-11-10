import 'package:flutter/material.dart';

/// Central colour palette for the Elite Play BD Ludo look.
abstract final class AppColors {
  static const bgTop = Color(0xFF1C2052);
  static const bgBottom = Color(0xFF12143A);
  static const glow = Color(0xFF3B43B8);

  static const cardTop = Color(0xFF2D3270);
  static const cardBottom = Color(0xFF212556);
  static const cardBorder = Color(0xFF424890);
  static const cardInset = Color(0xFF171A45);

  static const mint = Color(0xFF45E3A6);
  static const mintDeep = Color(0xFF1FBF86);
  static const cream = Color(0xFFFFF4DF);
  static const creamDim = Color(0xFFE9DDC6);
  static const ink = Color(0xFF0E3B2C);

  static const red = Color(0xFFE23B3B);
  static const green = Color(0xFF2EAD4B);
  static const yellow = Color(0xFFF6BC1E);
  static const blue = Color(0xFF2468DD);
  static const gold = Color(0xFFF8C22D);
  static const goldDeep = Color(0xFFD08A0C);
  static const wood = Color(0xFFA5643A);
  static const woodDeep = Color(0xFF6E3B1E);
  static const boardCream = Color(0xFFF7EBD3);
}

abstract final class AppText {
  static const family = 'Fredoka';

  static const title = TextStyle(
    fontFamily: family,
    fontWeight: FontWeight.w600,
    color: AppColors.cream,
    height: 1.08,
  );
}
