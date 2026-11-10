import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

Color _lighten(Color c, double t) => Color.lerp(c, Colors.white, t)!;
Color _darken(Color c, double t) => Color.lerp(c, Colors.black, t)!;

/// Five pointed star centred on [c].
Path starPath(Offset c, double r, {double inner = 0.45, double rotation = 0}) {
  final p = Path();
  for (var i = 0; i < 10; i++) {
    final rr = i.isEven ? r : r * inner;
    final a = -math.pi / 2 + rotation + i * math.pi / 5;
    final o = c + Offset(math.cos(a), math.sin(a)) * rr;
    i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
  }
  return p..close();
}

/// A glossy Ludo pawn drawn inside [r] (ideal aspect 1 : 1.6).
void paintPawn(Canvas canvas, Rect r, Color color, {bool shadow = true}) {
  final w = r.width, h = r.height, cx = r.center.dx, t = r.top;
  final light = _lighten(color, .38), dark = _darken(color, .38);
  final body = Paint()
    ..shader = LinearGradient(
      colors: [light, color, dark],
      stops: const [0, .45, 1],
    ).createShader(r);

  if (shadow) {
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx + w * .08, t + h * .93),
          width: w * 1.1,
          height: h * .13),
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * .08),
    );
  }

  final base = Rect.fromCenter(
      center: Offset(cx, t + h * .85), width: w * .92, height: h * .2);
  canvas.drawOval(base.shift(Offset(0, h * .035)), Paint()..color = dark);
  canvas.drawOval(base, body);

  final cone = Path()
    ..moveTo(cx - w * .33, t + h * .84)
    ..quadraticBezierTo(cx - w * .13, t + h * .62, cx - w * .11, t + h * .4)
    ..lineTo(cx + w * .11, t + h * .4)
    ..quadraticBezierTo(cx + w * .13, t + h * .62, cx + w * .33, t + h * .84)
    ..quadraticBezierTo(cx, t + h * .92, cx - w * .33, t + h * .84)
    ..close();
  canvas.drawPath(cone, body);

  canvas.drawOval(
    Rect.fromCenter(
        center: Offset(cx, t + h * .415), width: w * .48, height: h * .075),
    body,
  );

  final hc = Offset(cx, t + h * .24);
  final hr = w * .28;
  canvas.drawCircle(
    hc,
    hr,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-.4, -.45),
        radius: 1,
        colors: [light, color, dark],
        stops: const [0, .5, 1],
      ).createShader(Rect.fromCircle(center: hc, radius: hr)),
  );
  canvas.drawOval(
    Rect.fromCenter(
        center: hc + Offset(-hr * .38, -hr * .42),
        width: hr * .5,
        height: hr * .32),
    Paint()..color = const Color(0x99FFFFFF),
  );
}

const _pips = <int, List<Offset>>{
  1: [Offset(.5, .5)],
  2: [Offset(.27, .27), Offset(.73, .73)],
  3: [Offset(.25, .25), Offset(.5, .5), Offset(.75, .75)],
  4: [Offset(.27, .27), Offset(.73, .27), Offset(.27, .73), Offset(.73, .73)],
  5: [
    Offset(.25, .25),
    Offset(.75, .25),
    Offset(.5, .5),
    Offset(.25, .75),
    Offset(.75, .75)
  ],
  6: [
    Offset(.28, .23),
    Offset(.72, .23),
    Offset(.28, .5),
    Offset(.72, .5),
    Offset(.28, .77),
    Offset(.72, .77)
  ],
};

/// One glossy dice face centred on the origin: pearl body, bevelled edge,
/// inset pips (a ruby one for the 1). [light] dims faces turned away.
void _diceFace(Canvas canvas, double edge, int value, double light) {
  final square = Rect.fromCenter(center: Offset.zero, width: edge, height: edge);
  final body = RRect.fromRectAndRadius(square, Radius.circular(edge * .22));
  canvas.drawRRect(
    body,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFF4F1FF), Color(0xFFD5CDEE)],
        stops: [0, .55, 1],
      ).createShader(square),
  );
  // Bevel: bright rim that fades towards the lower right.
  canvas.drawRRect(
    body.deflate(edge * .035),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = edge * .045
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0x00FFFFFF), Color(0x33483C7A)],
      ).createShader(square),
  );
  final ruby = value == 1;
  final r = edge * (ruby ? .13 : .088);
  for (final p in _pips[value]!) {
    final c = Offset((p.dx - .5) * edge * .96, (p.dy - .5) * edge * .96);
    final pr = Rect.fromCircle(center: c, radius: r);
    // Soft lip of light under the hole, then the hole itself.
    canvas.drawCircle(c + Offset(r * .12, r * .16), r * 1.06,
        Paint()..color = const Color(0xCCFFFFFF));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.35, -.4),
          radius: 1.1,
          colors: ruby
              ? const [Color(0xFFFF7A86), Color(0xFFE0182D), Color(0xFF7A0613)]
              : const [Color(0xFF5B5873), Color(0xFF1B1930), Color(0xFF05040C)],
          stops: const [0, .5, 1],
        ).createShader(pr),
    );
    canvas.drawCircle(c + Offset(-r * .32, -r * .36), r * .2,
        Paint()..color = const Color(0x88FFFFFF));
  }
  if (light < 1) {
    canvas.drawRRect(
        body, Paint()..color = Color.fromRGBO(30, 20, 70, (1 - light) * .42));
  }
}

