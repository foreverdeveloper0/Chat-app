import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/snl_controller.dart';
import '../theme/app_colors.dart';

/// Fraction of the board edge taken by the gold rim on each side.
const snlRim = .026;

/// Centre of square [n] (1..100) in cell units; the numbers snake up from
/// the bottom-left corner.
Offset snlCentre(int n) {
  final row = (n - 1) ~/ 10;
  var col = (n - 1) % 10;
  if (row.isOdd) col = 9 - col;
  return Offset(col + .5, 9 - row + .5);
}

/// Points along the ride from [from] to [to], in cell units: straight up a
/// ladder, or down the curves of a snake.
List<Offset> snlRide(int from, int to, {required bool snake}) {
  final a = snlCentre(from), b = snlCentre(to);
  if (!snake) return [a, b];
  final d = b - a, len = d.distance;
  final normal = Offset(-d.dy, d.dx) / len;
  final waves = (len / 2.6).clamp(1.5, 3.5);
  // Bend the other way for every other snake so they do not all match.
  final side = from.isEven ? 1.0 : -1.0;
  return [
    for (var i = 0; i <= 48; i++)
      () {
        final t = i / 48;
        final sway = math.sin(t * math.pi * waves) *
            math.sin(t * math.pi).clamp(0, 1) *
            .42 *
            side;
        return a + d * t + normal * sway;
      }(),
  ];
}

const _tiles = [
  Color(0xFFFF7A7A),
  Color(0xFFFFD75E),
  Color(0xFF6FDB8C),
  Color(0xFF6CB6FF),
];
const _snakeSkins = [
  (Color(0xFF3FD06E), Color(0xFF12803A)),
  (Color(0xFFB06BFF), Color(0xFF5A1FB0)),
  (Color(0xFFFF8A3D), Color(0xFFB04A08)),
  (Color(0xFFFF5C7A), Color(0xFFA5142F)),
  (Color(0xFF35C9D6), Color(0xFF0B6E7A)),
  (Color(0xFFE8C431), Color(0xFF8A6B05)),
  (Color(0xFF5B8CFF), Color(0xFF1B3BB5)),
  (Color(0xFFEF6BD0), Color(0xFF8E1F74)),
];

/// The 10x10 board: gold rim, glossy numbered tiles, wooden ladders and
/// eight coloured snakes.
class SnlBoardPainter extends CustomPainter {
  const SnlBoardPainter({this.numbers = true});

  /// Square numbers are skipped on the tiny home-page demo board.
  final bool numbers;

