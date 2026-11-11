# Frame-rate notes (2026-11-05 pass)

Committed in `394c381` and `688887f` (releases 0.5.2 and 0.5.3). Earlier pass: see the project memory `perf-profiling`.

## How it was measured

Headless LÖVE driver: copy `game/` into a scratch folder, give it its own `t.identity` and `vsync = 0` in `conf.lua`, replace `main.lua`.
`docs/perf/bench-main.lua` is the plain version: `game.load()`, `menuAction("play", 1)`, `dev.noDamage`, fake mouse fire and key walking, then teleport camp / each area / each arena and log avg, p95, p99, max frame time, update and draw ms, draw calls and KB of garbage per frame. Run `lovec.exe .` from that folder.

Things that bit:
- `os.clock` only ticks about every 1 ms on this PC: use `love.timer.getTime` for anything under a few ms.
- A set but empty env var (`NOPIC= cmd`) is still set in Lua (`""` is truthy): unset it instead.
- The hunter gets stuck on a ledge in front of the buildings if walked with keys; set `body.x` and ground each frame to sweep the camp (x 480-1250). Do not use `atCave = true` for camp tests (he falls underground): `game.devTeleport({kind = "camp"})`.
- Unlock everything for a camp test: expose `unlockEverything` from `src/devpanel.lua` in the test copy, set `stats.resets/deaths/bosses`, call it, then teleport to camp.
- A `jit.attach` trace hook, or a second script left running, changes the results (the hook hid the slow-build mode; a leftover loop competed for CPU).
- The harness's own log write every 300 frames shows up as a 60+ ms hitch.

## Findings and what was done

