import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/snake_game.dart';
import '../theme/app_colors.dart';

/// Fraction of the board edge taken by the gold rim on each side.
const snakeRim = .026;

const fruitColors = [
  Color(0xFFE8232D), // apple
  Color(0xFFFF9A1F), // orange
  Color(0xFF8B4DF0), // plum
  Color(0xFFFF4D6A), // watermelon
];
const bonusColor = Color(0xFFFFD23A);

// ───────────────────────── Field ─────────────────────────

/// The arena: a gold rim around a deep checkered field. Walls show as a
/// solid inner edge; an open arena shows glowing portal dashes instead.
class SnakeFieldPainter extends CustomPainter {
  const SnakeFieldPainter({
    required this.cols,
    required this.rows,
    required this.wrap,
  });
  final int cols, rows;
  final bool wrap;

  @override
  void paint(Canvas canvas, Size size) {
    final b = size.width;
    final outer = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(b * .04));
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
    // Fine line that gives the rim a bevel.
    canvas.drawRRect(
      outer.deflate(b * .008),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = b * .003
        ..color = const Color(0x99FFFFFF),
    );

    final rim = b * snakeRim;
    final field = Rect.fromLTWH(rim, rim, b - rim * 2, size.height - rim * 2);
    final inner = RRect.fromRectAndRadius(field, Radius.circular(b * .02));
    final cell = field.width / cols;

    canvas.save();
    canvas.clipRRect(inner);
    canvas.drawRect(field, Paint()..color = const Color(0xFF141A52));
    final light = Paint()..color = const Color(0xFF1C2468);
    for (var y = 0; y < rows; y++) {
      for (var x = (y.isEven ? 0 : 1); x < cols; x += 2) {
        canvas.drawRect(
          Rect.fromLTWH(field.left + x * cell, field.top + y * cell, cell, cell),
          light,
        );
      }
    }
    // Soft light in the middle, shade towards the edges.
    canvas.drawRect(
      field,
      Paint()
        ..shader = const RadialGradient(
          radius: .78,
          colors: [Color(0x224F6BFF), Color(0x00000000), Color(0x73050718)],
          stops: [0, .6, 1],
        ).createShader(field),
    );

    if (wrap) {
      // Portal edges: a cyan glow with bright dashes.
      canvas.drawRRect(
        inner.deflate(cell * .06),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * .34
          ..color = const Color(0x5540E0FF)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * .22),
      );
      final dash = Paint()
        ..color = const Color(0xFF7DEBFF)
        ..strokeWidth = cell * .1
        ..strokeCap = StrokeCap.round;
      final e = cell * .1;
      for (var i = 0; i < cols; i++) {
        final x = field.left + (i + .3) * cell;
        canvas.drawLine(Offset(x, field.top + e), Offset(x + cell * .4, field.top + e), dash);
        canvas.drawLine(Offset(x, field.bottom - e), Offset(x + cell * .4, field.bottom - e), dash);
      }
      for (var i = 0; i < rows; i++) {
        final y = field.top + (i + .3) * cell;
        canvas.drawLine(Offset(field.left + e, y), Offset(field.left + e, y + cell * .4), dash);
        canvas.drawLine(Offset(field.right - e, y), Offset(field.right - e, y + cell * .4), dash);
      }
    } else {
      // Solid wall: a dark inner edge.
      canvas.drawRRect(
        inner,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * .32
          ..color = const Color(0xCC070A26),
      );
      canvas.drawRRect(
        inner.deflate(cell * .16),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * .05
          ..color = const Color(0x66FF6A5E),
      );
    }
    canvas.restore();

    canvas.drawRRect(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = b * .006
        ..color = const Color(0xFF6B4708),
    );
  }

  @override
  bool shouldRepaint(SnakeFieldPainter old) =>
      old.cols != cols || old.rows != rows || old.wrap != wrap;
}

// ───────────────────────── Fruit ─────────────────────────

void _sphere(Canvas canvas, Offset c, double r, List<Color> colors) {
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-.35, -.4),
        radius: 1.05,
        colors: colors,
        stops: const [0, .55, 1],
      ).createShader(Rect.fromCircle(center: c, radius: r)),
  );
}

void _leaf(Canvas canvas, Offset from, double r) {
  final leaf = Path()
    ..moveTo(from.dx, from.dy)
    ..quadraticBezierTo(from.dx + r * .2, from.dy - r * .55, from.dx + r * .75, from.dy - r * .42)
    ..quadraticBezierTo(from.dx + r * .5, from.dy + r * .05, from.dx, from.dy)
    ..close();
  canvas.drawPath(
    leaf,
    Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF9BE86A), Color(0xFF2E9E45)],
      ).createShader(leaf.getBounds()),
  );
}

