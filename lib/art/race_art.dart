import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/race_game.dart';

const carColours = [
  (Color(0xFFFF3B3B), Color(0xFF8E0B0B)), // red
  (Color(0xFF3B7BFF), Color(0xFF0B2E8E)),
  (Color(0xFF35D46A), Color(0xFF0B6E2E)),
  (Color(0xFFFFC233), Color(0xFF9A6A00)),
];

/// One picture inside the sprite sheet, and the point of it that stands on
/// the ground (bottom centre for most things).
class _Sprite {
  const _Sprite(this.src, this.ax, this.ay);
  final Rect src;
  final double ax, ay;
}

/// Every picture the race uses, packed into one sprite sheet so the whole
/// scene goes to the GPU in a single draw call.
abstract final class RaceSprites {
  static const _plain = [
    'tree0', 'tree1', 'tree2', 'tree3', 'tree4', 'tree5', 'tree6', 'tree7', //
    'bush0', 'bush1', 'bush2', 'bush3', 'bush4', 'bush5', 'bush6', 'bush7',
    'flower0', 'flower1', 'flower2', 'flower3', //
    'flower4', 'flower5', 'flower6', 'flower7',
    'rock0', 'rock1', 'rock2', 'rock3', 'fence0', 'fence1', 'rail',
    'warn', 'cone', 'barrel0', 'barrel1', 'barrel2', 'tyres0', 'tyres1',
    'hay', 'barrier0', 'barrier1', 'coin', 'nitro',
  ];

  /// Pictures that also get a mirrored copy, for the right of the road.
  static const _mirrored = [
    'lamp0', 'lamp1', 'flag0', 'flag1', 'flag2', 'flag3', 'chevron', //
  ];

  /// Cars seen from above, squashed to look as if seen from behind.
  static const carSquash = .6;

  static ui.Image? sheet;
  static final _sprites = <String, _Sprite>{};
  static Future<void>? _loading;

  static _Sprite? _of(String name) => _sprites[name];

  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    final images = <String, ui.Image>{};
    Future<void> decode(String name) async {
      try {
        final data = await rootBundle.load('assets/images/race/$name.png');
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        images[name] = (await codec.getNextFrame()).image;
      } catch (_) {
        // A missing picture is simply not drawn.
      }
    }

    await Future.wait([
      for (final n in [..._plain, ..._mirrored]) decode(n),
      for (var i = 0; i < 4; i++) decode('car$i'),
    ]);

    // What goes on the sheet: name, size, and how to draw it there.
    final items = <(String, Size, void Function(Canvas, Rect))>[];
    void paste(String name, ui.Image img, {bool flip = false}) {
      final size = Size(img.width.toDouble(), img.height.toDouble());
      items.add((
        flip ? '$name~' : name,
        size,
        (c, r) {
          final src = Offset.zero & size;
          if (!flip) {
            c.drawImageRect(img, src, r, Paint());
            return;
          }
          c.save();
          c.translate(r.left + r.right, 0);
          c.scale(-1, 1);
          c.drawImageRect(img, src, r, Paint());
          c.restore();
        },
      ));
    }

