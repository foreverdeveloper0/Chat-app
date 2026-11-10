import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'pieces.dart';

/// Hand-drawn vector illustrations. Everything is resolution independent
/// and painted once (each sits behind a RepaintBoundary via [Art]).
enum ArtKind {
  avatar,
  coinStack,
  calendar,
  globe,
  pawnPair,
  dicePair,
  robot,
  trophy,
  home,
  friends,
  history,
  agent,
}

class Art extends StatelessWidget {
  const Art(this.kind, {super.key, required this.size, this.tint});
  final ArtKind kind;
  final double size;
  final Color? tint;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          size: Size.square(size),
          painter: _ArtPainter(kind, tint),
        ),
      );
}

class _ArtPainter extends CustomPainter {
  const _ArtPainter(this.kind, this.tint);
  final ArtKind kind;
  final Color? tint;

  @override
  void paint(Canvas canvas, Size size) {
    // All art is authored on a 100x100 grid.
    canvas.scale(size.width / 100);
    switch (kind) {
      case ArtKind.avatar:
        _avatar(canvas);
      case ArtKind.coinStack:
        _coinStack(canvas);
      case ArtKind.calendar:
        _calendar(canvas);
      case ArtKind.globe:
        _globe(canvas);
      case ArtKind.pawnPair:
        paintPawn(canvas, const Rect.fromLTWH(44, 6, 46, 74), AppColors.yellow);
        paintPawn(canvas, const Rect.fromLTWH(8, 22, 48, 77), AppColors.red);
      case ArtKind.dicePair:
        _dicePair(canvas);
      case ArtKind.robot:
        _robot(canvas);
      case ArtKind.trophy:
        _trophy(canvas);
      case ArtKind.home:
        _home(canvas);
      case ArtKind.friends:
        _friends(canvas);
      case ArtKind.history:
        _history(canvas);
      case ArtKind.agent:
        _agent(canvas);
    }
  }

