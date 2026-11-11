# Elite Play BD Ludo

Flutter home page for the Elite Play BD Ludo app.

<img src="docs/home.png" width="320" alt="Home page">

- The board, pawns, match background and icons (`assets/images`) are supplied artwork. The dice, player docks and effects are drawn in code.
- The page is laid out on a 390pt design canvas and scaled to the device width.
- Static art sits behind `RepaintBoundary`, so the idle board animation only moves a cached layer.

## Play

- **Pass & Play** — 2 to 4 players on one phone.
- **Play vs Computer** — you against 1 to 3 bots.
- Pick the entry coins for the table; the header shows the prize pool and room id.

Rules: roll a 6 to leave the yard; a 6, a capture or reaching home earns
another roll; three 6s in a row lose the turn; start cells and star cells are
safe; an exact roll is needed to get home. The match continues until one
player is left, so players finish 1st, 2nd, 3rd and get a crown on their yard.

Each player has 5 lives and 20 seconds per turn. Running out of time costs a
life and the turn is played automatically; at 0 lives the player leaves.

Quick messages (emoji and phrases) show as bubbles on the player's panel.
The Voice button is only a mic toggle for now: real voice chat, coins that
are actually spent or won, and Play Online / Play with Friends / Tournament
all need a server and are not built yet.

## Snake

Classic Snake, opened from its tile or banner on the home page.

- Steer by swiping, with the on-screen arrow pad, or with the arrow keys.
- Three speeds (Easy, Normal, Hard) and two arenas: **Walls** (touching a
  wall ends the game) or **Open** (leave one edge, come back on the other).
- Fruit is worth 10 and grows the snake; every fifth fruit a timed gold
  bonus appears that is worth more the sooner it is eaten. The snake speeds
  up as it eats. Running into yourself ends the game.
- Pause, restart, and a best score kept on the device for each speed and arena.

The other games on the hub (Carrom, 16 Ghuti, Car Racing, Fruit Cut, Poker)
are placeholders that say "coming soon".

## Run

```
flutter pub get
flutter run
```

## Demo APK

Every push builds an APK with GitHub Actions and publishes it under
**Releases → Elite Play BD Ludo - demo APK**.

## Sounds

All effects in `assets/sounds` were synthesized for this project. The speaker button in a match mutes them.

## Fonts

Fredoka, licensed under the SIL Open Font License 1.1.
