/// How much may be brought to a table with small blind [sb]: from 20 to
/// 200 big blinds, 100 being the usual stack.
({int min, int usual, int max}) buyInRange(int sb) =>
    (min: sb * 40, usual: sb * 200, max: sb * 400);

/// Play chips for the card tables. They last while the app is open.
abstract final class PokerWallet {
  /// 10 lakh crore to start with.
  static int chips = 10000000000000;

  /// What is given when the account is empty.
  static const freeChips = 10000;
}
