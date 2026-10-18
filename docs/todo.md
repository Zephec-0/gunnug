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

## Tools (2026-10-18)
- [x] Sprite + animation editor, separate from the game (`spriteeditor/`, run `editor.bat`): game characters as presets with hitbox guides and in-game reference images, paint tools and modes, effects, timeline with onion skin/tags/preview, puppet bones with FK/IK keys, PNG sheet + Lua metadata export (headless-tested, not yet used by hand)

## Batch 3 (2026-10-18, headless-tested: doctor wake, compendium tiers, grade spread, AI runs; not played)
- [x] Sawbone floats on the real water surface; E wakes him (no more swim-to-free)
- [x] Ghoul digs toward the hunter nonstop whenever not in pounce range (claw animation while digging)
- [x] Swarm bats: staggering orbit plus random bolt when stuck on terrain
- [x] Miner dynamite bites terrain (about half the hunter dynamite crater), same blast
- [x] Weapon grades F-D-C-B-A-S-SS: tier rolled first, much wider spread (C is typical; F ~4%, SS ~0.5%)
- [x] Lamp/candle light radius and strength toned down
- [x] Diamond ore gold x2
- [x] Icons for all batch-2 ammo, attachments and fused items
- [x] Compendium: one tile per common item with grey tier bars (+1..+4) that light when collected

## Batch 4 (2026-10-18, headless-tested; not played)
- [x] Sawbone floats on the surface lake above the Flooded Caverns entrance; E wakes him
- [x] Compendium: tier text removed, tiers shown as roman numerals (I-IV) in tile blocks
- [x] Ghoul bite sized to its body; digging is silent unless terrain actually breaks
- [~] Swarm bat flow-field pathing round walls (verify in play; revisit if still stuck)
- [x] TNT barrel: first hit lights a 3s fuse, more hits shorten it, bigger blast/crater
- [x] Bloater gas x2; all gas now slowly decays (Queen arena gas); boss camera centres on on-screen boss pieces
- [x] Slot order: split/cluster/explosive/gravity before bounce fire on first impact (pieces inherit bounces)
- [ ] Item rarity weights are per item, so epic/cursed are far rarer than the table says (see reply); decide on per-tier weighting
- [x] F2 now opens a dev panel (toggles: no damage, one-hit kills, fly/no clip; teleports: camp, test room, every area, every boss arena)

## Batch 5 (2026-10-18)
- [x] Ghoul dig bigger; regular bats use flow pathing + orbit + unstick; roman numerals smaller; smoke fades faster and draws 1 pixel per cell
- [~] Needle doorway mouth flared/flush floor; shop ceiling opening flared + rubble on roof (verify look in play)
- [ ] Barrens set dressing (buried skeletons, rock formations, mirage oasis)
- [ ] 5 more random events (carnival aim test, gambler den, +3)
- [ ] 2 new weapons

## Batch 6 (2026-10-18, headless-tested; not played)
- [x] Flow pathing for wisps and dread bats; Needle doorway backdrop feathered; shop opening flare
- [x] Barrens dressing: arches, hoodoos, ruined walls, buried skeletons, a mirage oasis (turns into a dry bed with a coin pouch)
- [x] Random events (src/randevents.lua): carnival aim room (Easy/Medium/Hard), gambler den (slots + high-low), tinker (weapon re-roll), shrine, cave-in rescue, marked beast hunt; generic menu dialog page
- [x] New weapons: Crossbow (pierce 2, bolts stick in rock) and Flare Pistol (burning, lit flares that stay lit); both locked until taught/found
- [ ] Events: tune spawn timing/odds in play; mirage, hunt kinds, tinker price

## Batch 7 (2026-10-18)
- [x] Water drag: bullets, acid globs and thrown dynamite lose speed in water (bullets sink); flow pathing for dust devils, gargoyles, crows; crate and iron crate art detailed; buried fossil skeletons in the desert ground (replacing surface bones)
