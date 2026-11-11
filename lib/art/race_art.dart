import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/race_game.dart';

const carColours = [
  (Color(0xFFFF3B3B), Color(0xFF8E0B0B)), // red - the player
  (Color(0xFF3B7BFF), Color(0xFF0B2E8E)),
  (Color(0xFF35D46A), Color(0xFF0B6E2E)),
  (Color(0xFFFFC233), Color(0xFF9A6A00)),
];

/// The race seen from behind the player's car: sky and hills, the road
/// projected segment by segment, roadside props, rival cars and the
/// player's car.
class RaceScenePainter extends CustomPainter {
  RaceScenePainter({
    required this.game,
    required this.skyOffset,
    required this.time,
    required this.shake,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final RaceGame game;
  final double Function() skyOffset;
  final double Function() time;
  final double Function() shake;

  static const _fog = Color(0xFF9FB7E8);

  /// The horizon, and where the road under the player's car meets the
  /// screen, as fractions of the height: the car sits above the controls.
  static const horizon = .4, ground = .8;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final t = time();
    final s = shake();
    canvas.save();
    if (s > 0) {
      canvas.translate(math.sin(t * 90) * s * 6, math.cos(t * 70) * s * 4);
    }
    _background(canvas, size, skyOffset());

    final g = game, p = g.player;
    final n = g.segments.length, L = g.trackLength;
    final camZ = ((p.z - RaceGame.playerZ) % L + L) % L;
    final base = g.segmentAt(camZ);
    final basePct = (camZ % RaceGame.segLen) / RaceGame.segLen;
    final pSeg = g.segmentAt(p.z);
    final pPct = (p.z % RaceGame.segLen) / RaceGame.segLen;
    final playerY = pSeg.y1 + (pSeg.y2 - pSeg.y1) * pPct;
    final camX = p.x * RaceGame.roadWidth;
    final camY = RaceGame.cameraHeight + playerY;

    var maxy = h;
    var x = 0.0, dx = -(base.curve * basePct);
    final visible = <_Proj>[];

    (double, double, double, double) project(double wx, double wy, double wz) {
      final cx = wx - camX, cy = wy - camY, cz = wz - camZ;
      final scale = RaceGame.cameraDepth / cz;
      return (
        w / 2 + scale * cx * w / 2,
        h * horizon - scale * cy * h * (ground - horizon),
        scale * RaceGame.roadWidth * w / 2,
        scale,
      );
    }

    for (var i = 0; i < RaceGame.drawDistance; i++) {
      final seg = g.segments[(base.index + i) % n];
      final looped = seg.index < base.index;
      final z1 = seg.index * RaceGame.segLen + (looped ? L : 0);
      final cz1 = z1 - camZ;
      final p1 = project(-x, seg.y1, z1);
      final p2 = project(-x - dx, seg.y2, z1 + RaceGame.segLen);
      x += dx;
      dx += seg.curve;
      final clip = maxy;
      if (cz1 <= RaceGame.cameraDepth || p2.$2 >= p1.$2 || p2.$2 >= maxy) {
        continue;
      }
      visible.add(_Proj(seg, p1, p2, clip, i / RaceGame.drawDistance));
      maxy = p1.$2;
    }

    // Road far to near, so nearer segments cover farther ones.
    for (final v in visible.reversed) {
      _segment(canvas, w, v);
    }

    // Props and rival cars, far to near, each clipped by the road in front.
    final cars = <int, List<Racer>>{};
    for (final r in g.racers) {
      if (r.isPlayer) continue;
      cars.putIfAbsent(g.segmentAt(r.z).index, () => []).add(r);
    }
    for (final v in visible.reversed) {
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, 0, w, v.clip));
      for (final prop in v.seg.props) {
        final sx = v.p1.$1 + v.p1.$4 * prop.offset * RaceGame.roadWidth * w / 2;
        _prop(canvas, prop.kind, Offset(sx, v.p1.$2), v.p1.$4 * w / 2, v.fog);
      }
      for (final r in cars[v.seg.index] ?? const <Racer>[]) {
        final pct = (r.z % RaceGame.segLen) / RaceGame.segLen;
        final sc = v.p1.$4 + (v.p2.$4 - v.p1.$4) * pct;
        final sx =
            v.p1.$1 +
            (v.p2.$1 - v.p1.$1) * pct +
            sc * r.x * RaceGame.roadWidth * w / 2;
        final sy = v.p1.$2 + (v.p2.$2 - v.p1.$2) * pct;
        paintCar(
          canvas,
          Offset(sx, sy),
          640 * sc * w / 2,
          r.colour,
          steer: r.steer,
          braking: r.braking,
          boost: false,
          time: t,
        );
      }
      canvas.restore();
    }