    for (final n in _plain) {
      if (images[n] case final img?) paste(n, img);
    }
    for (final n in _mirrored) {
      if (images[n] case final img?) {
        paste(n, img);
        paste(n, img, flip: true);
      }
    }
    for (var i = 0; i < 4; i++) {
      final img = images['car$i'];
      if (img == null) continue;
      final size = Size(
        img.width.toDouble(),
        (img.height * carSquash).roundToDouble(),
      );
      items.add((
        'car$i',
        size,
        (c, r) => c.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          r,
          Paint()..filterQuality = FilterQuality.high,
        ),
      ));
    }
    // The warning sign stands on a pole.
    if (images['warn'] case final img?) {
      final w = img.width.toDouble(), h = img.height.toDouble();
      items.add((
        'sign',
        Size(w, h + 90),
        (c, r) {
          c.drawRect(
            Rect.fromLTWH(r.center.dx - 4, r.top + h - 4, 8, 94),
            Paint()..color = const Color(0xFF7D8494),
          );
          c.drawImageRect(
            img,
            Offset.zero & Size(w, h),
            r.topLeft & Size(w, h),
            Paint(),
          );
        },
      ));
    }
    // A soft shadow to sit things on the ground.
    items.add((
      'shadow',
      const Size(128, 40),
      (c, r) => c.drawOval(
        r.deflate(6),
        Paint()
          ..color = const Color(0x66000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      ),
    ));

    // Shelf packing, tallest first, two pixels apart so nothing bleeds.
    items.sort((a, b) => b.$2.height.compareTo(a.$2.height));
    const sheetW = 2048.0, gap = 2.0;
    var x = gap, y = gap, row = 0.0;
    final placed = <(String, Rect, void Function(Canvas, Rect))>[];
    for (final (name, size, draw) in items) {
      if (x + size.width + gap > sheetW) {
        x = gap;
        y += row + gap;
        row = 0;
      }
      placed.add((name, Offset(x, y) & size, draw));
      x += size.width + gap;
      row = math.max(row, size.height);
    }
    final sheetH = (y + row + gap).ceil();
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    for (final (name, rect, draw) in placed) {
      draw(c, rect);
      _sprites[name] = _Sprite(
        rect,
        rect.width / 2,
        name == 'shadow' ? rect.height / 2 : rect.height,
      );
    }
    sheet = await rec.endRecording().toImage(sheetW.toInt(), sheetH);
    for (final img in images.values) {
      img.dispose();
    }
  }
}

/// Which picture a prop uses, how many world units one of its pixels
/// covers, and how far above the ground it floats.
(String, double, double) _look(RoadProp p) => switch (p.kind) {
  Prop.tree => ('tree${p.variant % 8}', 9.5, 0),
  Prop.bush => ('bush${p.variant % 8}', 5, 0),
  Prop.flower => ('flower${p.variant % 8}', 4, 0),
  Prop.rock => ('rock${p.variant % 4}', 5, 0),
  Prop.fence => (const ['fence0', 'fence1', 'rail'][p.variant % 3], 3.3, 0),
  Prop.lamp => ('lamp${p.variant % 2}', 7.5, 0),
  Prop.flag => ('flag${p.variant % 4}', 8, 0),
  Prop.sign => ('sign', 6, 0),
  Prop.chevron => ('chevron', 6, 0),
  Prop.cone => ('cone', 3, 0),
  Prop.barrel => ('barrel${p.variant % 3}', 3.6, 0),
  Prop.tyres => ('tyres${p.variant % 2}', 3, 0),
  Prop.barrier => ('barrier${p.variant % 2}', 3.6, 0),
  Prop.hay => ('hay', 3.3, 0),
  Prop.coin => ('coin', 2.3, 150),
  Prop.nitro => ('nitro', 2.6, 150),
  Prop.arch => ('', 0, 0),
};

/// Smoke, nitro flames, dust and sparks around the player's car. Positions
/// are relative to the car's rear centre, in car widths.
class RaceFx {
  final _ps = <_Particle>[];
  final _rnd = math.Random();
  double _smoke = 0, _dust = 0, _jet = 0;

  void clear() => _ps.clear();

