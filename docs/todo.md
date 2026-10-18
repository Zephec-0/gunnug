# Gunnug TODO (running list)

[x] done (headless-tested, not yet played), [~] attempted but not confirmed in play

Check items off as they land; append new ones at the bottom.

## Bugs / fixes
- [x] Gatling gun and machine gun still drop from mobs/chests before the boss fight / gunsmith. Must not happen.
- [~] Shop item pedestals show two interact prompts (see screenshot: "[E] Buy Heavy Broomhandle" overlapping a second prompt). Pedestals should use the same single-prompt interaction as ground items.
- [x] Interactable text overlaps itself when the wording wraps (e.g. "CURSED: +60% damage..." over "[E] Take Glass Cannon (Cursed)"). Raise the text higher so wrapped lines don't collide.
- [~] Player gets flung when walking over destructibles/boxes. Fix the physics/collision interaction.
- [x] Elite mobs sometimes spawn on screen. They must spawn off screen.
- [x] Ghoul AI gets stuck. If they can't reach the player, they should dig through terrain with their attacks.
- [x] Vaults: make them big enough for the player to walk into (item dropped from the chest was hard to pick up). Chest can't be interacted with until the vault is unlocked.
- [x] Bounty / bounty board should reset per run.

## Balance
- [x] Shop health pedestal: each purchase multiplies the cost by 2.5 (currently each heal reduces cost, so no tension). Playtest the feel after.
- [x] Bloater: increase movement speed, reduce knockback by 80%.
- [x] Cinder Wasps spawn in all areas, not just area 3.
- [x] Area 2 mushroom glow is too strong: reduce by half.

## Features
- [x] Electric/shock rounds shot into water zap it, damaging anything in the water. Frost rounds freeze the water surface.
- [x] Shop background that blocks the parallax, with a title-screen-like "own void" vibe.
- [x] Fuses: when hovering an item in the hotbar, show a pulsing indicator on the items it can combine with.
- [x] Enemy audio: ghoul growls, miner yaps, etc.
- [x] Replace the shelving right of the shopkeep with a sell zone. Dropping an item there sells it for money based on rarity (scale back after testing).
- [x] Larger gold deposit variants around the maps. New diamond deposits (silver/blue): smaller, rarer, 10x money.
- [x] Dungeon entrances: name text appears over the hole, opacity scales with player proximity (fades when walking away or entering). Same for all entrances.
- [x] Generate ambient music for areas that don't have music yet, matching each area's vibe.

## Renames
- [x] "Catacombs" -> "The Old Mine"
- [x] "The Old Quarry" -> "The Quarry"

## Batch 2026-10-16 (headless-tested: loads, shop void and Needle backdrop screenshots; not played)
- [x] Cage floors are indestructible brick; bartender rule flags with icons (no lights); NPC stall/town lights reduced
- [x] Entrance names: 70% shorter range, colour-coded per area; banner has no seed; pause shows "seed - #" and run time
- [x] Enemy sounds positional (steeper falloff, stronger pan)
- [x] Shop/teleport room: swirling purple/blue void shader, same in every area
- [x] Diamonds sparkle; gold seams -1/3 max; ore deposits in varied shapes
- [x] Bloater: wandering gas trail, flees + big gas burst when hurt; gas damage ramps with time in it
- [x] Shop prices x2 and scale with depth; heal rise x1.5; Ricochet Master removed; no breath bubbles with Diving Helm
- [x] Teleport room: ledges removed (shallower), added under every shop from tier 4 down
- [x] Post-Queen paths: 644px diggable rock gap, entrances at inner top corners (areas 4 and 5)
- [x] The Needle: backdrop + parallax clipped to its silhouette, thicker walls

## Batch 2 (2026-10-16, from playtest)
- [x] Camp stall platforms indestructible
- [x] Entrance text larger + wider letter spacing
- [x] Needle entrance transition (long tunnel, gentler, per reference sketch)
- [x] Pause: only seed + run timer
- [x] Ghouls dig in bursts toward the player once locked on
- [x] Dynamite: 3x terrain AOE, same creature/player damage
- [x] Spitter sounds: charge-up then spit
- [x] Shop void: fractal warp reacting to player, teleport room continuous with shop
- [x] New NPC The Sawbone (heal, marks heal cost 2, upgrades, limb-removal trades x6)
- [x] Flooded Caverns: beach slope entrance, name over water, purple-tinged water
- [x] Dev mode F2 (noclip, god, 1000 dmg, fast); fkeys disabled in release
- [x] Indestructible boss barrier until boss dies
- [x] Per-area signs; generated area names shown on entry
- [x] Hub: clear the hill, more overworld variation, bg reaches deeper into ground
- [x] Water area: only fish/wisps/skeleton miners + jellyfish + 2 new aquatic enemies (with audio); 4-stage fish boss

