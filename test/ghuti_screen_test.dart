import 'dart:io';

import 'package:elite_play_ludo/game/ghuti_game.dart';
import 'package:elite_play_ludo/game/sounds.dart';
import 'package:elite_play_ludo/main.dart';
import 'package:elite_play_ludo/screens/ghuti_screen.dart';
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

  testWidgets('16 Ghuti: tap a piece, tap a point, the computer replies',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ElitePlayLudoApp());
    await tester.pump();
    final tile = find.byKey(const ValueKey('game-ghuti'));
    await tester.ensureVisible(tile);
    await tester.pump();
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('1 vs Computer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final game = GhutiScreen.debugGame!;
    expect(game.current, 0);
    expect(find.text('Your move'), findsOneWidget);

    // Step the piece on (2,3) forward to the empty (2,2).
    await tester.tap(find.byKey(const ValueKey('pt-2,3')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pt-2,2')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(game.board[const Pt(2, 2)], 0);
    expect(game.board.containsKey(const Pt(2, 3)), isFalse);
    expect(game.current, 1);

    // The computer answers.
    for (var i = 0; i < 40 && game.current == 1; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(game.current, 0);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
