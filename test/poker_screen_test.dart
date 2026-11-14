import 'dart:io';

import 'package:elite_play_ludo/game/sounds.dart';
import 'package:elite_play_ludo/main.dart';
import 'package:elite_play_ludo/screens/poker_screen.dart';
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

  testWidgets('Poker opens from its tile with tables to pick', (tester) async {
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
    expect(find.text("TEXAS HOLD'EM"), findsOneWidget);
    expect(find.text('Starter Table'), findsOneWidget);

    // Joining asks how much to bring; the rest stays in the account.
    await tester.tap(find.text('Starter Table'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('JOIN TABLE'), findsOneWidget);
    String shown(String key) =>
        tester.widget<Text>(find.byKey(ValueKey(key))).data!;
    expect(shown('buyin-amount'), '2K'); // 100 big blinds by default
    expect(shown('buyin-bank'), '50K');
    expect(shown('buyin-left'), '48K');
    await tester.tap(find.byKey(const ValueKey('buyin-MIN')));
    await tester.pump();
    expect(shown('buyin-amount'), '400');
    expect(shown('buyin-left'), '49.6K');
    await tester.tap(find.byKey(const ValueKey('buyin-MAX')));
    await tester.pump();
    expect(shown('buyin-amount'), '4K');
    expect(shown('buyin-left'), '46K');
    // Nothing leaves the account until you join.
    expect(PokerWallet.chips, 50000);
    await tester.tap(find.text('CANCEL'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('JOIN TABLE'), findsNothing);
    expect(PokerWallet.chips, 50000);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets("Hold'em: turns to landscape, you call, raise and fold", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2340, 1080);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    PokerWallet.chips = 50000;

    final orientations = <List<dynamic>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          orientations.add(call.arguments as List<dynamic>);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: PokerScreen(smallBlind: 10, buyIn: 2000)),
    );
    expect(orientations.last, [
      'DeviceOrientation.landscapeLeft',
      'DeviceOrientation.landscapeRight',
    ]);
    final game = PokerScreen.debugGame!;
    expect(game.seats.length, 5);
    expect(PokerWallet.chips, 48000);
    expect(find.byKey(const ValueKey('bank')), findsOneWidget);

    Future<void> untilMyTurn() async {
      for (var i = 0; i < 900; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final mine = find.text('Your turn').evaluate().isNotEmpty;
        if (mine && game.playing && game.turn == 0) return;
      }
      fail('never became your turn');
    }

    await untilMyTurn();
    final you = game.you;
    expect(you.hole.length, 2);
    expect(game.pot, greaterThanOrEqualTo(30));

    // Call (or check), then next time raise, then fold.
    final hand = game.hands;
    final before = you.total, owed = game.toCall(you);
    await tester.tap(find.textContaining(owed == 0 ? 'CHECK' : 'CALL'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(you.total, before + owed);

    await untilMyTurn();
    if (game.hands == hand && game.raiseRange(you) != null) {
      final to = game.raiseRange(you)!.min;
      // RAISE opens the panel; confirm makes the smallest raise.
      await tester.tap(find.textContaining(RegExp(r'^(BET|RAISE)$')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('raise-panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('raise-to')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('raise-confirm')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(you.bet, to);
      await untilMyTurn();
    }
    if (game.playing && game.turn == 0) {
      await tester.tap(find.byKey(const ValueKey('fold-btn')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(you.folded, isTrue);
    }
    // The computer players finish the hand and a result is shown.
    final h = game.hands;
    for (var i = 0; i < 900 && game.hands == h && game.result == null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (game.hands == h) {
      expect(find.byKey(const ValueKey('result')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);

    // Leaving cashes out and turns the phone upright again.
    final onTable = you.chips;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    expect(PokerWallet.chips, 48000 + onTable);
    expect(orientations.last, ['DeviceOrientation.portraitUp']);
  });
}
