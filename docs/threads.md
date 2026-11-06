# Building areas on worker threads (2026-11-06)

`src/genworker.lua` (main thread) and `src/genthread.lua` (the worker) build the dungeon's areas on other cores. Dev panel (F2):
"Areas built on worker threads" turns it off (the main thread's own coroutine build is still there and is the fallback).

## What goes over

- **Job:** the area's spec (plain data; the Needle's silhouette function goes as data, `src/profiles.lua`), the seed, the hunter's death marker
  for that area (the one piece of the save the layout reads, `src.story`), and the **cells of the whole region** the build works in
  (rectangle, the gaps beside it for side-by-side areas, a strip of 64 rows above it). The build reads what is already there before it
  writes (the overworld's terrain lies in some rectangles; the shaft is cut down into the area above), so the worker gets exactly
  what the main thread's build would have found.
- **Result:** the region's cells (a ByteData), the layout `info` (plain data), the lazy-paint operations (`claim` / `markLazy` /
  `repaintDeferred`, replayed on the main thread), the tints, the decoration materials the worker made, and the places a table was shared
  inside `info` (a channel copies a table once for every place it is found; `genworker` joins them again).
- **Merge** (main thread, about 1 ms of a frame at a time): relink, decoration ids swapped for the main thread's (`materials.decorKit` hands
  out ids on demand), tints, claims, cells (48 rows a step), lazy ops, then `catacombs.finishLevel` as before.

## Rules it keeps

- An area is only sent once the area above it is in the world (`parentBuilt`). Builds whose regions overlap run one after the other.
- A build that writes outside its region is refused by the worker (it says where); that area is then built on the main thread.
  Areas that legitimately write beyond their rectangle have an entry in `EXTRA` in `genworker.lua` (Cloud Reaches, Quarry, Mesosphere).
- A new run (`catacombs.start`) bumps an epoch: results of the old world are dropped when they arrive.
- Areas nobody needs yet are built at least 4 s apart (`BACKGROUND_GAP`), so they do not all land at the start of a run.

## Checked

17 areas built both ways with the same seed: terrain cell for cell (decoration pixels left out: `World:colorAt` clears a decoration pixel
whose support is gone when it is painted, so exactly when painting happens decides whether a dangling one survives), layouts, lazy
regions, tints and platforms were identical. The harness pins the seed (`EQSEED` in a scratch copy of `overworld.lua`), builds
everything before any game update runs, and hashes the result.

## Not threaded, and why

Water, gas and the monsters' AI share Lua tables with everything else; drawing needs the GL context. Startup audio synthesis
(`audio.load`, 4.6 s of the 5.7 s start, independent jobs, slowest 0.28 s) is the next good candidate.