void _stem(Canvas canvas, Offset c, double r) {
  canvas.drawLine(
    c + Offset(0, -r * .78),
    c + Offset(r * .1, -r * 1.2),
    Paint()
      ..color = const Color(0xFF6B3F1D)
      ..strokeWidth = r * .16
      ..strokeCap = StrokeCap.round,
  );
}

void _gloss(Canvas canvas, Offset c, double r) {
  canvas.save();
  canvas.translate(c.dx - r * .38, c.dy - r * .42);
  canvas.rotate(-.6);
  canvas.drawOval(
    Rect.fromCenter(center: Offset.zero, width: r * .5, height: r * .28),
    Paint()..color = const Color(0xAAFFFFFF),
  );
  canvas.restore();
}

/// A glossy fruit of the given [kind] centred on [c].
void paintFruit(Canvas canvas, Offset c, double r, int kind) {
  canvas.drawOval(
    Rect.fromCenter(
        center: c + Offset(r * .08, r * .92), width: r * 1.7, height: r * .42),
    Paint()..color = const Color(0x59000000),
  );
  switch (kind % SnakeGame.fruitKinds) {
    case 0: // apple
      _sphere(canvas, c, r,
          const [Color(0xFFFF9C8C), Color(0xFFE8232D), Color(0xFF8E0B14)]);
      canvas.drawOval(
        Rect.fromCenter(
            center: c + Offset(0, -r * .74), width: r * .6, height: r * .22),
        Paint()..color = const Color(0x55500007),
      );
      _stem(canvas, c, r);
      _leaf(canvas, c + Offset(r * .08, -r * 1.02), r);
    case 1: // orange
      _sphere(canvas, c, r,
          const [Color(0xFFFFE08A), Color(0xFFFF9A1F), Color(0xFFC45F00)]);
      final dot = Paint()..color = const Color(0x22703400);
      for (final o in const [
        Offset(.3, .2),
        Offset(-.1, .45),
        Offset(.45, -.15),
        Offset(-.4, .1),
        Offset(.1, -.05),
      ]) {
        canvas.drawCircle(c + o * r, r * .05, dot);
      }
      _leaf(canvas, c + Offset(-r * .05, -r * .86), r * .8);
    case 2: // plum
      _sphere(canvas, c, r,
          const [Color(0xFFD9B8FF), Color(0xFF8B4DF0), Color(0xFF3B137F)]);
      _stem(canvas, c, r);
      _leaf(canvas, c + Offset(r * .08, -r * 1.02), r * .85);
    default: // watermelon slice
      canvas.save();
      canvas.translate(c.dx, c.dy - r * .25);
      canvas.rotate(-.25);
      Path wedge(double rad) => Path()
        ..moveTo(-rad, 0)
        ..arcToPoint(Offset(rad, 0),
            radius: Radius.circular(rad), clockwise: false)
        ..close();
      canvas.drawPath(wedge(r * 1.12), Paint()..color = const Color(0xFF1E8E3E));
      canvas.drawPath(wedge(r * .98), Paint()..color = const Color(0xFFD8F7B8));
      canvas.drawPath(
        wedge(r * .88),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFF6A7A), Color(0xFFD61F3A)],
          ).createShader(Rect.fromLTWH(-r, 0, r * 2, r)),
      );
      final seed = Paint()..color = const Color(0xFF2A1210);
      for (final o in const [
        Offset(-.45, .22),
        Offset(0, .2),
        Offset(.45, .22),
        Offset(-.22, .5),
        Offset(.22, .5),
      ]) {
        canvas.drawOval(
          Rect.fromCenter(center: o * r, width: r * .1, height: r * .16),
          seed,
        );
      }
      canvas.restore();
      return;
  }
  _gloss(canvas, c, r);
}

Path _star(Offset c, double r) {
  final p = Path();
  for (var i = 0; i < 10; i++) {
    final rr = i.isEven ? r : r * .46;
    final a = -math.pi / 2 + i * math.pi / 5;
    final o = c + Offset(math.cos(a), math.sin(a)) * rr;
    i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
  }
  return p..close();
}

