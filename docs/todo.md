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
- [x] Item rarity weights are per item, so epic/cursed are far rarer than the table says (see reply); decide on per-tier weighting
- [x] F2 now opens a dev panel (toggles: no damage, one-hit kills, fly/no clip; teleports: camp, test room, every area, every boss arena)

## Batch 5 (2026-10-18)
- [x] Ghoul dig bigger; regular bats use flow pathing + orbit + unstick; roman numerals smaller; smoke fades faster and draws 1 pixel per cell
- [~] Needle doorway mouth flared/flush floor; shop ceiling opening flared + rubble on roof (verify look in play)
- [x] Barrens set dressing (buried skeletons, rock formations)
- [x] 5 more random events (carnival aim test, gambler den, +3)
- [x] 2 new weapons

## Batch 6 (2026-10-18, headless-tested; not played)
- [x] Flow pathing for wisps and dread bats; Needle doorway backdrop feathered; shop opening flare
- [x] Barrens dressing: arches, hoodoos, ruined walls, buried skeletons
- [x] Random events (src/randevents.lua): carnival aim room (Easy/Medium/Hard), gambler den (slots + high-low), tinker (weapon re-roll), shrine, cave-in rescue, marked beast hunt; generic menu dialog page
- [x] New weapons: Crossbow (pierce 2, bolts stick in rock) and Flare Pistol (burning, lit flares that stay lit); both locked until taught/found
- [x] Events: tune spawn timing/odds in play; hunt kinds, tinker price

## Batch 7 (2026-10-18)
- [x] Water drag: bullets, acid globs and thrown dynamite lose speed in water (bullets sink); flow pathing for dust devils, gargoyles, crows; crate and iron crate art detailed; buried fossil skeletons in the desert ground (replacing surface bones)

## Batch 8 (2026-10-18)
- [x] Icons for the Akimbo and Diving Helm perks (src/icons.lua)
- [x] Marble Colossus rebuilt as floating ore on the 1:1 pixel grid (src/colossusfig.lua + src/colossus.lua): 3/4 view, ore limbs, lopsided head, drifting shards, spring-driven pose per attack state, kneel in crystal shell, wake-up (spread), leap; body now 40x148 (headless-tested in the Marble Hall arena, not yet played; beam sweep, shell fight and stalactite/leap slam need a play-through)
- [x] Colossus pass 2: crystal-shard head (no mouth); shell slims up then grows from inside out (seed crystals, then one orange shard); leap = parts chase each other (stretch), slam breaks it apart and it reforms; rock throw gathers ore into a ball (wind-up 0.4 -> 0.9 s, thrown stone drawn 1.5x). Headless-tested in the arena, not yet played
- [x] Colossus: tune hit zones to the new reach (swipe 100 px, stomp waves from 40 px), check arena fit; death/shatter animation; the old S=2/3 attack constants
- [x] Colossus pass 3: motes fade slowly; leap stretch doubled; sealed figure clipped to the gem; throw wind-up 0.55 s; swipe aimed at the hunter (held wind-up, accelerating whip, motion ghosts); golemlings are gem bodies with marble legs (hitbox 16x26); wind-up cues and impact sounds per attack. Headless-tested, not played
- [x] Colossus pass 4: no motion ghosts; throw gathers streaming grit + gold trails; golemlings smaller, no outline, rim glow, legs swing past each other; random events never spawn in boss arenas, shops or the overworld (game.lua gate + catacombs.inArena); the Colossus waits dormant (dim, no bar, locked) beside the pedestal and wakes on E; boss health bar lifted above the head (def.barLift); Marble Hall floor +19 banded layers (cavegen). Headless-tested, not played
- [x] Colossus pass 5: soft additive glows (eye, heart stone, beam bands + pulses + bloom); stomp: ore piles onto both fists while they climb, then they fall hard (rings, rubble); shockwave redrawn as crystal-tipped marble spikes on a glowing crack with a flash at the front; dormant boss no longer pops in (drawn as the heap before its first update, 150 px draw margin) and faces the pedestal. Headless-tested, not played
- [x] Colossus pass 6: golemlings 1.5x faster and can trip over themselves (stumble, fall, lie dazed, get up); the boss casts pose-following soft light blockers (def.occluders + fig.occluders) instead of one solid box, so light slips between its legs and under the hovering gem. Headless-tested, not played

## Batch 9 (2026-10-19)
- [x] Sulfur Queen redrawn on the 1:1 pixel grid (src/queenfig.lua replaces the 3 px "cell" blob and fractional crown in enemies.lua): per-pixel shading, 1 px outline, face/crown/drips laid out for each remnant size. Headless-tested, not played
- [x] Sulfur Queen: pick a look from the Sprite Index "QueenCompare" board (current, B Jelly Empress, C Spore-Mother, D Toad Queen), then animations
- [x] Sulfur Queen slime pass: no crown, eyelids or teeth; eyes and mouth are dents pressed into a glassy gas-slime body with glowing embers; bubbles at 3 depths; drips grow, swell, snap off and fall; moving sways (sprung lean), thins and drags a slime tail. 1.4 ms per 84 px draw. Headless-tested in the test room, not played
- [x] Queen pass 2: slime crown (lobes + circlet with a bubble) as part of the head; drips are real falling drops (dripDamage 9, each drip lets go every 6 s, shot-down-able like globs); one sloshing blob on a stretching neck trails her; gas trail while she moves; split is mitosis (1.5 s swell/pinch/two faces, untouchable during and 0.7 s after). Headless-tested, not played
- [x] Queen perf: fight was ~22 ms/frame (45 fps) in the arena; her draw cost ~3.4 ms (a 1px rectangle per dithered run). Now written into a per-monster picture rebuilt at 30 Hz, body loop tightened, tail discs thinned, trail gas lighter (0.16 s, 8 px): about 17 ms. The arena itself (gas draw, boss zoom) is still ~17 ms without her: next target if more speed is wanted
- [x] Gas lag: the gas sweep ran as one 20-30 ms spike ten times a second. Now sliced into 6 equal-gas bands, one a frame, swept every 0.15 s (weights scaled to match), scratch tables reused, region a little tighter, gas drawing cheaper. Gas spreads/thins within ~6% of before. In a gas-heavy walk-and-shoot test: gas update p95 about 14 -> 4.5 ms, worst frame about 33 -> 12 ms. Whole frames still spike (28 ms p95) from the rest of the game; the area is ~14 ms with no gas at all
- [x] New lettering: Scientifica 11 (bitmap, 5 px advance, cap 7) replaces the old hand-drawn face; fonts.get(px) unchanged for callers (whole-number enlargement of the bitmap, white with a 1 px navy shadow). Source assets/fonts/scientifica-11.bdf, generated src/scientificadata.lua (200 glyphs: ASCII, Latin-1, dashes, quotes). The F3 stats overlay keeps its own debug font
- [x] Font weights: Scientifica bold (menu headings, the title) and italic (NPC speech); NPC speech is also drawn without the drop shadow (fonts.plain / fonts.like), which is what made its letters run together. Data in src/scientificabold.lua and src/scientificaitalic.lua, sources in assets/fonts/
- [x] Crates: warm umber/rust-black rims instead of near-black and cold grey frames; nails are dull rust-brown (no bright grey dots)
- [x] Grass: src/grass.lua draws 2-5 px swaying blades along the top of earth, blue clay and bile clay (materials.grass sets the greens); batched as point lists (about 1.7 ms in a cave full of moss)
- [x] Weapon rating: the pickup card now centres the title and grade letter together; the inventory badge letter is centred on its ink (fonts.ink)
- [x] Weapon panel layout chosen: hybrid of B (cards) and C (radar)
- [x] Grass is baked into the map at generation (src/grass.lua bake from cavegen; decor materials 30-38 are painted but not solid; areas 1-3 only, none in water, gone when the ground is dug away), replacing the per-frame pass
- [x] Weapon panel: radar + playing-card hybrid (src/itembar.lua drawPanel): tall cards side by side, picture box with grade badge, DPS headline, radar with value/difference per corner, impact/recoil/crit, slots shrinking to fit
- [x] Weapon cards: the ammo and attachment slots now sit right under the name; the found-a-weapon prompt (compare.lua) shows the found card, an arrow, then the three carried cards ("Replace which?") using the same card drawer (itembar.drawGunCard)
- [x] Area dressing: src/decor.lua bakes per-area decoration and rock tints at generation (cinder, drowned, quarry, needle, sky, flooded sets; see design 7b). Headless-tested in all of areas 4-13, not played
- [ ] Decor leftovers: the first three areas could take moss/roots/drips too (tint only so far: none); decor is not yet knocked off when a prop or minecart sits on it; the Needle's outer flank (outside the cave) has none; frost could also whiten the Needle's one-way ledges; a gust of dust or falling grains was left out on purpose (no animation)


