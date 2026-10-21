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
- [ ] Barrens set dressing (buried skeletons, rock formations)
- [ ] 5 more random events (carnival aim test, gambler den, +3)
- [ ] 2 new weapons

## Batch 6 (2026-10-18, headless-tested; not played)
- [x] Flow pathing for wisps and dread bats; Needle doorway backdrop feathered; shop opening flare
- [x] Barrens dressing: arches, hoodoos, ruined walls, buried skeletons
- [x] Random events (src/randevents.lua): carnival aim room (Easy/Medium/Hard), gambler den (slots + high-low), tinker (weapon re-roll), shrine, cave-in rescue, marked beast hunt; generic menu dialog page
- [x] New weapons: Crossbow (pierce 2, bolts stick in rock) and Flare Pistol (burning, lit flares that stay lit); both locked until taught/found
- [ ] Events: tune spawn timing/odds in play; hunt kinds, tinker price

## Batch 7 (2026-10-18)
- [x] Water drag: bullets, acid globs and thrown dynamite lose speed in water (bullets sink); flow pathing for dust devils, gargoyles, crows; crate and iron crate art detailed; buried fossil skeletons in the desert ground (replacing surface bones)

## Batch 8 (2026-10-18)
- [x] Icons for the Akimbo and Diving Helm perks (src/icons.lua)
- [x] Marble Colossus rebuilt as floating ore on the 1:1 pixel grid (src/colossusfig.lua + src/colossus.lua): 3/4 view, ore limbs, lopsided head, drifting shards, spring-driven pose per attack state, kneel in crystal shell, wake-up (spread), leap; body now 40x148 (headless-tested in the Marble Hall arena, not yet played; beam sweep, shell fight and stalactite/leap slam need a play-through)
- [x] Colossus pass 2: crystal-shard head (no mouth); shell slims up then grows from inside out (seed crystals, then one orange shard); leap = parts chase each other (stretch), slam breaks it apart and it reforms; rock throw gathers ore into a ball (wind-up 0.4 -> 0.9 s, thrown stone drawn 1.5x). Headless-tested in the arena, not yet played
- [ ] Colossus: tune hit zones to the new reach (swipe 100 px, stomp waves from 40 px), check arena fit; death/shatter animation; the old S=2/3 attack constants
- [x] Colossus pass 3: motes fade slowly; leap stretch doubled; sealed figure clipped to the gem; throw wind-up 0.55 s; swipe aimed at the hunter (held wind-up, accelerating whip, motion ghosts); golemlings are gem bodies with marble legs (hitbox 16x26); wind-up cues and impact sounds per attack. Headless-tested, not played
- [x] Colossus pass 4: no motion ghosts; throw gathers streaming grit + gold trails; golemlings smaller, no outline, rim glow, legs swing past each other; random events never spawn in boss arenas, shops or the overworld (game.lua gate + catacombs.inArena); the Colossus waits dormant (dim, no bar, locked) beside the pedestal and wakes on E; boss health bar lifted above the head (def.barLift); Marble Hall floor +19 banded layers (cavegen). Headless-tested, not played
- [x] Colossus pass 5: soft additive glows (eye, heart stone, beam bands + pulses + bloom); stomp: ore piles onto both fists while they climb, then they fall hard (rings, rubble); shockwave redrawn as crystal-tipped marble spikes on a glowing crack with a flash at the front; dormant boss no longer pops in (drawn as the heap before its first update, 150 px draw margin) and faces the pedestal. Headless-tested, not played
- [x] Colossus pass 6: golemlings 1.5x faster and can trip over themselves (stumble, fall, lie dazed, get up); the boss casts pose-following soft light blockers (def.occluders + fig.occluders) instead of one solid box, so light slips between its legs and under the hovering gem. Headless-tested, not played

## Batch 9 (2026-10-19)
- [x] Sulfur Queen redrawn on the 1:1 pixel grid (src/queenfig.lua replaces the 3 px "cell" blob and fractional crown in enemies.lua): per-pixel shading, 1 px outline, face/crown/drips laid out for each remnant size. Headless-tested, not played
- [ ] Sulfur Queen: pick a look from the Sprite Index "QueenCompare" board (current, B Jelly Empress, C Spore-Mother, D Toad Queen), then animations
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
- [ ] Maybe: optional full-world pre-generation at run start (about 80 s) / cache

## Batch 2026-10-20 round 6 (headless-tested; not played)
- [x] Needle lag: the surface-area generation boost no longer applies while the hunter is inside the mountain
- [x] Sky-hole glow in the mountain is cut out round creatures and the hunter (lighting.entityMask) and a little subdued
- [x] Dark Hunter hp 600 -> 300 (Crow Rider follows, it is double), aim spread about 3x looser, walking speed 140 -> 93
- [x] Quarry 1.5x deeper (2300 -> 3450), its boss hall moved down with it
- [x] Quarry creatures: Lamp Wraith, Cairn Crab (src/quarrymobs.lua) with sounds
- [x] Ether Crawler (src/ethercrawler.lua): spawns while the fuser is locked, flees, walks walls and ceilings, drops 12 ether
- [ ] Maybe: GPU offload ideas (bake parallax layers into canvases; LOVE 11 has no compute shaders)

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
- [ ] Sky dungeon boss still to design (Dark Hunter does not give a glyph)

## Batch 2026-10-21 save and quit (headless-tested; not played)
- [x] Quit to title / Quit to desktop / closing the window save the run, no confirm (no separate Save and quit button): writes runN.sav (src/save.lua saved runs, versioned, loadstring'd table) and returns to the title; the title offers "Continue run" (New run beside it), and the Save Files page has a Resume button per slot
- [x] Restored: seed (areas regenerate identically), position, hp, gold, guns (rolls, fitted items, chambers), loose items, fuser, perks, glyphs, flasks, dynamite, keys, relics
- [x] Not restored (respawn/reset): terrain changes, enemies (slain bosses come back), pickups, shop stock, opened chests/broken props, map chart, random events; the hunter is moved to open ground if he stood in his own hole
- [x] The saved run is used up on resume and cleared on death, restart, new run on the slot, slot delete (quitting saves it instead); corrupt, old or foreign-version files read as "no saved run"
- [ ] Maybe: remember slain bosses (and skip their respawn), keep the map chart, save broken terrain as a diff
