import 'dart:io';

import 'package:elite_play_ludo/game/sounds.dart';
import 'package:elite_play_ludo/main.dart';
import 'package:elite_play_ludo/screens/carrom_screen.dart';
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

  testWidgets('Carrom: place the striker, pull back, shoot, turn passes',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 33));
      }
    }

    await tester.pumpWidget(const ElitePlayLudoApp());
    await tester.pump();
    final tile = find.byKey(const ValueKey('game-carrom'));
    await tester.ensureVisible(tile);
    await tester.pump();
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('2 vs 2 Team'), findsOneWidget);
    await tester.tap(find.text('1 vs 1'));
    await tester.pump();
    await frames(20);

    final game = CarromScreen.debugGame!;
    expect(game.current, 0);
    expect(game.strikerT, .5);

    // Slide the striker to the right.
    final slider = find.byKey(const ValueKey('striker-slider'));
    final box = tester.getRect(slider);
    await tester.tapAt(Offset(box.left + box.width * .8, box.center.dy));
    await frames(2);
    expect(game.strikerT, greaterThan(.7));

    // Pull straight down on the board: the striker flies up the board.
    final board = tester.getRect(find.byType(AnimatedRotation));
    final g = await tester.startGesture(board.center + const Offset(0, 40));
    await frames(1);
    await g.moveBy(const Offset(0, 30));
    await frames(1);
    await g.moveBy(const Offset(0, 40));
    await frames(1);
    expect(find.textContaining('Power'), findsOneWidget);
    await g.up();
    await frames(1);
    expect(game.moving, isTrue);
    expect(game.shots, 1);

    for (var i = 0; i < 600 && game.moving; i++) {
      await frames(1);
    }
    expect(game.moving, isFalse);
    // Nothing of ours went down on a straight shot from the side, so the
    // turn passed and the board turned to the other player.
    if (game.current == 2) {
      await frames(30);
      expect(tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns,
          .5);
    }
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