    // The player's car, bobbing a little with speed and more off-road.
    final pct = p.speed / RaceGame.maxSpeed;
    final rough = p.x.abs() > 1 ? 4.0 : 1.2;
    final bob = math.sin(t * 40) * rough * pct;
    final carW = w * .36;
    paintCar(
      canvas,
      Offset(w / 2, h * ground + bob),
      carW,
      p.colour,
      steer: p.steer,
      braking: p.braking,
      boost: p.boosting,
      time: t,
    );

    if (p.boosting) _speedLines(canvas, size, t);
    canvas.restore();
  }

  void _background(Canvas canvas, Size size, double off) {
    final w = size.width, h = size.height;
    final hz = h * horizon;
    final sky = Rect.fromLTWH(0, 0, w, hz + 2);
    canvas.drawRect(
      sky,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1B2A8A), Color(0xFF5B74D8), Color(0xFFFFB27A)],
          stops: [0, .6, 1],
        ).createShader(sky),
    );
    // Sun.
    final sun = Offset(w * .7 - off * w * .05 % w, hz * .55);
    canvas.drawCircle(
      sun,
      w * .2,
      Paint()
        ..color = const Color(0x33FFE6A8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
    );
    canvas.drawCircle(sun, w * .08, Paint()..color = const Color(0xFFFFE9B0));

    void ridge(
      double baseY,
      double amp,
      double freq,
      double par,
      Color c,
      int seed,
    ) {
      final path = Path()..moveTo(0, h);
      for (var x = 0.0; x <= w + 4; x += 4) {
        final u = (x / w) + off * par;
        final y =
            baseY -
            amp *
                (.55 +
                    .3 * math.sin(u * freq + seed) +
                    .15 * math.sin(u * freq * 2.7 + seed * 2));
        path.lineTo(x, y);
      }
      path
        ..lineTo(w, h)
        ..close();
      canvas.drawPath(path, Paint()..color = c);
    }

    ridge(hz - h * .01, h * .12, 6, .05, const Color(0xFF7A86C8), 1);
    ridge(hz + h * .005, h * .07, 11, .1, const Color(0xFF4E5BA8), 3);
    // City skyline in between.
    final city = Paint()..color = const Color(0xFF3A3F86);
    final rnd = math.Random(4);
    for (var i = 0; i < 40; i++) {
      final bx = ((i * 37 + rnd.nextInt(20)) - off * w * .15) % (w + 60) - 30;
      final bh = h * (.03 + rnd.nextDouble() * .06);
      canvas.drawRect(
        Rect.fromLTWH(bx, hz + h * .005 - bh, 14 + rnd.nextDouble() * 18, bh),
        city,
      );
    }
    // Far grass behind the end of the road.
    canvas.drawRect(
      Rect.fromLTWH(0, hz, w, h - hz),
      Paint()..color = Color.lerp(const Color(0xFF2E9E45), _fog, .55)!,
    );
  }

  Color _fogged(Color c, double f) =>
      Color.lerp(c, _fog, (f * f * .9).clamp(0.0, .9))!;

  void _segment(Canvas canvas, double w, _Proj v) {
    final (x1, y1, w1, _) = v.p1;
    final (x2, y2, w2, _) = v.p2;
    final dark = (v.seg.index ~/ RaceGame.rumbleLen).isEven;
    final f = v.fog;
    canvas.drawRect(
      Rect.fromLTRB(0, y2, w, y1 + 1),
      Paint()
        ..color = _fogged(
          dark ? const Color(0xFF3FAF52) : const Color(0xFF34A048),
          f,
        ),
    );
    Path quad(double a1, double a2, double b1, double b2) => Path()
      ..moveTo(a1, y1 + .6)
      ..lineTo(a2, y1 + .6)
      ..lineTo(b2, y2)
      ..lineTo(b1, y2)
      ..close();
    final r1 = w1 / 6, r2 = w2 / 6;
    canvas.drawPath(
      quad(x1 - w1 - r1, x1 + w1 + r1, x2 - w2 - r2, x2 + w2 + r2),
      Paint()
        ..color = _fogged(
          dark ? const Color(0xFFE8E8E8) : const Color(0xFFD62828),
          f,
        ),
    );
    final start = v.seg.index < 2;
    canvas.drawPath(
      quad(x1 - w1, x1 + w1, x2 - w2, x2 + w2),
      Paint()
        ..color = _fogged(
          dark ? const Color(0xFF5A5A63) : const Color(0xFF55555E),
          f,
        ),
    );
    if (start) {
      // Chequered start and finish line.
      const cells = 12;
      for (var c = 0; c < cells; c++) {
        final a = c / cells, b = (c + 1) / cells;
        if ((c + v.seg.index).isEven) continue;
        canvas.drawPath(
          quad(
            x1 - w1 + 2 * w1 * a,
            x1 - w1 + 2 * w1 * b,
            x2 - w2 + 2 * w2 * a,
            x2 - w2 + 2 * w2 * b,
          ),
          Paint()..color = _fogged(Colors.white, f),
        );
      }
    } else if (dark) {
      final l1 = w1 / 32, l2 = w2 / 32;
      for (var lane = 1; lane < RaceGame.lanes; lane++) {
        final a = -1 + lane * 2 / RaceGame.lanes;
        canvas.drawPath(
          quad(
            x1 + w1 * a - l1,
            x1 + w1 * a + l1,
            x2 + w2 * a - l2,
            x2 + w2 * a + l2,
          ),
          Paint()..color = _fogged(const Color(0xFFF2F2F2), f),
        );
      }
    }
  }

  void _prop(Canvas canvas, Prop kind, Offset at, double unit, double fog) {
    // unit: screen pixels per world unit.
    double u(double world) => world * unit;
    switch (kind) {
      case Prop.tree:
        canvas.drawRect(
          Rect.fromCenter(
            center: at - Offset(0, u(220)),
            width: u(110),
            height: u(440),
          ),
          Paint()..color = const Color(0xFF6B3F1D),
        );
        for (final (dx, dy, r) in const [
          (0.0, 760.0, 360.0),
          (-210.0, 560.0, 270.0),
          (210.0, 560.0, 270.0),
        ]) {
          final c = at + Offset(u(dx), -u(dy));
          canvas.drawCircle(
            c,
            u(r),
            Paint()
              ..shader = RadialGradient(
                center: const Alignment(-.3, -.4),
                colors: const [Color(0xFF6FE07A), Color(0xFF1E8A3A)],
              ).createShader(Rect.fromCircle(center: c, radius: u(r))),
          );
        }
      case Prop.palm:
        final top = at - Offset(u(80), u(1200));
        canvas.drawPath(
          Path()
            ..moveTo(at.dx - u(50), at.dy)
            ..quadraticBezierTo(at.dx + u(90), at.dy - u(600), top.dx, top.dy)
            ..lineTo(top.dx + u(60), top.dy)
            ..quadraticBezierTo(
              at.dx + u(150),
              at.dy - u(600),
              at.dx + u(50),
              at.dy,
            )
            ..close(),
          Paint()..color = const Color(0xFF9A6A3A),
        );
        for (var k = 0; k < 6; k++) {
          final a = -math.pi / 2 + (k - 2.5) * .55;
          final tip =
              top + Offset(math.cos(a) * u(520), math.sin(a) * u(260) + u(170));
          canvas.drawPath(
            Path()
              ..moveTo(top.dx, top.dy)
              ..quadraticBezierTo(
                (top.dx + tip.dx) / 2,
                top.dy - u(160),
                tip.dx,
                tip.dy,
              )
              ..quadraticBezierTo(
                (top.dx + tip.dx) / 2,
                top.dy - u(40),
                top.dx,
                top.dy,
              ),
            Paint()..color = const Color(0xFF2FB34E),
          );
        }
      case Prop.billboard:
        final post = Paint()..color = const Color(0xFF555A66);
        canvas.drawRect(
          Rect.fromLTWH(at.dx - u(500), at.dy - u(700), u(60), u(700)),
          post,
        );
        canvas.drawRect(
          Rect.fromLTWH(at.dx + u(440), at.dy - u(700), u(60), u(700)),
          post,
        );
        final board = Rect.fromCenter(
          center: at - Offset(0, u(1050)),
          width: u(1500),
          height: u(700),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(board, Radius.circular(u(60))),
          Paint()..color = const Color(0xFFE3B341),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(board.deflate(u(45)), Radius.circular(u(40))),
          Paint()
            ..shader = const LinearGradient(
              colors: [Color(0xFF2A1F7A), Color(0xFF6A2BC8)],
            ).createShader(board),
        );
        if (board.width > 40) {
          final tp = TextPainter(
            text: TextSpan(
              text: 'ELITE PLAY BD',
              style: TextStyle(
                fontFamily: 'Fredoka',
                fontWeight: FontWeight.w700,
                fontSize: board.height * .3,
                color: const Color(0xFFFFE28A),
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: board.width);
          tp.paint(canvas, board.center - Offset(tp.width / 2, tp.height / 2));
        }
      case Prop.lamp:
        final pole = Paint()..color = const Color(0xFF8A8FA0);
        canvas.drawRect(
          Rect.fromLTWH(at.dx - u(30), at.dy - u(1700), u(60), u(1700)),
          pole,
        );
        final dir = at.dx < 0 ? 1.0 : -1.0;
        final head = at + Offset(dir * u(300), -u(1660));
        canvas.drawLine(
          at - Offset(0, u(1660)),
          head,
          pole..strokeWidth = u(50),
        );
        canvas.drawCircle(
          head,
          u(180),
          Paint()
            ..color = const Color(0x55FFF1B8)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, u(120) + 1),
        );
        canvas.drawOval(
          Rect.fromCenter(center: head, width: u(200), height: u(80)),
          Paint()..color = const Color(0xFFFFF4CC),
        );
      case Prop.rock:
        canvas.drawPath(
          Path()
            ..moveTo(at.dx - u(320), at.dy)
            ..lineTo(at.dx - u(240), at.dy - u(280))
            ..lineTo(at.dx - u(40), at.dy - u(380))
            ..lineTo(at.dx + u(200), at.dy - u(300))
            ..lineTo(at.dx + u(320), at.dy)
            ..close(),
          Paint()..color = const Color(0xFF8C8C96),
        );
      case Prop.cone:
        final base = Rect.fromCenter(
          center: at - Offset(0, u(15)),
          width: u(200),
          height: u(30),
        );
        canvas.drawRect(base, Paint()..color = const Color(0xFFE85A00));
        canvas.drawPath(
          Path()
            ..moveTo(at.dx - u(70), at.dy - u(30))
            ..lineTo(at.dx + u(70), at.dy - u(30))
            ..lineTo(at.dx + u(12), at.dy - u(300))
            ..lineTo(at.dx - u(12), at.dy - u(300))
            ..close(),
          Paint()..color = const Color(0xFFFF7A1A),
        );
        canvas.drawRect(
          Rect.fromCenter(
            center: at - Offset(0, u(160)),
            width: u(95),
            height: u(45),
          ),
          Paint()..color = Colors.white,
        );
      case Prop.barrel:
        final r = Rect.fromLTWH(at.dx - u(120), at.dy - u(340), u(240), u(340));
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, Radius.circular(u(40))),
          Paint()
            ..shader = const LinearGradient(
              colors: [Color(0xFF8E0B0B), Color(0xFFFF3B3B), Color(0xFF8E0B0B)],
            ).createShader(r),
        );
        for (final y in [.3, .7]) {
          canvas.drawRect(
            Rect.fromLTWH(r.left, r.top + r.height * y - u(20), r.width, u(40)),
            Paint()..color = Colors.white,
          );
        }
      case Prop.arch:
        final half = RaceGame.roadWidth * 1.25;
        final pillar = Paint()..color = const Color(0xFF2A2F78);
        for (final sx in [-1.0, 1.0]) {
          canvas.drawRect(
            Rect.fromLTWH(
              at.dx + u(half) * sx - u(110),
              at.dy - u(2200),
              u(220),
              u(2200),
            ),
            pillar,
          );
        }
        final banner = Rect.fromLTRB(
          at.dx - u(half) - u(110),
          at.dy - u(2400),
          at.dx + u(half) + u(110),
          at.dy - u(1900),
        );
        canvas.drawRect(
          banner,
          Paint()
            ..shader = const LinearGradient(
              colors: [Color(0xFFFFF1B8), Color(0xFFE3B341), Color(0xFFB8862B)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ).createShader(banner),
        );
        if (banner.width > 60) {
          final tp = TextPainter(
            text: TextSpan(
              text: 'START  •  FINISH',
              style: TextStyle(
                fontFamily: 'Fredoka',
                fontWeight: FontWeight.w700,
                fontSize: banner.height * .55,
                color: const Color(0xFF2A1F7A),
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: banner.width);
          tp.paint(canvas, banner.center - Offset(tp.width / 2, tp.height / 2));
        }
    }
  }

  void _speedLines(Canvas canvas, Size size, double t) {
    final c = Offset(size.width / 2, size.height * .45);
    final rnd = math.Random((t * 30).floor());
    final p = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 2;
    for (var i = 0; i < 26; i++) {
      final a = rnd.nextDouble() * 2 * math.pi;
      final r0 = size.width * (.35 + rnd.nextDouble() * .2);
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * r0, c + d * (r0 + size.width * .25), p);
    }
  }

  @override
  bool shouldRepaint(RaceScenePainter old) => true;
}