  static Paint _fill(Color c) => Paint()..color = c;
  static Paint _grad(Rect r, List<Color> colors,
          {Alignment begin = Alignment.topCenter,
          Alignment end = Alignment.bottomCenter}) =>
      Paint()
        ..shader = LinearGradient(begin: begin, end: end, colors: colors)
            .createShader(r);
  static Paint _stroke(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  static RRect _rr(double l, double t, double w, double h, double r) =>
      RRect.fromRectAndRadius(Rect.fromLTWH(l, t, w, h), Radius.circular(r));

  void _person(Canvas canvas, Offset head, double r, Paint paint) {
    canvas.drawCircle(head, r, paint);
    final top = head.dy + r * 1.25;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(head.dx - r * 1.75, top, r * 3.5, r * 2.3),
        topLeft: Radius.circular(r * 1.6),
        topRight: Radius.circular(r * 1.6),
        bottomLeft: Radius.circular(r * .5),
        bottomRight: Radius.circular(r * .5),
      ),
      paint,
    );
  }

  void _avatar(Canvas canvas) {
    const r = Rect.fromLTWH(0, 0, 100, 100);
    canvas.drawCircle(
        r.center, 50, _grad(r, const [Color(0xFF6FF0BF), AppColors.mintDeep]));
    canvas.save();
    canvas.clipPath(Path()..addOval(r.deflate(5)));
    canvas.drawCircle(r.center, 46, _fill(const Color(0xFF23936B)));
    // shoulders, neck, face, hair
    canvas.drawRRect(_rr(16, 70, 68, 50, 26), _fill(const Color(0xFF9B2F3A)));
    canvas.drawRRect(_rr(41, 56, 18, 22, 8), _fill(const Color(0xFFD9976A)));
    canvas.drawOval(
        const Rect.fromLTWH(30, 24, 40, 46), _fill(const Color(0xFFEDB083)));
    canvas.drawPath(
      Path()
        ..moveTo(28, 44)
        ..quadraticBezierTo(24, 14, 52, 14)
        ..quadraticBezierTo(78, 14, 72, 44)
        ..quadraticBezierTo(66, 30, 50, 30)
        ..quadraticBezierTo(36, 30, 28, 44)
        ..close(),
      _fill(const Color(0xFF231A1A)),
    );
    canvas.drawArc(const Rect.fromLTWH(41, 50, 18, 12), .2, math.pi - .4, false,
        _stroke(const Color(0xFF7A3B26), 2.4));
    canvas.restore();
  }

  void _coinStack(Canvas canvas) {
    void stack(double cx, double bottom, int n) {
      for (var i = 0; i < n; i++) {
        final y = bottom - i * 11.0;
        final top = Rect.fromCenter(center: Offset(cx, y), width: 40, height: 16);
        canvas.drawOval(top.shift(const Offset(0, 8)), _fill(AppColors.goldDeep));
        canvas.drawRect(Rect.fromLTWH(cx - 20, y, 40, 8), _fill(AppColors.goldDeep));
        canvas.drawOval(
            top,
            _grad(top, const [Color(0xFFFFE680), AppColors.gold],
                begin: Alignment.topLeft, end: Alignment.bottomRight));
        canvas.drawOval(top.deflate(4), _stroke(const Color(0x66B26A00), 1.2));
      }
    }

    stack(54, 52, 3);
    stack(30, 74, 2);
    stack(62, 80, 2);
    // green tick badge
    const c = Offset(76, 62);
    canvas.drawCircle(c, 17, _fill(const Color(0xFFFFE680)));
    canvas.drawCircle(
        c,
        14,
        _grad(Rect.fromCircle(center: c, radius: 14),
            const [Color(0xFF63E08A), Color(0xFF1FA653)]));
    canvas.drawPath(
      Path()
        ..moveTo(69, 62)
        ..lineTo(74.5, 68)
        ..lineTo(84, 56),
      _stroke(Colors.white, 4),
    );
  }

  void _calendar(Canvas canvas) {
    canvas.drawRRect(_rr(10, 24, 80, 68, 10), _fill(const Color(0xFFC53A3A)));
    canvas.drawRRect(_rr(14, 16, 74, 68, 9),
        _grad(const Rect.fromLTWH(14, 16, 74, 68),
            const [Color(0xFFFFFAEF), Color(0xFFEBDDC2)]));
    canvas.drawRRect(
        RRect.fromRectAndCorners(const Rect.fromLTWH(14, 16, 74, 15),
            topLeft: const Radius.circular(9),
            topRight: const Radius.circular(9)),
        _fill(const Color(0xFFE25050)));
    for (final x in const [30.0, 51.0, 72.0]) {
      canvas.drawRRect(_rr(x - 3, 8, 6, 17, 3), _fill(AppColors.gold));
    }
    for (var i = 0; i < 2; i++) {
      final y = 46.0 + i * 20;
      canvas.drawRRect(_rr(24, y - 7, 14, 14, 3.5), _fill(const Color(0xFF2FB765)));
      canvas.drawPath(
        Path()
          ..moveTo(27, y)
          ..lineTo(30.3, y + 3.4)
          ..lineTo(35.5, y - 3.2),
        _stroke(Colors.white, 2.6),
      );
      canvas.drawLine(Offset(46, y - 3), Offset(76, y - 3),
          _stroke(const Color(0xFF8C8FA8), 3));
      canvas.drawLine(Offset(46, y + 4), Offset(66, y + 4),
          _stroke(const Color(0xFFBDBFD0), 3));
    }
  }

  void _globe(Canvas canvas) {
    // stand
    canvas.drawOval(const Rect.fromLTWH(30, 86, 44, 11), _fill(AppColors.goldDeep));
    canvas.drawOval(const Rect.fromLTWH(30, 83, 44, 11), _fill(AppColors.gold));
    canvas.drawRect(const Rect.fromLTWH(49, 74, 6, 12), _fill(AppColors.goldDeep));
    canvas.drawArc(const Rect.fromLTWH(8, 2, 80, 80), .15, 2.5, false,
        _stroke(AppColors.gold, 5));
    // sphere
    const c = Offset(50, 40);
    final sphere = Rect.fromCircle(center: c, radius: 34);
    canvas.drawCircle(
      c,
      34,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.4, -.5),
          radius: 1.1,
          colors: [Color(0xFF7CC6FF), Color(0xFF2A7BEA), Color(0xFF123F9E)],
        ).createShader(sphere),
    );
    canvas.save();
    canvas.clipPath(Path()..addOval(sphere));
    final land = _grad(sphere, const [Color(0xFF7BE06A), Color(0xFF2E9E45)]);
    canvas.drawPath(
      Path()
        ..moveTo(22, 20)
        ..cubicTo(34, 6, 50, 12, 48, 22)
        ..cubicTo(47, 30, 38, 28, 40, 38)
        ..cubicTo(42, 50, 30, 46, 26, 38)
        ..cubicTo(22, 32, 14, 30, 22, 20)
        ..close(),
      land,
    );
    canvas.drawPath(
      Path()
        ..moveTo(60, 28)
        ..cubicTo(72, 22, 86, 30, 84, 42)
        ..cubicTo(82, 54, 74, 50, 70, 60)
        ..cubicTo(66, 70, 58, 62, 60, 52)
        ..cubicTo(61, 44, 52, 34, 60, 28)
        ..close(),
      land,
    );
    canvas.drawOval(const Rect.fromLTWH(34, 58, 18, 14), land);
    canvas.restore();
    canvas.drawOval(
        const Rect.fromLTWH(28, 13, 18, 10), _fill(const Color(0x55FFFFFF)));
  }

  void _dicePair(Canvas canvas) {
    final arrow = _stroke(AppColors.mint, 6);
    void head(Offset tip, double angle) {
      canvas.save();
      canvas.translate(tip.dx, tip.dy);
      canvas.rotate(angle);
      canvas.drawPath(
        Path()
          ..moveTo(7, 0)
          ..lineTo(-6, -9)
          ..lineTo(-6, 9)
          ..close(),
        _fill(AppColors.mint),
      );
      canvas.restore();
    }

    canvas.drawArc(const Rect.fromLTWH(38, 4, 44, 40), 3.5, 1.9, false, arrow);
    head(const Offset(79, 15), .95);
    canvas.drawArc(const Rect.fromLTWH(16, 58, 44, 40), .35, 1.9, false, arrow);
    head(const Offset(20, 86), .95 + math.pi);

    paintDice(canvas, const Rect.fromLTWH(48, 34, 50, 50), 4, angle: .2);
    paintDice(canvas, const Rect.fromLTWH(2, 16, 52, 52), 5, angle: -.22);
  }

  void _robot(Canvas canvas) {
    const blue = Color(0xFF3B82F6), blueDeep = Color(0xFF1E55C9);
    const shell = [Color(0xFFFFFFFF), Color(0xFFD5DDF2)];
    // antenna
    canvas.drawLine(const Offset(50, 10), const Offset(50, 22),
        _stroke(const Color(0xFFB8C2DD), 4));
    canvas.drawCircle(const Offset(50, 8), 6.5, _fill(const Color(0xFF34D17C)));
    canvas.drawCircle(const Offset(48, 6), 2, _fill(const Color(0x99FFFFFF)));
    // body + arms
    canvas.drawRRect(_rr(18, 64, 14, 26, 7), _fill(blue));
    canvas.drawRRect(_rr(68, 64, 14, 26, 7), _fill(blue));
    canvas.drawRRect(
        _rr(28, 60, 44, 36, 14), _grad(const Rect.fromLTWH(28, 60, 44, 36), shell));
    canvas.drawRRect(_rr(40, 74, 20, 11, 3.5), _fill(const Color(0xFF34D17C)));
    // ears + head
    canvas.drawRRect(_rr(6, 34, 14, 22, 6), _grad(const Rect.fromLTWH(6, 34, 14, 22), const [blue, blueDeep]));
    canvas.drawRRect(_rr(80, 34, 14, 22, 6), _grad(const Rect.fromLTWH(80, 34, 14, 22), const [blue, blueDeep]));
    canvas.drawRRect(
        _rr(13, 20, 74, 48, 22), _grad(const Rect.fromLTWH(13, 20, 74, 48), shell));
    canvas.drawRRect(_rr(22, 29, 56, 31, 14), _fill(const Color(0xFF14183D)));
    final eye = _stroke(AppColors.mint, 4.5);
    canvas.drawArc(const Rect.fromLTWH(31, 39, 13, 16), math.pi, math.pi, false, eye);
    canvas.drawArc(const Rect.fromLTWH(56, 39, 13, 16), math.pi, math.pi, false, eye);
    canvas.drawOval(
        const Rect.fromLTWH(24, 23, 22, 6), _fill(const Color(0x88FFFFFF)));
  }

  void _trophy(Canvas canvas) {
    paintLaurel(canvas, const Rect.fromLTWH(0, 46, 26, 50), AppColors.mint);
    paintLaurel(canvas, const Rect.fromLTWH(74, 46, 26, 50), AppColors.mint,
        mirror: true);
    const cupRect = Rect.fromLTWH(26, 10, 48, 46);
    final gold = _grad(cupRect,
        const [Color(0xFFFFE680), AppColors.gold, Color(0xFFE39A12)],
        begin: Alignment.topLeft, end: Alignment.bottomRight);
    final handle = _stroke(AppColors.gold, 5.5);
    canvas.drawArc(const Rect.fromLTWH(13, 14, 26, 26), math.pi * .5, math.pi, false, handle);
    canvas.drawArc(const Rect.fromLTWH(61, 14, 26, 26), -math.pi * .5, math.pi, false, handle);
    // base + stem
    canvas.drawRRect(_rr(30, 82, 40, 11, 4), _fill(AppColors.goldDeep));
    canvas.drawRRect(_rr(35, 74, 30, 10, 4), _fill(AppColors.gold));
    canvas.drawPath(
      Path()
        ..moveTo(43, 52)
        ..lineTo(57, 52)
        ..lineTo(55, 76)
        ..lineTo(45, 76)
        ..close(),
      _fill(const Color(0xFFE39A12)),
    );
    // cup
    canvas.drawPath(
      Path()
        ..moveTo(26, 10)
        ..lineTo(74, 10)
        ..cubicTo(74, 40, 64, 58, 50, 58)
        ..cubicTo(36, 58, 26, 40, 26, 10)
        ..close(),
      gold,
    );
    canvas.drawRRect(_rr(24, 7, 52, 7, 3.5), _fill(const Color(0xFFFFE680)));
    canvas.drawPath(starPath(const Offset(50, 32), 11, inner: .5),
        _fill(const Color(0xFFFFF3B8)));
  }

  void _home(Canvas canvas) {
    final c = tint ?? AppColors.mint;
    final r = const Rect.fromLTWH(14, 12, 72, 76);
    final paint = _grad(r, [Color.lerp(c, Colors.white, .25)!, c]);
    final house = Path()
      ..moveTo(50, 12)
      ..lineTo(86, 44)
      ..lineTo(86, 80)
      ..quadraticBezierTo(86, 88, 78, 88)
      ..lineTo(22, 88)
      ..quadraticBezierTo(14, 88, 14, 80)
      ..lineTo(14, 44)
      ..close();
    canvas.drawPath(
        house,
        paint
          ..style = PaintingStyle.fill
          ..strokeJoin = StrokeJoin.round);
    canvas.drawPath(house, _stroke(c, 6)..shader = paint.shader);
    canvas.drawRRect(
        RRect.fromRectAndCorners(const Rect.fromLTWH(39, 58, 22, 31),
            topLeft: const Radius.circular(6),
            topRight: const Radius.circular(6)),
        _fill(AppColors.cardBottom));
  }

  void _friends(Canvas canvas) {
    _person(canvas, const Offset(32, 30), 13,
        _grad(const Rect.fromLTWH(10, 16, 46, 60), const [Color(0xFFF2F4FF), Color(0xFFB9C1E6)]));
    _person(canvas, const Offset(62, 34), 17,
        _grad(const Rect.fromLTWH(32, 16, 60, 80), const [Color(0xFF6EB0FF), Color(0xFF2468DD)]));
  }

  void _history(Canvas canvas) {
    const c = Offset(46, 46);
    canvas.drawArc(Rect.fromCircle(center: c, radius: 34), -.2, math.pi * 1.65 + .2,
        false, _stroke(const Color(0xFFE8ECFF), 8));
    canvas.drawCircle(c, 25, _fill(const Color(0xFF3A4080)));
    canvas.drawPath(
      Path()
        ..moveTo(46, 30)
        ..lineTo(46, 47)
        ..lineTo(58, 54),
      _stroke(const Color(0xFFE8ECFF), 6),
    );
    // green redo arrow
    final g = _stroke(const Color(0xFF34D17C), 9);
    canvas.drawArc(const Rect.fromLTWH(38, 38, 52, 52), .25, 1.35, false, g);
    canvas.drawPath(
      Path()
        ..moveTo(72, 52)
        ..lineTo(96, 56)
        ..lineTo(84, 77)
        ..close(),
      _fill(const Color(0xFF34D17C)),
    );
  }

  void _agent(Canvas canvas) {
    const r = Rect.fromLTWH(8, 24, 84, 62);
    canvas.drawRRect(_rr(40, 10, 20, 22, 6), _fill(const Color(0xFF8FC0FF)));
    canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(12)),
        _grad(r, const [Color(0xFF6EB0FF), Color(0xFF2468DD)],
            begin: Alignment.topLeft, end: Alignment.bottomRight));
    canvas.drawRRect(_rr(43, 18, 14, 9, 4.5), _fill(const Color(0xFF1B3F96)));
    _person(canvas, const Offset(32, 47), 8, _fill(const Color(0xFFF2F6FF)));
    final line = _stroke(const Color(0xFFDCE8FF), 5.5);
    canvas.drawLine(const Offset(54, 46), const Offset(80, 46), line);
    canvas.drawLine(const Offset(54, 58), const Offset(80, 58), line);
    canvas.drawLine(const Offset(54, 70), const Offset(70, 70), line);
  }

  @override
  bool shouldRepaint(_ArtPainter old) => old.kind != kind || old.tint != tint;
}