/// The timed bonus: a glowing gold star coin with a ring that runs down.
void paintBonus(Canvas canvas, Offset c, double r, double life, double time) {
  canvas.drawCircle(
    c,
    r * 1.7,
    Paint()
      ..color = bonusColor.withValues(alpha: .28 + .12 * math.sin(time * 6))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .7),
  );
  canvas.drawArc(
    Rect.fromCircle(center: c, radius: r * 1.32),
    -math.pi / 2,
    2 * math.pi * life.clamp(0, 1),
    false,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * .18
      ..strokeCap = StrokeCap.round
      ..color = life < .3 ? const Color(0xFFFF6A5E) : const Color(0xFFFFF3B8),
  );
  _sphere(canvas, c, r,
      const [Color(0xFFFFF3B8), Color(0xFFF8C22D), Color(0xFFB8760A)]);
  canvas.drawCircle(
    c,
    r * .78,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * .08
      ..color = const Color(0x77FFFFFF),
  );
  canvas.save();
  canvas.translate(c.dx, c.dy);
  canvas.rotate(math.sin(time * 3) * .25);
  canvas.drawPath(_star(Offset.zero, r * .58),
      Paint()..color = const Color(0xFFFFFBE0));
  canvas.restore();
}

// ───────────────────────── Snake ─────────────────────────

/// The snake's spine from tail to head in cell units, eased [t] of the way
/// through the current step. In an open arena the line is "unwrapped": it
/// runs on past the edges, and the painter repeats it on the other side.
List<Offset> snakeSpine(SnakeGame g, double t) {
  final cells = [if (g.droppedTail != null) g.droppedTail!, ...g.body.reversed];
  final pts = <Offset>[Offset(cells[0].x + .5, cells[0].y + .5)];
  for (var i = 1; i < cells.length; i++) {
    var dx = (cells[i].x - cells[i - 1].x).toDouble();
    var dy = (cells[i].y - cells[i - 1].y).toDouble();
    if (dx.abs() > 1) dx = -dx.sign; // stepped across an edge
    if (dy.abs() > 1) dy = -dy.sign;
    pts.add(pts.last + Offset(dx, dy));
  }
  if (pts.length >= 2) {
    final last = pts.length - 1;
    pts[last] = Offset.lerp(pts[last - 1], pts[last], t)!;
    if (g.droppedTail != null) pts[0] = Offset.lerp(pts[0], pts[1], t)!;
  }
  return pts;
}

