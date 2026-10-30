# Changelog

All notable changes to Jharokha. Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/).

Each release's notes on GitHub are taken from its section here, so add one before tagging.

## [1.0.0] — 2026-10-31

The first release of Jharokha (झरोखा): automatic window tiling for macOS 15 and later, named after the carved windows of Rajasthan's palaces.

### Tiling
- Windows take a tile the moment they open, and the rest close the gap when one closes.
- Four layouts: Grid, Columns, Rows and Side, with sensible shapes on ultrawide and vertical monitors.
- Choose how many windows each screen tiles; extra windows stack neatly in a tile.
- Each desktop remembers its own layout, or use one layout everywhere.
- Save which app goes in which tile for a desktop, and Jharokha puts them back.
- Smart placement gives browsers, editors and other roomy apps the bigger tiles.
- Learns each app's minimum size and lays out around it. On a small screen, windows that can't shrink overlap a little instead of piling into one stack.
- Re-apply Tiling (⌃⌥R) puts every window back in its place.

### Moving and resizing
- Drag a window onto another tile to swap them, with a live preview of the result. Hold ⌥⌘ to add it to that tile's stack.
- Drag any shared edge and the neighbours follow; ⌃⌥= and ⌃⌥− resize from the keyboard, ⌃⌥0 resets.
- Smooth animations, with a soft blur that hides slow redraws while windows change size.
- Swap with a neighbour (⌃⌥ arrows), make the active window primary (⌃⌥↩), float a window (⌃⌥F).

### Stacks
- A pill above each stacked tile shows who's waiting; click an icon to bring that window forward.
- Scroll through a stack with ⌃⌥⌘↓ / ⌃⌥⌘↑.
- Rest on the grip above the active window for its stack or quick actions: Primary, Focus, Float, Minimize and Close.

### Modes
- **Focus Mode** (⌃⌥Z): one window fills the screen; press again to put everything back.
- **No Peek** (⌃⌥D): every window but the active one fades.
- **Privacy Mode** (⌃⌥P): for screen sharing. Every screen is covered; other windows become calm cards with their app's icon and name, never their content. Show as many as you like. Backgrounds in Jodhpur Indigo, Makrana Marble or Jaisalmer Sandstone.
- The menu bar icon shows a dot while a mode is on.

### Everywhere
- Pin an app to every desktop and screen (⌃⌥⌘P), like a picture-in-picture player.
- Tab View (⌃⌥⇥): every window, drawn where it sits on each of your screens.
- Every shortcut can be changed in Settings › Keyboard, with warnings before you clash with macOS.
- A first-run welcome explains Accessibility access and asks before the first tidy.
- Respects Reduce Motion and Reduce Transparency; VoiceOver reads notices and Privacy Mode controls.

### Requirements
- macOS 15 Sequoia or later.
- Accessibility access (System Settings › Privacy & Security › Accessibility). No Screen Recording, no network, no changes to System Integrity Protection.
