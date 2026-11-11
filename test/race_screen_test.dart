import 'dart:io';

import 'package:elite_play_ludo/game/sounds.dart';
import 'package:elite_play_ludo/main.dart';
import 'package:elite_play_ludo/screens/race_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    Sounds.enabled = false;
    final loader = FontLoader('Fredoka');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      final bytes = File('assets/fonts/Fredoka-$w.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });

  testWidgets('Car Racing: countdown, drive, steer and brake', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ElitePlayLudoApp());
    await tester.pump();
    final tile = find.byKey(const ValueKey('game-racing'));
    await tester.ensureVisible(tile);
    await tester.pump();
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('4 Car Race'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final game = RaceScreen.debugGame!;
    expect(game.racers.length, 4);
    expect(game.started, isFalse);
    expect(find.text('GET READY'), findsWidgets);

    // Frames are capped at 1/20 s, so pump in 50 ms steps.
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.started, isTrue);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final p = game.player;
    expect(p.speed, greaterThan(0));

    // Hold right: the car moves right.
    final x0 = p.x;
    final right = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('right'))),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await right.up();
    expect(p.x, greaterThan(x0));

    // Hold the brake: the car slows.
    final v0 = p.speed;
    final brake = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('brake'))),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(p.braking, isTrue);
    await brake.up();
    expect(p.speed, lessThan(v0));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