void _paintSnake(
  Canvas canvas,
  List<Offset> spine,
  double cell, {
  required double time,
  required bool dead,
  required bool hungry,
  required Rect field,
}) {
  final path = Path()..moveTo(spine.first.dx, spine.first.dy);
  for (final p in spine.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  Paint stroke(double width, Color color) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = cell * width
    ..color = color;

  // Shadow, dark outline, body, then a soft highlight for a tube look.
  canvas.drawPath(path.shift(Offset(cell * .06, cell * .14)),
      stroke(.8, const Color(0x55000010)));
  canvas.drawPath(
      path, stroke(.86, dead ? const Color(0xFF5A1A1A) : const Color(0xFF0B5A2A)));
  canvas.drawPath(
    path,
    stroke(.72, Colors.white)
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dead
            ? const [Color(0xFFB7C0B9), Color(0xFF7D8A80)]
            : const [Color(0xFF7BF29A), Color(0xFF2FCB62), Color(0xFF159A45)],
      ).createShader(field),
  );

  // Scales: darker dots that travel with the body.
  final spot = Paint()
    ..color = dead ? const Color(0x55404A44) : const Color(0x70108A3C);
  for (final metric in path.computeMetrics()) {
    var i = 0;
    for (var d = metric.length - cell * .95; d > cell * .25; d -= cell * .5) {
      final at = metric.getTangentForOffset(d);
      if (at == null) continue;
      final side = Offset(-at.vector.dy, at.vector.dx) * (i.isEven ? 1 : -1);
      canvas.drawCircle(at.position + side * cell * .15, cell * .1, spot);
      i++;
    }
  }
  canvas.drawPath(path.shift(Offset(-cell * .07, -cell * .1)),
      stroke(.2, const Color(0x55FFFFFF)));

  // Head, turned to face the way it is moving.
  var heading = const Offset(1, 0);
  for (var i = spine.length - 1; i > 0; i--) {
    final v = spine[i] - spine[i - 1];
    if (v.distance > 1e-3) {
      heading = v / v.distance;
      break;
    }
  }
  canvas.save();
  canvas.translate(spine.last.dx, spine.last.dy);
  canvas.rotate(math.atan2(heading.dy, heading.dx));

  final flick = !dead && (hungry || math.sin(time * 7) > .55);
  if (flick) {
    final tongue = Paint()
      ..color = const Color(0xFFFF3B5C)
      ..strokeWidth = cell * .09
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      Path()
        ..moveTo(cell * .42, 0)
        ..lineTo(cell * .72, 0)
        ..lineTo(cell * .88, -cell * .11)
        ..moveTo(cell * .72, 0)
        ..lineTo(cell * .88, cell * .11),
      tongue,
    );
  }
  final skull = Rect.fromCenter(
      center: Offset(cell * .06, 0), width: cell * 1.08, height: cell * .98);
  canvas.drawOval(skull.inflate(cell * .05),
      Paint()..color = dead ? const Color(0xFF5A1A1A) : const Color(0xFF0B5A2A));
  canvas.drawOval(
    skull,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-.2, -.45),
        radius: 1,
        colors: dead
            ? const [Color(0xFFC6CFC8), Color(0xFF7D8A80)]
            : const [Color(0xFF9CF7B4), Color(0xFF2FCB62), Color(0xFF128C3C)],
      ).createShader(skull),
  );
  if (hungry && !dead) {
    // Mouth open for the bite.
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cell * .12, 0), radius: cell * .44),
      -.5,
      1,
      true,
      Paint()..color = const Color(0xFF7A0613),
    );
  }
  for (final side in const [-1.0, 1.0]) {
    final eye = Offset(cell * .1, side * cell * .25);
    canvas.drawCircle(eye, cell * .21, Paint()..color = const Color(0xFF0B5A2A));
    canvas.drawCircle(eye, cell * .18, Paint()..color = Colors.white);
    if (dead) {
      final x = Paint()
        ..color = const Color(0xFF2A1210)
        ..strokeWidth = cell * .07
        ..strokeCap = StrokeCap.round;
      final k = cell * .09;
      canvas.drawLine(eye + Offset(-k, -k), eye + Offset(k, k), x);
      canvas.drawLine(eye + Offset(-k, k), eye + Offset(k, -k), x);
    } else {
      canvas.drawCircle(eye + Offset(cell * .06, 0), cell * .1,
          Paint()..color = const Color(0xFF14181F));
      canvas.drawCircle(eye + Offset(cell * .02, -cell * .04), cell * .035,
          Paint()..color = Colors.white);
    }
    canvas.drawCircle(Offset(cell * .46, side * cell * .1), cell * .03,
        Paint()..color = const Color(0xFF0B5A2A));
  }
  canvas.restore();
}

// ───────────────────────── Scene ─────────────────────────

class _Spark {
  _Spark(this.origin, this.velocity, this.color, this.born, this.size);
  final Offset origin, velocity;
  final Color color;
  final double born, size;
}

class _Popup {
  _Popup(this.at, this.text, this.color, this.born);
  final Offset at;
  final String text;
  final Color color;
  final double born;
}

/// Everything about how the board looks right now that is not game state:
/// the clock, how far through the current step we are, and the effects.
class SnakeView extends ChangeNotifier {
  /// Seconds since the board appeared; drives idle animation.
  double time = 0;

  /// 0..1 through the current step (1 = snake drawn exactly on its cells).
  double t = 1;

  /// 0..1 bump of the head into whatever killed it.
  double lunge = 0;

  /// 0..1 red flash over the field after a crash.
  double flash = 0;

  /// When the fruit and the bonus appeared, for their pop-in.
  double foodBorn = 0;
  double bonusBorn = 0;

  /// A fruit already eaten in the rules but not yet reached on screen.
  ({Cell at, int kind, bool bonus})? ghost;

  final _sparks = <_Spark>[];
  final _popups = <_Popup>[];
  final _rng = math.Random();

  void reset() {
    t = 1;
    lunge = 0;
    flash = 0;
    foodBorn = time;
    ghost = null;
    _sparks.clear();
    _popups.clear();
  }

  /// A burst of sparks and a floating score where a fruit was eaten.
  void burst(Cell at, Color color, String text) {
    final c = Offset(at.x + .5, at.y + .5);
    for (var i = 0; i < 12; i++) {
      final a = _rng.nextDouble() * 2 * math.pi;
      _sparks.add(_Spark(
        c,
        Offset(math.cos(a), math.sin(a)) * (2 + _rng.nextDouble() * 3.5),
        Color.lerp(color, Colors.white, _rng.nextDouble() * .5)!,
        time,
        .1 + _rng.nextDouble() * .1,
      ));
    }
    _popups.add(_Popup(c, text, color, time));
  }

