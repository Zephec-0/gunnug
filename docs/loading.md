# How the dungeons are built and when (2026-11-05)

All numbers are from the code as it stands after the loading pass of 2026-11-05 and from headless runs on this machine.
Screen = the 640 x 360 world-pixel view round the hunter.

## 1. What "building" an area is

One area = one call of `cavegen.generate` (src/cavegen.lua), run as a coroutine by `catacombs.resume` (src/scenes/catacombs.lua).
It carves the **whole rectangle of the area** in one go, in this order: base rock and dirt, cave automaton over the whole grid,
caverns, the routes that cross the whole height, ore, the shop room and its hatch, the reachability check, then everything
placed on top (monsters list, props, pools, vault, sluice, gas line, cave-ins, Stormglass, journal spots, edges), and last a
repaint of the whole rectangle. The result is `levels[i].info`.

The coroutine yields from `tick()` (once per row in the heavy loops) as soon as its slice of the frame is used up, so the work is
spread over many frames. It is **not** built by screen region: the routes and caves cross the whole area, so a half-built area is
not usable. Only an area's *finished* state matters to the game.

Measured here, clean foreground runs (after the 2026-11-06 pass): area 1 (Old Mine) 1.65 s, Quarry 1.35 s (3.1 s and 3.6 s before it). A full run of all 17 areas as a low-priority
background process took 285 s (Needle 59 s, the biggest; Fossil Beds 22 s; the rest 4-19 s) and the same areas took about 4.5x
longer there than in a clean run, so a busy or throttled machine is several times slower than the clean figures. That is the
range your "well over 15 s" falls in.

## 2. When an area gets built (the scheduler: `catacombs.step`, every frame)

Called from `overworld.background` with `spare` = what is left of the frame (`target - lastWork`).

| Situation | Which area | Time per frame |
|---|---|---|
| Inventory or compare open in a run ("idle"; nothing is built on the title screen any more) | the next unfinished in order: area 1, then the walk-in entries (the Needle first, it is seen from the desert), then the other entries (Quarry, Flooded Caverns), then the rest in order, the Undercroft last | 10 ms |
| Playing, area 1 not built yet | area 1 | 4.5 ms, 8 ms once within 700 px of the shaft |
| Playing, an unbuilt area is "needed" (within 4500 px) | the **nearest** one (entry areas by horizontal distance from the crevice or doorway, stacked areas by how far above their top the hunter is) | the larger of `spare` and an urgency floor: the estimated remaining build / the seconds before he is 450 px short of it (220 px/s toward an entrance, 320 px/s down), 0.75-12 ms, cap 14 ms |
| Playing, nothing within 4500 px | the next unfinished in order | 0.75 ms (2.5 ms while he is on the surface and the next one is an entry area) |

"Needed" means: an entry area (Quarry, Flooded Caverns, Needle) when `|px - entry.x| < reach` and he is above its bottom and
no more than 400 px above the entrance; a stacked area when he is within `reach` px above its top and within `reach` px of its
width. The area's parent is built first if missing. (Before today the first one in the list order won, so the Old Mine's
neighbour far below the camp was built before the Quarry, and the floor was only 0.75 to 3 ms.)

## 3. The safety net: building on the spot (blocking)

If the hunter gets there first, `catacombs.ensure(py, px)` (every frame) builds the area and its parents **at once**, with a
"Building ..." screen after 0.25 s:

- a stacked area: when he is within **450 px** above its top (or inside it) and within 450 px of its x range;
- an entry area: when `|px - entry.x| < 750` and he is between 450 px above the entrance and 600 px below it;
- area 1: the moment he goes under the surface (`py > surface + 12`) if it is not ready;
- a shop hatch: shooting the chain builds the area below (`shop.onHatchBreak`).

450 px is a bit more than a screen and a half of height; 4500 px is about seven screens of width. The aim of the scheduler is
that `ensure` never has anything left to do.

## 4. What happens when an area finishes (spawn)

On the next `catacombs.update`, `catacombs.spawnProps` spawns **everything in the area in one frame**, regardless of distance:
crates and breakables (asleep), mine lamps and carts, the shops with their dummies, the pools and fluids, piranhas, the prisoner's
cage, the events (altars, vault, sluice, gas line, cave-ins, Stormglass, journal pages), and every monster of the area
(`enemies.rollElites`, `events.spawnArea`). Measured under 50 ms for the Quarry. After that:

- monsters further than **520 px** (a square) from the hunter are frozen (`ACTIVE_RANGE`, src/enemies.lua);
- `enemies.nearby()` (what drawing, lights and blasts look at) is the ones within about 1000 px;
- terrain was painted for the whole rectangle at the end of the build; the screen only draws the tiles in view.

## 5. What is lazy and what is not

- Lazy (on demand): the plain surface and rock outside the areas (`world.lazy`, claimed rectangles are painted by the build),
  enemy activity, rigid-body outlines of props (asleep until woken).
- Not lazy: each area's carve (whole rectangle), its spawn (whole area, one frame).
- The Undercroft (areas 14-17) is no longer a special case: it is built with the others, closed off by a 14 px band of bedrock
  under the Deep until the Sunken Key turns (src/deepseal.lua cuts the shaft through it). Nothing is built when it opens.

## 6. If a streamed build is wanted later

A true "build by screen" would mean splitting `cavegen.generate` so that the carve of each horizontal band (say 400 px tall) can
finish on its own: the cave automaton grid and the routes would have to be decided up front (cheap, they are coarse) and the
per-pixel carving, ore, decor and spawn done band by band as the hunter nears it. That is a rework of most of the 2400 lines of
`cavegen.lua`; the scheduler above is the cheap version of the same idea (build the nearest area first, with more time the
closer he gets).
