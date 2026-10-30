# Pane

Automatic window tiling for macOS 15+. Every window gets a place as it opens, and the rest reflow when one closes.

## Build and run

```sh
./scripts/bundle.sh          # builds build/Pane.app (ad-hoc signed)
open build/Pane.app          # menu bar only; grant Accessibility access when asked
swift run PaneCoreChecks     # layout and tiling model checks
```

This needs only the Command Line Tools, not Xcode. Ad-hoc signing changes the app's identity on every build, so macOS asks for Accessibility access again each time. To avoid that, set `SIGN_IDENTITY` to a stable signing identity.

## Layout

- `Sources/PaneCore`: the pure layout engine (Grid, Columns, Rows, Side, plus ultrawide and vertical handling) and the per-screen tile and stack model.
- `Sources/Pane`: the app. It has the Accessibility window wrapper, window observer, tiling manager, hotkeys, menu bar and toasts.

## Shortcuts (⌃⌥ prefix)

| Keys | Action |
|---|---|
| ← → ↑ ↓ | Swap with the neighbour in that direction; past the screen edge, move to the next display |
| ↩ | Make the active window primary |
| ] / [ | Activate the next / previous window |
| ` / ⇧` | Next / previous window in this tile's stack |
| F | Float the active window, or tile it again |
| Z | Focus mode |
| R | Retile |
| ⌘1–⌘5 | Tile up to N windows on this screen |

Drag a window onto another tile to swap the two, or onto another screen to move it there.

## Credits

Window-handling techniques (the size/position/size frame write, the enhanced-UI workaround, `_AXUIElementGetWindow`) follow [Rectangle](https://github.com/rxhanson/Rectangle) (MIT, © Ryan Hanson).
