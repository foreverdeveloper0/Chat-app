import 'dart:io';

import 'package:elite_play_ludo/game/holdem.dart';
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
    expect(find.text('500 Crore Table'), findsOneWidget);

    // Joining asks how much to bring; the rest stays in the account.
    await tester.ensureVisible(find.text('Starter Table'));
    await tester.pump();
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
      const MaterialApp(
        home: PokerScreen(smallBlind: 10, buyIn: 2000, start: PokerStart.now),
      ),
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
    await tester.tap(find.byKey(const ValueKey('call-btn')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(you.total, before + owed);

    await untilMyTurn();
    if (game.hands == hand && game.raiseRange(you) != null) {
      final to = game.raiseRange(you)!.min;
      // RAISE opens the panel; confirm makes the smallest raise.
      await tester.tap(find.byKey(const ValueKey('raise-btn')));
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

  /// A table in landscape, started as [start]; returns its game.
  Future<Holdem> table(
    WidgetTester tester, {
    required PokerStart start,
    int buyIn = 2000,
    int players = 5,
  }) async {
    tester.view.physicalSize = const Size(2340, 1080);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    PokerWallet.chips = 50000;
    await tester.pumpWidget(
      MaterialApp(
        home: PokerScreen(
          smallBlind: 10,
          buyIn: buyIn,
          players: players,
          start: start,
        ),
      ),
    );
    return PokerScreen.debugGame!;
  }

  /// Pumps in 100 ms steps until [done], or fails after [seconds].
  Future<void> until(
    WidgetTester tester,
    bool Function() done, {
    int seconds = 150,
    String what = 'the condition',
  }) async {
    for (var i = 0; i < seconds * 10; i++) {
      if (done()) return;
      await tester.pump(const Duration(milliseconds: 100));
    }
    fail('timed out waiting for $what');
  }

  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets(
    'A waiting table counts down for at most 20 seconds, then deals',
    (tester) async {
      final game = await table(tester, start: PokerStart.wait);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('table-countdown')), findsOneWidget);
      int seconds() => int.parse(
        tester
            .widget<Text>(find.byKey(const ValueKey('countdown-seconds')))
            .data!,
      );
      final first = seconds();
      expect(first, inInclusiveRange(8, 20));
      expect(game.playing, isFalse);
      await tester.pump(const Duration(seconds: 3));
      expect(seconds(), lessThan(first));
      await until(
        tester,
        () => game.playing,
        what: 'the first hand',
        seconds: 30,
      );
      expect(find.byKey(const ValueKey('table-countdown')), findsNothing);
      expect(game.you.inHand, isTrue);
      expect(game.seats.every((s) => s.hole.length == 2 || !s.inHand), isTrue);
      await leave(tester);
    },
  );

  testWidgets(
    'Sitting at a running table: a hand is under way, you join next',
    (tester) async {
      final game = await table(tester, start: PokerStart.running);
      await tester.pump(const Duration(milliseconds: 500));
      // Nobody has had to wait: the hand is already going, without you.
      expect(game.hands, 1);
      expect(game.you.away, isTrue);
      expect(game.you.hole, isEmpty);
      if (game.playing) {
        expect(game.board.length, greaterThanOrEqualTo(3));
        expect(game.pot, greaterThan(game.bigBlind));
      }
      // Once it ends you are dealt into the next.
      await until(
        tester,
        () => game.hands >= 2 && game.you.inHand,
        what: 'being dealt in',
      );
      expect(game.you.away, isFalse);
      expect(game.you.hole.length, 2);
      await leave(tester);
    },
  );

  testWidgets('Stand up, watch, and sit down again with a new buy-in', (
    tester,
  ) async {
    final game = await table(tester, start: PokerStart.now);
    await until(
      tester,
      () => game.playing && game.hands == 1 && game.you.inHand,
      what: 'the deal',
      seconds: 20,
    );
    final you = game.you;
    final bank = PokerWallet.chips, onTable = you.chips;
    expect(find.byKey(const ValueKey('sit-btn')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('menu')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('STAND UP'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Standing: out of the hand, chips back in the account, a SIT button.
    expect(you.away, isTrue);
    expect(you.folded || !game.playing, isTrue);
    expect(PokerWallet.chips, bank + onTable);
    expect(you.chips, 0);
    expect(find.byKey(const ValueKey('sit-btn')), findsOneWidget);
    expect(find.text('Empty seat'), findsOneWidget);

    // The table carries on without you, hand after hand.
    final hand = game.hands;
    await until(
      tester,
      () => game.hands > hand && game.playing,
      what: 'another hand without you',
    );
    expect(you.inHand, isFalse);
    expect(you.hole, isEmpty);

    // Sit down again: a buy-in screen, then you are back.
    final wallet = PokerWallet.chips;
    await tester.tap(find.byKey(const ValueKey('sit-btn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('JOIN TABLE'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('buyin-join')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(you.away, isFalse);
    expect(you.chips, 2000);
    expect(PokerWallet.chips, wallet - 2000);
    expect(find.byKey(const ValueKey('sit-btn')), findsNothing);
    await until(
      tester,
      () => game.you.inHand && game.playing,
      what: 'being dealt in again',
    );
    await leave(tester);
  });

  testWidgets('Out of chips you stand up, and can buy in again', (
    tester,
  ) async {
    // Less than a big blind: the first deal stands you up.
    final game = await table(tester, start: PokerStart.now, buyIn: 15);
    final bank = PokerWallet.chips;
    await until(
      tester,
      () => find.byKey(const ValueKey('sit-btn')).evaluate().isNotEmpty,
      what: 'the SIT DOWN button',
      seconds: 20,
    );
    expect(game.you.away, isTrue);
    expect(game.you.chips, 0);
    expect(PokerWallet.chips, bank + 15);
    expect(find.text('Out of chips'), findsOneWidget);
    // The bots play on.
    await until(tester, () => game.playing, what: 'bots playing', seconds: 30);
    expect(game.you.inHand, isFalse);
    await tester.tap(find.byKey(const ValueKey('sit-btn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('buyin-join')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(game.you.chips, 2000);
    await until(
      tester,
      () => game.you.inHand && game.playing,
      what: 'being dealt in',
    );
    await leave(tester);
  });
}
