# Gunnug Sprite Editor

A small pixel-art sprite and animation editor built on LÖVE 11.5. It is a separate program from
the game: it lives outside `game/`, so the game's builds never include it and the game can't
reach it.

Run it with `editor.bat` in the repository root, or:

```
"C:\Program Files\LOVE\love.exe" spriteeditor
```

## What it does

- **Game characters as the starting point.** *New* lists the hunter, every enemy and every boss with
  a canvas sized around its in-game hitbox. The hitbox and ground line are drawn as a guide (H), and
  the character as it looks in the game is added as a faded reference layer (`refs/*.png`).
- **Painting:** pencil (pixel-perfect option), eraser, bucket fill (contiguous or every pixel of a
  colour), line, rectangle and ellipse (filled or not), picker (or hold Alt), rectangle select,
  move/nudge, copy/cut/paste. Brush sizes 1-8, mirror X/Y, lock alpha.
- **Paint modes:** normal, shade lighter/darker (steps to the nearest palette colour), dither.
- **Effects** on the cel, the whole layer, or every layer of the frame, limited to the selection
  when there is one: flip, quarter turns, outline (4 or 8 sides), inline, drop shadow,
  brightness/hue/saturation, invert, grayscale, snap to palette, replace colour, wrap-shift,
  despeckle, clear.
- **Timeline:** frames with their own durations, onion skin (1-3 frames each way), playback with
  loop, tags (named ranges such as idle / walk), drag to scrub, a live preview at the game's 3x scale.
- **Puppet rigging:** bones with parents, keyed per frame and interpolated between keys (linear
  or eased). Part layers hold one image that rides a bone rigidly. Pose with FK (drag a bone) or
  two-bone IK (drag near a tip). Rig templates (humanoid with the hunter's proportions, quadruped,
  winged, chain) create the bones plus a part layer for each. *Bake* flattens the puppet animation
  into frame-by-frame pixels for cleanup.
- **Files:** projects save to `projects/*.gspr` (autosave to `projects/_autosave.gspr` every minute
  while there are changes). *Export* writes PNG sprite sheets (strip, grid or one file per frame,
  1-4x, optionally one sheet per tag) to `export/`, with a Lua file of frame rectangles, durations,
  tags, the anchor point (feet) and the hitbox. Drop a PNG on the window to import it as a layer,
  a reference, frames split from a sheet, or a new sprite.

Press **Keys** in the top bar for the shortcut list.

## Folders

| Folder      | Holds                                                     |
|-------------|-----------------------------------------------------------|
| `src/`      | the editor's code                                         |
| `refs/`     | the in-game look of each character, captured from Gunnug   |
| `projects/` | saved `.gspr` projects                                     |
| `export/`   | exported sheets and metadata                               |
