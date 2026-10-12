# Gunnug — Design Document

> Living document. Sections marked **[Later]** are intentionally deferred; we'll revisit them once the current milestone is playable.

## 1. Concept

A **dark fantasy** 2D roguelite dungeon crawler built on the bones of **Noita**: pixel-simulated, destructible terrain and a deep, buildable weapon system. Noita's wizard, wands, and spells are replaced with a **monster hunter** in the mould of Van Helsing, wielding firearms (and later other weapons) with ammunition and attachments, spanning **old designs up to roughly WW2-era**. Tone: the grim gothic world of *Warhammer: Vermintide*, rendered in the art style of *Dead Cells*.

- **Engine:** LÖVE 11.5 (via the bootstrap-love2d-project template)
- **Controls:** Mouse aim + WASD
- **Platforms:** Windows first; template supports others later

## 2. Art Direction

- **Dark fantasy, Dead Cells-style pixel art — desolate rather than gothic:** muted, weathered bases (dusty sand, red sandstone, slate, dark earth) that stay readable rather than pitch dark, with a few **vivid accents** — glowing eyes, lantern and campfire flames, teal cave fungus, silver fittings — and punchy, glowing muzzle flashes and sparks. No vampire/graveyard imagery.
- **Lighting:** each scene has an ambient light level; a light map with soft radial lights (the hunter's own light, candles, lanterns, the sun, muzzle flashes, bullets, flames, glowing fungus and gas) is multiplied over the scene. Flames, eyes, sparks and bullets are drawn afterwards as **emissive** so they glow even in darkness (§2b).

### 2b. Lighting, post-processing and lettering (shaders, `src/lighting.lua`, `src/render.lua`, `src/fonts.lua`)

- **Shadows:** every light is drawn by a shader that marches a ray from each pixel to the light through a mask of the terrain, 24 steps with a per-pixel start offset (so shadow edges are fine grain, not bands). Rock casts shadows: a pillar or ledge darkens the cave behind it, lights in a room stay in the room, and the sun is blocked by the pit's walls. 30% of the light still leaks through rock so cave walls stay visible, and rock faces right at the edge of open air stay lit. Falloff is `f^1.7` with a hot core.
- **Volumetric haze:** a second, softer pass of the same lights (radius x1.3, falloff `f^2.4`, 20% strength, lights over 200 px excluded) is added on top of the lit scene, so the air around a lantern, candle, flame, gas cloud or the hunter's own light glows. The haze is blocked by walls too. On the surface a column of evening light falls straight down the mine shaft (breathing slowly, thinning with depth) with dust turning in it.
- **Post-process:** the finished frame gets bloom (everything brighter than 0.8 is blurred at half and quarter size and added back: flames, eyes, sparks, bullets, the sun), a gentle S-curve for contrast, cool tint in the shadows and warm in the lights, and a soft vignette. UI is drawn after it, untouched.
- **Fallbacks:** if shaders can't be built, the game falls back to plain radial lights with no shadows, haze or post-process.
- **Lettering:** the game's own hand-drawn **32-bit-style pixel face**, stubby and refined: capitals and a full lower case drawn on a wide 6x7 grid (cap height 7, x-height 5, descenders two rows below the baseline), then enlarged 2x with a pixel-art smoothing pass (Scale2x/EPX) that rounds corners and straightens diagonals while every pixel stays hard-edged, giving two-pixel strokes on a 14-row cap height. Small sizes use the 6x7 grid as it is; large ones scale the smoothed glyphs by whole numbers. The text is **mostly white**: bright along every upper edge and through the body, easing to a pale steel blue only at the foot, with a slightly darker rim on lower edges, and a **two-step drop shadow** (deep navy against the letter, fainter black beyond) down and to the right. Everything that used to be gold or yellow is white or near-white; reds and greens stay where they mean something. **Damage numbers are red** (crits a brighter red-orange). Titles (area banners, the menu, "You Died") get an ornamental rule under them: a line fading out to both sides with a diamond and two beads, in steel blue (dark red for "You Died"). The glyphs carry their own colour, so text is printed white.
- **Terrain shading:** terrain is at full brightness at its edges and darkens with distance from open air (lit rims around dark masses); digging re-shades automatically.
- **Rendering:** the terrain image is split into 256×256 tiles (only changed tiles are re-uploaded, only visible ones drawn). The game draws to a low-resolution canvas of **640×360**, which maps exactly **3:1 onto 1920×1080** — every game pixel is a crisp 3×3 block, with no blurring of moving objects. (The view shows the same amount of world as the earlier 400×225 zoom, at 1.6× the pixel density.) Other window sizes that aren't a whole multiple use "sharp bilinear" scaling: a crisp whole-number upscale followed by a smooth fit. Moving props are drawn at whole-pixel positions so they step cleanly instead of resampling. One game pixel = one terrain pixel. Screen-space UI (HUD, item bar, text) has its own scale and is unaffected by pixel density.
- **Rescaling rule:** all world values are in game pixels. To change pixel density again, multiply lengths, speeds, accelerations and forces by the factor; masses and times stay the same; pixel-count limits scale by the factor squared. The Box2D metre scales too, so physics behaves identically.
- **Camera:** keeps the player centred (leaning slightly toward the aim) and is not clamped to the level; past a level's edge, the edge terrain continues.
- **Character:** a lanky, slim **Van Helsing-style hunter**, drawn as pixel limbs on a procedural skeleton rather than sprite frames. His head is mostly a tall, wide-brimmed hat worn low, the brim pulled down to two glowing eyes peering from the shadow beneath; he wears a slim long dark coat with a crimson lining and a **light-grey shoulder mantle** (part of the coat, its loose end trailing in the wind), dark trousers and buckled boots, and carries an engraved dark-steel revolver. Legs walk via inverse kinematics, both hands grip the gun and follow the aim, the gun kicks on firing, legs tuck when rising and dangle when falling, the kick extends a leg, landings dip the body, and he has crouch and slide poses. The coat tails and mantle tail follow the motion with simple secondary physics.

### 2a. Art bible (implemented so far)

**Palette rules.** The world stays muted and desolate (greys, slate, dusty earth, cold cave violet). Colour is spent only on things that matter, and each effect uses one accent from a small fixed set so a busy screen stays readable:

| Accent | Used for |
|--------|----------|
| warm gold / yellow | the hunter's eyes, gold, candles, muzzle fire, Gilded and Glowing rounds |
| orange | fire, explosions, embers (Incendiary, Explosive, Cluster) |
| pale ice blue | Frost, Spectral, shock arcs, the ghoul's eyes |
| acid green | Venom, Acid, spitter globs, cave fungus, regeneration |
| blood red | damage, Blood and Vampiric rounds, curses (red rim) |
| violet | Singularity, the monsters' motes, Rare items are blue-rimmed instead |

**Item and perk icons.** Every ammo type, attachment and perk has an 8x8 pixel icon (`src/icons.lua`) tinted with the item's own colour, with a rarity rim (none for common, blue for rare, red for cursed). Icons appear in the item bar, weapon panel, shop pedestals and dropped items.

**Hunter.** Hits whip the upper body back; a kick throws it back for balance; a double jump twirls him around his middle; death knocks the hat off, drops the gun, topples him from the feet and then bursts him apart.

**Ammo effects.** Frost leaves ice crystals, Venom and Vampiric drip, Acid bubbles, Shock crackles in a jagged line and rings on hit, Concussive throws a shock ring, Singularity draws sparks inward and collapses a ring, Seeker and Boomerang leave a trail (the boomerang spins), Spectral flickers, Glowing has a glare, Sticky bombs fizz and Cluster bomblets blink faster before they blow. Muzzle flashes differ by gun: round with side sparks (revolver), small star (pistol), wide fan (shotgun), thin needle (machine gun).

**Enemies.** Hits shove the sprite back for a moment. Each monster dies its own way: the ghoul crumbles to ash and rags and a pale wisp leaves it; the bat folds into wings and body and plummets; the spitter pops into acid and flesh. The spitter now has twitching tendrils, an eye that tracks you, a swelling and throbbing sac and a throat that glows brighter before it spits.

**Shop.** A market hall: perk daises with glowing runes that brighten (and shed sparks) as you approach, a hooded merchant behind a counter who breathes, blinks and follows you with their eyes (and sleeps when the shop closes), a lantern, a red floor runner, swaying banners, a barrel and crates. Cave backgrounds have two layers of far rock pillars that scroll slower than the terrain.

## 3. Game Structure

```
Overworld (hand-built, same every run)
   └─► Dungeon entrance
          └─► Area 1 (randomly generated) ─► Shop room ─► Area 2 ─► Shop ─► ...
```

- **One seamless world, no loading screens** (as in Noita): the overworld and the areas below it are a single continuous level. The whole world is there from the start of a run — you walk to the mine shaft and drop straight down into Area 1, and could dig down from anywhere. Areas are stacked vertically under the overworld.
- **Overworld:** hand-crafted, consistent across runs. Eventually large and explorable; for now a walkable area that leads to the dungeon entrance.
- **Areas:** each is randomly generated, stacked one under the next in the one seamless world (the Catacombs, the Sunken Hollows and the Sulfur Vents, each 2880×3100 px, then a fourth row of two areas side by side, §7e), and ends at a **shop room**. The Sulfur Vents end in a **boss arena** with two shops below it (§7d). A shop with another area below it has a **hatch** in its floor that drops into the next area (like the mine shaft does from the surface); the last area's shop has none yet. Areas generate in order in the background, 10 ms per frame (about 3.3 s of work per area), and an area is finished at once if the hunter gets within 900 px of its top before it is ready.
- **Background generation:** a new run builds the overworld at once (~0.3 s) and generates the areas a slice per frame. Generation also keeps running while the game is paused (title screen, pause menu, weapon panel), so the title screen gives Area 1 a head start. Even with no time on the title screen, Area 1 is ready by the time the hunter reaches the shaft (a straight walk takes ~5.8 s). If the hunter gets underground first, the rest is generated immediately.
- **Shop room:** healing, goods and the hatch (§9). Leaving the shop locks it.

## 4. Player

### 4.1 Movement
Modelled on Noita: walk, jump, air control, gravity, collision against pixel terrain (including walking up small slopes/steps). The player's hitbox is 8×19 px, and the player feels **80% of world gravity** (its own gravity scale, like physics objects have) with strong air control, so it stays manoeuvrable in the air.

**Levitation is replaced by recoil jumping.** Firing a weapon pushes the player in the direction opposite the shot. Firing downward launches the player upward; this is the primary means of gaining height and crossing gaps. Each weapon has its own recoil strength, so weapon choice affects mobility (e.g. the shotgun is a strong "jump" gun).

- Recoil pushes in **all directions** opposite the shot, but is **mainly an airborne mechanic**: while standing on the ground, recoil is significantly reduced.
- Recoil jumping has **no extra limit** — it is bounded only by the gun's chambers and reload time.

### 4.1a Crouching & sliding (Ctrl)
- **Crouch:** pressing Ctrl while still crouches (hitbox 8×12, so the hunter fits under low gaps); holding it while moving is a slow crouch-walk.
- **Slide:** pressing Ctrl while moving (or landing with it held while moving) starts a slide that keeps momentum — a small speed boost (×1.2, not repeatable within 0.4 s), no steering, low friction — and becomes a crouch-walk once slow. Kicks up dust.
- **Slopes:** while sliding, gravity along the slope speeds the slide up downhill and slows it uphill (capped at 380 px/s); crouching on a steep slope (rise/run ≥ 0.4) starts a slide downhill on its own, and a slide doesn't stop on a steep slope just for being slow.
- Releasing Ctrl stands back up, but only when there's headroom (terrain only; loose objects resting on the hunter are shoved off). **Slide-jump:** jumping out of a slide (or within 0.12 s of one ending) springs out of it — ×1.15 jump height and a burst of extra horizontal speed (×1.3 + 40 px/s, capped at 380) that **fades while airborne** (half gone in ~0.28 s; any remainder is removed on landing), so it carries ~25% further and 50% higher than a running jump but chaining slide-jumps can't build speed. The slide-entry boost applies only to a fresh Ctrl press on the ground, not to landing into a slide; holding Ctrl in the air keeps him tucked.

### 4.2 Kick
Kept from Noita. A short-range kick (**F**) that shoves loose objects (and later enemies) in the facing direction.

### 4.3 Health
- Same model as Noita, displayed as a number. Player starts with **100 HP**.
- **Damage:** monsters and their acid globs hurt the hunter. A hit knocks him away from its source (170 px/s sideways, a small hop), flashes the screen red and makes him invulnerable for 0.9 s (he blinks).
- **Health bar** (top right, drawn at the window's full resolution): a glass tube of **dark blood** (crimson at the surface, near-black red at the foot) with a **smooth gradient** down every pixel row. The surface ripples in hard pixel steps. **Bubbles** are arcade-style pixel sprites on a chunky pixel grid (a single dot, a 2x2 blob, or an eight-pixel ring with a dark centre and a pale glint) that rise now and then and pop into pixel spray at the top. Under 30% health the blood **boils**: the surface churns, bubbles are bigger and constant, spray flies off, the whole tube shakes and a red glow pulses around it, more so the lower the health.
- **Testing:** **F8** finishes generating the areas and drops the hunter on the Sulfur Queen's arena floor (a few seconds' pause the first time).
- **Death:** at 0 HP he bursts apart and a "You Died" screen appears; **R** starts a new run (new world, fresh inventory).
- **[Later]** healing, max-HP upgrades.

## 5. Weapons

### 5.1 How guns map to Noita wands

| Noita wand | Gunnug gun |
|---|---|
| Capacity | Chambers / magazine size |
| Spell slots | Ammo/attachment slots, separate from chambers (revolver: 4) |
| Spells | Ammo types and attachments **[Later]** |
| Cast delay | Fire delay (time between shots) |
| Recharge time | Reload time — **automatic** when the gun is empty |
| Spread | Spread (accuracy) |
| Mana | Not used |

### 5.2 Firing model
- A gun holds N chambers. Firing consumes the next chamber in order.
- When all chambers are spent, the gun **automatically reloads** over its reload time, then is ready again.
- **Manual reload (right click):** the held gun can be reloaded early whenever at least one chamber is spent. It takes the gun's full reload time (no partial or faster reloads) and can't fire meanwhile.
- Every gun fires its **default round** with its own base damage and behaviour. Ammo types and attachments fitted in the gun's slots will later alter how shots behave (exact rules to be designed — see §5.5).
- Every gun has an **impact force**: the impulse a bullet applies to physics objects where it hits. Deliberately larger than realistic (a crate shot should skip across the room), and a stat that ammo types/attachments can modify later (e.g. heavy slugs).

### 5.3 Base weapon archetypes
Starting tuning values — to be adjusted by feel.

| Archetype | Example | Chambers | Fire delay | Reload | Spread | Damage / shot | Recoil | Notes |
|---|---|---|---|---|---|---|---|---|
| **Revolver** | Single-action revolver | 6 | 0.25 s | 1.2 s | 2° | 10 | Medium | **Implemented** |
| **Shotgun** | Double-barrel ("Double-Barrel") | 2 | 0.35 s | 1.5 s | 15° (cone) | 6 × 7 pellets | High | Best recoil jumper; pellet speed ±15% so the cone spreads out. **Implemented** |
| Semi-auto | Broomhandle-style pistol | 10 | 0.15 s | 1.6 s | 3° | 7 | Low | Fast follow-ups |
| **Automatic** | Drum-fed early machine gun ("Machine Gun") | 40 | 0.06 s | 3.0 s | 6° | 4 | Low per shot, sustained | Long reload; firing down mid-air gives a slow, steady lift for as long as the drum lasts. **Implemented** |

Current tuning (recoil in px/s; a recoil jump from a standing jump while holding fire straight down): revolver 184 (6 shots ≈ 205 px), shotgun 340 (2 shots ≈ 220 px, in a fraction of a second), machine gun 64 (≈ 135 px over ~2 s). Ammo/attachment slots: revolver 4, shotgun 3, machine gun 5. Each gun is drawn differently in the hunter's hands: the revolver held out in both hands, the long guns shouldered with the support hand under the fore-end (shotgun: wooden stock and side-by-side barrels; machine gun: boxy receiver, drum magazine and a vented cooling jacket). Heavier guns kick harder in the hands and have bigger muzzle flashes. The HUD shows big magazines as a row of cartridge ticks instead of chamber pips.

Until weapon pickups exist, every run starts with one of each implemented gun in the three weapon slots.

### 5.4 Era scope
Old designs up to roughly **WW2-era** firearms (e.g. crossbows, blunderbusses, flintlocks, revolvers, lever-action rifles, double-barrel shotguns, Gatling and Maxim guns, bolt-action rifles, early submachine guns), styled to fit the dark-fantasy world. No modern tactical firearms. Specific weapon roster **[Later]**.

### 5.5 Ammo types & attachments (implemented, roadmap step 3)
Each gun has its own number of slots for them (revolver 4, shotgun 3, machine gun 5), separate from its chamber count. **Simple per-slot modifiers:** every filled slot applies on its own and order doesn't matter (no Noita-style ordered stacking). **Ammo types stack** — every ammo type in a slot applies to every shot, so a gun loaded with several gets all their effects at once. Items are **pure data** (src/items.lua) over the gun's stat block; a gun's *effective stats* (`Gun:stats()`, cached until the slots change) are its definition with every fitted item applied, and the weapon panel, HUD, recoil and firing all use them. Stat multipliers multiply, additions add, and effect counts add up (two explosive rounds make a bigger blast). Dragging items in the weapon panel fits them (that UI already existed); hovering an item shows what it does. No colour-coded rarity for now.

| Ammo | Effect |
|---|---|
| Heavy Slug | +50% damage, ×2 impact, ×1.3 recoil, tighter (×0.7 spread), 15% slower fire |
| Piercing Rounds | passes through 1 enemy, +1 dig power, −10% damage |
| Ricochet Rounds | bounces off rock up to 2 times |
| Explosive Rounds | bursts on impact: a **wide blast** (radius 26, damage 10, falling off toward the edge; each extra explosive ammo +6 radius, +4 damage) that hurts and shoves enemies and loose objects, but takes only a **small bite out of the terrain** (crater about a quarter of the blast radius, power 1.5), so it is not a tunnelling tool (mining attachments are planned separately). **It hurts the hunter too** (same falloff, with the usual hurt knockback and invulnerability). -20% damage, 20% slower fire. Multi-pellet shots scale the blast down so a shotgun is not seven explosions. |
| Incendiary Rounds | sets enemies alight: 3 damage/s for 3 s (stronger and longer when stacked), refreshed by hits |
| Scatter Shot | +2 pellets, −40% damage per pellet, ×1.6 spread |

| Attachment | Effect |
|---|---|
| Long Barrel | +25% bullet speed, ×0.7 spread, +10% damage |
| Extended Magazine | +50% chambers, 15% slower reload |
| Recoil Compensator | −40% recoil |
| Speed Loader | −40% reload time |
| Hair Trigger | −25% time between shots, +30% spread |
| Choke | halves the spread |
| Powder Charge | +50% recoil (bigger recoil jumps), +15% damage, +30% impact |

**Getting them (for now):** dropped by broken crates (wooden 12%, iron 40%) and dying monsters (10%) as little glowing crates in the item's colour; they never despawn, are picked up by walking over them when there's a free loose item slot, and are then fitted in the weapon panel. Finding and buying them properly arrives with the chests and shop (steps 5–6).

### 5.6 Item bar & weapon panel
Noita-style, along the top-left of the screen:
- **3 weapon slots** (keys **1–3** or the mouse wheel select one; the selected slot is outlined in gold), followed by **7 slots** for loose ammo types and attachments.
- **Tab** opens the weapon panel in the middle of the screen and **pauses the game**. Each carried weapon gets a card with its stats and its own ammo/attachment slots. Anything in a slot can be dragged to another slot (dropping on a full slot swaps them); weapons only go in weapon slots, ammo/attachments everywhere else. Hovering shows the name. Tab or Escape closes it.
- The inventory belongs to the run: it carries over between areas and resets on restart. All carried guns keep reloading, held or not.

### 5.7 The full item list: 53 ammo types & attachments, with rarity (implemented)

Every item has a **rarity**: **Common** (grey rim, drops most, ~20-35g), **Rare** (blue rim, ~45-70g) or **Cursed** (red rim, ~35-55g; powerful with a real downside). Drop and shop weights are 70 / 24 / 6. Each is pure data in `src/items.lua`; effects are applied in `src/guns.lua` (stats), `src/bullets.lua` (flight and impact) and `src/player.lua` (side effects).

**Original 13:** Heavy Slug, Piercing Rounds (rare), Ricochet Rounds, Explosive Rounds (rare), Incendiary Rounds, Scatter Shot - Long Barrel, Extended Magazine, Recoil Compensator, Speed Loader, Hair Trigger, Choke, Powder Charge.

**New ammo (20):**

| # | Name | Rarity | Effect |
|---|------|--------|--------|
| 1 | Frost Rounds | common | Hits slow the enemy to under half speed for 3s |
| 2 | Shock Rounds | rare | A hit arcs lightning to 2 nearby enemies for half damage |
| 3 | Venom Rounds | common | Poison: steady damage for 5s |
| 4 | Vampiric Rounds | rare | Kills heal 3 HP |
| 5 | Gilded Rounds | common | Kills spill 50% more gold |
| 6 | Sticky Bombs | rare | Bullets stick (to terrain or an enemy) and detonate 0.8s later |
| 7 | Seeker Rounds | rare | Bullets curve toward the nearest enemy |
| 8 | Singularity Rounds | rare | Impacts drag nearby enemies toward the point |
| 9 | Auger Rounds | common | Bigger craters, digs hard rock |
| 10 | Splitting Rounds | common | On impact, splits into two weaker bullets |
| 11 | Boomerang Rounds | common | Turn around after a short flight and hit again |
| 12 | Acid Rounds | common | Enemies take +30% damage from everything for 4s |
| 13 | Concussive Rounds | common | Huge impact and a stun, half damage |
| 14 | Spectral Rounds | rare | Fly through terrain, stop only on enemies |
| 15 | Executioner Rounds | rare | Double damage to enemies under 30% health |
| 16 | Glowing Rounds | common | Bullets light up the dark; +10% damage |
| 17 | Cluster Rounds | rare | Burst into three small bombs on impact |
| 18 | Featherweight Rounds | common | Faster bullets, less recoil, faster fire, less damage |
| 19 | Blood Rounds | **cursed** | +90% damage, +15% crit; every shot costs 1 HP (never lethal) |
| 20 | Unstable Rounds | **cursed** | Explosive, +75% damage, faster fire; 1 shot in 5 explodes in your face |

**New attachments (20):**

| # | Name | Rarity | Effect |
|---|------|--------|--------|
| 21 | Burst Fire | common | Bursts of three, then a pause |
| 22 | Backblast | common | Also fires a weaker bullet backwards |
| 23 | Primer Coil | common | First shot after each reload deals double damage |
| 24 | Suppressor | common | Triple damage to sleeping enemies; quieter |
| 25 | Laser Sight | common | Shows the aim line; tighter spread |
| 26 | Bayonet | common | Kick deals triple damage |
| 27 | Overclock | rare | 35% faster fire, but overheats and dumps the magazine after ~9 rapid shots |
| 28 | Magnetic Loader | common | Gold within 90px flies to you |
| 29 | Muzzle Lantern | common | Lights the dark around you while held |
| 30 | Jump Jets | rare | +30% recoil, and recoil lifts you almost as much on the ground |
| 31 | Mortar Breech | rare | Every fifth shot is a big explosive round |
| 32 | Scavenger Bolt | common | Kills refill a chamber / speed a reload |
| 33 | Quickdraw Holster | common | First shot after switching to the gun deals double damage |
| 34 | Glass Barrel | rare | Double damage, half the chambers, slower reload |
| 35 | Hunter's Scope | rare | +20% crit chance (crits deal double damage); tighter spread |
| 36 | Weighted Stock | common | Much tighter spread, less recoil, slightly slower fire |
| 37 | Penetrator Rod | rare | Bullets pass through two enemies |
| 38 | Stabilizer Grip | common | Standing still makes shots almost perfectly accurate |
| 39 | Dead Man's Mag | **cursed** | 2.5x chambers and +20% damage; reloads over twice as long, 30% slower fire |
| 40 | Reckless Trigger | **cursed** | 55% faster fire and +25% damage; triple spread and you take 25% more damage |

### 5.7b Weapon grades, the weapon card and dropping weapons

- **Grade:** every generated weapon has a **grade from D to S** (grey, green, blue, purple, orange) for how good its rolls are: the sum of how much better or worse each rolled stat (damage, fire rate, reload, spread, bullet speed, impact, magazine) came out than the archetype's base, plus 0.03 per slot above the usual count, cut at 0.10 / 0.19 / 0.27 / 0.35. Shop weapons cost 12g more per grade above D. The grade shows on the weapon card, the hover tooltip, the shop prompt and the compare prompt.
- **Weapon card (Tab):** per weapon: a framed icon with its slot number, the name, the archetype, a grade badge at the right, then nine stats in three columns (Damage, Rate in shots per second, Reload, Magazine, Spread, Impact, Recoil, sustained DPS, Crit), each with its **change against the archetype's base in percent** (green better, red worse), any special effects, and the ammo/attachment slots.
- **Hover card:** moving the mouse over a weapon lying on the ground, or on a shop pedestal, shows a **vertical card** above it: name, the **grade letter in the grade's colour**, archetype and damage, shots per second and DPS, chambers and slots, in a box bordered in that colour, so you know what it is before taking it. (Swapping one in also raises the card briefly.) The grade letter is coloured everywhere it appears: the Tab card badge, the tooltip, the shop prompt, the compare prompt and the cards.
- **Dropping weapons:** any weapon, **even the last one**, can be dragged **off the bar**, like ammo and attachments, and lands at the hunter's feet (pick it up again with E).
- **Bare hands:** keys 1-3 and the mouse wheel select a weapon slot **whether or not it holds a weapon**; an empty slot means the hunter carries nothing (he can still kick and move, and nothing shoots or reloads). A weapon picked up goes into the selected slot if it is empty, otherwise the first empty one.

### 5.7a Weapon slots roll with the weapon

A generated weapon's number of ammo/attachment slots is rolled: from **2 fewer** than the archetype's base up to **5 more**, weighted toward the middle (10% -2, 12% -1, 28% 0, 22% +1, 14% +2, 8% +3, 4% +4, 2% +5). Double-barrels and machine guns carry a **-1 bias** so they average fewer slots (about 2.9 and 3.7; revolvers and broomhandles average about 4.7). Minimum 1. Slot count is shown in the weapon stats and raises a shop weapon's price.

### 5.8 Perks (implemented)

Passive upgrades for the run. They have no slot and cannot be dropped. They appear **only in the shop**: three perk pedestals sit at the far left, past the healing pedestal; the three perks are rolled (never repeating ones you own) when you walk in. They are **free - take one and the other two vanish.** Perks have the same rarities as items. Taken perks show as small badges under the item bar (hover them in the weapon panel for their text). Implemented in `src/perks.lua`.

| # | Perk | Rarity | Effect |
|---|------|--------|--------|
| 1 | Thick Skin | common | +25 max health |
| 2 | Iron Will | rare | +50 max health |
| 3 | Second Wind | rare | First lethal hit of the run leaves you on 30% health |
| 4 | Scar Tissue | common | Take 15% less damage |
| 5 | Last Stand | rare | Below 30% health, deal 50% more damage |
| 6 | Regeneration | rare | Heal 1 HP every 3s |
| 7 | Bloodthirst | common | Heal 2 HP per kill |
| 8 | Adrenaline | common | Being hurt makes you 35% faster for 3s |
| 9 | Springheel | common | Jump 15% higher |
| 10 | Fleet Foot | common | Walk 15% faster |
| 11 | Slick Soles | common | Slides carry far more momentum |
| 12 | Double Jump | rare | One extra jump in mid-air |
| 13 | Prospector | common | Gold picked up is worth 25% more |
| 14 | Haggler | common | Shop prices 20% lower |
| 15 | Lucky Find | rare | Monsters drop items 2.5x as often |
| 16 | Magnetic Pockets | common | Gold is drawn from 2.5x further |
| 17 | Sharp Eyes | common | +10% crit chance on every gun |
| 18 | Heavy Hitter | common | +15% damage on every gun |
| 19 | Quick Hands | common | Reload 20% faster |
| 20 | Momentum | rare | Each kill: +6% fire rate for 4s, stacking to 5x |
| 21 | Pyromaniac | rare | Every shot ignites |
| 22 | Ricochet Master | rare | Every bullet ricochets once |
| 23 | Needle Sight | rare | Every bullet pierces one extra enemy |
| 24 | Death Burst | rare | Killed enemies explode, hurting others (never you) |
| 25 | Kicker | common | Kick deals triple damage |
| 26 | Glass Cannon | **cursed** | +60% damage, but 40% less max health |
| 27 | Devil's Bargain | **cursed** | Gold worth double, but you take 50% more damage |
| 28 | Greedy Hands | **cursed** | +60% gold and 30% off the shop, but healing costs double |
| 29 | Berserker | **cursed** | Fire 40% faster, reload 30% faster, but 70% wider spread |
| 30 | Pact of Pain | **cursed** | Kills heal 6 HP and kicks hit triple, but you bleed 1 HP every 3s (never to death) |

### 5.9 Starting a run

A run starts with a single **Revolver** that has rolled like a generated weapon: a random stat variation, a random slot count, and a 50% chance of one (never cursed) ammo type or attachment already fitted - so every run starts differently. The shotgun and machine gun come from chests, drops and the shop.

### 5.10 The shop layout

The shop room is 700 px wide. Left to right: a **DPS dummy** on a little practice range (80 px, ending at a chalk line and a barrel), three free perk pedestals, the healing pedestal, two weapons, eight ammo/attachment pedestals, the merchant, and the hatch at the far right. The dummy is at the far left so missed shots hit the shop's brick wall, never the hatch chain.

### 5.11 Reloading, reload animations and casings

- **Reload animations** are per gun model and keyed to reload progress, so reload-speed modifiers speed them up and slow them down: the revolver tips up, ejects its shells, takes rounds from the belt and snaps the cylinder shut; the double-barrel breaks open, drops two hulls, reloads from the belt and flicks shut; the Broomhandle gets a clip pressed in from the top and its slide racked; the machine gun drops its drum, slaps on a new one and hauls the charging handle.
- **Casings** (2-4 px) fly out on every shot from pistols and machine guns. Revolvers and the double-barrel keep spent shells until the reload ejects them. Casings tumble, bounce with a tick, and disappear after 10 seconds (max 250 at once).
- **Reloads don't carry over:** only the held gun reloads. Switching away mid-reload cancels it (it restarts when you switch back). Exceptions: the **Holster Loader** attachment (that gun keeps reloading holstered) and the **Juggler** perk (all guns do).

### 8a. Enemy animation

- **Ghoul** (10x18): grey, ghost-pale and hunched. It shuffles with its arms trailing and dragging behind it, kicking up dust. To attack it rears back (arms raised behind its head, jaw open) for 0.4s, then lunges and flings both arms forward.
- **Bat** (10x7): a bigger bat with ears, finger-boned wings and fangs. Once it has line of sight and is within 130px it locks on: it hangs still with its wings spread and shaking, screeches for 0.55s, then dives in a straight line at where the hunter stood. A bite sends it flying off; hitting rock or missing leaves it dazed/recovering. Without line of sight it just flutters closer and never dives.

## 6. World & Terrain

- **Pixel terrain, destructible, static materials.** Bullets and explosions carve holes in terrain. Detached chunks/debris may fall. Gas, water, fire and smoke are simulated separately from the terrain (§6c); terrain itself does not burn or flood.
- Built so a full falling-sand simulation (sand, liquids, fire, gas) can be added later without a rewrite.
- **Materials (initial):** e.g. dirt (easy to destroy), rock (harder), bedrock (indestructible, used for area bounds).

## 6c. Gas, water, fire and smoke (`src/fluids.lua`)

A sparse grid of 4-px cells per substance, simulated only within ~400x270 px of the hunter (everything farther away is frozen as it was) and drawn from the same grid. Terrain is only read, never changed.

- **Gas** (poison, yellow-green): a concentration 0-1 per cell that **diffuses slowly** through open space - faster downward (it is heavy), a little upward, thinning as it spreads and vanishing below ~1%. Pools start at 0.85; **vents** on pool floors keep feeding gas (up to ~0.9) so a pool refills slowly after it spreads or burns. Gas is drawn as a glowing, drifting haze whose alpha follows the concentration. **Breathing it hurts:** 3 HP x (0.6 + concentration) every 0.5 s while the head or middle is in gas above 12%, ignoring invulnerability and without knockback; the view tints green. Monsters aren't hurt by gas.
- **Fire** (orange flames that flicker, yellow-white when young): a cell lives about as long as its fuel - a fraction of a second in open air, up to ~1 s in thick gas. **Burning gas:** each flame ignites gas within two cells (75% per 0.1 s tick), turning it to fire (and some smoke), so a flame runs through a cloud as a fast, rolling flash fire that consumes the gas. Fire hurts the hunter (5 HP per 0.5 s, none while swimming) and sets monsters alight (the usual burn, 3 dps for 2.5 s; cinder wisps are immune). Sources: **incendiary rounds** (ignite gas they pass through), **explosions** (all gas in the blast ignites, plus scattered flames), burning monsters (they ignite gas around them), **cinder wisps** (a flame every 0.2 s), a **bloater** that dies burning, the campfire.
- **Smoke:** grey, rises with a sideways drift and thins out (decays about 2.5% per tick). Made by burning gas, flames dying out, steam (fire meeting water) and the campfire (its smoke is now real). It is drawn as single pixels dithered by density and re-rolled six times a second, so it reads as fine drifting grit.
- **Edges:** cells are simulated at 4 px but gas and water are drawn at 2 px and only where the terrain is not, so they follow slopes and cave walls instead of the grid (a piece next to rock also fills in when a neighbouring cell is filled).
- **Water:** blue cellular water: each cell falls, then slides diagonally, then flows sideways toward a drop within 6 cells, otherwise rests, so surfaces settle flat; it displaces gas and puts out flames. It is drawn in front of the hunter (lit) with a rippling lighter surface. **Swimming:** in water the hunter walks at 60% speed, sinks slowly (gravity x0.3, falling at most 90 px/s), is slowed by drag, and swims up while jump is held (up to 95 px/s); he splashes on entering or leaving. Monsters in water have burning put out.
- **Where:** water pools in low spots in every area (Catacombs 8 pools, Sunken Hollows 36, Sulfur Vents 6) and a small oasis pond on the surface; gas only in the Sulfur Vents (§7d). Pools use the same basin flood-fill (cells within a level 14-44 px (water) or 22-52 px (gas) above a floor spot; fills that pour down a hole or spread past ~4000 cells are dropped; never near the entrance or the shop).
- Cost: about 0.8 ms per frame on average with a large pool burning.

## 6a. Physics Objects

Loose objects (crates now; later barrels, debris, dynamite, physics-based projectiles) are **Box2D rigid bodies** via `love.physics`, as in Noita: they tumble, spin when hit off-centre, stack, slide and come to rest.

- **One world gravity**, shared with the player. Each object type sets its own **gravity scale** (how strongly world gravity affects it — Noita's floaty feel comes from objects having a low scale) and its own **mass**. Together these define an item's "weight" and how far forces throw it.
- **Terrain collision:** the pixel terrain is traced into collision outlines, split into chunks, so destroying terrain only rebuilds the outlines of the chunks it touched. Chunks are traced **on demand**, only around moving objects, so the large world needs no up-front tracing; objects placed by generation start asleep, and a dig only wakes objects near it.
- **Forces on objects:** bullets apply their gun's impact force at the exact hit point; kicks apply a fixed impulse. Heavier objects move less from the same force.
- **Player interaction:** the player stays on precise pixel movement (not a physics body), but:
  - can **stand** on objects, and is carried along by them,
  - **pushes** objects by walking into them (heavier objects push slower),
  - **kicks** them,
  - blocks objects falling onto them.

### 6a-i. Impact damage
A moving physics object hurts what it hits, judged by its **momentum** (mass × speed, in the same units as a kick's impulse) at the moment of impact — measured just before the physics step, since the collision itself changes the velocity. Damage = (momentum − 90) / 25, rounded down; below 90 an object just bumps. A kicked crate (momentum ≈ 270) does about 7, an iron crate or a big falling rock far more, and slow or resting objects nothing. Currently **enemies take it**: only the **object's own motion** counts (never the target's), so a creature walking or lunging into a resting crate takes nothing. A hit also **knocks the enemy back** along the object's path by its momentum (speed gained = momentum ÷ the enemy's weight, capped at 340 px/s, plus a small hop and a brief stun): a kicked crate shoves a ghoul (weight 2.5) about 20 px and flings a bat (0.6) much further; spitters cling to their rock and aren't moved. Each object can hurt a given enemy at most once per second. `props.impactDamage(prop, vx, vy)` is the shared rule so the hunter, other objects and future projectiles can use it later. Tuning constants are in props.lua.

### 6b. Destruction rules
- A bullet digs a small crater (revolver: radius 4 px, power 1). Each pixel in range is removed with probability *power / hardness*: dirt and sand (1) break readily, sandstone and wood (2) take a couple of hits, rock (3) chips slowly. Bedrock and brick never break.
- Terrain that gets cut loose (no longer connected to bedrock/brick) **falls as physics debris**: it becomes a rigid body carrying its own pixels, with mass from its materials. Tiny pieces (< 15 px) crumble to particles; A **floating mass larger than 100 px stays where it is - still solid terrain that can be dug at like any other**; only once digging shrinks it to 100 px or fewer does it turn into physics debris and fall (the 100-px threshold is `MAX_FALLING_PIXELS` in destruction.lua, which also keeps the connectivity search cheap). Fallen debris is **breakable**: it crumbles to particles once damaged for about 40% of its pixel count (at least 6), so bullets, kicks, explosions and thrown objects can finish it off. Up to 60 debris bodies exist at once.

## 7. Procedural Generation
- Each area is generated at the start of the run/area: caves and tunnels carved through terrain, a guaranteed traversable path from the entrance to the **shop room** at the end.
- The path must be reachable with walking + jumping + recoil jumping.
- **Area 1 ("The Catacombs")**: 2880×3100 px (the full width of the world, directly under the overworld; areas were 1920×3680 until 2026-10-11 and were made wider and a little shorter), a **descending** cave. Dirt pockets in rock (more dirt near the top), organic caves (cellular automata, with rounded ceilings near the top), **large open caverns** spread down its depth (up to ~640×380 px; ragged edges, flatter floors, 3–6 rock ledges each), a timber-ledged entrance chamber at the top under the mine shaft, and the brick shop room at the bottom. Everything that is counted (caverns, crossings, ore veins, monsters, crates, chests, glowing clusters) scales with the area's size, from counts tuned for the old 1920×3680 (×1.26 now: about 9–10 caverns, ~75 monsters).
- **Multiple intertwining routes:** four routes (one wide, three narrower) lead from the entrance down to the shop, each built from **vertical drops** (220–480 px, now and then a slanting one) alternating with **level corridors** (300–1000 px) that only wander gently up and down — so a route never climbs and is easy to walk and fall through. Extra corridors and drops scattered across the cave (13 and 8) cut through the routes, so they cross into each other and you can switch between them.
- **The funnel to the shop:** the lowest 30% of each area narrows toward the shop, wherever it was placed: outside a funnel whose half-width shrinks from the whole area to 270 px at the bottom (with a ragged edge), nothing is carved, so sloping rock walls lead down and inward from both sides. Routes, caverns and corridors in that band stay inside it (corridors there always head toward the shop), and it ends in a **bowl-shaped antechamber** right over the shop whose floor curves down to the drop into the shop's ceiling. Whichever way the hunter explores the bottom of an area, he is drawn to the shop.
- **Never fails:** the finished area is checked with a reachability search (a coarse 4×4-px grid); if no route is found a straight emergency tunnel is carved. Seeds are shown on the area banner.

### 7a. Overworld ("The Barrens")
Hand-built and the same every run, 2880 px wide (the width of the areas below): a **desolate desert at dusk** — dusty sand over banded red sandstone over gently rolling ground, tall canyon walls closing off each end, a violet-to-ember evening sky with a low setting sun, long thin clouds lit from below, a few early stars, three parallax layers (far hazy mountains, then two rows of mesas, the nearer with the stumps of ruined towers), vultures circling high over the mine, drifting dust haze, wind lifting sand off the ground, and tumbleweeds rolling west past the hunter. Dry grass tufts and pebbles are strewn along the ground. Left to right:

- **West badlands:** a boulder, a tall mesa with a **chest on top** (reachable by recoil jumping), a natural sandstone arch, dead trees and a small horned skull.
- **The hunter's camp (spawn, x 990):** a canvas lean-to with a bedroll and a lantern on a post, a smoking **campfire**, crates, and a practice range just west with a **DPS dummy** (§8) and crates to kick.
- **The walk to the mine (~650 px, ~6 s):** open, gently rolling ground with nothing in the way — a signpost ("Old Mine >"), the half-buried bleached ribcage and horned skull of some great beast beside the path, a dead tree.
- **The old mine:** a rail track with an ore cart at the top runs down an eased **ramp** (lantern posts at its top and bottom) into a dug-out **pit** about 64 px deep with a floor of grey-brown spoil (tailings). The timber-lined **shaft** drops from the middle of the pit floor straight into the catacombs' entrance chamber. A tall timber **headframe** (two leaning legs, crossbeams and X-braces, a slowly turning sheave wheel, a hanging lantern) stands over the shaft and is visible from the camp; a back-brace and the hoist rope run east to a plank **winch house** with a lit window. The far side of the pit climbs back up in two timber-shored steps (each a normal jump).
- **East:** spoil heaps, a boulder, crumbling **ancient ruins** in breakable stone brick (broken pillars, a lintel fragment, a low wall remnant, a fallen column and a gateway with a **chest** under it), an iron crate, a second mesa and dead trees, then the canyon wall.

Warm evening ambient light, not night; the camp, the lanterns and the winch house window are lit.

### 7b. The Catacombs
The generated area (above) under the dark-fantasy palette: the light blends from the warm surface ambient to dim but readable cave light as the hunter goes underground (the sunlight fades with it), and the backdrop behind the rock gets gloomier with depth. Entering it shows the "The Catacombs" banner; clusters of glowing teal fungus scattered across the cave floors (they light the way), and a candlelit stone shop room with wall sconces and candles on the counter.

### 7c. The Sunken Hollows
The second area, reached by dropping through the first shop's hatch into a timber-lined shaft that opens into its entrance chamber. It follows the same generation and layout (routes of drops and corridors, large caverns, chests, crates, gold ore, monsters - tougher by 0.6 toughness than the first area), under a **cold palette**: dark grey-blue **slate** for rock and **blue clay** with cold-green moss for earth, a darker, bluer ambient light and backdrop, and **lots of green glowing mushrooms** (480 clusters, brighter and larger-lit than the first area's 150 teal ones) as the main light. Chests there are better equipped. Its shop at the bottom has a hatch down into the Sulfur Vents.

### 7d. The Sulfur Vents
The third area, below the Hollows' shop hatch, built the same way (monsters another 0.6 toughness up) under a **sulfur-and-poison palette**: crusted yellow **sulfur rock** (bright sulfur crust on exposed tops) and olive **bile clay** with sickly green moss, a murky yellow-green ambient light, an olive-black backdrop and far rock pillars, and clusters of pale **sulfur crystals** with glowing tips as the light sources. Its end is the Sulfur Queen's arena (below).

**The arena.** The last quarter of the area (from 75% of its height down) is one **huge boxy chamber**, about 1500 px wide (52% of the world's width, narrow enough to force the fight in) and 400 px tall, with a flat slab floor, rounded corners and **twelve platforms in a V from the middle**: a low pair just either side of the centre (36 px up, 56 px apart), then each one further out 32 px higher (a jump) and a short hop across, six to a side, so the hunter can climb either arm. Every route in the area ends in its ceiling, so the whole cave funnels into it (the funnel to a single shop is not used here). There are no ordinary monsters, crates, chests or gas pools in it. **Five braziers** (stone bowls of real fire that never go out, `fluids.addBrazier`) stand along the floor: gas that drifts into one ignites and the flash runs through the whole connected cloud. In the floor, about 170 px in from each end (a shop sits under each, at 30% and 70% of the world's width), is a **shaft 43 px wide, about 160 px deep, down into a shop's ceiling**, shut by an **iron gate** until the boss is dead.

**The Sulfur Queen** (1400 HP x1.5 per area below the first = 2800 here, 24 contact damage; a bloater six times the size, 84x84, with a gold crown and a glowing gem) waits asleep in the middle of the arena and wakes when the hunter comes within 560 px inside it. **She is fast and tracks him hard:** she flies at 78 px/s (x1.35 and x1.7 in later stages) with 260 px/s² of acceleration, aiming where he is *going* (his velocity counts) to a point 80 px above him, and never leaves the arena. **She is immune to fire** and **flies through everything inside her arena** (the platforms, rock and walls: nothing stops her, she is only held within the arena's bounds), so the fight is about out-fighting her gas, not burning her. Her attacks come constantly, three stages by health:

| Stage | Gas | Volleys | Calls | Gas columns | Extra |
|---|---|---|---|---|---|
| 1 (above 66%) | breathes gas every 0.38 s, radius 36 | 3 acid globs every 2.2 s | a bloater every 6 s (up to 4) | 2, every 8 s | |
| 2 (33-66%) | every 0.28 s, radius 44; a burst of gas and a roar on entering | 5 globs every 1.8 s | **wisps** every 4.5 s (up to 5): their flames light her gas | 3, every 7 s | 35% faster |
| 3 (below 33%) | every 0.2 s, radius 52; burst on entering | 7 globs every 1.4 s | bloaters and wisps (up to 6) | 4, every 6 s | 70% faster; every 4.5 s she **swells for 1.2 s and bursts a huge cloud** (radius 96, full strength) |

**Gas columns.** Every few seconds vents crack open across the arena at 2-4 places (spread over its width with some jitter): for 1.4 s a pale beam flickers from floor to ceiling and dust jumps up, then **dense gas pours up through the whole 400 px height for 8 seconds**, in a column 64 px wide, and walls that part of the arena off. Standing in a column does **9 damage every 0.5 s** (a thin cloud does 3-5), more than a gas cloud does, and the gas spreads out of the column afterwards. A new set, in new places, comes every 6-8 s, so the safe ground keeps changing. It is still gas: the braziers or incendiary rounds will burn a column in a flash.

The globs do 12 damage (x2.0 at this depth). The braziers and the wisps ignite her gas, which burns the hunter (and the minions) but not her: a burning cloud is a hazard to stay out of, and a way to clear gas. Killing her drops the usual boss loot (about double the gold, four items and a weapon) and **opens both gates**.

### 7e. After the Queen: two shops, two paths
The arena's two shops sit at the left and right bottom (a fifth in from each edge), each a normal shop with a DPS dummy, its own stock and perks, and a **hatch**. The left hatch leads to **The Cinder Warrens** (area 4a: scorched basalt and ash, ember light, ghouls, bats, spitters, **wisps** and swarms) and the right to **The Drowned Halls** (4b: slate and blue clay, cyan glowcaps, a great deal of water, hoppers, spitters, bloaters). Each is a normal generated area of half the world's width (1440 px) directly under its side of the arena, with the usual funnel to a last shop with no hatch yet. They are placeholders for the real areas (monsters one more area tougher, health x3.7 and damage x2.05 against the first area).

**The lock-out:** the moment the hunter steps into one shop's room, the shaft above the **other** shop collapses: filled solid with that area's breakable rock, with a rumble and a banner ("The Way Behind You Collapses"). It stays reachable only by **digging** it out (or by going back up from the chosen shop through its own shaft, then digging down the other side). Leaving a shop still locks its goods, as before.

**Poison gas:** about 20-29 pools (34 tried for) settle in **low spots**, each with a crusted **vent** on its floor, and then **flow and burn** as in §6c: they drift outward over a minute or so, thinning, while the vents keep feeding them, and a spark (an incendiary round, an explosion, a wisp) sets the whole cloud alight. Gas sheds a sickly light, with wisps drifting through it. Stepping out of it doesn't reset the next damage tick.

## 8. Targets & Enemies

**Scaling per area:** monster **health** is multiplied by 1 + 0.9 per area below the first (plus up to +0.6 deeper within an area), **gold** drops scale with it, and **damage** (contact and acid globs) rises 35% per area (x1.35 in the Hollows, x1.7 in the Vents). Bosses scale less (health x1.5 and x2 in the second and third areas).
- **Test dummies / targets** in the test room, for checking damage numbers and hit detection.
- **DPS dummy:** a straw training dummy on a stand (burlap body with a painted target, crossbar arms, stitched head) at the left end of every shop, on the camp's practice range and in the test room, for checking guns. It is an enemy of kind `dummy` that never dies, moves or fights back, so **everything lands on it as on a monster**: crits, burning, poison, acid's +30%, shock arcs, blasts, sticky bombs, kicks and thrown crates. Over its head it shows **just the damage dealt, as a bare number** (no labels), gold while hits keep coming. A session starts with the first hit and keeps adding up; once **2 seconds pass without damage** it stops and the number freezes (grey) until the next hit starts a new one from zero. (The meter still keeps its time span internally, `dpsSpan` in `src/enemies.lua`, if DPS is wanted on screen again.) Hits in the same frame (shotgun pellets, a blast) count as one volley, and the time is padded by one average gap between volleys (six shots 0.25 s apart span 1.25 s but are a 1.5 s rate of fire); while a session runs, time since the first hit counts too, so reloads pull the reading down. Measured: a plain revolver (10 damage, 0.25 s, 6 chambers, 1.2 s reload) reads 24.1 DPS over 8 s of firing, against 24.5 in theory. (Executioner Rounds never trigger on it: it is never below 30% health.)
- **Enemies** (first batch), all pixel-collision creatures like the hunter: they collide with terrain **and physics objects** (crates, fallen debris) — standing on them, and ghouls shove crates in their way (and hop over them when chasing). While active, each has a kinematic physics stand-in, so falling crates and debris land on them; acid globs splash on objects and nudge them. Bullets hurt them (with knockback from the gun's impact force), kicks hurt and shove them, and being shot wakes them and sets them on the hunter. They notice the hunter only with a clear line of sight. Bullets start at the hunter's shoulder, so a monster pressed against him (closer than the muzzle) can still be shot.

| Enemy | HP | Behaviour | Damage |
|---|---|---|---|
| **Ghoul** | 30 | Hunched, ash-pale scavenger with red eyes. Shuffles about when idle; on sight (280 px) chases at 62 px/s (slower than the hunter), hops up ledges, and lunges when close. Gives up beyond 460 px. | 12 on contact |
| **Cave bat** | 8 | Hangs asleep from ceilings; on sight (210 px) flutters at the hunter, bites, veers off for 0.8 s, and comes back. | 6 on contact |
| **Spitter** | 20 | Fleshy sac clinging to a ceiling. On sight (300 px) swells up (0.45 s tell) and lobs an acid glob in an arc that lands on the hunter, every 2.4 s. Globs can be dodged or shot down. Falls if its rock is shot away. | 10 per glob |
| **Mire hopper** | 14 | A squat marsh toad. Idles with small hops; on sight (250 px) it crouches for 0.3 s (a tell), then leaps in an arc at the hunter every 1 s. A few in the Catacombs, everywhere in the Sunken Hollows. | 9 on contact |
| **Bloater** | 26 | A veined sac of gas with a glowing core. Floats from the ceiling toward the hunter (24 px/s), leaking a little gas every ~2 s; **bursts into a poison cloud** when killed, and a lit one if it dies in or near fire. Hollows (a few) and Vents. | 6 on contact |
| **Cinder wisp** | 10 | A fiery spark that flits at the hunter (58 px/s) in a wobbling line, **leaving a flame every 0.2 s** that burns him and ignites any gas; bursts into flame when killed; immune to fire. Vents only. | 7 on contact |
| **Swarm bat** | 5 | One of a colony of 8-12 that hangs together under a ceiling. **The whole swarm wakes together** (when one sees the hunter or is shot) and flocks at him as a fluttering cloud: separation, cohesion toward the swarm's centre, a wobble, and a quick (96 px/s) erratic flight; bites for 3 and veers off for 0.5 s. | 3 on contact |

- **Swarms:** colonies are placed under ceilings with room around them: Catacombs about 4 swarms (per 1920x3680, so ~5 at the real size), Hollows 2, Vents 2 more of bats and **3 flocks of 4-6 cinder wisps**, which flock the same way.
- **Area rosters:** Catacombs: ghouls, bats, spitters, a few hoppers, and the bat swarms. Sunken Hollows: hoppers (the commonest), bloaters, fewer ghouls, bats and spitters. Sulfur Vents: bloaters and wisps (the commonest), a few of the others.
- **Bosses (one per area, never respawn):** each is a larger version of a monster, placed once in the lower two thirds of the cave on a roomy floor, away from the entrance and the shop. They shrug off knockback and show a **health bar floating above their head** once awake or hurt: red, with no name and no outline, a smooth gradient down every pixel row (bright red at the top to deep red) with a faint lit top edge. When such a boss has noticed the hunter but **no part of it is on screen**, a **small, wide red triangle** on the screen edge points toward it (pulsing); it disappears the moment the boss is back in view. When one dies it drops **a lot of gold (about double the usual scaling), four items and a weapon**, with a burst of flame.

| Boss | HP | Behaviour | Damage |
|---|---|---|---|
| **The Dread Bat** (Catacombs, alternative to the Warden: each run picks one) | 600 | A bat three times the size (30x21). **Needs no line of sight:** once the hunter is within 560 px it wakes and flutters at him (held back by rock like any bat); within 420 px, every 2.4 s, it hangs and screeches for 0.85 s, then **dives in a straight line at where he stood at 250 px/s for up to 1.5 s, boring through everything in its path**: a 17-px-radius crater is dug every 5 px of travel just ahead of it (power 40, so dirt, sandstone, rock and gold ore all go; the pieces fall as debris and spray out as particles). Only bedrock and the shop's masonry and iron stop it (it is stunned for 0.4 s when it hits them). After a dive it recovers for 0.9 s. Hangs asleep from a ceiling at the start; faintly lit so its bulk can be seen in the dark. Tested: it cleared a 140-px sandstone wall (4300 to 500 solid pixels) to reach the hunter. | 18 |
| **The Ashen Warden** (Catacombs) | 500 | A giant ghoul (2x): lunges from 64 px at 170 px/s after a longer rear-back; chases at 50 px/s; hops ledges. | 22 |
| **The Mire Matron** (Sunken Hollows) | 650 | A giant hopper (2x): crouches half a second, then bounds in great leaps every 1.7 s; **every third leap she calls two hoppers** (at most four alive). | 20 |
| **The Sulfur Queen** (Sulfur Vents, in the arena, §7d) | 1400 | A giant crowned bloater (6x): fast and tracking, immune to fire, flies through everything in the arena; gas, volleys, gas columns, minions. | 24 |
| The Gas Behemoth (no longer placed; the Queen replaced it) | 800 | A giant bloater (2x): drifts at the hunter, **pouring out gas every 0.9 s**; bursting in fire it makes a huge explosion of burning gas. | 16 |

(Health shown is for the first area; multiply by 1.5 and 2.)

- **Placement:** each generated area places its monsters at generation: none near the entrance or in the shop, at least 48 px apart, and **more and tougher deeper down** (spawn chance 35% at the top to 100% at the bottom; HP up to ×1.6). About 75-90 per area (counts per monster kind are set per area, §8). Only monsters within ~520 px of the hunter are active.
- **Visibility:** every monster sheds a few purple motes that drift up and trail away (no halo or back-light), so they can be tracked in the dark.
- **[Later]** more types, respawning.

## 9. Economy & Shop **[Roadmap steps 1 and 6]**
- **Gold** (implemented, step 1) spills out as small coins that bounce on the terrain, glint (they're drawn emissive so they can be spotted in the dark) and are pulled toward the hunter within ~36 px, then collected on touch (a short delay after spilling). **A coin that has landed and isn't picked up vanishes 7 seconds later** (blinking for the last 1.5 s); its gold is lost, and being pulled toward the hunter restarts the timer. Coins are pixel-simulated like particles rather than Box2D bodies, so hundreds can lie around (cap 400; the oldest give way and their value carries on to the next coin). The run's total shows next to a coin icon under the gun status. **It resets every run** (no meta-progression for now).
- **Sources:** enemy drops (ghoul 3–6, bat 1–3, spitter 4–8, × the monster's toughness), **crates, which now break** from damage (wooden: 25 total, 0–4 gold; iron: 90, 5–12 gold) and splinter, and the dungeon itself: **gold ore** (rock veined with gold flecks, scattered through the cave walls — about 190 veins per area) spills a speck or two from a tenth of the pixels you dig out. Rare hidden chests in caverns come with the weapon chests (step 5).
- **Shop** (implemented, roadmap step 6): each shop room has, left to right: an **ivory healing pedestal** with a glowing heart, **one generated weapon** (30% chance per slot of a fitted item), and **4 different ammo types/attachments**, on stone pedestals with prices floating over them (gold, or red when you cannot afford them). Standing next to one shows "[E] Buy Name"; E buys it. Weapon price 45g + 25g per fitted item + 0-20g, items 20-35g. A weapon bought with all three slots full opens the **compare prompt** and is paid for only once you pick which gun to replace. **Healing:** each E on the pedestal heals 10% of max health, priced by how much is missing, **and by how deep the shop is**: (8g when nearly full up to 40g when nearly dead) x (1 + 0.8 per area below the first), so 8-40g in the first shop, 14-72g in the second and 21-104g in the third ("Already at full health" costs nothing). **The hatch:** an iron plate set into the floor at the right end of the room (indestructible terrain), held shut by a **chain hanging from the ceiling** - shoot the chain (or blow it up) and a moment later the plate drops away, opening a shaft down into the next area. **Leaving the shop locks it** (stepping out of the room after having been in it): nothing can be bought afterwards (the items dim and the prompt says the shop is closed). The stock is generated with the area, not restocked; selling is not possible yet.

## 9a. Items, finding & generating weapons **[Roadmap steps 1, 4, 5, 6]**
- **Pickups:** gold is collected by walking near it. **Ammo types, attachments and (later) weapons are picked up with E** while standing next to them (within ~18 px; a "[E] Name" prompt shows over the nearest one, and "No room" appears if the loose item slots are full).
- **Dropping:** dragging an ammo type or attachment out of its slot and releasing it away from every slot drops it on the ground by the hunter's feet (thrown a little in the direction he faces); it can be picked up again with E.
- **Finding weapons** (implemented, roadmap step 5): **weapon chests** (15 per area, plus two on the surface, on cave floors away from the entrance and the shop) - standing next to one shows "[E] Open chest". A chest holds **either gold (80%) or a generated weapon (20%), never both**: gold is 15-40 (more when deeper), and a weapon is better equipped the deeper the chest (a 15% chance per slot at the top rising to 60% at the bottom). **Monsters never drop weapons** (except the bosses, §8): the incentive is to play well down to the shop, where a better weapon can be bought. A weapon on the ground is drawn as its own icon with a pulse and glow and picked up with E. Guarded chests and altars at the ends of side routes are still to do.
- **Weapon slots:** picking a weapon up with a free weapon slot puts it straight in; with all three slots full it opens the compare prompt (below).
- **Weapon generation** (implemented, roadmap step 4; `guns.generate`): a weapon is a base archetype (revolver, double-barrel, **Broomhandle semi-auto pistol** — 10 chambers, 0.15 s, 1.6 s reload, 3° spread, 7 damage, low recoil — and machine gun; later rifle, crossbow) plus **rolled stat variance**: two stats rolled better (+8–18%), one worse (−5–12%), the rest nudged ±4% (a "capacious" roll always adds at least one whole chamber), named after its best roll ("Rapid Revolver", "Heavy Double-Barrel", "Longshot Machine Gun", "Accurate", "Swift", "Punching", "Capacious"). Each ammo/attachment slot has a 22% chance of already holding a random item (never the same one twice). It takes an optional random generator so chests, drops and the shop can all use it with seeds; adding a new archetype only means adding a definition. **F6** (debug) swaps the held weapon for a generated one, until chests and the shop exist.
- **Fourth gun - the compare/choose prompt** (implemented): the game pauses and shows the found weapon on top (icon, name, effective stats, fitted ammo/attachments) over the three carried ones. Click a carried weapon (on release) or press 1-3 to replace it - the replaced gun, with whatever was fitted in it, drops at the hunter's feet and can be picked up again; Esc, E or Tab cancels and leaves the found weapon where it lay.

## 9b. Menu & audio **[Roadmap steps 2 and 7]**
- **Menu** (implemented, step 2): the game opens on a **title screen** (Play, Quit) over the dimmed, paused world, and **Esc** during play opens a **pause menu** (Resume, Restart run, Title screen, Quit) — Esc no longer quits instantly (Esc still closes the weapon panel first). Navigate with W/S or the arrows and Enter/Space, or the mouse (hovering selects; a button fires on release, so the click never also fires a shot). Menus pause the game and swallow all other keys. R still restarts directly; settings (volume, keys) come later.
- **Audio** (implemented, roadmap step 7): placeholder sounds are **synthesised in code at start-up** (src/audio.lua: noise bursts, sine thumps and chirps with envelopes, 23 sounds): shots per gun, bullet hits and impacts, explosions, enemy death, the hunter being hurt and dying, coins, pickups, chests, buying and denied purchases, healing, reload, kick, menu clicks, the chain clank and hatch opening; plus looping beds - desert wind on the surface and a low drone underground, faded by depth. Each play varies pitch and volume a little; overlapping voices are capped. The mixer is silent if there is no audio device. Swap in real recordings later by loading files under the same names.

---

## 10. Milestone 1 — Build Order

1. **Movement + revolver in a test room** — Noita-style movement, recoil jumping, mouse aiming, the revolver firing 6 shots with auto-reload, test targets. Low-res scaled canvas in place.
1.5. **Physics objects** — Box2D crates with per-object weight/gravity scale, terrain collision outlines, bullet impact force, standing/pushing/kicking.
2. **Destructible pixel terrain** — bullets carve the terrain; materials with different toughness.
3. **Random dungeon generation** — one area with a guaranteed path to its end.
4. **Overworld + dungeon entrance** — hand-built walkable area leading into the dungeon.
5. **Shop room** — empty room at the end of the generated area.

**Done when:** you can walk from the overworld into the dungeon, shoot and recoil-jump your way through a randomly generated area, and reach the shop room. **Status: all steps implemented (2026-10-10), awaiting play-testing.**

After Milestone 1, add the shotgun, semi-auto, and automatic archetypes, then start designing ammo types and attachments. **Shotgun and automatic added 2026-10-11; semi-auto still to do.**

## 11. Roadmap
Order of work, by what unlocks what (items/pickups → loot → shop; ammo/attachments → weapon generation → shop; menu is independent):

1. **Pickup system + gold** — *done:* coins from enemies, breakable crates and gold ore, collected by walking near, gold counter on the HUD. (Weapon/item pickups arrive with steps 4–5.)
2. **Menu** — *done:* title screen and Esc pause menu.
3. **Ammo types & attachments** — *done:* 6 ammo types and 7 attachments as data, effective gun stats, drops from crates and monsters.
4. **Weapon generation** — *done:* archetype + rolled variance + chance of fitted ammo/attachments; semi-auto added; F6 debug key.
5. **Finding weapons** - *done:* chests (gold or a weapon), weapon pickups with E, the 4th-gun compare/choose prompt.
6. **Shop** - *done:* 3 generated weapons and 4 ammo types/attachments on pedestals with prices, bought with E.
7. **Audio** - *done:* generated placeholder sounds.
8. **Healing** - *done:* the shop pedestal. **Area 2** - *done:* the Sunken Hollows. **Area 3** - *done:* the Sulfur Vents with poison gas; areas widened, the funnel to the shop; the reworked overworld; the DPS dummy. **Then:** more enemy types (to give each area its own character), a boss, healing pickups, a run summary on death.

## 12. Open Questions
- Overworld size and contents for the long-term version.
