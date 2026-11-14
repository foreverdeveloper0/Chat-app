import 'package:flutter/material.dart';


/// Player colours used on the playable board (red, green, yellow, blue).
const playerColors = [
  Color(0xFFE5332A),
  Color(0xFF3AAA35),
  Color(0xFFFFD21F),
  Color(0xFF2F8CF0),
];
const playerDeep = [
  Color(0xFFA81610),
  Color(0xFF1C6E1F),
  Color(0xFFD99A00),
  Color(0xFF134FC4),
];
const playerLight = [
  Color(0xFFFF6A5E),
  Color(0xFF6FD45F),
  Color(0xFFFFEE7A),
  Color(0xFF6CC0FF),
];

/// Artwork files.
const boardAsset = 'assets/images/ludo_board.png';
const gameBgAsset = 'assets/images/game_bg.jpg';
const pawnAssets = [
  'assets/images/pawn_red.png',
  'assets/images/pawn_green.png',
  'assets/images/pawn_yellow.png',
  'assets/images/pawn_blue.png',
];

/// Width / height of every pawn image (they share one canvas, base at the bottom).
const pawnAspect = 560 / 910;

/// Where the 15x15 playing grid sits inside the board image, as fractions
/// of the image edge.
const gridInset = 20 / 1160;
const gridSize = 1120 / 1160;
