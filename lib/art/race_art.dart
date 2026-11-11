import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/race_game.dart';

const carColours = [
  (Color(0xFFFF3B3B), Color(0xFF8E0B0B)), // red - the player
  (Color(0xFF3B7BFF), Color(0xFF0B2E8E)),
  (Color(0xFF35D46A), Color(0xFF0B6E2E)),
  (Color(0xFFFFC233), Color(0xFF9A6A00)),
];

/// The pictures the race is drawn with, decoded once and kept.
abstract final class RaceSprites {
  static final _names = [
    for (var i = 0; i < 8; i++) 'tree$i',
    for (var i = 0; i < 8; i++) 'bush$i',
    for (var i = 0; i < 8; i++) 'flower$i',
    for (var i = 0; i < 4; i++) 'rock$i',
    for (var i = 0; i < 4; i++) 'car$i',
    for (var i = 0; i < 4; i++) 'flag$i',
    for (var i = 0; i < 3; i++) 'barrel$i',
    'fence0',
    'fence1',
    'rail',
    'lamp0',
    'lamp1',
    'chevron',
    'sign80',
    'warn',
    'cone',
    'tyres0',
    'tyres1',
    'hay',
    'barrier0',
    'barrier1',
  ];
  static final _images = <String, ui.Image>{};
  static Future<void>? _loading;

  static ui.Image? of(String name) => _images[name];

  static Future<void> load() => _loading ??= Future.wait([
    for (final n in _names)
      () async {
        try {
          final data = await rootBundle.load('assets/images/race/$n.png');
          final codec = await ui.instantiateImageCodec(
            data.buffer.asUint8List(),
          );
          _images[n] = (await codec.getNextFrame()).image;
        } catch (_) {
          // A missing picture is simply not drawn.
        }
      }(),
  ]);
}

/// Which picture a prop uses, how many world units one of its pixels
/// covers, and how far off the ground it stands (signs sit on a pole).
(String, double, double) _look(RoadProp p) => switch (p.kind) {
  Prop.tree => ('tree${p.variant % 8}', 9.5, 0),
  Prop.bush => ('bush${p.variant % 8}', 5, 0),
  Prop.flower => ('flower${p.variant % 8}', 4, 0),
  Prop.rock => ('rock${p.variant % 4}', 5, 0),
  Prop.fence => (const ['fence0', 'fence1', 'rail'][p.variant % 3], 3.3, 0),
  Prop.lamp => ('lamp${p.variant % 2}', 7.5, 0),
  Prop.flag => ('flag${p.variant % 4}', 8, 0),
  Prop.sign => (p.variant.isEven ? 'sign80' : 'warn', 6, 520),
  Prop.chevron => ('chevron', 6, 0),
  Prop.cone => ('cone', 3, 0),
  Prop.barrel => ('barrel${p.variant % 3}', 3.6, 0),
  Prop.tyres => ('tyres${p.variant % 2}', 3, 0),
  Prop.barrier => ('barrier${p.variant % 2}', 3.6, 0),
  Prop.hay => ('hay', 3.3, 0),
  Prop.arch => ('', 0, 0),
};