  void update(double dt, RaceGame g, RaceInput input, RaceEvents ev) {
    final p = g.player;
    final pct = (p.speed / RaceGame.maxSpeed).clamp(-1.0, 1.3);
    final moving = pct.abs() > .02;

    // Exhaust: thick while pulling away, a wisp at speed.
    final pulling = input.gas && pct < .7;
    _smoke += dt * (pulling ? 26 : (moving ? 6 : 2));
    while (_smoke >= 1) {
      _smoke -= 1;
      for (final side in const [-1.0, 1.0]) {
        _ps.add(
          _Particle(
            _Kind.smoke,
            side * .2 + (_rnd.nextDouble() - .5) * .04,
            0,
            side * .05 + (_rnd.nextDouble() - .5) * .12,
            .25 + pct.abs() * 1.2 + _rnd.nextDouble() * .2,
            .5 + _rnd.nextDouble() * .4,
            .05 + _rnd.nextDouble() * .03,
          ),
        );
      }
    }
    if (p.boosting) {
      _jet += dt * 70;
      while (_jet >= 1) {
        _jet -= 1;
        final side = _rnd.nextBool() ? -1.0 : 1.0;
        _ps.add(
          _Particle(
            _Kind.jet,
            side * .2,
            0,
            (_rnd.nextDouble() - .5) * .25,
            1.4 + _rnd.nextDouble() * .8,
            .25 + _rnd.nextDouble() * .15,
            .035 + _rnd.nextDouble() * .03,
          ),
        );
      }
    }
    // Grass thrown up by the wheels.
    if (p.x.abs() > 1 && moving) {
      _dust += dt * 40 * pct.abs();
      while (_dust >= 1) {
        _dust -= 1;
        final side = _rnd.nextBool() ? -1.0 : 1.0;
        _ps.add(
          _Particle(
            _Kind.dust,
            side * .4,
            -.05,
            side * (.2 + _rnd.nextDouble() * .5),
            .6 + _rnd.nextDouble() * .8,
            .5 + _rnd.nextDouble() * .3,
            .06 + _rnd.nextDouble() * .05,
          ),
        );
      }
    }
    if (ev.bump || ev.crash) {
      final side = p.x >= 0 ? 1.0 : -1.0;
      for (var i = 0; i < (ev.crash ? 22 : 12); i++) {
        final a = _rnd.nextDouble() * math.pi * 2;
        _ps.add(
          _Particle(
            _Kind.spark,
            (ev.crash ? 0 : side * .45) + (_rnd.nextDouble() - .5) * .3,
            -.3 - _rnd.nextDouble() * .3,
            math.cos(a) * 1.4,
            math.sin(a) * 1.4 - .4,
            .35 + _rnd.nextDouble() * .25,
            .015 + _rnd.nextDouble() * .015,
          ),
        );
      }
    }
    for (final q in _ps) {
      q.x += q.vx * dt;
      q.y += q.vy * dt;
      q.age += dt;
      if (q.kind == _Kind.spark) q.vy += 3 * dt;
    }
    _ps.removeWhere((q) => q.age >= q.life);
    if (_ps.length > 220) _ps.removeRange(0, _ps.length - 220);
  }

  void paint(Canvas canvas, Offset rear, double carW) {
    final paint = Paint();
    for (final q in _ps) {
      final t = q.age / q.life;
      final c = rear + Offset(q.x * carW, q.y * carW);
      switch (q.kind) {
        case _Kind.smoke:
          paint.color = Color.fromRGBO(225, 228, 236, .38 * (1 - t) * (1 - t));
          canvas.drawCircle(c, carW * q.size * (1 + t * 2.5), paint);
        case _Kind.jet:
          paint.color = Color.lerp(
            const Color(0xFFEFFBFF),
            const Color(0x003FA9FF),
            t,
          )!;
          canvas.drawCircle(c, carW * q.size * (1 - t * .5), paint);
        case _Kind.dust:
          paint.color = Color.fromRGBO(150, 120, 70, .6 * (1 - t));
          canvas.drawCircle(c, carW * q.size * (1 + t), paint);
        case _Kind.spark:
          paint.color = Color.fromRGBO(255, 220, 90, 1 - t);
          canvas.drawCircle(c, carW * q.size, paint);
      }
    }
  }
}

enum _Kind { smoke, jet, dust, spark }

class _Particle {
  _Particle(this.kind, this.x, this.y, this.vx, this.vy, this.life, this.size);
  final _Kind kind;
  double x, y, vx, vy, age = 0;
  final double life, size;
}

