import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'pieces.dart';

/// The hero Ludo board: a flat 15x15 board drawn under a perspective
/// transform, with a wooden rim, upright pawns and a dice.
class LudoBoardPainter extends CustomPainter {
  const LudoBoardPainter();

  static const _yardColors = [
    AppColors.red,
    AppColors.green,
    AppColors.blue,
    AppColors.yellow,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final b = size.width * .75; // flat board edge
    final centre = Offset(size.width * .51, size.height * .44);

    final m = Matrix4.identity()
      ..translateByDouble(centre.dx, centre.dy, 0, 1)
      ..setEntry(3, 2, .0011)
      ..rotateX(-.92)
      ..rotateZ(-.13)
      ..translateByDouble(-b / 2, -b / 2, 0, 1);

    final frame = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, b, b), Radius.circular(b * .07));

    // Soft ground shadow.
    canvas.save();
    canvas.translate(0, b * .1);
    canvas.transform(m.storage);
    canvas.drawRRect(
      frame.inflate(b * .02),
      Paint()
        ..color = const Color(0x77000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, b * .06),
    );
    canvas.restore();

    // Extruded wooden side.
    final depth = (b * .055).round();
    final side = Paint()..color = AppColors.woodDeep;
    for (var i = depth; i > 0; i--) {
      canvas.save();
      canvas.translate(0, i.toDouble());
      canvas.transform(m.storage);
      canvas.drawRRect(frame, side);
      canvas.restore();
    }

    canvas.save();
    canvas.transform(m.storage);
    _paintFlatBoard(canvas, b, frame);
    canvas.restore();

    // Upright pieces, positioned by projecting board coordinates.
    Offset project(double x, double y) =>
        MatrixUtils.transformPoint(m, Offset(x * b, y * b));

    const yards = [
      Offset(.24, .24),
      Offset(.76, .24),
      Offset(.24, .76),
      Offset(.76, .76),
    ];
    final pw = b * .15;
    for (var i = 0; i < 4; i++) {
      final foot = project(yards[i].dx, yards[i].dy);
      final scale = i < 2 ? .92 : 1.08; // nearer pawns look bigger
      final w = pw * scale, h = w * 1.6;
      paintPawn(
        canvas,
        Rect.fromLTWH(foot.dx - w / 2, foot.dy - h * .86, w, h),
        _yardColors[i],
      );
    }

    final d = size.width * .19;
    paintDice(
      canvas,
      Rect.fromLTWH(size.width * .03, size.height * .68, d, d),
      5,
      angle: -.18,
    );
  }

  void _paintFlatBoard(Canvas canvas, double b, RRect frame) {
    canvas.drawRRect(
      frame,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFC07C4C), AppColors.wood, Color(0xFF8A4F2A)],
        ).createShader(frame.outerRect),
    );

    final inset = b * .04;
    final g = b - inset * 2; // playable square
    final c = g / 15;
    canvas.save();
    canvas.translate(inset, inset);
    canvas.clipRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, g, g), Radius.circular(b * .035)));
    canvas.drawRect(
        Rect.fromLTWH(0, 0, g, g), Paint()..color = AppColors.boardCream);

    Rect cell(int col, int row, [int cw = 1, int ch = 1]) =>
        Rect.fromLTWH(col * c, row * c, cw * c, ch * c);

    // Yards.
    const origins = [(0, 0), (9, 0), (0, 9), (9, 9)];
    for (var i = 0; i < 4; i++) {
      final r = cell(origins[i].$1, origins[i].$2, 6, 6);
      final col = _yardColors[i];
      canvas.drawRect(r, Paint()..color = col);
      canvas.drawCircle(r.center, c * 2.2,
          Paint()..color = Color.lerp(col, Colors.white, .22)!);
      canvas.drawCircle(
        r.center,
        c * 2.2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = c * .18
          ..color = Color.lerp(col, Colors.black, .18)!,
      );
      canvas.drawCircle(r.center, c * 1.05,
          Paint()..color = Color.lerp(col, Colors.black, .16)!);
    }

    // Home columns and start cells.
    final red = Paint()..color = AppColors.red;
    final green = Paint()..color = AppColors.green;
    final yellow = Paint()..color = AppColors.yellow;
    final blue = Paint()..color = AppColors.blue;
    canvas.drawRect(cell(1, 7, 5, 1), red);
    canvas.drawRect(cell(1, 6), red);
    canvas.drawRect(cell(7, 1, 1, 5), green);
    canvas.drawRect(cell(8, 1), green);
    canvas.drawRect(cell(9, 7, 5, 1), yellow);
    canvas.drawRect(cell(13, 8), yellow);
    canvas.drawRect(cell(7, 9, 1, 5), blue);
    canvas.drawRect(cell(6, 13), blue);

    // Safe-cell stars.
    void star(int col, int row, Color color) => canvas.drawPath(
        starPath(cell(col, row).center, c * .42), Paint()..color = color);
    star(2, 8, AppColors.red);
    star(6, 2, AppColors.green);
    star(12, 6, AppColors.yellow);
    star(8, 12, AppColors.blue);

    // Grid lines on the cross.
    final line = Paint()
      ..color = const Color(0x33503A1E)
      ..strokeWidth = c * .06;
    for (var i = 0; i <= 15; i++) {
      final p = i * c;
      if (i >= 6 && i <= 9) {
        canvas.drawLine(Offset(p, 0), Offset(p, g), line);
        canvas.drawLine(Offset(0, p), Offset(g, p), line);
      } else {
        canvas.drawLine(Offset(p, 6 * c), Offset(p, 9 * c), line);
        canvas.drawLine(Offset(6 * c, p), Offset(9 * c, p), line);
      }
    }

    // Centre home triangles.
    final mid = Offset(7.5 * c, 7.5 * c);
    final tl = Offset(6 * c, 6 * c), tr = Offset(9 * c, 6 * c);
    final bl = Offset(6 * c, 9 * c), br = Offset(9 * c, 9 * c);
    Path tri(Offset a, Offset b2) => Path()..addPolygon([a, b2, mid], true);
    canvas.drawPath(tri(tl, bl), red);
    canvas.drawPath(tri(tl, tr), green);
    canvas.drawPath(tri(tr, br), yellow);
    canvas.drawPath(tri(bl, br), blue);

    // Gentle top-light sheen.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, g, g),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x26FFFFFF), Color(0x00FFFFFF), Color(0x1F000000)],
        ).createShader(Rect.fromLTWH(0, 0, g, g)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(LudoBoardPainter old) => false;
}