- Camp steady state with everything unlocked: about 94-98 fps with vsync off (update 2 ms, draw 5.5-6 ms before these changes).
- Lighting is steady (about 1.5-1.9 ms render + 1-1.5 ms entity mask), not the cause of the drops.
- **Area generation** (`catacombs.step`) caused most slow frames. Fixed: tick checks in `cavegen.lua` loops (every 64 columns, every 2 carve steps); first area slice lowered from 12/8 ms to 8/4 ms (`catacombs.lua` ~1056). At 60 Hz the first 400 frames over 17 ms went from about 230 to about 88.
- **Chunk-trace storm** when an area spawned (hundreds of chunks in one frame): `physics.track` now switches far-away new bodies off at once.
- **Garbage**: inline colour tables in `R({...})` in `npcs.lua`, `people.lua`, `town.lua` replaced by constants / `RA`; `town.shade` cached. Draw garbage 230 -> 125 KB per frame.
- **Cached pictures** for camp shacks/facades (`town.drawPicture`) and the four stall frames in `people.drawStall`: pixel-identical to direct drawing (tested), about 0.8 ms less draw. `town.noPictures` / `people.noPictures` turn them off for tests. Not done: the gunsmith, prospector and taxidermist stalls drawn in `npcs.lua`.
- Rejected: GC tuning (no gain), GPU tile uploads (cheap), a pure-Lua `love.math.noise` (does not match LÖVE's output, and 7x slower than the C call).

## Open problem: slow first-area build in about 1 run in 6-8

In those processes area 1 gets about 5x fewer generation steps per slice (210-240 ticks per step instead of about 1000-1900), same total work (about 216,000 ticks), so the Old Mine takes about 15-20 s instead of 4-6 s. Not seed dependent (40 seeds in one process were all fine). JIT is on in the bad runs (`jit.status` true); forcing the JIT off gives about 96 per step; `jit.flush()` / `jit.on(f, true)` mid-build did not help; raising `maxtrace`/`maxmcode` did not help. Cause unknown. The main cost is `love.math.noise` once per pixel in the fill loops at `cavegen.lua` ~271 and ~331 (about 3.9 s of the 4.2 s build).

Ideas left: build the next run's first area while the recap is open (needs the world build split from the run-state reset in `newRun`, `game.lua` ~406; stats like `runs`/`countReset` must not change until Restart is pressed); cache the noise fill; move generation to a `love.thread`.

# 2026-11-10 pass: 120 fps target

## The big one: LuaJIT was throwing its compiled code away
LuaJIT keeps 1000 traces and 512 KB of machine code by default, and flushes everything when either is full. Counted with `jit.attach(fn, "trace")`: in a fight, 80 flushes and 160,000 traces compiled per 750 frames (a flush about every 9 frames). `src/jittune.lua` raises the limits (`maxtrace=60000`, `maxmcode=262144`, `sizemcode=256`); a session settles at about 20,000 traces and never flushes. It must be required first in every Lua state (main.lua, `src/genthread.lua`). This is very likely what the "slow first-area build in 1 run of 6-8" below was, too.

| Headless, vsync off | before | after |
|---|---|---|
| Fight, area 1 (machine gun: scatter, incendiary, ricochet, splitting, shock, venom, glowing, seeker; ~40 monsters) | 72 fps, p95 23 ms | 192 fps, p95 7.0 ms |
| Fight, area 3 | 42 fps, p95 36 ms | 181 fps, p95 7.2 ms |
| Fight, area 5 | 55 fps, p95 27 ms | 160 fps, p95 8.0 ms |
| Same with explosive + cluster rounds, area 1 / 3 | 28 / 21 fps | 90 / 77 fps |
| Fly-through camp -> bottom of area 3 at 300 px/s | 75 fps, p99 37 ms, 637 frames over 16.7 ms, worst 265 ms | 190 fps, p99 10 ms, 8 over 16.7 ms, worst 23 ms |
| Garbage per frame in the fight | 330-500 KB | 110-140 KB |

## The rest
- `main.lua` `love.run`: LÖVE's loop without the 1 ms sleep while vsync is on (measured 1.5 ms a frame).
- `World:prewarm`: by the clock (1.2 ms, 4 ms when what it paints is within 40 px of the view), nearest tile first, margin stretched the way the view moves. Painting costs 0.15-0.8 us per pixel (10-54 ms a tile, most in the deep areas: tint layers); it is all compiled code with no single hot spot, so it is scheduled better, not made faster.
- `World:repaintDeferred` without a tick (an area merged from a worker): painted tiles go on `world.stale` and prewarm repaints them in strips. Was one 370 ms frame when area 1 arrived with the hunter by the shaft.
- `World:flushRepaints`: 3 ms a frame (7 ms with more than 120,000 px waiting), in bands of 24 rows and columns of 256.
- `fluids.runJobs`: `love.timer.getTime` instead of `os.clock`, and pauses every 64 cells inside a pool.
- `World:importRegion`: the id swap table as an FFI byte array; `MERGE_ROWS` 16; genworker uses `love.timer.getTime`.
- `save.update`: the periodic write goes to a writer thread (see the comment in `src/save.lua`); explicit flushes are still synchronous.

## Method
`docs/perf/bench2-main.lua`: `SCEN=combat` (BENCH_AREAS, AMMO, GUN, NEN) keeps N monsters round the hunter and fires at the nearest; `SCEN=travel` flies camp -> shaft -> down; `SCEN=paint` times `repaintRect`. Per-lap averages come from the dev panel's laps (perf.lap replaced by a raw recorder). `XT=1` adds named timers, `JITSTAT=1` counts traces and flushes, `PROF=l` runs `jit.profile` (one window, GC stopped; starting the profiler flushes every trace, so short windows show mostly the compiler), `SHOTS=n` takes a screenshot every n frames.
- A frame's delta belongs to the frame before the one being drawn: attribute spikes to the previous frame's laps.
- Wrapping functions with `...` to time them stops the JIT compiling through them: use fixed-arity wrappers.
- `sed -i` in Git Bash strips the CRs from these CRLF files.

Left: `catacombs.spawnProps` (8-20 ms, all of an area in one frame), `World:exportRegion` on submit (8 ms), bullets/glows/smoke with explosive loadouts.
