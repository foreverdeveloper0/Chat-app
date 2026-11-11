import 'dart:io';

import 'package:elite_play_ludo/game/dice_game.dart';
import 'package:elite_play_ludo/game/sounds.dart';
import 'package:elite_play_ludo/main.dart';
import 'package:elite_play_ludo/screens/snl_screen.dart';
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

  testWidgets('Snake & Ladder opens from its tile and the match advances',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ElitePlayLudoApp());
    await tester.pump();

    final tile = find.byKey(const ValueKey('game-snake'));
    await tester.ensureVisible(tile);
    await tester.pump();
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Snake & Ladder'), findsOneWidget);
    await tester.tap(find.text('Pass & Play'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('2 Players'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Board intro, then the "GAME START" ribbon.
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('GAME START'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump(const Duration(milliseconds: 100));

    final game = SnlScreen.debugController!;
    expect(game.phase, Phase.awaitingRoll);
    expect(game.position.values, everyElement(1));

    // Both seats roll by tapping their dock until someone is well up the board.
    var rolls = 0;
    for (var i = 0; i < 4000 && rolls < 40 && game.phase != Phase.gameOver; i++) {
      if (game.phase == Phase.awaitingRoll) {
        await tester.tap(find.byKey(ValueKey('panel-${game.current}')),
            warnIfMissed: false);
        rolls++;
      }
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(rolls, greaterThan(10));
    expect(game.position.values.any((s) => s > 1), isTrue);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