class _Proj {
  _Proj(this.seg, this.p1, this.p2, this.clip, this.fog);
  final Segment seg;
  final (double, double, double, double) p1, p2;
  final double clip, fog;
}

/// A sports car seen from behind, standing on [bottom] (its centre at
/// ground level) and [width] pixels wide.
void paintCar(
  Canvas canvas,
  Offset bottom,
  double width,
  int colour, {
  required double steer,
  required bool braking,
  required bool boost,
  required double time,
}) {
  if (width < 2) return;
  final (light, dark) = carColours[colour % carColours.length];
  final w = width, h = width * .52;
  final x = bottom.dx, y = bottom.dy;
  final lean = steer * w * .04;

  // Shadow.
  canvas.drawOval(
    Rect.fromCenter(
      center: Offset(x, y - h * .02),
      width: w * 1.1,
      height: h * .2,
    ),
    Paint()..color = const Color(0x66000000),
  );
  // Tyres.
  final tyre = Paint()..color = const Color(0xFF16161C);
  for (final s in [-1.0, 1.0]) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + s * w * .38, y - h * .14),
          width: w * .2,
          height: h * .3,
        ),
        Radius.circular(w * .04),
      ),
      tyre,
    );
  }
  // Lower body.
  final body = Rect.fromLTRB(x - w / 2, y - h * .66, x + w / 2, y - h * .1);
  canvas.drawRRect(
    RRect.fromRectAndCorners(
      body,
      topLeft: Radius.circular(w * .12),
      topRight: Radius.circular(w * .12),
      bottomLeft: Radius.circular(w * .06),
      bottomRight: Radius.circular(w * .06),
    ),
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color.lerp(light, Colors.white, .25)!, light, dark],
        stops: const [0, .45, 1],
      ).createShader(body),
  );
  // Cabin.
  final cabin = Path()
    ..moveTo(x - w * .36, y - h * .64)
    ..lineTo(x + w * .36, y - h * .64)
    ..lineTo(x + w * .27 + lean, y - h * .98)
    ..lineTo(x - w * .27 + lean, y - h * .98)
    ..close();
  canvas.drawPath(cabin, Paint()..color = dark);
  final glass = Path()
    ..moveTo(x - w * .31, y - h * .67)
    ..lineTo(x + w * .31, y - h * .67)
    ..lineTo(x + w * .24 + lean, y - h * .93)
    ..lineTo(x - w * .24 + lean, y - h * .93)
    ..close();
  canvas.drawPath(
    glass,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Color(0xFF8FB4FF), Color(0xFF1A2050)],
      ).createShader(glass.getBounds()),
  );
  // Spoiler.
  final spoiler = Paint()..color = Color.lerp(dark, Colors.black, .3)!;
  canvas.drawRect(
    Rect.fromLTRB(x - w * .52, y - h * .78, x + w * .52, y - h * .7),
    spoiler,
  );
  for (final s in [-1.0, 1.0]) {
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(x + s * w * .3, y - h * .69),
        width: w * .04,
        height: h * .08,
      ),
      spoiler,
    );
  }
  // Tail lights.
  for (final s in [-1.0, 1.0]) {
    final r = Rect.fromCenter(
      center: Offset(x + s * w * .34, y - h * .46),
      width: w * .2,
      height: h * .1,
    );
    if (braking) {
      canvas.drawOval(
        r.inflate(w * .06),
        Paint()
          ..color = const Color(0x99FF2020)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * .05),
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, Radius.circular(h * .04)),
      Paint()
        ..color = braking ? const Color(0xFFFF5050) : const Color(0xFFB01818),
    );
  }
  // Number plate.
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(x, y - h * .32),
        width: w * .24,
        height: h * .1,
      ),
      Radius.circular(h * .02),
    ),
    Paint()..color = const Color(0xFFF2F2F2),
  );
  // Exhausts, with nitro flames.
  for (final s in [-1.0, 1.0]) {
    final e = Offset(x + s * w * .16, y - h * .15);
    canvas.drawCircle(e, w * .03, Paint()..color = const Color(0xFF2A2A30));
    if (boost) {
      final len = h * (.35 + .15 * math.sin(time * 60 + s));
      final flame = Path()
        ..moveTo(e.dx - w * .03, e.dy)
        ..lineTo(e.dx + w * .03, e.dy)
        ..lineTo(e.dx, e.dy + len);
      canvas.drawPath(
        flame,
        Paint()
          ..color = const Color(0xCC4FC3FF)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * .02),
      );
      canvas.drawPath(flame, Paint()..color = const Color(0xFFFFE28A));
    }
  }
}
