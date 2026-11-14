import 'dart:io';

import 'package:elite_play_ludo/game/sounds.dart';
import 'package:elite_play_ludo/main.dart';
import 'package:elite_play_ludo/screens/teen_patti_screen.dart';
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

  testWidgets('Teen Patti: sit down, see your cards, bet, pack, cash out', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    PokerWallet.chips = 50000;

    await tester.pumpWidget(const ElitePlayLudoApp());
    await tester.pump();
    final tile = find.byKey(const ValueKey('game-poker'));
    await tester.ensureVisible(tile);
    await tester.pump();
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Starter Table'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final game = TeenPattiScreen.debugGame!;
    expect(game.seats.length, 5);
    expect(PokerWallet.chips, 49000);

    Future<void> untilMyTurn() async {
      for (var i = 0; i < 600; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final mine = find.textContaining('Your turn').evaluate().isNotEmpty;
        if (mine && game.playing && game.turn == 0) return;
      }
      fail('never became your turn');
    }

    await untilMyTurn();
    expect(game.pot, greaterThanOrEqualTo(50));
    final you = game.you;
    expect(you.cards.length, 3);

    // Look at the cards: still your turn, and the hand is named.
    await tester.tap(find.text('SEE'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(you.seen, isTrue);
    expect(game.turn, 0);
    expect(find.text(you.hand.rank.label), findsWidgets);

    // A chaal costs double the stake.
    final before = you.chips, cost = game.callFor(you);
    await tester.tap(find.textContaining('CHAAL'));
    await tester.pump(const Duration(milliseconds: 100));
    if (game.result == null) {
      expect(you.chips, before - cost);
      // Next time round, pack; the computer players finish the hand.
      if (game.playing) {
        await untilMyTurn();
        if (game.hands == 1) {
          await tester.tap(find.text('PACK'));
          await tester.pump(const Duration(milliseconds: 100));
          expect(you.packed, isTrue);
        }
      }
    }
    for (var i = 0; i < 600 && game.hands == 1 && game.result == null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (game.hands == 1) {
      expect(find.byKey(const ValueKey('result')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);

    // Leaving the table brings the chips back to the wallet.
    final onTable = you.chips;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    expect(PokerWallet.chips, 49000 + onTable);
  });
}