  /// Advances the clock, drops finished effects and repaints.
  void tick(double dt) {
    time += dt;
    _sparks.removeWhere((s) => time - s.born > .5);
    _popups.removeWhere((p) => time - p.born > .8);
    notifyListeners();
  }
}

/// Paints the fruit, the snake and the effects over a [SnakeFieldPainter].
class SnakeScenePainter extends CustomPainter {
  SnakeScenePainter(this.game, this.view) : super(repaint: view);
  final SnakeGame game;
  final SnakeView view;

  @override
  void paint(Canvas canvas, Size size) {
    final rim = size.width * snakeRim;
    final field = Rect.fromLTWH(
        rim, rim, size.width - rim * 2, size.height - rim * 2);
    final cell = field.width / game.cols;
    Offset centre(Cell c) =>
        field.topLeft + Offset((c.x + .5) * cell, (c.y + .5) * cell);
    double pop(double born) =>
        Curves.easeOutBack.transform(((view.time - born) / .28).clamp(0, 1));

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
        field, Radius.circular(size.width * .02)));

    final beat = 1 + .06 * math.sin(view.time * 5);
    if (!game.won) {
      final s = pop(view.foodBorn);
      if (s > 0 && game.inside(game.food)) {
        paintFruit(canvas, centre(game.food), cell * .36 * s * beat, game.foodKind);
      }
    }
    if (game.bonus != null) {
      paintBonus(canvas, centre(game.bonus!), cell * .34 * pop(view.bonusBorn),
          game.bonusSteps / SnakeGame.bonusLife, view.time);
    }
    final ghost = view.ghost;
    if (ghost != null) {
      ghost.bonus
          ? paintBonus(canvas, centre(ghost.at), cell * .34, 1, view.time)
          : paintFruit(canvas, centre(ghost.at), cell * .36, ghost.kind);
    }

    // The snake, repeated across the edges it is passing through.
    final spine = snakeSpine(game, view.t);
    if (view.lunge > 0) {
      spine[spine.length - 1] += Offset(
          game.dir.dx.toDouble(), game.dir.dy.toDouble()) * view.lunge * .3;
    }
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final p in spine) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    final px = [for (final p in spine) field.topLeft + p * cell];
    // Is the fruit right in front of the head?
    final ahead = game.neighbour(game.head, game.dir);
    final hungry = game.alive &&
        (ahead == game.food || ahead == game.bonus || ghost != null);
    for (var ky = (minY / game.rows).floor(); ky <= (maxY / game.rows).floor(); ky++) {
      for (var kx = (minX / game.cols).floor(); kx <= (maxX / game.cols).floor(); kx++) {
        canvas.save();
        canvas.translate(-kx * game.cols * cell, -ky * game.rows * cell);
        _paintSnake(canvas, px, cell,
            time: view.time, dead: !game.alive, hungry: hungry, field: field);
        canvas.restore();
      }
    }

    // Sparks.
    for (final s in view._sparks) {
      final age = (view.time - s.born) / .5;
      final at = s.origin + s.velocity * (age * (1 - age * .5)) * .5;
      canvas.drawCircle(
        field.topLeft + at * cell,
        cell * s.size * (1 - age * .6),
        Paint()..color = s.color.withValues(alpha: (1 - age).clamp(0, 1)),
      );
    }
    if (view.flash > 0) {
      canvas.drawRect(
          field, Paint()..color = Color.fromRGBO(255, 40, 40, view.flash * .38));
    }
    canvas.restore();

    // Floating scores, above the clip so they can rise past the rim.
    for (final p in view._popups) {
      final age = (view.time - p.born) / .8;
      final painter = TextPainter(
        text: TextSpan(
          text: p.text,
          style: TextStyle(
            fontFamily: AppText.family,
            fontWeight: FontWeight.w700,
            fontSize: cell * .78,
            color: Color.lerp(p.color, Colors.white, .55)!
                .withValues(alpha: (1 - age * age).clamp(0, 1)),
            shadows: const [Shadow(color: Color(0xCC000010), blurRadius: 4)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final at = field.topLeft +
          Offset(p.at.dx, p.at.dy - .6 - age * 1.1) * cell;
      painter.paint(canvas, at - Offset(painter.width / 2, painter.height / 2));
    }
  }

  @override
  bool shouldRepaint(SnakeScenePainter old) => old.game != game;
}