/// The race seen from above and behind the player's car: sky and hills,
/// the road projected segment by segment, roadside scenery, rival cars
/// and the player's car.
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

  static const _haze = Color(0xFFCFEBF7);

  /// The horizon, and where the road under the player's car meets the
  /// screen, as fractions of the height: the car sits above the controls.
  static const horizon = .3, ground = .8;

  /// How much a car seen from above is squashed by the low camera.
  static const _carSquash = .64;
  static const _carWidth = 620.0;

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

    // Scenery and rival cars, far to near, each clipped by the road in
    // front of it.
    final cars = <int, List<Racer>>{};
    for (final r in g.racers) {
      if (r.isPlayer) continue;
      cars.putIfAbsent(g.segmentAt(r.z).index, () => []).add(r);
    }
    for (final v in visible.reversed) {
      final here = cars[v.seg.index];
      if (v.seg.props.isEmpty && here == null) continue;
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, 0, w, v.clip));
      final unit = v.p1.$4 * w / 2;
      for (final prop in v.seg.props) {
        final sx = v.p1.$1 + unit * prop.offset * RaceGame.roadWidth;
        _prop(canvas, w, prop, Offset(sx, v.p1.$2), unit, v.fog);
      }
      for (final r in here ?? const <Racer>[]) {
        final pct = (r.z % RaceGame.segLen) / RaceGame.segLen;
        final sc = v.p1.$4 + (v.p2.$4 - v.p1.$4) * pct;
        final sx =
            v.p1.$1 +
            (v.p2.$1 - v.p1.$1) * pct +
            sc * r.x * RaceGame.roadWidth * w / 2;
        final sy = v.p1.$2 + (v.p2.$2 - v.p1.$2) * pct;
        _car(canvas, Offset(sx, sy), _carWidth * sc * w / 2, r, t, false);
      }
      canvas.restore();
    }

    // The player's car, bobbing a little with speed and more off-road.
    final pct = p.speed / RaceGame.maxSpeed;
    final off = p.x.abs() > 1;
    final bob = math.sin(t * 40) * (off ? 3.5 : 1) * pct;
    final carW = _carWidth / RaceGame.cameraHeight * w / 2;
    final at = Offset(w / 2, h * ground + bob);
    if (off && pct > .05) _dust(canvas, at, carW, t);
    _car(canvas, at, carW, p, t, p.boosting);

    if (p.boosting) _speedLines(canvas, size, t);
    canvas.restore();
  }

  void _car(
    Canvas canvas,
    Offset at,
    double width,
    Racer r,
    double t,
    bool boost,
  ) {
    if (width < 2) return;
    final img = RaceSprites.of('car${r.colour % 4}');
    if (img == null) {
      paintCar(
        canvas,
        at,
        width,
        r.colour,
        steer: r.steer,
        braking: r.braking,
        boost: boost,
        time: t,
      );
      return;
    }
    final height = width * img.height / img.width * _carSquash;
    final dst = Rect.fromLTWH(-width / 2, -height, width, height);
    canvas.save();
    canvas.translate(at.dx, at.dy);
    // Turn about the middle of the car.
    canvas.translate(0, -height / 2);
    canvas.rotate(r.steer * .09);
    canvas.translate(0, height / 2);
    if (boost) {
      for (final s in [-1.0, 1.0]) {
        final e = Offset(s * width * .17, -height * .06);
        final len = height * (.5 + .12 * math.sin(t * 60 + s));
        final flame = Path()
          ..moveTo(e.dx - width * .07, e.dy)
          ..quadraticBezierTo(e.dx, e.dy + len * 1.6, e.dx + width * .07, e.dy)
          ..close();
        canvas.drawPath(
          flame,
          Paint()
            ..color = const Color(0xCC3FA9FF)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * .04),
        );
        canvas.drawPath(
          Path()
            ..moveTo(e.dx - width * .035, e.dy)
            ..quadraticBezierTo(e.dx, e.dy + len, e.dx + width * .035, e.dy)
            ..close(),
          Paint()..color = const Color(0xFFEFFBFF),
        );
      }
    }
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
    if (r.braking) {
      for (final s in [-1.0, 1.0]) {
        final c = Offset(s * width * .27, -height * .12);
        canvas.drawOval(
          Rect.fromCenter(center: c, width: width * .3, height: height * .14),
          Paint()
            ..color = const Color(0xDDFF2A2A)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * .05),
        );
        canvas.drawOval(
          Rect.fromCenter(center: c, width: width * .14, height: height * .05),
          Paint()..color = const Color(0xFFFFD0D0),
        );
      }
    }
    canvas.restore();
  }

  void _dust(Canvas canvas, Offset at, double carW, double t) {
    final rnd = math.Random((t * 20).floor());
    for (var i = 0; i < 9; i++) {
      final c =
          at +
          Offset(
            (rnd.nextDouble() - .5) * carW * 1.3,
            rnd.nextDouble() * carW * .35,
          );
      canvas.drawCircle(
        c,
        carW * (.08 + rnd.nextDouble() * .12),
        Paint()..color = const Color(0x66C9A46B),
      );
    }
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
          colors: [Color(0xFF1E7BE6), Color(0xFF58B4F5), Color(0xFFC9ECFB)],
          stops: [0, .6, 1],
        ).createShader(sky),
    );
    // Puffy clouds drifting with the bends.
    final cloud = Paint()..color = Colors.white;
    final shade = Paint()..color = const Color(0xFFDDEEFA);
    const clouds = [
      (.12, .22, 1.0),
      (.48, .1, .7),
      (.8, .3, 1.15),
      (1.15, .16, .85),
    ];
    for (final (cx, cy, sc) in clouds) {
      final bx = ((cx - off * .08) % 1.4) * w - w * .2;
      final by = hz * (cy + .25), r = w * .05 * sc;
      for (final (dx, dy, k) in const [
        (-1.5, .3, .8),
        (-.6, -.2, 1.1),
        (.4, -.45, 1.25),
        (1.3, 0.0, 1.0),
        (2.1, .35, .7),
      ]) {
        canvas.drawCircle(
          Offset(bx + dx * r, by + dy * r + r * .25),
          r * k,
          shade,
        );
        canvas.drawCircle(Offset(bx + dx * r, by + dy * r), r * k, cloud);
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(bx - 2.2 * r, by + r * .2, bx + 2.8 * r, by + r * 1.1),
          Radius.circular(r),
        ),
        cloud,
      );
    }

    void ridge(
      double baseY,
      double amp,
      double freq,
      double par,
      Paint paint,
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
      canvas.drawPath(path, paint);
    }

    Paint grad(Color a, Color b) => Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [a, b],
      ).createShader(Rect.fromLTRB(0, hz - h * .16, w, hz));
    ridge(
      hz,
      h * .15,
      5,
      .05,
      grad(const Color(0xFF5FA6C9), const Color(0xFF8FCFD9)),
      1,
    );
    ridge(
      hz + h * .004,
      h * .09,
      9,
      .1,
      grad(const Color(0xFF3F9A4E), const Color(0xFF7CC85A)),
      3,
    );
    // A far line of tree tops.
    final trees = Paint()..color = const Color(0xFF2F8A3A);
    final rnd = math.Random(7);
    for (var i = 0; i < 46; i++) {
      final bx = ((i * 31 + rnd.nextInt(18)) - off * w * .16) % (w + 60) - 30;
      final r = h * (.008 + rnd.nextDouble() * .012);
      canvas.drawCircle(Offset(bx, hz - r * .5), r, trees);
    }
    // Far grass behind the end of the road.
    canvas.drawRect(
      Rect.fromLTWH(0, hz, w, h - hz),
      Paint()..color = Color.lerp(const Color(0xFF66C22E), _haze, .35)!,
    );
  }

  Color _hazed(Color c, double f) =>
      Color.lerp(c, _haze, (f * f * .55).clamp(0.0, .55))!;

  void _segment(Canvas canvas, double w, _Proj v) {
    final (x1, y1, w1, _) = v.p1;
    final (x2, y2, w2, _) = v.p2;
    final band = v.seg.index ~/ RaceGame.rumbleLen;
    final dark = band.isEven;
    final f = v.fog;
    // No anti-aliasing: it would leave hairline seams between segments.
    Paint ink(Color c) => Paint()
      ..color = _hazed(c, f)
      ..isAntiAlias = false;
    canvas.drawRect(
      Rect.fromLTRB(0, y2, w, y1 + 1),
      ink(dark ? const Color(0xFF6CC72F) : const Color(0xFF61BA29)),
    );
    Path quad(double a1, double a2, double b1, double b2) => Path()
      ..moveTo(a1, y1 + 1)
      ..lineTo(a2, y1 + 1)
      ..lineTo(b2, y2)
      ..lineTo(b1, y2)
      ..close();
    // A strip between two fractions of the road's half-width.
    void strip(double a, double b, Color c) => canvas.drawPath(
      quad(x1 + w1 * a, x1 + w1 * b, x2 + w2 * a, x2 + w2 * b),
      ink(c),
    );

    // Kerbs: a dark outer lip, then chunky red and white blocks.
    strip(-1.2, 1.2, dark ? const Color(0xFF4E9A22) : const Color(0xFF468D1E));
    strip(
      -1.16,
      1.16,
      dark ? const Color(0xFFB8BCC4) : const Color(0xFFA01818),
    );
    strip(
      -1.14,
      1.14,
      dark ? const Color(0xFFF7F7F7) : const Color(0xFFE02A2A),
    );
    // Tarmac.
    strip(-1, 1, dark ? const Color(0xFF3C3E48) : const Color(0xFF393B44));
    if (v.seg.index < 2) {
      // Chequered start and finish line.
      const cells = 12;
      for (var c = 0; c < cells; c++) {
        if ((c + v.seg.index).isEven) continue;
        strip(-1 + 2 * c / cells, -1 + 2 * (c + 1) / cells, Colors.white);
      }
      return;
    }
    // Solid white lines along both edges, dashes between the lanes.
    strip(-.95, -.915, const Color(0xFFF4F4F4));
    strip(.915, .95, const Color(0xFFF4F4F4));
    if (band % 3 != 2) {
      for (var lane = 1; lane < RaceGame.lanes; lane++) {
        final a = -1 + lane * 2 / RaceGame.lanes;
        strip(a - .02, a + .02, const Color(0xFFF4F4F4));
      }
    }
  }

  void _prop(
    Canvas canvas,
    double w,
    RoadProp prop,
    Offset at,
    double unit,
    double fog,
  ) {
    // unit: screen pixels per world unit.
    double u(double world) => world * unit;
    if (prop.kind == Prop.arch) {
      _arch(canvas, at, u);
      return;
    }
    final (name, perPixel, lift) = _look(prop);
    final img = RaceSprites.of(name);
    if (img == null) return;
    final width = u(img.width * perPixel);
    if (width < 1.5) return;
    final height = width * img.height / img.width;
    final dst = Rect.fromLTWH(
      at.dx - width / 2,
      at.dy - height - u(lift),
      width,
      height,
    );
    if (dst.right < 0 || dst.left > w) return;
    // Fade in out of the haze instead of popping up.
    final alpha = (1 - (fog - .7) / .3).clamp(0.0, 1.0);
    if (alpha <= 0) return;
    if (alpha == 1 && prop.kind != Prop.flower) {
      canvas.drawOval(
        Rect.fromCenter(center: at, width: width * .8, height: width * .12),
        Paint()..color = const Color(0x38000000),
      );
    }
    if (lift > 0) {
      canvas.drawRect(
        Rect.fromLTWH(at.dx - u(22), at.dy - u(lift) - 1, u(44), u(lift) + 1),
        Paint()..color = const Color(0xFF7D8494),
      );
    }
    final paint = Paint()
      ..filterQuality = FilterQuality.low
      ..color = Color.fromRGBO(255, 255, 255, alpha);
    final src = Rect.fromLTWH(
      0,
      0,
      img.width.toDouble(),
      img.height.toDouble(),
    );
    // Lamps, flags and arrows on the right lean back over the road.
    final flip =
        prop.offset > 0 &&
        (prop.kind == Prop.lamp ||
            prop.kind == Prop.flag ||
            prop.kind == Prop.chevron);
    if (flip) {
      canvas.save();
      canvas.translate(at.dx * 2, 0);
      canvas.scale(-1, 1);
      canvas.drawImageRect(img, src, dst, paint);
      canvas.restore();
    } else {
      canvas.drawImageRect(img, src, dst, paint);
    }
  }

  void _arch(Canvas canvas, Offset at, double Function(double) u) {
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