  @override
  void paint(Canvas canvas, Size size) {
    final b = size.width;
    final outer =
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(b * .04));
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFF3B8),
            Color(0xFFE3B341),
            Color(0xFFFFE28A),
            Color(0xFF9C6B0E),
            Color(0xFFE9C46A),
          ],
          stops: [0, .3, .55, .82, 1],
        ).createShader(outer.outerRect),
    );
    canvas.drawRRect(
      outer.deflate(b * .008),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = b * .003
        ..color = const Color(0x99FFFFFF),
    );

    final rim = b * snlRim;
    final field = Rect.fromLTWH(rim, rim, b - rim * 2, b - rim * 2);
    final cell = field.width / 10;
    Offset at(Offset cells) => field.topLeft + cells * cell;

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(field, Radius.circular(b * .02)));
    for (var n = 1; n <= 100; n++) {
      final c = snlCentre(n);
      final r = Rect.fromCenter(center: at(c), width: cell, height: cell);
      final special = n == 100 || n == 1;
      final base = n == 100
          ? const Color(0xFFFFC93A)
          : _tiles[((c.dx - .5).round() + (c.dy - .5).round()) % 4];
      canvas.drawRect(
        r,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(base, Colors.white, .38)!,
              base,
              Color.lerp(base, Colors.black, .14)!,
            ],
          ).createShader(r),
      );
      canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * .03
          ..color = const Color(0x55241A4A),
      );
      if (numbers) {
        final label = n == 100 ? 'WIN' : (n == 1 ? 'GO' : '$n');
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              fontFamily: AppText.family,
              fontWeight: FontWeight.w700,
              fontSize: cell * (special ? .3 : .27),
              color: const Color(0xCC2B2140),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, r.topLeft + Offset(cell * .08, cell * .04));
      }
    }

    // Ladders first, snakes over them.
    SnlController.ladders.forEach((from, to) {
      _ladder(canvas, at(snlCentre(from)), at(snlCentre(to)), cell);
    });
    var i = 0;
    SnlController.snakes.forEach((from, to) {
      _snake(
        canvas,
        [for (final p in snlRide(from, to, snake: true)) at(p)],
        cell,
        _snakeSkins[i++ % _snakeSkins.length],
      );
    });
    canvas.restore();

    canvas.drawRRect(
      RRect.fromRectAndRadius(field, Radius.circular(b * .02)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = b * .006
        ..color = const Color(0xFF6B4708),
    );
  }

  void _ladder(Canvas canvas, Offset a, Offset b, double cell) {
    final d = b - a, len = d.distance;
    final dir = d / len, side = Offset(-dir.dy, dir.dx) * cell * .2;
    Paint line(double w, Color c) => Paint()
      ..strokeWidth = cell * w
      ..strokeCap = StrokeCap.round
      ..color = c;
    final shadow = Offset(cell * .06, cell * .08);
    for (final s in [side, -side]) {
      canvas.drawLine(a + s + shadow, b + s + shadow,
          line(.13, const Color(0x44000010)));
    }
    final rungs = (len / (cell * .42)).floor();
    for (var i = 1; i < rungs; i++) {
      final p = a + dir * (len * i / rungs);
      canvas.drawLine(p + side, p - side, line(.12, const Color(0xFF6B3F1D)));
      canvas.drawLine(p + side, p - side, line(.07, const Color(0xFFE2A85A)));
    }
    for (final s in [side, -side]) {
      canvas.drawLine(a + s, b + s, line(.15, const Color(0xFF6B3F1D)));
      canvas.drawLine(a + s, b + s, line(.095, const Color(0xFFD9963F)));
      canvas.drawLine(a + s - side * .12, b + s - side * .12,
          line(.03, const Color(0x88FFE2A8)));
    }
  }

  void _snake(Canvas canvas, List<Offset> pts, double cell,
      (Color, Color) skin) {
    final n = pts.length - 1;
    // Thick at the head, thin at the tail.
    double width(int i) => cell * (.34 - .2 * math.pow(i / n, 1.6));
    void pass(double grow, Color color, [Offset shift = Offset.zero]) {
      for (var i = n; i > 0; i--) {
        canvas.drawLine(
          pts[i] + shift,
          pts[i - 1] + shift,
          Paint()
            ..strokeCap = StrokeCap.round
            ..strokeWidth = width(i) + cell * grow
            ..color = color,
        );
      }
    }

    pass(.06, const Color(0x40000010), Offset(cell * .05, cell * .09));
    pass(.07, skin.$2);
    pass(0, skin.$1);
    // Diamond markings and a soft highlight along the back.
    for (var i = 4; i < n - 2; i += 4) {
      canvas.drawCircle(pts[i], width(i) * .24,
          Paint()..color = skin.$2.withValues(alpha: .75));
    }
    pass(-.24, const Color(0x40FFFFFF), Offset(-cell * .03, -cell * .04));

    // Head, looking back along the body's first stretch.
    final v = pts[0] - pts[2];
    canvas.save();
    canvas.translate(pts[0].dx, pts[0].dy);
    canvas.rotate(math.atan2(v.dy, v.dx));
    final tongue = Paint()
      ..color = const Color(0xFFFF2B4F)
      ..strokeWidth = cell * .035
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      Path()
        ..moveTo(cell * .2, 0)
        ..lineTo(cell * .36, 0)
        ..lineTo(cell * .44, -cell * .06)
        ..moveTo(cell * .36, 0)
        ..lineTo(cell * .44, cell * .06),
      tongue,
    );
    final head = Rect.fromCenter(
        center: Offset(cell * .04, 0), width: cell * .5, height: cell * .42);
    canvas.drawOval(head.inflate(cell * .03), Paint()..color = skin.$2);
    canvas.drawOval(
      head,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.2, -.5),
          colors: [Color.lerp(skin.$1, Colors.white, .45)!, skin.$1],
        ).createShader(head),
    );
    for (final s in const [-1.0, 1.0]) {
      final eye = Offset(cell * .08, s * cell * .11);
      canvas.drawCircle(eye, cell * .075, Paint()..color = Colors.white);
      canvas.drawCircle(eye + Offset(cell * .02, 0), cell * .04,
          Paint()..color = const Color(0xFF14181F));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SnlBoardPainter old) => old.numbers != numbers;
}
