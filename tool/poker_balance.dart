// ignore_for_file: avoid_print

// Plays many hands with every seat driven by the computer-player logic and
// reports how each seat fares, so the bots' temperaments can be tuned
// until nobody has a big edge:
//
//   dart run tool/poker_balance.dart [hands] [players]
import 'dart:math';

import 'package:elite_play_ludo/game/holdem.dart';

void main(List<String> args) {
  final hands = args.isNotEmpty ? int.parse(args[0]) : 20000;
  final players = args.length > 1 ? int.parse(args[1]) : 5;
  final nerves = args.length > 2
      ? [for (final v in args[2].split(',')) double.parse(v)]
      : defaultNerves;
  const stack = 2000;
  final g = Holdem(
    smallBlind: 10,
    buyIn: stack,
    players: players,
    random: Random(7),
    nerves: nerves,
  );
  final net = List.filled(players, 0), won = List.filled(players, 0);
  final showdown = List.filled(players, 0), folds = List.filled(players, 0);
  var played = 0, allIns = 0;
  for (var h = 0; h < hands; h++) {
    for (final s in g.seats) {
      s.chips = stack;
    }
    if (!g.deal()) break;
    var guard = 0;
    while (g.playing) {
      if (++guard > 600) throw StateError('hand never ended');
      if (g.awaitingStreet) {
        g.nextStreet();
      } else {
        g.botTurn();
      }
    }
    played++;
    final r = g.result!;
    for (final s in g.seats) {
      net[s.index] += s.chips - stack;
      if (r.winnings.containsKey(s)) won[s.index]++;
      if (s.folded) folds[s.index]++;
    }
    for (final s in r.revealed) {
      showdown[s.index]++;
    }
    if (g.seats.any((s) => s.chips == 0 || s.total >= stack)) allIns++;
  }
  final bb = g.bigBlind;
  print(
    '$played hands, $players players, ${g.seats.map((s) => s.nerve)} nerve',
  );
  for (final s in g.seats) {
    final i = s.index;
    print(
      '${s.name.padRight(6)} nerve ${s.nerve.toStringAsFixed(2)}  '
      'net ${(net[i] / bb / played).toStringAsFixed(3)} bb/hand  '
      'won ${(100 * won[i] / played).toStringAsFixed(1)}%  '
      'folded ${(100 * folds[i] / played).toStringAsFixed(1)}%  '
      'showdowns ${(100 * showdown[i] / played).toStringAsFixed(1)}%',
    );
  }
  print(
    'hands with someone all in: ${(100 * allIns / played).toStringAsFixed(1)}%',
  );
}
