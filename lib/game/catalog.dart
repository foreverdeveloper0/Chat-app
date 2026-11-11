/// A game on the hub. Artwork lives in `assets/images/banners` and
/// `assets/images/logos` under [key].
class GameInfo {
  const GameInfo(this.name, this.key, {this.ready = false});
  final String name;
  final String key;

  /// Only finished games open; the rest are announced as coming soon.
  final bool ready;

  String get banner => 'assets/images/banners/$key.jpg';
  String get logo => 'assets/images/logos/$key.png';
}

/// In the order the home page shows them.
const games = [
  GameInfo('Ludo', 'ludo', ready: true),
  GameInfo('Snake', 'snake', ready: true),
  GameInfo('Carrom', 'carrom'),
  GameInfo('16 Ghuti', 'ghuti'),
  GameInfo('Car Racing', 'racing'),
  GameInfo('Fruit Cut', 'fruit'),
  GameInfo('Poker', 'poker'),
];