/// The dice at rest: a glossy face with a little thickness underneath.
void paintDice(Canvas canvas, Rect r, int value, {double angle = 0}) {
  canvas.save();
  canvas.translate(r.center.dx, r.center.dy);
  canvas.rotate(angle);
  final s = r.shortestSide;
  final edge = s * .84;
  final rad = Radius.circular(edge * .22);
  final face = Rect.fromCenter(
      center: Offset(0, -s * .04), width: edge, height: edge);
  canvas.drawRRect(
    RRect.fromRectAndRadius(face.shift(Offset(s * .02, s * .13)), rad),
    Paint()
      ..color = const Color(0x73000014)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * .07),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(face.shift(Offset(0, s * .075)), rad),
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFB9AEDD), Color(0xFF8679B8)],
      ).createShader(face.shift(Offset(0, s * .075))),
  );
  canvas.translate(0, -s * .04);
  _diceFace(canvas, edge, value, 1);
  // Glossy sweep across the top.
  canvas.clipRRect(RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: edge, height: edge), rad));
  canvas.drawOval(
    Rect.fromCenter(
        center: Offset(-edge * .1, -edge * .62),
        width: edge * 1.5,
        height: edge * .8),
    Paint()..color = const Color(0x40FFFFFF),
  );
  canvas.restore();
}

typedef _M3 = List<List<double>>;

_M3 _rotX(double a) => [
      [1, 0, 0],
      [0, math.cos(a), -math.sin(a)],
      [0, math.sin(a), math.cos(a)],
    ];
_M3 _rotY(double a) => [
      [math.cos(a), 0, math.sin(a)],
      [0, 1, 0],
      [-math.sin(a), 0, math.cos(a)],
    ];
_M3 _rotZ(double a) => [
      [math.cos(a), -math.sin(a), 0],
      [math.sin(a), math.cos(a), 0],
      [0, 0, 1],
    ];
_M3 _mul(_M3 a, _M3 b) => [
      for (var i = 0; i < 3; i++)
        [
          for (var j = 0; j < 3; j++)
            a[i][0] * b[0][j] + a[i][1] * b[1][j] + a[i][2] * b[2][j],
        ],
    ];
List<double> _apply(_M3 m, List<double> v) => [
      for (var i = 0; i < 3; i++) m[i][0] * v[0] + m[i][1] * v[1] + m[i][2] * v[2],
    ];

// Cube faces as (value, normal, u, v); opposite faces add up to seven.
const _cubeFaces = <(int, List<double>, List<double>, List<double>)>[
  (1, [0, 0, 1], [1, 0, 0], [0, 1, 0]),
  (6, [0, 0, -1], [-1, 0, 0], [0, 1, 0]),
  (2, [1, 0, 0], [0, 0, -1], [0, 1, 0]),
  (5, [-1, 0, 0], [0, 0, 1], [0, 1, 0]),
  (3, [0, 1, 0], [1, 0, 0], [0, 0, -1]),
  (4, [0, -1, 0], [1, 0, 0], [0, 0, 1]),
];

/// Rotation that turns the face showing [value] towards the viewer.
_M3 _faceForward(int value) => switch (value) {
      6 => _rotY(math.pi),
      2 => _rotY(-math.pi / 2),
      5 => _rotY(math.pi / 2),
      3 => _rotX(math.pi / 2),
      4 => _rotX(-math.pi / 2),
      _ => _rotX(0),
    };

/// A real 3D dice centred on [centre] with edge [edge]. It is spun by
/// [rx], [ry], [rz] away from the pose where [value] faces the viewer, so
/// at zero rotation it shows exactly that face.
void paintDice3D(
  Canvas canvas,
  Offset centre,
  double edge,
  int value, {
  double rx = 0,
  double ry = 0,
  double rz = 0,
}) {
  final m = _mul(_mul(_rotZ(rz), _mul(_rotX(rx), _rotY(ry))), _faceForward(value));
  final h = edge / 2;
  final square = Rect.fromCenter(center: Offset.zero, width: edge, height: edge);

  for (final pass in const [0, 1]) {
    for (final (face, n, u, v) in _cubeFaces) {
      final rn = _apply(m, n);
      if (rn[2] <= .001) continue; // facing away
      final ru = _apply(m, u), rv = _apply(m, v);
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.transform(Float64List.fromList([
        ru[0], ru[1], ru[2], 0, //
        rv[0], rv[1], rv[2], 0, //
        rn[0], rn[1], rn[2], 0, //
        rn[0] * h, rn[1] * h, rn[2] * h, 1,
      ]));
      if (pass == 0) {
        // Square under-layer fills the gaps the rounded corners leave.
        canvas.drawRect(
            square.deflate(edge * .06), Paint()..color = const Color(0xFF9D92C8));
      } else {
        // Lit from the front and slightly from above.
        _diceFace(canvas, edge, face,
            (.5 + .5 * rn[2] - .2 * rn[1]).clamp(.0, 1.0));
      }
      canvas.restore();
    }
  }
}