## Batch 2026-10-20 compendium visual pass (headless-tested screenshots; not played)
- [x] Item/ammo/perk icons doubled to 16x16 (EPX smoothing, rim light, outline; icons.getHD) in compendium, item bar; world keeps the 8x8
- [x] Compendium window scaled to 84% and centred
- [x] Compendium detail plate: real additive light (breathing pool, hot core, floor glow, motes) in the item colour instead of circles
- [x] Settings tabs/switches/swatches/key boxes and compendium tiles use the item bar slot look (itembar.slotBox)

## Batch 2026-10-20 (headless-tested: screenshots of crow frames, bestiary sheet, events row; not played)
- [x] Crow Rider: crow redrawn as 1:1 pixel art (src/crowfig.lua): feathered wings that flex through 16 frames, dive and shriek poses, talons, tilt; rider sits higher on its back
- [x] Compendium bestiary: swarm bat is now a flock, every entry idles (wingbeats, pulses, pacing, hopper leaps), tight portrait boxes; added Crow Rider and the Big Fish's four sizes (Big / Bigger / Even Bigger / The Biggest); Colossus portrait no longer errors
- [x] Random events: half as often (first 90-230s, then 240-480s apart)
- [x] Test room: events row past the far wall with one stand of every random event (each returns after it is spent)
- [x] Fixed a crash drawing the Colossus (colossus.lua sent a shader uniform the outline-less shader no longer has)

## Batch 2026-10-20 random events overhaul (headless-tested with screenshots; not played)
- [x] Crow: black outline removed
- [x] Event art redone on the game's pixel grid: people (carny, dealer, tinker) use the camp figure style, pixel targets, a pixel wheel, new slot machine, src/eventart.lua
- [x] Shooting gallery: carny stands off to the side in his own booth and everything goes through him; 3 second count; speech and prompt no longer overlap; prizes drop apart. Medium: targets bounce diagonally; Hard: targets blink in for 0.25s
- [x] Slot machine is its own interactable: 10g per pull taken straight from you, reels spin in the world, lights/lever animate, pays out as coins, "not enough gold" shown on it. New sounds
- [x] High-Low: green felt table page (lamp lighting, shadows), pixel cards with worn paper, card back, J = golemling, Q = Sulfur Queen, K = Biggest Fish, A = Crow Rider; choices to the right with arrows; new card flies in from the top and stacks; fixed bet, higher multipliers; "Leave table"
- [x] Tinker: weapon cards on screen (scaled), one Re-roll button under them, card shakes on a re-roll; undo removed
- [x] Shrine: three offering cards instead of a button list
- [x] Test room events row spaced out (200px) so every stand fits

## Batch 2026-10-20 events round 2 (headless-tested; not played)
- [x] Dev panel: "Drop 100 gold + 12 ether" (ether only charges a locked fuser)
- [x] Tinker: a re-roll button under each card (icon + price), no instruction text; the card flips into the new gun, which may have more or fewer slots (items that no longer fit pop out onto the ground)
- [x] Slot machine smaller, dark reel backs (icons keep their colour), dimmer glow, prompt beside it: "Play!"
- [x] High-Low is a pop-out table panel, cards land tilted and offset
- [x] Gallery: count painted on the stall, 17s rounds, just difficulty + cost in the menu, goal-based rewards (Easy item, Medium gun, Hard perk; under 60% of the goal pays nothing)
- [x] Hard targets stay 1s
- [x] Shrine: click the card (or press 1-3), cost is a block on the card, no buttons

## Batch 2026-10-20 events round 3 (released as 0.2.6)
- [x] Gallery: Easy gives one item (not two), prize guns never above S, goals 30 / 25 / 20, a Hard perk drops as loot in front of the carny, difficulty picker is three colour-coded cards with what they may pay
- [x] High-Low: text and cards more central, the dealt card is face up all the way down
- [x] Shrine cards centred, rounded; tinker flip faster

## Batch 2026-10-20 events round 4 (released as 0.2.7)
- [x] Gallery goals 35 / 30 / 25
- [x] Tinker: re-roll price is per gun (35 + 30 per re-roll of that gun), bigger cards, re-roll icon redrawn so the arrowhead is not cut off
- [x] Gun cards: Impact / Recoil / Crit centred in their columns; effects line moved down


## Batch 2026-10-20 polish round (headless-tested; not played)
- [x] Slot machine: outcome rolled first, jackpot 2%, pair 18%, otherwise nothing
- [x] High-Low: its own lounge track (src/audio.lua TABLE_TRACK, audio.setTable) while the table is open
- [x] Cave far backgrounds at half brightness (dimmed in overworld.drawDecor)
- [x] Item drops from enemies and destructibles halved
- [x] Mountain: built early in the background (surface-entered areas right after area 1), and if the hunter still gets there first a "Building ..." progress screen replaces the 9 s freeze with a gap
- [x] Summit arena: black hall with slow smoke swirls and drifting dust; the mountain sky-hole glow no longer shows inside it
- [x] Item/perk UI icons: exact 2x of the 8x8 art (16x16) instead of the 1.5x resample that squashed circles
- [x] Maybe: optional full-world pre-generation at run start (about 80 s) / cache

## Batch 2026-10-20 round 6 (headless-tested; not played)
- [x] Needle lag: the surface-area generation boost no longer applies while the hunter is inside the mountain
- [x] Sky-hole glow in the mountain is cut out round creatures and the hunter (lighting.entityMask) and a little subdued
- [x] Dark Hunter hp 600 -> 300 (Crow Rider follows, it is double), aim spread about 3x looser, walking speed 140 -> 93
- [x] Quarry 1.5x deeper (2300 -> 3450), its boss hall moved down with it
- [x] Quarry creatures: Lamp Wraith, Cairn Crab (src/quarrymobs.lua) with sounds
- [x] Ether Crawler (src/ethercrawler.lua): spawns while the fuser is locked, flees, walks walls and ceilings, drops 12 ether
- [x] Maybe: GPU offload ideas (bake parallax layers into canvases; LOVE 11 has no compute shaders)

## Batch 2026-10-20 cached drawing (src/bake.lua; headless-tested; not played)
- [x] Baked into canvases, each with a dev panel (F2) switch and a flag in bake.enabled: rock slabs, the mine's rails/supports/skeletons/pickaxes, item bar slot boxes
- [ ] Next: the far-background cell caching idea (parallax.lua)
- [x] Cave background cell caching (mesh per cell) tried and removed: no measurable gain (4.51 vs 4.47 ms draw in the Quarry, more GPU draw calls); the FFI rectangle batch is already cheap when JIT-compiled. Profile.lua hooks switch the JIT off, which made the rectangles look expensive.

