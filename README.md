# Elite Play BD Ludo

Flutter home page for the Elite Play BD Ludo app.

<img src="docs/home.png" width="320" alt="Home page">

- All artwork (board, pawns, dice, icons) is drawn in code with `CustomPainter`, so it stays sharp on every screen and adds no image assets.
- The page is laid out on a 390pt design canvas and scaled to the device width.
- Static art sits behind `RepaintBoundary`, so the idle board animation only moves a cached layer.

## Play

- **Pass & Play** — 2 to 4 players on one phone.
- **Play vs Computer** — you against 1 to 3 bots.

Rules: roll a 6 to leave the yard; a 6, a capture or reaching home earns
another roll; three 6s in a row lose the turn; start cells and star cells are
safe; an exact roll is needed to get home. First player with all four pieces
home wins.

Play Online, Play with Friends and Tournament are not built yet.

## Run

```
flutter pub get
flutter run
```

## Demo APK

Every push builds an APK with GitHub Actions and publishes it under
**Releases → Elite Play BD Ludo - demo APK**.

## Fonts

Fredoka, licensed under the SIL Open Font License 1.1.