/// The race seen from above and behind the player's car: sky and hills,
/// the road projected segment by segment, roadside scenery, rival cars
/// and the player's car.
class RaceScenePainter extends CustomPainter {
  RaceScenePainter({
    required this.game,
    required this.skyOffset,
    required this.cameraX,
    required this.time,
    required this.shake,
    required this.fx,
    required this.pixelRatio,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final RaceGame game;
  final double Function() skyOffset;

  /// Where the camera is across the road; it trails the car a touch.
  final double Function() cameraX;
  final double Function() time;
  final double Function() shake;
  final RaceFx fx;
  final double pixelRatio;

  static const _haze = Color(0xFFCFEBF7);

  /// The horizon, and where the road under the player's car meets the
  /// screen, as fractions of the height: the car sits above the controls.
  static const horizon = .3, ground = .8;

  /// A car's width in world units.
  static const _carWidth = 760.0;

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
    final camAt = cameraX();
    final camX = camAt * RaceGame.roadWidth;
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
    _verts = 0;
    for (final v in visible.reversed) {
      _segment(w, v);
    }
    _flushRoad(canvas);

    // Scenery and rival cars, far to near, in one batch.
    final sheet = RaceSprites.sheet;
    if (sheet != null) {
      final cars = <int, List<Racer>>{};
      for (final r in g.racers) {
        if (r.isPlayer) continue;
        cars.putIfAbsent(g.segmentAt(r.z).index, () => []).add(r);
      }
      _count = 0;
      for (final v in visible.reversed) {
        final here = cars[v.seg.index];
        if (v.seg.props.isEmpty && here == null) continue;
        final unit = v.p1.$4 * w / 2;
        final alpha = (1 - (v.fog - .7) / .3).clamp(0.0, 1.0);
        if (alpha <= 0) continue;
        for (final (k, prop) in v.seg.props.indexed) {
          if (prop.kind == Prop.arch || g.taken(v.seg, k)) continue;
          var (name, perPixel, lift) = _look(prop);
          final mirror =
              prop.offset > 0 &&
              (prop.kind == Prop.lamp ||
                  prop.kind == Prop.flag ||
                  prop.kind == Prop.chevron);
          if (mirror) name = '$name~';
          final sprite = RaceSprites._of(name);
          if (sprite == null) continue;
          final scale = unit * perPixel;
          final full = sprite.src.width * scale;
          // Tiny far-off things are not worth drawing.
          if (full < (prop.kind == Prop.tree ? 3 : 5)) continue;
          final sx = v.p1.$1 + unit * prop.offset * RaceGame.roadWidth;
          if (sx + full < 0 || sx - full > w) continue;
          var sy = v.p1.$2;
          if (prop.pickup) {
            sy -= unit * lift * (1 + .25 * math.sin(t * 5 + v.seg.index));
          }
          if (full > 24 && !prop.pickup && prop.kind != Prop.flower) {
            final shadow = RaceSprites._of('shadow')!;
            _add(
              shadow,
              full * .8 / shadow.src.width,
              0,
              sx,
              sy,
              alpha,
              v.clip,
            );
          }
          _add(sprite, scale, 0, sx, sy, alpha, v.clip);
        }
        for (final r in here ?? const <Racer>[]) {
          final sprite = RaceSprites._of('car${r.colour % 4}');
          if (sprite == null) continue;
          final pct = (r.z % RaceGame.segLen) / RaceGame.segLen;
          final sc = v.p1.$4 + (v.p2.$4 - v.p1.$4) * pct;
          final sx =
              v.p1.$1 +
              (v.p2.$1 - v.p1.$1) * pct +
              sc * r.x * RaceGame.roadWidth * w / 2;
          final sy = v.p1.$2 + (v.p2.$2 - v.p1.$2) * pct;
          final width = _carWidth * sc * w / 2;
          final shadow = RaceSprites._of('shadow')!;
          _add(
            shadow,
            width * 1.05 / shadow.src.width,
            0,
            sx,
            sy,
            alpha,
            v.clip,
          );
          _add(
            sprite,
            width / sprite.src.width,
            r.steer * .1,
            sx,
            sy,
            alpha,
            v.clip,
          );
        }
      }
      _flushSprites(canvas, sheet);
    }
    _arch(canvas, w, visible);

    // The player's car.
    final pct = p.speed / RaceGame.maxSpeed;
    final off = p.x.abs() > 1;
    final bob = math.sin(t * 40) * (off ? 3 : .8) * pct.abs();
    final carW = _carWidth / RaceGame.cameraHeight * w / 2;
    final at = Offset(
      w / 2 +
          (p.x - camAt) * RaceGame.roadWidth / RaceGame.cameraHeight * w / 2,
      h * ground + bob,
    );
    _playerCar(canvas, sheet, at, carW, t);
    fx.paint(canvas, at, carW);

    if (p.boosting) _speedLines(canvas, size, t);
    canvas.restore();
  }

  void _playerCar(
    Canvas canvas,
    ui.Image? sheet,
    Offset at,
    double width,
    double t,
  ) {
    final p = game.player;
    final sprite = RaceSprites._of('car${p.colour % 4}');
    if (sheet == null || sprite == null) return;
    final height = width * sprite.src.height / sprite.src.width;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, -height * .06),
        width: width * 1.12,
        height: height * .3,
      ),
      Paint()..color = const Color(0x55000000),
    );
    // Turn about the middle of the car.
    canvas.translate(0, -height / 2);
    canvas.rotate(p.steer * .1);
    canvas.translate(0, height / 2);
    if (p.boosting) {
      // Nitro: flickering jets from both pipes.
      for (final side in [-1.0, 1.0]) {
        final e = Offset(side * width * .2, -height * .02);
        final len = height * (.42 + .12 * math.sin(t * 55 + side * 2));
        canvas.drawPath(
          Path()
            ..moveTo(e.dx - width * .08, e.dy)
            ..quadraticBezierTo(
              e.dx,
              e.dy + len * 1.5,
              e.dx + width * .08,
              e.dy,
            )
            ..close(),
          Paint()..color = const Color(0xAA3FA9FF),
        );
        canvas.drawPath(
          Path()
            ..moveTo(e.dx - width * .04, e.dy)
            ..quadraticBezierTo(e.dx, e.dy + len, e.dx + width * .04, e.dy)
            ..close(),
          Paint()..color = const Color(0xFFEFFBFF),
        );
      }
    }
    canvas.drawImageRect(
      sheet,
      sprite.src,
      Rect.fromLTWH(-width / 2, -height, width, height),
      Paint()..filterQuality = FilterQuality.medium,
    );
    // Tail lights: dim when cruising, bright when braking.
    final glow = p.braking ? 1.0 : .25;
    for (final side in [-1.0, 1.0]) {
      final c = Offset(side * width * .3, -height * .07);
      canvas.drawOval(
        Rect.fromCenter(center: c, width: width * .34, height: height * .2),
        Paint()..color = Color.fromRGBO(255, 40, 40, .35 * glow),
      );
      canvas.drawOval(
        Rect.fromCenter(center: c, width: width * .17, height: height * .07),
        Paint()..color = Color.fromRGBO(255, 215, 215, glow),
      );
    }
    canvas.restore();
  }

  // ── Sprite batch ──

  static const _maxSprites = 3000;
  static final _rst = Float32List(_maxSprites * 4);
  static final _rects = Float32List(_maxSprites * 4);
  static final _colors = Int32List(_maxSprites);
  int _count = 0;

  /// Queue [sprite] standing at (x, y), cut off below [clipY] where a
  /// nearer hill hides it.
  void _add(
    _Sprite sprite,
    double scale,
    double rotation,
    double x,
    double y,
    double alpha,
    double clipY,
  ) {
    if (_count >= _maxSprites || scale <= 0) return;
    final src = sprite.src;
    final top = y - sprite.ay * scale;
    if (top >= clipY) return;
    var srcH = src.height;
    if (top + srcH * scale > clipY) srcH = (clipY - top) / scale;
    final scos = scale * math.cos(rotation), ssin = scale * math.sin(rotation);
    final i = _count * 4;
    _rst[i] = scos;
    _rst[i + 1] = ssin;
    _rst[i + 2] = x - scos * sprite.ax + ssin * sprite.ay;
    _rst[i + 3] = y - ssin * sprite.ax - scos * sprite.ay;
    _rects[i] = src.left;
    _rects[i + 1] = src.top;
    _rects[i + 2] = src.right;
    _rects[i + 3] = src.top + srcH;
    final a = (alpha * 255).round();
    _colors[_count] = (a << 24) | (a << 16) | (a << 8) | a;
    _count++;
  }

  void _flushSprites(Canvas canvas, ui.Image sheet) {
    if (_count == 0) return;
    canvas.drawRawAtlas(
      sheet,
      Float32List.sublistView(_rst, 0, _count * 4),
      Float32List.sublistView(_rects, 0, _count * 4),
      Int32List.sublistView(_colors, 0, _count),
      BlendMode.modulate,
      null,
      Paint()..filterQuality = FilterQuality.low,
    );
    _count = 0;
  }

  // ── Road batch ──

  // The whole road goes to the GPU as one batch of coloured triangles.
  static const _maxVerts = 24000;
  static final _xy = Float32List(_maxVerts * 2);
  static final _rgba = Int32List(_maxVerts);
  int _verts = 0;

  void _quad(
    double ax,
    double bx,
    double ay,
    double cx,
    double dx,
    double cy,
    int colour,
  ) {
    if (_verts + 6 > _maxVerts) return;
    var i = _verts * 2;
    void v(double x, double y) {
      _xy[i++] = x;
      _xy[i++] = y;
    }

    v(ax, ay);
    v(bx, ay);
    v(dx, cy);
    v(ax, ay);
    v(dx, cy);
    v(cx, cy);
    _rgba.fillRange(_verts, _verts + 6, colour);
    _verts += 6;
  }

  void _flushRoad(Canvas canvas) {
    if (_verts == 0) return;
    canvas.drawVertices(
      ui.Vertices.raw(
        ui.VertexMode.triangles,
        Float32List.sublistView(_xy, 0, _verts * 2),
        colors: Int32List.sublistView(_rgba, 0, _verts),
      ),
      BlendMode.dst,
      Paint()..isAntiAlias = false,
    );
    _verts = 0;
  }

  Color _hazed(Color c, double f) =>
      Color.lerp(c, _haze, (f * f * .55).clamp(0.0, .55))!;

  void _segment(double w, _Proj v) {
    final (x1, y1, w1, _) = v.p1;
    final (x2, y2, w2, _) = v.p2;
    final band = v.seg.index ~/ RaceGame.rumbleLen;
    final dark = band.isEven;
    final f = v.fog;
    final near = y1 + 1; // overlap a pixel so no seams show
    int ink(Color c) => _hazed(c, f).toARGB32();
    _quad(
      0,
      w,
      near,
      0,
      w,
      y2,
      ink(dark ? const Color(0xFF6CC72F) : const Color(0xFF61BA29)),
    );
    // A strip between two fractions of the road's half-width.
    void strip(double a, double b, Color c) => _quad(
      x1 + w1 * a,
      x1 + w1 * b,
      near,
      x2 + w2 * a,
      x2 + w2 * b,
      y2,
      ink(c),
    );

    // Kerbs: a dark outer lip, then chunky red and white blocks.
    strip(-1.2, 1.2, dark ? const Color(0xFF4E9A22) : const Color(0xFF468D1E));
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

  // ── Background ──

  static ui.Image? _sky;
  static Size? _skySize;

  /// Sky, clouds, hills and a far tree line, drawn once into a picture
  /// twice the screen's width that wraps round as the road bends.
  ui.Image _skyImage(double w, double hz) {
    final size = Size(w, hz);
    if (_sky != null && _skySize == size) return _sky!;
    _sky?.dispose();
    final k = pixelRatio.clamp(1.0, 2.0);
    final W = w * 2;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec)..scale(k);
    final sky = Rect.fromLTWH(0, 0, W, hz);
    c.drawRect(
      sky,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E7BE6), Color(0xFF58B4F5), Color(0xFFC9ECFB)],
          stops: [0, .6, 1],
        ).createShader(sky),
    );
    final cloud = Paint()..color = Colors.white;
    final shade = Paint()..color = const Color(0xFFDDEEFA);
    const clouds = [
      (.06, .22, 1.0), (.27, .08, .7), (.42, .3, 1.15), //
      (.62, .14, .85), (.83, .26, 1.0),
    ];
    for (final (cx, cy, sc) in clouds) {
      final bx = cx * W, by = hz * (cy + .2), r = w * .05 * sc;
      for (final (dx, dy, kk) in const [
        (-1.5, .3, .8), (-.6, -.2, 1.1), (.4, -.45, 1.25), //
        (1.3, 0.0, 1.0), (2.1, .35, .7),
      ]) {
        c.drawCircle(Offset(bx + dx * r, by + dy * r + r * .25), r * kk, shade);
        c.drawCircle(Offset(bx + dx * r, by + dy * r), r * kk, cloud);
      }
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(bx - 2.2 * r, by + r * .2, bx + 2.8 * r, by + r * 1.1),
          Radius.circular(r),
        ),
        cloud,
      );
    }
    // Hills that repeat exactly every W, so the picture wraps seamlessly.
    void ridge(double amp, int waves, Color top, Color bottom, int seed) {
      final path = Path()..moveTo(0, hz);
      for (var x = 0.0; x <= W; x += 6) {
        final u = x / W * math.pi * 2;
        final y =
            hz -
            amp *
                (.55 +
                    .3 * math.sin(u * waves + seed) +
                    .15 * math.sin(u * waves * 3 + seed * 2));
        path.lineTo(x, y);
      }
      path
        ..lineTo(W, hz)
        ..close();
      c.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, bottom],
          ).createShader(Rect.fromLTRB(0, hz - amp * 1.1, W, hz)),
      );
    }

    ridge(hz * .5, 3, const Color(0xFF5FA6C9), const Color(0xFF8FCFD9), 1);
    ridge(hz * .3, 7, const Color(0xFF3F9A4E), const Color(0xFF7CC85A), 3);
    final trees = Paint()..color = const Color(0xFF2F8A3A);
    final rnd = math.Random(7);
    for (var x = 0.0; x < W; x += 9 + rnd.nextDouble() * 10) {
      final r = hz * (.025 + rnd.nextDouble() * .03);
      c.drawCircle(Offset(x, hz - r * .4), r, trees);
    }
    _sky = rec.endRecording().toImageSync((W * k).ceil(), (hz * k).ceil());
    _skySize = size;
    return _sky!;
  }

  void _background(Canvas canvas, Size size, double off) {
    final w = size.width, h = size.height;
    final hz = h * horizon;
    final img = _skyImage(w, hz);
    final W = w * 2;
    final shift = ((off * w * .12) % W + W) % W;
    final src = Rect.fromLTWH(
      0,
      0,
      img.width.toDouble(),
      img.height.toDouble(),
    );
    final paint = Paint()..filterQuality = FilterQuality.low;
    for (final start in [-shift, W - shift]) {
      if (start >= w || start + W <= 0) continue;
      canvas.drawImageRect(img, src, Rect.fromLTWH(start, 0, W, hz + 1), paint);
    }
    canvas.drawRect(
      Rect.fromLTWH(0, hz, w, h - hz),
      Paint()..color = Color.lerp(const Color(0xFF66C22E), _haze, .35)!,
    );
  }

  /// The start and finish gate, drawn over the scenery.
  void _arch(Canvas canvas, double w, List<_Proj> visible) {
    for (final v in visible) {
      if (v.seg.index != 2) continue;
      final unit = v.p1.$4 * w / 2;
      double u(double world) => world * unit;
      final at = Offset(v.p1.$1, v.p1.$2);
      if (at.dy > v.clip + .5) return;
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, 0, w, v.clip));
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
      canvas.restore();
      return;
    }
  }

  void _speedLines(Canvas canvas, Size size, double t) {
    final c = Offset(size.width / 2, size.height * .45);
    final rnd = math.Random((t * 30).floor());
    final p = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 2;
    for (var i = 0; i < 22; i++) {
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