/// Gold coin with an embossed star.
void paintCoin(Canvas canvas, Offset c, double r) {
  final rect = Rect.fromCircle(center: c, radius: r);
  canvas.drawCircle(c + Offset(0, r * .1), r, Paint()..color = AppColors.goldDeep);
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = const RadialGradient(
        center: Alignment(-.4, -.5),
        radius: 1.1,
        colors: [Color(0xFFFFE680), AppColors.gold, Color(0xFFE39A12)],
      ).createShader(rect),
  );
  canvas.drawCircle(
    c,
    r * .74,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * .09
      ..color = const Color(0x55B26A00),
  );
  canvas.drawPath(
      starPath(c, r * .5, inner: .5), Paint()..color = const Color(0xFFFFE680));
}

/// Flat-top cut blue gem.
void paintGem(Canvas canvas, Rect r) {
  final w = r.width, h = r.height, l = r.left, t = r.top;
  Offset p(double x, double y) => Offset(l + w * x, t + h * y);
  Path poly(List<Offset> pts) => Path()..addPolygon(pts, true);

  final tip = p(.5, .98);
  canvas.drawPath(
    poly([p(.2, .08), p(.8, .08), p(1, .36), tip, p(0, .36)]),
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF6FD3FF), Color(0xFF1E8BFF), Color(0xFF0B56D6)],
      ).createShader(r),
  );
  canvas.drawPath(poly([p(.2, .08), p(.8, .08), p(.66, .36), p(.34, .36)]),
      Paint()..color = const Color(0x88D9F4FF));
  canvas.drawPath(poly([p(.34, .36), p(.66, .36), tip]),
      Paint()..color = const Color(0x5599E2FF));
  canvas.drawPath(poly([p(0, .36), p(.34, .36), tip]),
      Paint()..color = const Color(0x33003FA8));
}

/// Half of a laurel wreath (the left half; set [mirror] for the right).
void paintLaurel(Canvas canvas, Rect r, Color color, {bool mirror = false}) {
  canvas.save();
  if (mirror) {
    canvas.translate(r.right, r.top);
    canvas.scale(-1, 1);
  } else {
    canvas.translate(r.left, r.top);
  }
  final w = r.width, h = r.height;
  final centre = Offset(w * 1.25, h * .42);
  final radius = w * 1.05;
  final fill = Paint()..color = color;
  final stem = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = w * .045;

  const a0 = 2.0, a1 = 3.75;
  canvas.drawArc(Rect.fromCircle(center: centre, radius: radius), a0, a1 - a0,
      false, stem);

  const n = 6;
  for (var i = 0; i < n; i++) {
    final a = a0 + (a1 - a0) * (i + .6) / n;
    final pt = centre + Offset(math.cos(a), math.sin(a)) * radius;
    final len = w * (.42 - i * .018);
    for (final side in const [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(pt.dx, pt.dy);
      canvas.rotate(a + math.pi / 2 + side * .75);
      canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..quadraticBezierTo(len * .5, -len * .42, len, 0)
          ..quadraticBezierTo(len * .5, len * .42, 0, 0),
        fill,
      );
      canvas.restore();
    }
  }
  canvas.restore();
}

class PawnPainter extends CustomPainter {
  const PawnPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) =>
      paintPawn(canvas, Offset.zero & size, color);

  @override
  bool shouldRepaint(PawnPainter old) => old.color != color;
}

class LaurelPainter extends CustomPainter {
  const LaurelPainter({this.mirror = false, this.color = AppColors.mint});
  final bool mirror;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) =>
      paintLaurel(canvas, Offset.zero & size, color, mirror: mirror);

  @override
  bool shouldRepaint(LaurelPainter old) => false;
}

class CoinPainter extends CustomPainter {
  const CoinPainter();

  @override
  void paint(Canvas canvas, Size size) => paintCoin(
      canvas, size.center(Offset.zero), size.shortestSide / 2 * .92);

  @override
  bool shouldRepaint(CoinPainter old) => false;
}

class GemPainter extends CustomPainter {
  const GemPainter();

  @override
  void paint(Canvas canvas, Size size) => paintGem(canvas, Offset.zero & size);

  @override
  bool shouldRepaint(GemPainter old) => false;
}
