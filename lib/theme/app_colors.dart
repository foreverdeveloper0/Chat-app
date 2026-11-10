import 'package:flutter/material.dart';

/// Central colour palette for the Elite Play BD Ludo look.
abstract final class AppColors {
  static const bgTop = Color(0xFF0B1235);
  static const bgBottom = Color(0xFF050818);
  static const glow = Color(0xFF3B43B8);

  static const cardTop = Color(0xFF151F52);
  static const cardBottom = Color(0xFF0B1132);
  static const cardBorder = Color(0xFF2A3A85);
  static const cardInset = Color(0xFF060A20);

  // Brand accents: royal blue for actions, soft gold for trim and titles.
  static const royal = Color(0xFF3A66F5);
  static const royalDeep = Color(0xFF1B3BB5);
  static const goldSoft = Color(0xFFEBCB7A);
  static const goldTrim = Color(0xFFC9A24B);
  static const goldGradient = [
    Color(0xFFFFF1B8),
    Color(0xFFEBCB7A),
    Color(0xFFB8862B),
  ];

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