- [x] Hung lights ("beacons") added in world gen for the Old Mine, Hollows, Vents and Quarry: theme.beacons = { count, radius, color, strength, style } in src/scenes/catacombs.lua; placed last in cavegen so layouts do not change
- [x] The beacons are now the mine's own hung oil lamps (breakable, same light), added to mine.lamps in cavegen

## Batch 2026-10-21
- [x] Mirage removed; mountain-door light now eases in over 160px instead of stepping
- [x] Dungeon edge walls are plain rock (boss-arena seals unchanged); Quarry narrowed to 1800 wide (Foreman's Hall keeps its size)
- [x] Boss glyphs (src/glyphs.lua): one per boss (Old Mine, Fen, Queen, Colossus, Big Fish), per run, shown left of the health bottle; all five + the Dark Hunter open the sky door
- [x] Prospector perk shelf: one perk kept between runs (not Akimbo)
- [x] Sky dungeon boss still to design (Dark Hunter does not give a glyph)

## Batch 2026-10-21 save and quit (headless-tested; not played)
- [x] Quit to title / Quit to desktop / closing the window save the run, no confirm (no separate Save and quit button): writes runN.sav (src/save.lua saved runs, versioned, loadstring'd table) and returns to the title; the title offers "Continue run" (New run beside it), and the Save Files page has a Resume button per slot
- [x] Restored: seed (areas regenerate identically), position, hp, gold, guns (rolls, fitted items, chambers), loose items, fuser, perks, glyphs, flasks, dynamite, keys, relics
- [x] Not restored (respawn/reset): terrain changes, enemies (slain bosses come back), pickups, shop stock, opened chests/broken props, map chart, random events; the hunter is moved to open ground if he stood in his own hole
- [x] The saved run is used up on resume and cleared on death, restart, new run on the slot, slot delete (quitting saves it instead); corrupt, old or foreign-version files read as "no saved run"
- [x] Maybe: remember slain bosses (and skip their respawn), keep the map chart, save broken terrain as a diff

## Batch 2026-10-21 (headless-tested: loads, camp page, bartender pond flow, support checks, bottle pulse frames; not played)
- [x] Menu cursor light no longer lags the cursor (read at draw time, no smoothing)
- [x] Mine scenery (rails, shoring, post/hung lamps, skeletons, pickaxes), story scenes and non-vault chests vanish when the ground under them is dug away (hung lamps when their ceiling or timber goes; breaking a lamp spills oil). Also fixed blasts never breaking lamps (string vs number grid key)
- [x] Low-health bottle: shake is a whole-cell offset and the pulse is pre-drawn frames of the bottle's own outline, so the cached glass is used (1.36 ms -> 0.08 ms of CPU per frame)
- [x] The first area is built at 8-12 ms a frame from the start of a run (title screen already did it), so entering the shaft no longer freezes for seconds
- [x] Floating water: fluids.clear never reset blockVer/runCache (declared below it, so clear assigned globals): water cached from the previous run was drawn in the new world. Fixed
- [~] Sprites no longer cast or take shadows from lights (lighting.spriteShadows = false, litSprites = false), a test; dev panel toggle "Sprites cast shadows (test)"
- [x] Bartender: found drinking at the oasis pond after the 3rd death; talk to him, he walks off east and the saloon goes up once he is off screen (meta.bartenderAtPond / meetBartender)
- [x] Bartender drinks (2 on the shelf, +2 per Back-Room Stock tier, 6 total), timed buffs bought with marks (wear off with underground time), HUD rows; upgrades Back-Room Stock, A Stiffer Pour, House Rules (house rules are locked until bought)
- [x] Rebalance NPC unlocks and weapon drops (see docs/unlocks.md for how they work now)

## Batch 2026-10-21 b (headless-tested; not played)
- [x] Bottle pulse: soft-edged ring following the bottle's shape, eased out (fast, then slowing)
- [x] Sprite shadows back to normal; scenery lights (scene, props, chests, shop, npcs) are not shadowed by sprites (lighting.backgroundLights), rock still shadows them
- [x] Bartender stays at the pond; saloon goes up once the pond and his lot are both off screen
- [x] Resets (stats.resets) replace deaths for unlocks: Bartender/Apothecary/Cartographer/Gunsmith 1, Prospector 3
- [x] Drink shelves with bottles, locked options hidden, gulp sound, stacking, drunk aim/view wander past 3, pass out at 10 (run resets); buffs shown beside perks
- [x] Crossbow from the Sawbone, flare gun from the Cartographer (gifts; teachable once the giver is at camp); Sawbone moved to the lake's right edge

## Batch 2026-10-21 c (released as 0.3.0; headless-loaded, not played)
- [x] Drinks: bigger bottles, text spaced below the shelf, no tip; buffs halved (whiskey now +15% crit); drunk from the 3rd drink at double strength, lower jump, stumbling movement keys; passing out ragdolls
- [x] Ragdoll (src/ragdoll.lua) on death and when passing out, instead of the topple-and-burst animation
- [x] Gunsmith sells unlocked guns for gold, one per run, B-grade (shotgun 50, semiauto 80, flare 100, automatic 200, crossbow 200, gatling 300)
- [x] NPC card prices centred on the card's height and kept clear of the text
- [x] Prospector's Perk Shelf is a purchasable upgrade; perks shown as icons and picked onto the shelf
- [x] Cartographer's chart (src/chart.lua): aged parchment map filled in as areas and surface places are found, kept on the profile (M opens it without the survey upgrade; buttons on his page and the survey map)
- [x] No breakables in the camp except the crates by the tent; freed prisoners' cages are gone for good
- [x] The sun's light casts no shadows (the blown-out shadow down the shaft); sprite shadows unchanged. Low-health pulse fainter, shorter, dies out before the next
- [x] Test room: perk gallery at the far end (every perk)

## 0.3.1 (headless-loaded; not played)
- [x] Swarm bats: a shriek when the colony wakes, wing flutter and the odd chirp while they fly
- [x] Boss pointers only appear once the boss has been on screen (split bosses share it)
- [x] Bottle scratches and cracks subtler (the bullet hole and its web unchanged); still drawn once per damage stage

## Batch 2026-10-21 d (headless-loaded; not played)
- [x] Swarm bats per colony 8-12 -> 5-8 (wisps unchanged)
- [x] Random events carve a clear room (breakable rock only) around their stage, not just in cramped caves
- [x] Item bar lag: pulsing glows/fuser capsule/locked tints were baked into a new canvas per colour (bake churn); now drawn live. No steady per-frame cost found headless
- [x] Windowed fullscreen: Settings > Display toggle (settings.borderless), a borderless window the size of the desktop; F11 still real fullscreen
- [x] A random event's menu plays the area music muffled (dlg.event) instead of silent
- [x] App icon = the title cylinder: window icon at runtime (titlelogo.iconData); exe icon via tools/build-windows.py from tools/icon/gunnug.ico (regenerate: `love tools/icon` then `python tools/make-icon.py`)
- [x] Fuser flask pulses (rings + glow) when the two slotted items can fuse
- [x] Item tier badge is a roman numeral (I-IV) centred along the slot's bottom instead of plus signs
- [x] Display settings: Screen is a 3-way choice (Windowed / Windowed fullscreen / Fullscreen) replacing the two toggles; F11 still toggles fullscreen
- [x] Windowed mode is a real window (two thirds of the desktop, centred) when the saved size would fill the screen; changing the window mode keeps every canvas's picture (settings.keepingCanvases), which fixes missing UI after switching

## Next up (2026-10-23, from a full playthrough; not started)
Priority order roughly as listed. Items 1 and 7 are the biggest.

1. [~] **Lag: distance-based simulation limit.** (done: pickups and gas beyond three screens; not found: a single culprit, see notes below) Lag came from keeping everything on screen/active: enemy info, items, fluid sims. Only simulate within about 3 screens of the player; beyond that reduce to a cheap form or despawn (enemies, drops, fluids, gas, lights). Seen while finishing the main dungeon: the water + golem dungeons lagged badly and it only stopped after climbing the mountain dungeon. Profile those two first (see perf-profiling notes).
2. [x] **Drops and rarity rebalance.** (headless-tested: roll distribution; not played)
   - Fewer item and attachment drops overall (first dungeon was trivially cleared by drops).
   - Rare/epic rarity scaled way down (about half of drops were rares). Ties into the open per-tier weighting item in Batch 4 (2026-10-18).
   - Split some tiers up for more variety and challenge.
   - Nerf self-heal / life-steal items; nerf multiplicative damage items.
3. [x] **DPS check / scarecrow target:** no life steal (or any heal-on-hit) from hitting it.
4. [x] **Background light fix everywhere.** (Queen arena, Big Fish arena and mountain sky-hole glows no longer cut out round creatures, like the mine's lanterns; the other parallax lights (fungus caps, lava falls, crystal spires, Drowned Halls light) are still dim: they are drawn under the lighting, not emissive. Not played.) The main-cave lighting fix needs applying to all background light sources: the Queen arena gas at the bottom, the water/fish-fight lights, and others (audit every scenery/ambient light).
5. [x] **Unlock gates for ammo/attachments:** lock some behind kill-X-elites, buying certain items, performing N in-game actions, etc. (see docs/unlocks.md for current rules).
6. [x] **Enemy scaling by areas completed:** currently looks like only health scales. Add native armor to enemies and scale armor more than health, so life steal stays weak later.
7. [~] **Sky dungeon (second biggest).** (first pass built, see notes below; polish later) Discuss first, in full: the concept, entrance, look of the area, final boss. Then build the boss and game adjustments after the discussion. Best done after the rest of this list.
8. [~] **Hidden secrets (found, not told):** (motherlode done; airship waits for the sky design)
   - A large gold deposit between dungeons, reachable only by a lot of digging.
   - An airship in the sky with a special unlock, reachable only with a good gun to jump up to it.
9. [x] **Random events fixes:**
   - Spawn bug: one spawned inside the walls at the end of a dungeon. Spawn them near the horizontal middle of the dungeon so they are easy to reach and not missed.
   - Fold the ghost and perk/curse events into the random event pool (they predate it and live outside it).

### Notes on the 2026-10-23 batch (items 2-6; headless-loaded, rarity roll distribution and armour numbers checked, Queen/Fish/Summit arenas drawn; not played)
- Rarity: new Uncommon tier (green) between Common and Rare: 35 uncommon (most from rare/common), 30 common, 25 rare, 4 cursed, 5 epic. Weights common 100 / uncommon 36 / rare 7 / cursed 4 / epic 0.8 (about 68 / 24 / 5 / 2.6 / 0.5 % with everything unlocked). Uncommon is free from the start like common and can be fused up.
- Drops: monster item drop 5% -> 2.5%, props 0.5x -> 0.3x of their listed chance, weapon chests per area 12 -> 9.
- Damage: item damage bonuses now add (slug +50% and hollow point +25% = +75%); fused +N is additive for damage (slug +4: x3.5, was x7.6).
- Life steal: scarecrow gives none; leech 0.25 hp per hit, at most 1 hp / 4 s (2 hp burst), vamp kills heal 1 less (Vampiric 3 -> 2), both weaker by 20% per area of the enemy's depth.
- Armour: monsters get flat armour = (toughness - 1) x 1.6 per direct hit (min 30% of the hit goes through; fire, poison, bleed ignore it; bosses and the dummy have none). Area health growth cut from 0.9 to 0.55 per area. Knobs: enemies.ARMOR_PER_TOUGHNESS / ARMOR_FLOOR, cavegen toughnessAt.
- Feats (meta.FEATS, docs/unlocks.md): ~30 items need a lifetime stat first (elites slain, monsters killed, bosses, shop purchases, gold); shown in the compendium and the Gunsmith's page. New stat: bought.

### Notes on the second 2026-10-23 batch (items 1, 8, 9; headless-tested, not played)
- Random events: every kind now looks for its spot in the middle half of the dungeon's width, on a floor near the hunter's depth, out of sight and never in a boss arena or shop (tested: 0.67-0.72 of the width in the Hollows); the cramped-cave nook fallback is held to the same band. Events stay up 240 s for the stage kinds. The violet altar (perk + curse) and the ghost merchant are now ordinary random events (src.randevents `external`, their logic still in src.events): altars are no longer placed in every dungeon, the ghost no longer has its own timer.
- Lag: config.FAR_X/FAR_Y = 3 screens. Loose gold further than that is dropped, other pickups freeze, gas further than that is let go (every 2 s). Enemies already slept beyond 760 px, water and gas are only stepped round the camera. Headless timing found no distance-related cost: empty areas run 7-9 ms a frame whether or not the rest of the world is generated, so the lag in the water and golem dungeons probably comes from the fights themselves (water cells, golemlings, debris, lights). Needs a profile from a real run there (F3 overlay or a saved timing log).
- Secret: a motherlode of gold (~35 px radius, about 300 gold) is buried in the middle of the rock between the two post-Queen paths, in both pairs (areas 4/5 and the two below). No sign of it above ground.
- [x] Airship: built, see the sky dungeon notes
- [x] Item 4 remainder: the other parallax lights (fungus caps, lava falls, crystal spires, Drowned Halls light) are drawn under the lighting and look dim; give them emissive glow like the mine's lanterns

### Sky dungeon, first pass (2026-10-23; headless-tested with screenshots of every turn, the eclipse and the airship; not played)
Design decisions: the premise is that the hunter is defying the gods, and the last boss is the gods' champion. Beating him does not end the game: it changes the world a little and unlocks things. The airship is a secret over the desert between the hub and the sky, in the middle of nothing.
- Entrance (reworked twice): no glyph door and no chamber. After the Dark Hunter the exit shaft comes out on the mountain's top: flat bedrock with four pedestals, each showing its glyph's rune, E to set (only the [E] prompt, no text). Setting a glyph lights its constellation in the sky: the glyph's own rune enlarged, a star at each end, corner and crossing, the stars real lights (vibrant, they colour the ground and pedestals). With all four, a gust rises from the middle and carries the hunter up the 900 px gap and through a hole in the Cloud Reaches' cloud floor, which now starts there (the sky area was raised by 900: catacombs LAYOUT). Needs the Hunter's glyph, so the Dark Hunter cannot be skipped. src/summit.lua; the old door, runes-on-the-door, held-gate and chamber code is removed. Headless-tested (placing, constellations, flight through the hole); not played.
- Arena: the Cloud Reaches get a floating citadel of cloudstone (src.cavegen: block, oval hall, two mouths with cloud slabs; iron ring seals them in the fight) with a pedestal at its middle. Entered like the Needle's hall; theme fields boss/arena/arenaCx in catacombs.lua. Dev panel F2 > Boss arenas > 11 teleports there.
- Boss, src/starwarden.lua: The Champion of the Heavens (hp 420 x toughness, about 1260). Turn 1 The Clock Turns: a hand of light sweeps round him, star bolts fan out. Turn 2 The Heavens Bend: two hands, gravity wells (enemies.wells) that bend every shot (src.bullets steer) and pull the hunter. Turn 3 The Stars Align: untouchable; three stars light in an order to shoot back (3, 4, 5 long rounds), a wrong one repeats it and sends bolts, each round done is a blow (the last kills). Placeholder pixel art and sounds, hunter's boss theme.
- Victory (meta.skyBeaten, stats.skyBeaten): the overworld sun becomes a black eclipse with a corona (the sky and sunlight go cold), all epic items join the pool, two epics drop. The title screen is unchanged.
- Airship (src/airship.lua): at x 2300, deck y -90 (about 600 px over the desert, out of normal jump reach: only recoil jumps get up), solid planks and cabin, striped balloon drawn behind, lanterns. A chest in the cabin holds the Skybound perk (new Epic: two air jumps, +10% jump) once, then gold and two rare/epic items.
- [x] Polish: boss pixel art and animation (wings, halo), real sounds and music, sky monsters with an identity (cloud rays, star-moths, brass sentinels), the three-band sky (golden cloud sea, ruins, star-dark), a door updraft, the title-screen eclipse, the ending banner, tune hp and hand speed in play; check the hand is dodgeable and the airship reachable with each gun

### Sky dungeon, layout, monsters and hazards (2026-10-24; headless-tested with screenshots, 4 seeds; not played)
- Layout (src/skygen.lua, called from cavegen when the theme has `skyRoute`; the old random `carveIslands` is still there for other open areas): one guided climb east to west along a chain of islands (about 26), in three bands: the Cloud Sea (x 6000 and east: broad cloud islands low over the floor), the Ruins (x 3300-6000: narrower islands with broken stone colonnades, lintels with brass bells, plank bridges, some with a plank missing), the Star Fields (west of 3300: small islands far apart, up to 180 px gaps). Each step is limited to what a jump reaches (gap shrinks as the rise grows). The Citadel moved to the far west and up high (arenaCx 1000, arenaFrac 0.107); the chain ends at the slab at its east mouth.
- Shop moved from the far west to beside the landing (cx = hole - 400, its mouth in the sea floor). The area has no random monsters/swarms from the theme lists any more: `monsters = {}`, and the layout lists where each monster goes (cavegen checks they fit).
- Side branches (chests are now only on these, plus the far-east bank): a stair of three small islands going up off a chain island, or a small island at the top of a vent column. Every branch has a guard.
- Falling: the cloud floor is the net under everything; two real gaps in it over the mountain's top (x 8320-8450 east of the landing, x 6950-7030 west of the shop) drop onto the summit, 1100 px down; the gust stays on once lit, so walking back into it carries him up again (tested: through the hole, fall through a gap, back up).
- Monsters (src/skymobs.lua, all fliers, 4 kinds, none from the old lists; bestiary entries, death adjectives, voices reuse existing sounds): Cloud Ray (packs of 3 sharing a swarm: drift, then tilt and dive in turn), Star Moth (hovers over drops, leashed to its place, comes out to meet you, short stab), Brass Sentinel (floating turret: charges 1 s, a dotted aim line follows then holds, fires a slow bolt), Wind Spirit (takes the island side of you and blows you off the other, 1.2 s gale after a 0.9 s spin-up). Toughness rises with height.
- Hazards (src/skyhazards.lua): permanent gust vents (shortcuts up the chain, loot-island vents, traps in gaps that throw a jumper high; streaks on the column), lightning (telegraphed 1.5 s with a glow and a thread of light, then a bolt; never in the Cloud Sea, every 11-17 s in the Ruins, 4-7 s in the Star Fields; hurts the hunter and monsters near it; death cause "lightning"), bells that ring when brushed past.
- Secret: a wreck of a sky ship half buried in the sea floor under the Ruins (x about 5150): only its mast and a lamp show above the cloud; dig or shoot down through the cloud to its hold. The chest holds a locked weapon, a locked item and 220 gold. Nothing points to it.
- [x] Polish: real art for the four monsters (placeholders are rects and polygons), sounds of their own, a sound for the vents and lightning, wind streaks on the wind spirit's gale, bells that can be shot, wreck interior dressing (crates, skeleton), vent bases and the ruins' look, tune gaps/heights/counts in play (are vent shortcuts worth it? is band 3 too dark/dangerous?), music per band, check the whole route with each gun and without air jumps, the Compendium icons of the new monsters
- Sky revisions (2026-10-24, after the first look): the sea floor west of the shop is patches of cloud with drops between them (a fall there goes all the way to the desert; only the two east gaps land on the summit); no walls at the area's edges; the Citadel is an open floating disc, no walls, gates, ring or seal; ruins columns/lintels are scenery to walk through; lightning tell is sparks that build, die, then strike; sentinel charges 0.65 s with a closing ring on the hunter, shoots faster and its bolts home for 2.4 s; island sizes vary (stepping stones, great banks); about 75 monsters, toughness x1.3.

### Final boss rework (2026-10-24; headless-driven through all four turns with screenshots; not played)
- src/starwarden.lua rewritten. Look after the reference image: golden core with a halo ring, a lance body, feathered plates, cloud arms with gold gauntlets, orbs with spikes ringing him (placeholder shapes, not pixel art yet). He now patrols the whole disc (figure-eight, swoops in turns 1-2, blinks in turn 3), hp 480 x toughness.
- Four turns: 1 Ascension (one hand, star bolts, swoop), 2 The Divine Orbs (two hands, gravity wells, orbs break from his ring and home), 3 The Celestial Rays (blinks; pillars of light on the hunter, combs with a sliding gap, sweeps), 4 The Stars Align (largest, the star puzzle as before; a wrong star sends bolts and rays; rays also fall during input).
- Between turns (at 75/50/25% health): he goes faint and untouchable, high up, and grows (1.0 > 1.25 > 1.5 > 1.8); minions of the sky fight (rays, sentinels, spirits, moths, more each time); when they are dead (or after 50 s) he returns with a flash.
- Sounds (synthesised in audio.lua): sw_chime, sw_orb, sw_charge, sw_ray, sw_grow, sw_vanish, sw_hum; others reused.
- [ ] Polish: hand-pixeled sprite with real animation frames, music for the fight, tune hp/rate of attacks in play, check rays and swoops are dodgeable, a death animation, a fight-specific camera.

### Final boss, second pass (2026-10-24; headless-driven through all four turns, the death and the hole; not played)
- Every turn now opens with a gate: he is untouchable while stars (3, 4, 5, 5; each its own colour, shape and note) light in an order of 3, 4, 5, 6 to be shot back; a strip over the hunter's head shows the order (done = lit, next = ringed, red on a wrong star, which sends bolts and rays). He keeps attacking during it. Then the window: hurt him like anything else. At 75/50/25% he slips out (interlude), grows and burns brighter (form 0 > 1: lance and plates fall away, the core swells to a sun, corona rays, a second halo), and his own minions fight (src/starmobs.lua: Gilded Lens = brass contraption fanning homing bolts, Cometling, Storm Cloud = calls lightning with the spark tell and rains bolts, Star Guardian). Turn 2 adds Star Guardians: while one burns he is shielded; a second comes half way.
- Hand sweeps faster (0.8 / 0.95 / 0.7 / 0.62 rad/s), turn 4 has two hands, orbs, wells, rays, and ring/fan bolts together.
- Lighting: new enemies.afterLights hook; the hand lights along its length, every bolt and orb, the rays as a column of light, the gate's stars in their colours, the guardian's shield, his own light grows with his form. The death is a blaze that is drawn in.
- Death: at the last blow he does not die: he unravels (2.5 s), collapses in on himself (4.5 s, everything falling in, rings drawn inward), flashes, and only then dies (loot as before). A black hole stays where he was: black disc with a burning rim; the post pass bends the light round it (render.setLens, a new lens uniform in the final shader); the space background turns violet and its stars wheel round it (overworld.drawSpace; per run, reset with the area).
- [ ] Polish: lens strength and size, the hole's disc art, ray/lighting intensity is high in the sun turn, hand-pixeled sprite, music, real sounds for the minions; the hole does nothing but bend light (no pull on the hunter); decide whether the violet sky should persist in later runs (now only the run it died in).
- Boss, third pass (2026-10-24; headless-driven, not played): the black hole he leaves sinks to a jump above the floor, pulls the hunter (strong inside ~150 px, felt to 300) and ends the run on touch: cause "blackhole", wanted poster labelled UNKNOWN with the middle of the paper pinched into a collapsing black disc (menu.drawCollapsingPoster). The overworld sun becomes this black hole once the sky is beaten (lensed light, darker sky and surface). Gravity wells got lensing, a burning rim, inflowing light and orbiting lights; the sun-boss sheds drifting motes; pillars throw dust, sparks and rings. The Champion's floor is a flat indestructible cloud slab (materials.CLOUDSTONE), no jump platforms, no lightning during the fight, and the sky background drops to space while he fights (enemies.skyFight). Sky monsters take 10% of knockback. Cloud enemies redrawn in the boss's style (cream puffs, gold rim, star heart). Only the turn's name is shown between turns. Dust storms are off (weather.lua).
- Boss, fourth pass: the hole stays where he died (hangs in the air; the pull reaches 340 px, so a jump in is enough); the small wells have a rim of living pixels; every glow that was a flat disc or column is now a soft gradient (src/softglow.lua); the gate's stars and their light go when the gate breaks; the wanted poster is drawn whole into the hole, which then shrinks away to nothing; the overworld black sun only bends its own sky, and is alive with pixels drifting and spiralling in (scenes/overworld.lua drawBlackSun).

## Sulfur Queen rework (2026-10-27; headless-driven in the Vents arena with screenshots; not played)
- [x] Health x3 (1000 -> 3000 x toughness), contact 24 -> 34, globs 14 -> 20, drips 9 -> 14, splitDamage 0.75 -> 0.9
- [x] Attack order is drawn from a weighted pool per stage (never the same twice, no spawn while her bloaters live) instead of a fixed cycle
- [x] Enrage: 7 s without taking damage and she stops resting (recover x0.5) and attacks 30% faster, until she has lost 4% of her health
- [x] Gas seals: the arena is four sections wide; every 15/11/8 s (by stage) one fills with gas from the floor up (2 s warning, rising over 2.5 s, 9-11 s long), usually the one the hunter stands in; at most 1/2/2 at once; the brood shares one timer. fluids.addColumn gained a `rise` option and refills every 0.15 s
- [x] Tether attack (idea 7): a slime strand pins the hunter while she charges; add last, after the above is played
- [x] Tune in play: seal timing and warning, enrage threshold, whether 3x health is long enough/too long

## Sulfur Queen round 2 (2026-10-27; headless-driven with screenshots and a fire test; not played)
- [x] Gas seals gush up from the floor in about 0.9 s with a soft gradient front (fluids.stepSeal), thinner at the sides; once full nothing is added and it thins out (top first) by the end of its life, so burning gas is never fed (a fire in a seal: worst frame 15 ms)
- [x] The old gas pillars (vents attack) are removed from the fight
- [x] Bloaters replaced by Gas Spirits (src/gasspirit.lua): drift about the hunter, lock on within 230 px (0.6 s brighten), then home loosely (1.5 rad/s turn, 100 px/s), burst into gas on touch or after a 3.2 s fuse; shot down they leak a small puff only
- [x] Queen hover now circles above the hunter (150 px over, 170 px sway) and climbs off the floor faster after a dash, so her drips fall on him
- [x] Tune in play: spirit lock range, turn rate, fuse; seal timing; hover height
- [x] Seal look fixed: the stacked-slab look was my fill skipping a band each step (thin dips every ~50 px); the seal is now one flat full-strength body with a 20 px soft front and an even fade-out, and dense gas shimmers less (fluids.lua draw, k factor)
- [x] Queen dash is a U swoop (enemies.lua queenAttack): down through where the hunter stood (locked 0.3 s before), up the far side to her starting height, 0.9-1.5 s; the dotted path indicator is gone, the charge-up swell is the only tell. Headless-tested path; not played

## Entrance storytelling and the Cork's chamber (requested 2026-11-04; designs only, nothing built)
- [x] (first pass 2026-11-04, headless screenshots; not played) Old Mine entrance: more environmental storytelling outside it (props, signs, wreckage, tracks).
- [x] (first pass) Sunken Hollows entrance (the lake): more around the lake for the sunken caverns.
- [x] (first pass) Quarry entrance: more outside it; blocked-out areas like a stepped quarry; ground colour gradient changes to the dungeon's own palette.
- [x] (first pass) Needle entrance: update it; darker tones of ground and rock leading up to it.
- [x] (built 2026-11-04, headless-tested with screenshots incl. the pour; not played) Cork of Lerna chamber (buried vault): replace the two rectangle rooms with a goblet/hourglass-shaped chamber (sketch at C:\Users\ktkne\.claude\projects\E--gametest\images\1.png area, see below). Upper bulb: three item locks on a ledge (the fused-item door's sockets) with a pool of water above the neck. Narrow neck. Lower sphere: enclosed, the cork on a pedestal. Filling the locks opens the neck and the water pours down, filling the bottom sphere.
- First pass lives in src/entrances.lua (terrain terraces, tints via the new World:addTint `wash` layer, drawn dressing). Tune in play: add more per entrance, the Needle doorway itself is untouched.

## Three pivots (2026-11-04; headless-tested with screenshots, not played)
- [x] Bottle states / conditions (src/status.lua): Soaked, Oiled, Burning, Poisoned, Shocked. Sources: water, oil pools, fire, lava, gas, acid, shock rounds in water, and attackers (spitter, bloater, hopper, wisp, slagback, jellyfish, storm cloud, lightning...). Rules: water puts out fire and washes oil off, burning can't take hold while soaked, oil makes burning 80% longer and 50% hotter and the boots slide (35% grip), poison stacks to 3 (1-3 dmg per 0.8 s, slower walk), shock staggers (25% speed, no jump or roll) and hurts 75% more when soaked, a roll smothers burning 3x as fast, a burning hunter lights gas and oil. The bottle shows each: oil sheen and water layers on top of the blood, fire tints orange with sparks and smoke from the neck, venom tints green, shock arcs across the glass, drips off the base. The Compendium has a Conditions tab (felt the first time).
- [ ] Tune in play: durations and damage, how readable the bottle states are at a glance, oil and water sources are rare so far (only existing pools and pools of oil; no oil flasks or rain yet), whether the slide is too much.
- [x] Journal (src/journal.lua): 8 torn pages at the four entrances, E to read, kept per profile; Compendium Journal tab. Add more by adding to journal.PAGES.
- [x] Sluice caches (src/sluice.lua, cavegen): a sealed, brim-full chamber in the rock (area 2 and deeper) with a chest at the bottom and a plank gate at the end of a short corridor; breaking the gate floods the cave and drains the chamber. Not yet: a lever/lock version, draining a flooded passage, more than one per area, a hint that one is near beyond the damp gate.
- [x] (2026-11-04, headless-tested: barrel -> Oiled 30 s, fire -> Burning 7.2 s instead of 4, jug -> Soaked and both put out) Oil barrels (leak as shot, pour out when broken, no fire of their own) in the Old Mine, Quarry and Needle, and water jugs (splash 24 cells, soak and douse) in the Quarry, Hollows and Needle; fluids.addWater added. Oiled now also triggers from oil on the floor under the feet.
- [x] (2026-11-04, headless screenshots; not played) Journal pages redone as damaged scrap notes: cream card base like the playing cards, yellowed and stained, torn edges, creases, thin faded italic ink (Scientifica italic, no shadow), sized to the text, lower on the screen. Five more pages inside the dungeons (Old Mine, Hollows, Vents, Quarry, Flooded Caverns) placed on a cavegen floor spot when the area spawns (events.spawnArea -> journal.setupArea).
- [ ] Still to verify in real play: the dungeon pages actually appear on dungeon floors (only tested by placing them at camp), and that a second sluice cache generates in area 3+ (one cache confirmed in area 2; none seen in areas 1 and 3 in one seed). Floor page sprite is small.
- [x] (2026-11-04) Sluice tested for real: shooting the gate (a bullet-sized dig) frees the water; found the water only spread along the corridor and did not drain (chamber still ~85% full), so a 22 x 46 px sump is now cut in the corridor floor just outside the gate. Retested: the chamber drains to ~1% in about 8 s and the chest is left in a film of water. The sump is a gap to jump to reach the chest.
- [x] (2026-11-04, prototype, staged test only) Cave-in (src/cavein.lua + destruction.collapse): a roof slab held by timber props; cutting a prop through (8 px gap) starts a 1.5 s rumble (grit, cracks, screen shake), then the slab comes down as ~30 physics debris blocks, snapping the timber, 26 damage to anyone under it, 70 to enemies. An unsupported slab lets go after ~220 px of its underside is dug out. Not placed by cavegen yet; cavein.addZone is called by hand. To do: generate zones in the Old Mine and Quarry, place timber props there, a sign of weak ground, tune.
- [x] (2026-11-04, generated in real areas; headless) Cave-ins placed by cavegen (area.cavein = 4 in the Old Mine and the Quarry): flat roomy stretches of cave whose roof is a 20 px solid slab get three timber props and a beam; zones register in events.spawnArea. Test seed: 4 zones in the Old Mine, 1 in the Quarry (finds are seed dependent, and the rules are strict). Shooting a prop: 1.5 s rumble, then the slab (1533 px) comes down; a held roof shows hairline cracks and a thread of grit. Tune in play: how many per area, how readable the warning is, damage (26 hunter / 70 enemies), whether the props are too easy to hit by accident in fights. A nearby TNT barrel and enemies muddy the test shots.
- [x] (2026-11-04, generated in real areas, tested end to end headless) Puzzle: gas line (src/gasline.lua, cavegen, area.gasline = 1 in the Old Mine and Quarry). A sealed chamber full of gas (vent in its floor) with a chest in it, a corridor to the cave stopped by a 6 px brick plug with a 4 px slit through the top so gas seeps out; two oil barrels stand by the slit and a flame is stencilled on the plug. Spill the oil to the slit and light it: flame runs to the slit, the chamber catches, 0.7 s later the plug is blown out (blast + screen shake). Tune: it is a fire hazard in a gas area, how obvious the solution is (only the stencil and the barrels hint at it), what happens if the player digs in instead (gas pours into the cave). Next puzzle idea still unbuilt: weight and water pulley.
- [x] (2026-11-04, headless) Puzzle chambers (sluice cache and gas line) are now walled in vault rock (the rock under the mountain, as the Buried Vault is): 4 px thick round the chamber and the corridor by the plug or gate. Ordinary digging and blasts leave it untouched; a round with a digging attachment (vaultDig: Auger, Corkscrew, Acid, Blight, Prospector Pick, Treasure Hunter barrel) digs through (test: 494 vault cells, 0 lost to an ordinary dig, 46 lost to vaultDig). Gas line also got a level oil trough with a lip outside the plug and its slit moved down to floor level (oil ran off sloping floors, and flames sat too high to reach the slit). Re-tested: oil stays, lit, the chamber burns off and the plug goes.
- [x] (2026-11-04, tuning pass, headless) Cave-in warning 1.5 -> 2.2 s, hunter damage 26 -> 22, 3 per area (was 4), placement rule loosened again (test seed: 3 Old Mine, 2 Quarry). Oil slip grip 35% -> 45%, shock slow 25% -> 35% speed. Journal pages: bigger reach (34 x 40) and a wider glow. Still only guesses: needs play.
- [x] (2026-11-04, headless: all three fought in the camp, generated in real areas; not played) Condition monsters (src/hazardmobs.lua) and live wires (src/livewire.lua):
  - Arc Beetle (shock): crawls close, glows 0.9 s, discharges a ring (shock + Shocked, 1.75x if Soaked; zaps the whole pool if it stands in water). Hollows (12), Old Mine (4).
  - Torchbearer (fire): skeleton with a torch, keeps its distance, lobs fire bottles (Burning 4 s); its torch ignites oil and gas it passes; fireproof; drops a flame on death. Old Mine (6), Quarry (8).
  - Tar Crawler (oil): leaves an oil trail, spits globs (Oiled 20 s), bursts into 34 cells of oil, catches fire from flames. Old Mine (8), Quarry (10), Vents (6).
  - Live wires (shock, environment): cables hang from the roof, charge 1.1 s then arc 34 px down (shock; zaps water under it), every 3.5-6 s. Old Mine (8) and Hollows (6) scaled per area. Not yet: shooting one dead (livewire.shot is not hooked to bullets), the wires only update inside a dungeon.
  - Tune: counts, damage, how readable the tells are, a wet Hollows full of beetles is harsh (Soaked doubles shock), sprites are first pass.
- [x] (2026-11-04, headless) Second pass: bullets now cut live wires (src.bullets -> livewire.shot; a cut wire arcs once, then is dead) and can shoot a torchbearer bottle or a tar glob out of the air (hitTest/hit wrapped in hazardmobs). Torchbearer now runs the skeleton miner AI (idle/chase, holdMin/holdMax, windup, no hit stun, wander, hops ledges, pushes props) with a longer arm: range 330 (miner 230), hold 110-210 (80-150), flight time 0.35-0.8 s (0.45-1.0), windup 0.42 s (0.55), cooldown 2.4 s (3.2), 30 hp. Tar crawler now walks floor, walls and roof (the ether crawler method), tracks the hunter along whatever it is on, wakes within 130 px with no line of sight, drops off the roof onto him, spits from the surface it is on, and drips oil off roofs. Redrawn: arc beetle (16 x 9, coil seam that lights, six legs, earthing tail), torchbearer (coat, bandolier of bottles, flaring torch), tar crawler (glossy slug, eye stalks, rotates with the surface). Tested: crawler climbed a wall and went under an overhang to reach a hunter on top. Not tested: it dropping from a roof, full chase in a real dungeon.
- [x] (2026-11-05, headless) Ground texture mix (src/groundtex.lua, materials `texture = "stratamottle"` on sandstone, hook in world.lua baseColorAt): uneven dipping beds with seams and lenses over soft rust/tan/pink patches. Cost: 0.16 us per pixel (old 0.05), patches cached per 4 x 4 block; repainting 640 x 200 of mostly sandstone 79.0 ms old vs 79.7 ms new; generating the Quarry area 21.3 s vs 22.1 s (the original code takes 23.7 s on this machine: area generation is slow regardless). Looks good on the surface (camp, Needle approach, lake bank); inside dungeons (Quarry, Needle caves use sandstone rock) it is too dark to read the mottling. Tune: more mottling contrast if wanted.
- [x] (2026-11-05) Sandstone grain halved: variation 0.07 -> 0.03 (tried 0.07 / 0.035 / 0.018, docs/ground_grain.png). Only the speckle changed. Could go to 0.02 or swap the white-noise grain for a 2 px blocky grain.
- [x] (2026-11-05, screenshots) Lake border: the two banks shared one tint box, and a wash holds its full strength past the end of its range, so the whole east side of the lake box was painted brown right up to the box edge at x -100 (a hard vertical line out on the plain). Now one box per bank. Remaining hard edge not touched: the sand layer under the mesas ends sharply at the mesa walls.

## Hollow King pass 2 (2026-11-05, headless-tested with screenshots; not played)
- [x] Bare-prism weak point, five turns with a Champion form, chains of attacks, lava rain, floor cracks into magma pits, pillars of light, sweeping beam, rubble from the roof, rising magma in the last turn, wisps; 2000 health (see docs/undercroft-design.md)
- [ ] Tune from play: health, damage, open window length, flood timing; a sound for the metal; brighter hall

## Fixes from play (2026-11-05; headless-tested, not played)
- [x] Journal pages now lie only inside the dungeons (Old Mine 1, Quarry 6, Flooded Caverns 8, Needle 10 plus the earlier ones; up to three per area on cavegen's pageSpots, the Needle gets spots too). The miners' graves and the notice board by the pond right of camp are gone (entrances.lua); the rope posts stay. The "graves" page became "Names Cut into the Timbers".
- [x] Area loading: the background builder picked the first area in list order within reach, so area 2 (far under the camp) was built before the Quarry; it now picks the nearest one, reach 4500, and the per-frame floor ramps with nearness (4 / 8 / 11 / 14 ms at 4500 / 2800 / 1700 / 900 px). Walk camp -> Quarry with 10 ms of extra load per frame: the blocking build at the crevice went from 3.3-4.5 s to 0.3 s (area costs ~4 s of CPU here). The blocking safety net (catacombs.ensure, "Building ...") is still there. Generation is still whole-area, not by screen region (cavegen's routes cross the whole area).
- [x] Conditions: Soaked ends after 3 rolls (or 12 s); Oiled 30 -> 15 s (tar crawler 20 -> 10 s); Burning ends after 3 rolls (the 3x smother is gone), and the hunter now burns visibly (flames up the body, crown of fire, orange light, more sparks).
- [x] Cork of Lerna: no item any more; E on the pedestal puts the Cork in the bottle and sets the hunter back on the shelf above. The brick ledges up the sphere are gone (the lift replaces them as the way out). Old "sunkenkey" items are still converted by deepseal.update.
- [x] Live wires became Stormglass (src/livewire.lua; same mechanics): spurs of lightning-struck blue glass hanging from the roof, a bullet shatters one. File and area setting keep the name "wires".
- [x] Arc Beetle smaller: 16 x 9 -> 12 x 7 hitbox, redrawn.
- [ ] Tune in play: the lift out of the Cork's sphere (teleport) if a nicer way out is wanted; Stormglass look; beetle size.

## Second round of fixes (2026-11-05; headless-tested with screenshots, not played)
- [x] Cave-in debris (destruction.collapseRock, cavein.collapse): the slab now breaks into jagged Voronoi shards (jittered seeds, about 12 x 9) instead of 11 x 9 boxes, and only the columns that hang over open air (air 1 and 3 px under the slab, and the neighbouring columns) come down, so nothing is cut out of the cave wall to sit stuck in its own pocket.
- [x] Stormglass: rooted in the ceiling (ragged collar of rock crumbs, the first rows of each shard sunk and faint, no bracket), the arc reaches the floor under it (scanned down from the tip when it starts charging, 34 to 320 px) and lights run down the whole length; the glow round the bolt, the charge and the idle shimmer are a soft gradient image, not stacked boxes.
- [x] Burning: the drawn flames are gone; he sheds orange (and now and then dark smoke) pixels that rise and fade, with the orange light kept.
- [x] Cork chamber: no teleport. The shelf with the three locks and the seven ledges up the sphere are one-way platforms (world.platforms), drawn as thin stone slabs; the shelf hovers over the pool with a faint ripple light under it. The socket hints (the item a lock wants) now float up above the lock, larger (2.6x socket height), no box, fade in over 0.4 s and out over 0.75 s.
- [x] Undercroft is built with all the other areas (no dormant state; it is the last in the build order): a band of bedrock 14 px thick closes its roof, the iron plate's shaft is cut through it when the key turns (deepseal.carve), and a save that already has it open gets the shaft left open. The edges of every dungeon are now bedrock (sides and the bottom of the last area; the inner sides facing the other path below the Queen stay plain rock so you can dig across). Tested: closed state = iron plate, then bedrock rows, then the Undercroft's air; after the key = no solid cell in the column down into the Undercroft.
- [x] After the Hollow King: the red sun has a hot core, a tight bloom and a wide red glow in the painted sky, plus a slow additive red breath over it.
- [ ] Not played: how the long Stormglass arcs read in a tall cavern, whether the shards break up the cave-in nicely in every cave, the new bedrock edges where a dungeon meets the desert.

## Loading and frame-rate pass (2026-11-06; headless benchmark, not played)
- Benchmark (area 1, scripted shooting and walking, 30 s, vsync off; driver idea in docs/perf): **as it was** (everything on) 47-51 fps, frame avg 20-21 ms, p95 25-28 ms, the background builder 9.1 ms of every frame; **no background loading** (area 1 built at run start) 102 fps, avg 9.8 ms, p95 14 ms. **After this pass** everything on: 75.5 fps, avg 13.2 ms, p95 20.5 ms, builder 1.9 ms a frame, and it built 4 more areas during the 30 s; no background loading: 100 fps, avg 10.0 ms, p95 15.8 ms.
- The 9 ms a frame was my own distance floors from the previous round (4-8 ms forced whenever the next area was within 2800-4500 px, which in the Old Mine is always). Replaced by an urgency floor (catacombs.step): the remaining build (estimated from the measured seconds per pixel of the last area) divided by the time left before the hunter is ENSURE_NEAR short of it (220 px/s toward an entrance, 320 px/s down), clamped 0.75-12 ms, plus whatever the frame has spare. Area 1 at run start: 4.5 ms a frame (8 near the shaft). On the surface with only a far entry area left: 2.5 ms (was 7).
- Nothing is built behind the title screen any more (game.lua): pressing Play makes a new world, so what was built there was thrown away.
- Build cost: area 1 3.1 s -> 1.65 s, Quarry 3.6 s -> 1.35 s (clean foreground runs). (a) The final whole-area colour repaint (about 45% of the build) is deferred: World:repaintDeferred marks the rectangle lazy, and each tile is coloured from its cells when first needed (prewarm paints the tiles round the view a little each frame; a first touch of a tile is 3-14 ms). (b) fillBase and carveCaves sample their noise on a 4 px / 2 px lattice and interpolate (one love.math.noise call per 16 / 4 pixels); the caves differ slightly in the fine edge, not in layout rules. (c) carveCaves' tick moved out of the pixel loop (64-column pieces).
- Found: the first discovery of anything (first kill, pickup) built the whole compendium catalogue, every enemy portrait with 6 canvas read-backs, in one frame: a 550-600 ms stall. Enemy portraits are now drawn the first time they are looked at (compendium.lua, lazy `image`).
- Not changed / ideas: the Needle (22 M pixels) will still take several seconds; the remaining 1.3-1.7 s of an area is the cave grid, routes (carveCircle), base fill and placements. A `love.thread` build is the next big step.
- Correction to docs/loading.md: the 285 s all-areas figure was a slow process, not proof of background priority; a clean run is 3 s (now 1.4-1.7 s) per big area, but runs vary (an occasional 5-7 s, rarely much worse: see docs/perf-notes.md).
- [x] (2026-11-06) Journal page glow: the blocked square is gone; an unread page now has a soft round halo (gradient image, fading to nothing at its edge) plus a tighter warm one and a pulse, and throws a little warm light on the cave (journal.drawEmissive / addLights). Headless screenshot only.