(Batch 2: headless-tested only - loads, boss stages cycle, camp/Sawbone menu and lake screenshots checked; not played. Not verified: Needle tunnel look, enemy fights, dig-through seal.)

## Batch 3 (2026-10-16, headless-tested only)
- [x] Entrance names smaller/higher; Quarry parallax (strata, outcrops, shimmering ore); shop void: no stars, pulsing blue oval
- [x] Sawbone: DOCTOR sign, full heal tab with gold/marks buttons, limb wounds drawn on the hunter, eye vignette x3; camp porch timber indestructible (street fill removed)
- [x] Fish boss: round arena, wakes on aggro (no pedestal), fixed the stage-up teleport (nil position bug), yellow zig-zag lines, close = bubbles / far = wide zag, 3x jellies, camera on hunter, new final fish, 99% body resistance until teeth gone
- [x] Monsters no longer cast shadows (self-shadowing from their own glow lights)
- [x] Colossus rebuilt (src/colossus.lua): 2x size, rusty orange and gold, floating head, chained fists, dormant rise, faster slam/beam, stomp chains, leap-slam with stalactites, ceiling-drop golemlings (7 the second time, beam during shell 2), beam warp + fire trail, rect arena 1/3 narrower with rocky floor and stalactites

## Batch 4 (2026-10-17, headless-tested only)
- [x] Water area background: remove the sand dunes, keep the moving seaweed; slow smooth fractal wave motion and rising bubbles
- [x] Quarry background: keep the top half; replace the flat bottom wall with layered parallax copies of the top style
- [x] Machine gun: never in chests/drops until unlocked; the gunsmith gives it the first time you find him, then crafting it adds it to the pool (per profile)
- [x] Gatling gun: same, but the Queen drops it first; the gunsmith crafts it to add it to the pool
- [x] The Needle: entrance passage runs about halfway into the mountain (rock-lined) before it opens up
- [x] Sky dungeon: fluffy white/blue cloud ground, background darkening to space toward the top, invisible ceiling above the camera's reach (camera clamped, Terraria-style)
- [x] Peak boss rework: Dark Hunter (akimbo S-grade revolvers, triple jump, air dash, clone beam special) -> kneels -> crow swoops in -> Crow Rider (double HP, hover, swoop)
- [x] Akimbo perk (first Epic rarity): drops slot 3, slots 1+2 fire together, reload 10% slower; unlocked by beating the peak boss

(Batch 4: headless-tested - backdrops, cloud ground, space fade, sky ceiling/camera clamp, Needle passage, full boss flow (both phases, shadows + beam, kneel, crow, swoop, death -> Akimbo unlock + drop), Akimbo fold/fire, gun unlock flow. Not played: boss difficulty/feel, crow swoop dodgeability.)

## Batch 5 (2026-10-17, from playtest of batch 4; headless-tested only)
- [x] Water in the water area: opacity -40%
- [x] Shop (and area) backdrops: fade/bleed into the overlapping background instead of a harsh edge, same effect everywhere (e.g. overworld into the Needle)
- [x] Needle cave generation pushed ~300px right (more depth to the mountain face), keeping structures
- [x] Zone name pops up on screen on every enter/leave of a zone (not shops)
- [x] Area 5 left/right lost their backgrounds (showing the underwater one): fix. Area 5: 3x elites, tougher mobs, more spawns (should kill the unprepared)
- [x] Needle: small crow enemy (orbits the player and spits) + 3 more unique enemies, each with its own audio
- [x] Needle dungeon twice as tall
- [x] Needle one-way ladder platforms can't be landed on: fix
- [x] Needle background: inside-of-a-cave look, parallaxed holes peeping out to open sky that give light
- [x] Dense fog: spawns, blocks all light/visuals, pushed by bullets/mobs/player/explosions, dissipates once disturbed
- [x] Dark Hunter: clones space out further, beam comes out faster; Crow Rider fires 2 beams; arena round, entrance from below into a side corner, dark-hunter-coloured arena visuals; crow swoop faster with a short wind-up; unique sounds for both; intense boss music
- [x] Bestiary missing sprites: fix
- [x] Akimbo HUD: both magazines top right (unselected behind, faded purple-grey); both guns use all ammo/attachments (laser etc.)
- [x] Sky dungeon: remove the indestructible layer

(Batch 5 notes: the one-way platforms could not be made to fail in the headless tests (landing from above, jumping up through and climbing a ladder pair all worked), so the lookup was made faster and nothing else changed: if they still fail in play, say where. Not played: boss/mob feel, fog readability, the blended borders at real speed.)
