import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/ludo_rules.dart';
import 'pieces.dart';

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

/// Fraction of the board edge taken by the gold rim on each side.
const boardRim = .02;

/// Top-down playable board: gold rim, gradient yards with a white diamond
/// for the four pieces, white track with coloured home lanes, arrows and
/// star safe cells.
class PlayBoardPainter extends CustomPainter {
  const PlayBoardPainter();

  static const _ink = Color(0xFF2A2A33);

  @override
  void paint(Canvas canvas, Size size) {
    final b = size.width;
    final outer = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(b * .028));
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFF0A8),
            Color(0xFFE3B341),
            Color(0xFFFFE28A),
            Color(0xFFB98518),
          ],
          stops: [0, .35, .65, 1],
        ).createShader(outer.outerRect),
    );

    final rim = b * boardRim;
    final g = b - rim * 2;
    final c = g / 15;
    canvas.save();
    canvas.translate(rim, rim);
    canvas.clipRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, g, g), Radius.circular(b * .012)));
    canvas.drawRect(Rect.fromLTWH(0, 0, g, g), Paint()..color = Colors.white);

    Rect cell((int, int) p) => Rect.fromLTWH(p.$1 * c, p.$2 * c, c, c);
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(.6, c * .035)
      ..color = const Color(0xFF9A9AA6);
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(.8, c * .05)
      ..strokeJoin = StrokeJoin.round
      ..color = _ink;

    Paint lane(int p, Rect r) => Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [playerLight[p], playerColors[p], playerDeep[p]],
        stops: const [0, .5, 1],
      ).createShader(r);

    // Track cells.
    for (final t in LudoRules.track) {
      canvas.drawRect(cell(t), grid);
    }
    for (var p = 0; p < 4; p++) {
      for (final h in LudoRules.homeColumns[p]) {
        canvas.drawRect(cell(h), lane(p, cell(h)));
        canvas.drawRect(cell(h), grid);
      }
      final start = cell(LudoRules.track[LudoRules.startIndex[p]]);
      canvas.drawRect(start, lane(p, start));
      canvas.drawRect(start, grid);

      // Entry arrow on the cell before the home lane.
      final a = cell(LudoRules.track[LudoRules.trackIndex(p, 50)]);
      canvas.save();
      canvas.translate(a.center.dx, a.center.dy);
      canvas.rotate(const [0.0, math.pi / 2, math.pi, -math.pi / 2][p]);
      final arrow = Path()
        ..moveTo(c * .3, 0)
        ..lineTo(-c * .24, -c * .3)
        ..lineTo(-c * .24, c * .3)
        ..close();
      canvas.drawPath(arrow, Paint()..color = playerColors[p]);
      canvas.drawPath(arrow, outline);
      canvas.restore();

      // Star safe cell, eight steps after the start.
      final s = cell(LudoRules.track[LudoRules.trackIndex(p, 8)]);
      final star = starPath(s.center + Offset(0, c * .03), c * .36, inner: .48);
      canvas.drawPath(star, Paint()..color = playerColors[p]);
      canvas.drawPath(star, outline);
    }

    // Yards.
    for (var p = 0; p < 4; p++) {
      final o = LudoRules.yardOrigins[p];
      final r = Rect.fromLTWH(o.$1 * c, o.$2 * c, 6 * c, 6 * c);
      canvas.drawRect(
        r,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [playerLight[p], playerColors[p], playerDeep[p]],
            stops: const [0, .45, 1],
          ).createShader(r),
      );
      canvas.drawRect(r, outline);

      canvas.save();
      canvas.translate(r.center.dx, r.center.dy);
      canvas.rotate(math.pi / 4);
      final d = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: c * 3.7, height: c * 3.7),
          Radius.circular(c * .75));
      canvas.drawRRect(
        d.shift(Offset(c * .1, c * .1)),
        Paint()
          ..color = const Color(0x55000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, c * .18),
      );
      canvas.drawRRect(d, Paint()..color = Colors.white);
      canvas.restore();

      for (final slot in LudoRules.yardSlots) {
        final at = r.topLeft + slot * c + Offset(0, c * .2);
        canvas.drawOval(
          Rect.fromCenter(center: at, width: c * .95, height: c * .5),
          Paint()..color = playerColors[p].withValues(alpha: .16),
        );
      }
    }

    // Centre home.
    final mid = Offset(7.5 * c, 7.5 * c);
    final tl = Offset(6 * c, 6 * c), tr = Offset(9 * c, 6 * c);
    final bl = Offset(6 * c, 9 * c), br = Offset(9 * c, 9 * c);
    final tris = [
      [tl, bl],
      [tl, tr],
      [tr, br],
      [bl, br],
    ];
    for (var p = 0; p < 4; p++) {
      final path = Path()..addPolygon([tris[p][0], tris[p][1], mid], true);
      canvas.drawPath(path, lane(p, path.getBounds()));
      canvas.drawPath(path, outline);
    }
    canvas.restore();

    // Inner bevel on the rim.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(rim, rim, g, g),
          Radius.circular(b * .012)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, b * .004)
        ..color = const Color(0xFF7A5A12),
    );
  }

  @override
  bool shouldRepaint(PlayBoardPainter old) => false;
}
