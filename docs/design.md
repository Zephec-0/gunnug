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
- **Character:** a lanky, slim **Van Helsing-style hunter**, drawn as pixel limbs on a procedural skeleton rather than sprite frames. His head is mostly a tall, wide-brimmed hat worn low, the brim pulled down to two glowing eyes peering from the shadow beneath; he wears a slim long dark coat with a crimson lining and a **light-grey shoulder mantle** (part of the coat, its loose end trailing in the wind), dark trousers and buckled boots, and carries an engraved dark-steel revolver. Legs walk via inverse kinematics, both hands grip the gun and follow the aim, the gun kicks on firing, legs tuck when rising and dangle when falling, the kick extends a leg, landings dip the body, and he has crouch and slide poses. The coat tails and mantle tail follow the motion with simple secondary physics. **Since 2026-10-14** the hat comes down to the shoulders (the brim sits two pixels over the neck, so only the eyes peek out between brim and mantle; the crown and brim are drawn apart from the face so hats can be swapped later), and the coat lining and the death burst use the ether's teal instead of crimson.

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

**Bosses.** The larger versions of ordinary monsters (the Ashen Warden, the Mire Matron, the Dread Bat, the Gas Behemoth and the Sulfur Queen) are drawn at their own size with their own, more detailed art rather than being the small sprite scaled up: the Warden has a dented iron half-helm, a spiked pauldron, manacles with chains, ribs showing through its rags and bone spikes down its back; the Matron a crest of bone spines, purple warts, a pulsing throat sac and a mouth of small teeth; the Dread Bat shaggy fur, big ears, fangs and wings of veined, ragged membrane over finger bones; the gas bags (Behemoth, Queen and her remnants) a mottled, pustuled, veined sac with pores, a toothed mouth and swaying tendrils, the Queen with a gem-studded crown. They share the small monster's animation states.

**Shop.** A market hall: perk daises with glowing runes that brighten (and shed sparks) as you approach, a hooded merchant behind a counter who breathes, blinks and follows you with their eyes (and sleeps when the shop closes), a lantern, a red floor runner, swaying banners, a barrel and crates. Cave backgrounds have two layers of far scenery that scroll slower than the terrain, **different in every area** (`src/parallax.lua`): the old mine has far rock pillars and ruined timber frames (some fallen) with lanterns glimmering in the distance; the Sunken Hollows giant glowing fungi, hanging roots and drifting spores; the Sulfur Vents crystal spires and vent chimneys breathing pale steam; the Cinder Warrens basalt columns and glowing lava falls with rising embers; the Drowned Halls a drowned colonnade of arches, swaying chains and wavering light from above.

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
| **Gatling** | Old crank-style six-barrel rotary gun in a brass frame ("Gatling Gun") | 150 | 0.03 s (the fastest) | 6.0 s | 7° | 4 | Very low per shot | **Spool-up:** holding the trigger winds the barrels up over 1.1 s (a dry ratchet clicking faster and higher); it starts firing at 20% (about 0.2 s) and fires up to 5x slower until fully spun; the barrels wind down when let go or holstered. Then about 30 rounds/s (the machine gun ~17). The hopper on top takes 6 s to refill. Drawn with turning barrels and a turning crank; the HUD wraps its belt into rows of 50. 3 slots (one fewer on average). **Implemented** |

Current tuning (recoil in px/s; a recoil jump from a standing jump while holding fire straight down): revolver 184 (6 shots ≈ 205 px), shotgun 340 (2 shots ≈ 220 px, in a fraction of a second), machine gun 64 (≈ 135 px over ~2 s). Ammo/attachment slots: revolver 4, shotgun 3, machine gun 5. Guns lying on the ground or on shop pedestals show their item-bar model at half size (each 2x2 block averaged). Each gun is drawn differently in the hunter's hands: the revolver held out in both hands, the long guns shouldered with the support hand under the fore-end (shotgun: wooden stock and side-by-side barrels; machine gun: boxy receiver, drum magazine and a vented cooling jacket). Heavier guns kick harder in the hands and have bigger muzzle flashes. The HUD shows big magazines as a row of cartridge ticks instead of chamber pips.

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
- **3 weapon slots** (keys **1–3** or the mouse wheel select one; the selected slot is outlined in gold), followed by **11 slots** for loose ammo types and attachments.
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

### 5.7c The fuser and fused items (implemented; `src/fuser.lua`, `items.fusions`)
- **The fuser** sits on the item bar right after the 11 loose slots: **two slots** in a teal frame with a "+" between them, a **switch toggle**, and an **ether gauge** under the slots. Drag two items in (with the weapon panel open, Tab), then lock them with the toggle (click it in the panel) or the **Fuse key (G**, rebindable). Only pairs with a recipe lock ("These two won't fuse" otherwise); hovering the toggle says what they make (named once the save file has found it, else "something new").
- **Ether:** while locked, every monster killed gives up **1 ether** (a boss, or miniboss, **10**: it counts as ten kills) as tiny **neon teal sparks (1-2 px, glowing, with a faint light)** that burst from the body and stream to the hunter, charging the gauge as they arrive (a glassy blip each, rising in pitch as it fills). **20 ether fuses** (`fuser.NEED`; balance later): the two items become the fused one, left in the first slot, with a burst of sparks and a bright chord. Locked items can't be dragged out.
- **Releasing early:** toggling a locked fuser unlocks it and **loses the ether**: it spills out of the hunter as sparks that fall, settle on the ground glowing and fade over a few seconds (sparks still in flight drop too).
- **Fused items** (rarity **Fused**, teal rim; never found, dropped or sold): made from two **common** items, keeping both effects with the downsides trimmed:

| Fused | From | Effect |
|---|---|---|
| Thermal Shock Rounds | Incendiary + Frost | Burns and chills; +10% damage |
| Hellfume Rounds | Incendiary + Venom | Burns and poisons, no damage loss |
| Blight Rounds | Venom + Acid | Poisons and corrodes (+30% damage taken), eats rock |
| Sledge Rounds | Heavy Slug + Concussive | +60% damage, huge impact, stun |
| Shrapnel Rounds | Ricochet + Splitting | 2 bounces and splits; -10% damage |
| Birdshot | Scatter + Featherweight | +3 fast pellets, less recoil |
| Sungold Rounds | Gilded + Glowing | +75% gold, glowing, no damage loss |
| Corkscrew Rounds | Auger + Boomerang | Bores hard rock, comes back |
| Marksman Barrel | Long Barrel + Choke | +35% speed, 65% tighter, +20% damage |
| Drum Loader | Extended Magazine + Speed Loader | +50% chambers, 30% faster reload |
| Braced Frame | Recoil Compensator + Weighted Stock | 60% less recoil, 45% tighter, no slowdown |
| Ripper Trigger | Hair Trigger + Burst Fire | Bursts of three, 25% faster, no spread penalty |
| Prospector's Lamp | Magnetic Loader + Muzzle Lantern | Wide light, gold magnet 140 px |
| Deadeye Rig | Laser Sight + Stabilizer Grip | Laser, steady aim, half spread |
| Duelist's Kit | Primer Coil + Quickdraw Holster | Both double-damage shots; +10% damage |
| Assassin's Edge | Suppressor + Bayonet | Triple damage on sleepers, triple kick |
| Twin Blast | Powder Charge + Backblast | Rear shot, +20% damage, +50% recoil |

- **Levelling (+1 to +4):** two of the **same common** item fuse into one a level up. An item at **+N works as N+1 copies fitted together** (its multiplied stats raised to the power N+1, its added effects times N+1): two plain ones make +1, two +1s make +3, a +3 and a plain one make +4; nothing goes past **+4**. Levelled items show "+N" in their name and **N light teal plus signs** along the bottom of their icon (one per level: +1 one plus, +4 four). (The small square teal pip in the top corner is separate and means "could be fused".) Rare, cursed and fused items don't level, and a levelled item doesn't go into a two-item recipe.
- **The toggle** is a switch standing on end, in chunky icon-sized pixels: a 7x11 pill filling its slot with a flat 3x3 knob (no shine) that slides up when on (the pill lit teal) and down when off (dark).
- **The always-visible bar is drawn at 80% size** (so it clears the health display at the top right); the weapon panel keeps full size.
- **Guns fill their slots:** each gun model (they come in different sizes, from the revolver to the Gatling) is scaled to fill 92% of its slot, whatever its size: drawn crisp at a whole-number scale into a canvas and then scaled smoothly to the exact size, so no gun looks small or oversized next to another. **Fuse hints:** any loose item on the bar (or waiting in an unlocked fuser) that has a partner it could be fused with gets a small pulsing teal pip in its top-left corner.
- **In the compendium** every common item has entries for +1 to +4 right after it (the item tabs are 10 wide, so a common and its four levels fill half a row; commons come first, then rare and cursed, then fused); a levelled entry says how it is made. Fused items are listed after the commons in the Ammo and Attachments tabs; a found one shows "Fused from A + B"; an unfound one shows "Try fusing A + B" once both are found, else "Made in the fuser from two common items". New recipes: add the item to `FUSED`/`items.fusedOrder` and a line to `items.fusions` in `src/items.lua`, and an icon in `src/icons.lua`.

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
- **Grid (baseline for every liquid and gas):** all four share a sparse grid of **2-px cells** (halved from 4 px), nearly pixel-fine. Water moves a cell per 0.025 s step (80 px/s falling, sideways flow searches 12 cells) and only cells that may move are processed: one that can't goes to sleep until a neighbour moves, and every 1.5 s all water near the hunter is woken (in case the rock under it was dug). Gas diffuses with weights doubled for the finer cells; smoke steps every 0.05 s; flames reach about as far in pixels as before. Water is drawn a pixel row at a time: only cells on the edge of the water check the rock pixel by pixel (so edges hug the terrain), single-cell dips in the surface are drawn filled, the edge gradient is one strip image, and the body is see-through enough (74%) that the hunter and fish in it show. Gas is batched into a few point draws by brightness. Cavegen still hands pools over on its 4-px grid; each cell fills four. **Splash sound:** one short splash (a slap and a quick burst of spray, about 0.2 s) plays both going into water and coming out. **Digging wakes water:** removing terrain wakes the water around the hole at once (`fluids.wake`, called from `src/destruction.lua`), so it starts to run within about 0.1 s instead of waiting for the periodic sweep.

A sparse grid of 4-px cells per substance, simulated only within ~400x270 px of the hunter (everything farther away is frozen as it was) and drawn from the same grid. Terrain is only read, never changed.

- **Gas** (poison, yellow-green): a concentration 0-1 per cell that **diffuses slowly** through open space - faster downward (it is heavy), a little upward, thinning as it spreads and vanishing below ~1%. Pools start at 0.85; **vents** on pool floors keep feeding gas (up to ~0.9) so a pool refills slowly after it spreads or burns. Gas is drawn as a glowing, drifting haze whose alpha follows the concentration. **Breathing it hurts:** 3 HP x (0.6 + concentration) every 0.5 s while the head or middle is in gas above 12%, ignoring invulnerability and without knockback; the view tints green. Monsters aren't hurt by gas.
- **Fire** (orange flames that flicker, yellow-white when young): a cell lives about as long as its fuel - a fraction of a second in open air, up to ~1 s in thick gas. **Burning gas:** each flame ignites gas within two cells (75% per 0.1 s tick), turning it to fire (and some smoke), so a flame runs through a cloud as a fast, rolling flash fire that consumes the gas. Fire hurts the hunter (5 HP per 0.5 s, none while swimming) and sets monsters alight (the usual burn, 3 dps for 2.5 s; cinder wisps are immune). Sources: **incendiary rounds** (ignite gas they pass through), **explosions** (all gas in the blast ignites, plus scattered flames), burning monsters (they ignite gas around them), **cinder wisps** (a flame every 0.2 s), a **bloater** that dies burning, the campfire.
- **Smoke:** grey, rises with a sideways drift and thins out (decays about 2.5% per tick). Made by burning gas, flames dying out, steam (fire meeting water) and the campfire (its smoke is now real). It is drawn as single pixels dithered by density and re-rolled six times a second, so it reads as fine drifting grit.
- **Edges:** cells are simulated at 4 px but gas and water are drawn at 2 px and only where the terrain is not, so they follow slopes and cave walls instead of the grid (a piece next to rock also fills in when a neighbouring cell is filled).
- **Water:** teal cellular water: each cell falls, then slides diagonally, then flows sideways toward a drop within 6 cells, otherwise rests, so surfaces settle flat; it displaces gas and puts out flames. It is drawn in front of the hunter (lit), nearly opaque: a deep blue-green body (about rgb 33,79,107) that lightens toward its edges in a smooth gradient (to about 69,138,143), with a faint grain, now and then a glint, and a pale, rippling surface line. **Swimming:** in water the hunter walks at 60% speed, sinks slowly (gravity x0.3, falling at most 90 px/s), is slowed by drag, and swims up while jump is held (up to 95 px/s); he splashes on entering or leaving. **Breath:** with his head under water, three bubbles hang over his head and pop one a second (3 s in all); with none left he **drowns**, taking 4 damage every half second (the empty rings flash red) until he is out of the water, where the bubbles come back in about a second. Monsters in water have burning put out. **Pools of water** are common in every area (about 30 in the Catacombs, 60 in the Hollows, 22 in the Vents, 14 and 100 in the two last areas, as many as basins allow), 20-64 px deep.
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
**The old mine.** Area 1 is dressed as an abandoned mine (`area.mine`, generated by `cavegen`, drawn by `src/minedecor.lua`): **rail tracks** laid along level stretches of floor (sleepers, rails, a buffer stop), many with a **minecart** (a physics prop: an iron-bound box heaped with ore that can be kicked, shot open for gold and loot); **timber shoring** between floor and ceiling, either standing (two posts, a cap beam, braces), **half fallen** (one post snapped, the beam hanging from the other) or **collapsed** into planks on the floor; **oil lanterns** hanging from the beams and on lamp posts (they flicker and light their surroundings); **skeletal remains** (lying, slumped against a wall in a hard hat, a skull pile, scattered bones), **pickaxes** stuck in the ground or left beside the dead; **stalactites** (cones of real, shootable rock, 6-24 px long, hanging from ceilings with room left under them so no passage is blocked; the other areas have some too); and **TNT barrels** (below).

**Old TNT.** A barrel with a red-stencilled label. It has 12 HP: once damaged enough (a bullet, a blast, a thrown cart) it fizzes, blinking white for 0.15-0.3 s, and goes off as an explosive blast (radius 38, damage 36 at the centre, a 13-px crater) that hurts the hunter, monsters and other props, so barrels set each other off in a chain.

The generated area (above) under the dark-fantasy palette: the light blends from the warm surface ambient to dim but readable cave light as the hunter goes underground (the sunlight fades with it), and the backdrop behind the rock gets gloomier with depth. Entering it shows the "The Catacombs" banner; clusters of glowing teal fungus scattered across the cave floors (they light the way), and a candlelit stone shop room with wall sconces and candles on the counter.

### 7c. The Sunken Hollows
The second area, reached by dropping through the first shop's hatch into a timber-lined shaft that opens into its entrance chamber. It follows the same generation and layout (routes of drops and corridors, large caverns, chests, crates, gold ore, monsters - tougher by 0.6 toughness than the first area), under a **cold palette**: dark grey-blue **slate** for rock and **blue clay** with cold-green moss for earth, a darker, bluer ambient light and backdrop, and **lots of green glowing mushrooms** (480 clusters, brighter and larger-lit than the first area's 150 teal ones) as the main light. Chests there are better equipped. Its shop at the bottom has a hatch down into the Sulfur Vents.

### 7d. The Sulfur Vents
The third area, below the Hollows' shop hatch, built the same way (monsters another 0.6 toughness up) under a **sulfur-and-poison palette**: crusted yellow **sulfur rock** (bright sulfur crust on exposed tops) and olive **bile clay** with sickly green moss, a murky yellow-green ambient light, an olive-black backdrop and far rock pillars, and clusters of pale **sulfur crystals** with glowing tips as the light sources. Its end is the Sulfur Queen's arena (below).

**The arena.** The last quarter of the area (from 75% of its height down) is one **huge boxy chamber**, about 1500 px wide (52% of the world's width, narrow enough to force the fight in) and 400 px tall, with a flat slab floor, rounded corners and **twelve platforms in a V from the middle**: a low pair just either side of the centre (36 px up, 56 px apart), then each one further out 32 px higher (a jump) and a short hop across, six to a side, so the hunter can climb either arm. Every route in the area ends in its ceiling, so the whole cave funnels into it (the funnel to a single shop is not used here). There are no ordinary monsters, crates, chests or gas pools in it. **Five braziers** (stone bowls of real fire that never go out, `fluids.addBrazier`) stand along the floor: gas that drifts into one ignites and the flash runs through the whole connected cloud. In the floor, about 170 px in from each end (a shop sits under each, at 30% and 70% of the world's width), is a **shaft 43 px wide, about 160 px deep, down into a shop's ceiling**, shut by an **iron gate** until the boss is dead.

**The Sulfur Queen** (1000 HP x2 here = 2000, 24 contact damage; a bloater six times the size, 84x84, with a gem-studded gold crown and a glowing core) waits asleep in the middle of the arena and wakes when the hunter comes within 560 px inside it. **She fights in a cycle**, not a constant spray: she hovers high over the arena, drifting along it after the hunter (90-150 px/s); picks an attack and **tells you** (she stops dead and swells, the whole sac glowing, motes drawn into her); carries it out; and then she is **spent**: she sinks to the hunter's height, **dazed (stars over her head) and taking 50% more damage** for 1.9-2.8 s (0.8 s longer after a dash), then hovers again. She is immune to fire, flies through rock and platforms, and never leaves the arena; a dodge roll slips through her globs and her dash. A faint leak of gas from her sac is all she breathes now; the arena is no longer a gas soup.

| Attack | Telegraph | What it does |
|---|---|---|
| **Fan** | swells 0.9 s | three fans of 9 (11 in the last stage) gas globs over an 86-degree arc aimed at the hunter, 0.5 s apart, each with a **two-glob gap** to slip through |
| **Dash** | swells 1.1 s, with a **dotted line** showing her path (it follows the hunter, then flickers faster and locks for the last 0.3 s) | barrels across the arena along the line at 560 px/s for 0.9 s, leaving a trail of gas |
| **Bloom** | swells 1.3 s | bursts: a cloud of gas and a ring of 14 globs with a two-glob gap (from stage 2) |
| **Vents** | 0.7 s | gas columns crack open across the arena (each shows a beam of warning first) (from stage 2) |
| **Spawn** | 0.7 s | calls bloaters, then wisps |

Cycles: stage 1 (above 66%) fan, dash, fan, spawn; stage 2 fan, bloom, dash, vents, fan, dash; stage 3 (below 33%) fan, dash, bloom, dash, vents, fan, dash, bloom, with shorter pauses and recoveries. Below a third of her health she **splits once** into two smaller Queens (what she had left divided between them, each weaker), which only fan and dash, and both must die. The globs do 14 damage (x2.0 at this depth). Killing her drops the usual boss loot (about double the gold, four items and a weapon) and **opens both gates**.

### 7e. After the Queen: two shops, two paths
The arena's two shops sit at the left and right bottom (a fifth in from each edge), each a normal shop with a DPS dummy, its own stock and perks, and a **hatch**. The left hatch leads to **The Cinder Warrens** (area 4a: scorched basalt and ash, ember light, ghouls, bats, spitters, **wisps** and swarms) and the right to **The Drowned Halls** (4b: slate and blue clay, cyan glowcaps, a great deal of water, hoppers, spitters, bloaters). Each is a normal generated area of half the world's width (1440 px) directly under its side of the arena, with the usual funnel to a last shop with no hatch yet. They are placeholders for the real areas (monsters one more area tougher, health x3.7 and damage x2.05 against the first area).

**The lock-out:** the moment the hunter steps into one shop's room, the shaft above the **other** shop collapses: filled solid with that area's breakable rock, with a rumble and a banner ("The Way Behind You Collapses"). It stays reachable only by **digging** it out (or by going back up from the chosen shop through its own shaft, then digging down the other side). Leaving a shop still locks its goods, as before.

**Poison gas:** about 20-29 pools (34 tried for) settle in **low spots**, each with a crusted **vent** on its floor, and then **flow and burn** as in §6c: they drift outward over a minute or so, thinning, while the vents keep feeding them, and a spark (an incendiary round, an explosion, a wisp) sets the whole cloud alight. Gas sheds a sickly light, with wisps drifting through it. Stepping out of it doesn't reset the next damage tick.

## 8. Targets & Enemies

**Scaling per area:** monster **health** is multiplied by 1 + 0.9 per area below the first (plus up to +0.6 deeper within an area), **gold** drops scale with it, and **damage** (contact and acid globs) rises 35% per area (x1.35 in the Hollows, x1.7 in the Vents). Bosses scale less (health x1.5 and x2 in the second and third areas).
- **Test dummies / targets** in the test room, for checking damage numbers and hit detection.
- **DPS dummy:** a straw training dummy on a stand (burlap body with a painted target, crossbar arms, stitched head) at the left end of every shop, on the camp's practice range and in the test room, for checking guns. It is an enemy of kind `dummy` that never dies, moves or fights back, so **everything lands on it as on a monster**: crits, burning, poison, acid's +30%, shock arcs, blasts, sticky bombs, kicks and thrown crates. Over its head it shows **just the damage dealt, as a bare number** (no labels), gold while hits keep coming. A session starts with the first hit and keeps adding up; once **2 seconds pass without damage** it stops and the number freezes (grey) until the next hit starts a new one from zero. (The meter still keeps its time span internally, `dpsSpan` in `src/enemies.lua`, if DPS is wanted on screen again.) Hits in the same frame (shotgun pellets, a blast) count as one volley, and the time is padded by one average gap between volleys (six shots 0.25 s apart span 1.25 s but are a 1.5 s rate of fire); while a session runs, time since the first hit counts too, so reloads pull the reading down. Measured: a plain revolver (10 damage, 0.25 s, 6 chambers, 1.2 s reload) reads 24.1 DPS over 8 s of firing, against 24.5 in theory. (Executioner Rounds never trigger on it: it is never below 30% health.)
- **Enemies** (first batch), all pixel-collision creatures like the hunter: they collide with terrain **and physics objects** (crates, fallen debris) — standing on them, and ghouls shove crates in their way (and hop over them when chasing). While active, each has a kinematic physics stand-in, so falling crates and debris land on them; acid globs splash on objects and nudge them. Bullets hurt them (with knockback from the gun's impact force, 60% less while they are in the air), kicks hurt and shove them, and being shot wakes them and sets them on the hunter. They notice the hunter only with a clear line of sight. Bullets start at the hunter's shoulder, so a monster pressed against him (closer than the muzzle) can still be shot.

| Enemy | HP | Behaviour | Damage |
|---|---|---|---|
| **Ghoul** | 30 | Hunched, ash-pale scavenger with red eyes. Shuffles about when idle; on sight (280 px) chases at 62 px/s (slower than the hunter), hops up ledges, and lunges when close. Gives up beyond 460 px. | 12 on contact |
| **Cave bat** | 8 | Hangs asleep from ceilings; on sight (210 px) flutters at the hunter, bites, veers off for 0.8 s, and comes back. | 6 on contact |
| **Spitter** | 20 | Fleshy sac clinging to a ceiling. On sight (300 px) swells up (0.45 s tell) and lobs an acid glob in an arc that lands on the hunter, every 2.4 s. Globs can be dodged or shot down. Falls if its rock is shot away. | 10 per glob |
| **Mire hopper** | 14 | A squat marsh toad. Idles with small hops; on sight (250 px) it crouches for 0.3 s (a tell), then leaps in an arc at the hunter every 1 s. A few in the Catacombs, everywhere in the Sunken Hollows. | 9 on contact |
| **Bloater** | 26 | A veined sac of gas with a glowing core. Floats from the ceiling toward the hunter (24 px/s), leaking a little gas every ~2 s; **bursts into a poison cloud** when killed, and a lit one if it dies in or near fire. Hollows (a few) and Vents. | 6 on contact |
| **Cinder wisp** | 10 | A fiery spark that flits at the hunter (58 px/s) in a wobbling line, **leaving a flame every 0.2 s** that burns him and ignites any gas; bursts into flame when killed; immune to fire. Vents only. | 7 on contact |
| **Tunnel worm** | 14 (halved again 2026-10-15) | A long, thin burrower (17 thin segments, a 4-px head). Coiled out of sight in solid rock until the hunter is within 300 px (no line of sight needed), then **swims through anything but bedrock and masonry at 108 px/s (20% slower since 2026-10-14)** (never slowed by the rock), swinging its head toward him (and where he is heading) and bursting to 172 px/s as it nears the surface close to him, so it **leaps out of the ground at him**. **The moment its head breaks into open air it has no control at all**: it flies on the speed it had, with gravity and a little drag (the only place it loses speed), its body dragging behind, until its head touches the ground or a wall again and it dives back in at full speed. Can be hit anywhere along its length; the body hurts too (60%). Its sounds are only heard as it gets close. | 5 head, 3 body (halved on 2026-10-14) |
| **Skeleton miner** | 22 | Shambles after the hunter and keeps its distance (backs off inside 80 px, closes beyond 150), then lights a **stick of dynamite** (0.55 s tell with the fuse sparking over its head) and lobs it in an arc every 3.2 s. The stick bounces and goes off 1.6 s later (a blast of 1.2x a basic explosive round, which also hurts monsters); **shoot it out of the air to set it off early**. Its hat lamp lights it. | 9 contact, blast 12+ |
| **Cave roller** | 30 | An armoured grey pillbug. Crawls (30 px/s); within 190 px with a clear line it **curls into a ball** (0.55 s tell, shaking) and **rolls at 165 px/s for up to 2.8 s**, bouncing off walls (usually back toward the hunter), smashing crates, hurting 1.3x as much. Curled or rolling it takes **30% of all damage** (sparks); spent, it uncurls **dizzy for 1.5 s** (stars over its head) and takes **150%**, then rests before rolling again. | 12 (x0.4 crawling) |
| **Piranha** | 8 | A small toothy fish (silver, dark back, red belly, an underbite of white teeth), in schools in the cave pools (one per ~80 pool cells, up to six a pool). Swims freely; once any part of the hunter (head, middle or feet) is in the water within 190 px it closes in (62 px/s), aiming at his feet when those are the wet part, and **darts** at him from 64 px (240 px/s for 0.22 s, every ~0.9 s). Before its first bite it never swims out; **after its first dash or bite it is set on him for good** (follows up to 480 px), leaping out of the surface after him when he is on land, and **out of the water it flops along in short hops** toward him. | 4 on contact, in or out of water |
| **Swarm bat** | 5 | One of a colony of 8-12 that hangs together under a ceiling. **The whole swarm wakes together** (when one sees the hunter or is shot) and flocks at him as a fluttering cloud: separation, cohesion toward the swarm's centre, a wobble, and a quick (96 px/s) erratic flight; bites for 3 and veers off for 0.5 s. | 3 on contact |

- **Swarms:** colonies are placed under ceilings with room around them: Catacombs about 4 swarms (per 1920x3680, so ~5 at the real size), Hollows 2, Vents 2 more of bats and **3 flocks of 4-6 cinder wisps**, which flock the same way.
- **Area rosters:** Catacombs: ghouls, bats, spitters, a few hoppers, the bat swarms, and the old mine's skeletal miners (the commonest after ghouls), cave rollers and tunnel worms. The worms, miners and rollers appear in every deeper area too, in smaller numbers (rollers and worms are common in the Cinder Warrens; the Drowned Halls have few miners). Sunken Hollows: hoppers (the commonest), bloaters, fewer ghouls, bats and spitters. Sulfur Vents: bloaters and wisps (the commonest), a few of the others.
- **Bosses (one per area, never respawn):** each is a larger version of a monster, placed once in the lower two thirds of the cave on a roomy floor, away from the entrance and the shop. They shrug off knockback and show a **health bar floating above their head** once awake or hurt: red, with no name and no outline, a smooth gradient down every pixel row (bright red at the top to deep red) with a faint lit top edge. When such a boss has noticed the hunter but **no part of it is on screen**, a **small, wide red triangle** on the screen edge points toward it (pulsing); it disappears the moment the boss is back in view. When one dies it drops **a lot of gold (about double the usual scaling), four items, a weapon and a perk** (one the hunter does not have; it is left on the ground where the boss fell and taken with E, like an item but with no slot needed), with a burst of flame.

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
- **Gold** (implemented, step 1) spills out as small coins that bounce on the terrain, glint (they're drawn emissive so they can be spotted in the dark) and are pulled toward the hunter within ~36 px, then collected on touch (a short delay after spilling). **A coin that has landed and isn't picked up vanishes 7 seconds later** (blinking for the last 1.5 s); its gold is lost, and being pulled toward the hunter restarts the timer. Coins are pixel-simulated like particles rather than Box2D bodies, so hundreds can lie around (cap 400; the oldest give way and their value carries on to the next coin). The run's total shows next to a coin icon under the gun status. **It resets every run**; what carries over is **marks** (§11a-viii).
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
- **Menu** (implemented, step 2; `src/menu.lua`, `src/menubg.lua`): the game opens on a **title screen** — Continue (the last save file played, with its playtime and compendium %), Save Files (New Game when there are none), Compendium, Settings, Quit — in a column on the left, with the title lettering drawn crisp over the menu's dark wash. **Esc** during play opens the **pause menu** (Resume, Compendium, Settings, Restart run, Quit to title, Quit to desktop; the last three ask first, since the run is lost). Navigation is spatial: arrows/WASD move to the nearest control in that direction (so grids and rows work), Enter/Space chooses, left/right change sliders and switches, Q/E (or [ ]) switch tabs, Esc/Backspace or the right mouse button go back. The mouse hovers to select (only when it moves, so it doesn't fight the keys) and clicks on release, so the click never also fires a shot. Menus pause the game and swallow all other keys. Pages fade in briefly; the focused control has a pulsing steel-blue frame with white corner ticks.
- **The title backdrop: a black hole** (`src/menubg.lua`). Everything in the compendium — guns, ammo types, attachments, perks and monster portraits — drifts in from the edges of the screen and spirals down into a black hole right of centre, on a Keplerish orbit (slow and wide at the edge, whipping round near the hole; about 20 s from edge to rim), shrinking, reddening and stretching along its orbit as it goes, with a faint ember trail, until it is swallowed in a small cross-shaped flare on the rim (sometimes with a low sigh). ~700 dust motes (amber, violet, white) stream in on the same orbits and a field of stars twinkles behind. Drawn at 640x360 so it stays pixel art, in three passes: (1) a **nebula shader** (fbm noise wound into spiral arms round the hole, dusk violet with amber arms and a warm haze toward the centre, dark dust lanes) plus the stars, dust and falling things on their own canvas; (2) a **lens shader** onto the game canvas: light bent round the hole (a point at r is seen at r - k·rs²/r, giving an Einstein ring), red and blue split slightly near the edge, a swirling **accretion disc** of hot streaked gas, a burning **photon ring** and the black **event horizon**; (3) the game's usual bloom, grading and vignette. New compendium entries join the whirl automatically.
- **Settings** (`src/settings.lua`, saved to `settings.sav`, shared by all save files): **Audio** — master, music and sound-effect volumes (sliders in tenths); **Display** — fullscreen (also **F11** anywhere), vertical sync, bloom and colour grading on/off, FPS counter, pause when the window loses focus; **Controls** — every action rebindable with a main and a spare key (`src/input.lua`: move left/right, jump, drop through ledges, crouch/slide, dodge roll, kick, interact, weapon panel, weapons 1-3, restart run). Binding a key takes it off any other action; Delete clears one; Esc and the debug F-keys can't be bound. The mouse (fire, reload, switch) is listed but fixed. On-screen prompts ("[E] Open chest", "Press R to begin a new hunt", the weapon panel's hint) show whatever key is bound. Restore defaults / Reset controls buttons. (No key hints along the bottom of the screen.)
- **With the weapon panel open (Tab)** the current area's sound keeps playing but muffled (a low-pass filter on the music, the wind, the shop piano and one-off sounds), instead of the surface wind. **Audio** (implemented, roadmap step 7): sounds are **synthesised in code at start-up** (src/audio.lua, about 0.7 s): noise bursts, sine thumps and chirps with envelopes, with a soft limiter. **Each gun has its own voice**: the revolver a sharp crack over a deep thump with a ring, the double-barrel a long low boom with a blast tail, the Broomhandle a bright snap, the machine gun a tight tick; (reloads share the plain click and snap sounds). Monsters have sounds too (worm waking, digging, bursting and lunging, the miner's match and fuse, the roller curling and rolling). **Every area has its own ambient theme** (replacing the noisy background loops, in the spirit of Terraria's underground tracks: slow, sparse and quiet; every theme shares the Sunken Hollows' recipe, the favourite: slow pads, soft plucked notes, a deep sub and a long echo, built from chiptune voices (triangle, sine, pulse) played from note lists and looped), with a few quiet little events over it (drips, creaks, plops): the surface has just the desert wind; the old mine is a cave-like A-minor drift, the Hollows a low synth drift, the Vents a slow plucked bass-guitar line under the pads, the Warrens dark and smouldering in E phrygian, and the Drowned Halls slow echoing sine arpeggios. The themes crossfade by area and sit low in the mix. **Area 1 (the Catacombs) uses a recorded track instead of a synthesised theme:** `game/audio/caves.wav` (85.3 s, stereo), loaded into memory and looped (it starts over the moment it ends); **to swap the track, replace that file** (or point `AREA_FILES` in `src/audio.lua` at another): its volume is set automatically at load by measuring how loud the recording is and bringing it to a fixed loudness (`TARGET_RMS`), so a new file needs no tuning; if the file is missing the old synthesised theme plays. Other areas can be given recorded tracks the same way (`AREA_FILES` and `AREA_GAIN` in `src/audio.lua`). **In a shop room the area's theme fades out and a quiet jazz piano plays** (16 bars: a walking bass, sparse comping on the off-beats, a soft ride cymbal and a swung melody through seventh chords; it fades in and out as the hunter enters and leaves). Each play varies pitch and volume a little; overlapping voices are capped. The mixer is silent if there is no audio device. Swap in real recordings later by loading files under the same names.


## 9c. Save files & the compendium (implemented; `src/save.lua`, `src/compendium.lua`)
- **Three save slots.** A save file is a **profile**, not a mid-run save: runs stay roguelike and are lost on quitting, but everything a profile learns persists. Choosing a slot on the Save Files page starts a run with it (an empty one becomes a new hunter); each card shows the compendium count with a bar, playtime, runs, deaths, monsters slain, bosses, gold earned, the deepest area reached and when it was last played, and has a **Delete** button (asks first). Files live in the LÖVE save directory as `slotN.sav`, a plain Lua table literal loaded in an empty environment; the last good copy is kept as `slotN.bak`. The profile is written every 5 s while something changed, on death, on leaving to the title and on quitting.
- **What is recorded:** every weapon, ammo type and attachment that reaches the inventory (picked up, bought, or fitted to a gun that was) counts once per object, so dropping and picking up the same thing doesn't count twice; every perk taken in a run; every monster slain (a split Sulfur Queen counts once, when the last of her falls). Plus lifetime stats (runs, deaths, kills, bosses, gold, deepest area, playtime in a run).
- **"New in the compendium":** the first time a profile records something, a note slides in at the right of the screen (under the gold count) with its icon and a soft three-note chime.
- **The compendium page** (from the title screen, for any save file — switch with < > or Z/C — or from the pause menu for the one in play): tabs for **Weapons, Ammo, Attachments, Perks and the Bestiary**, each with its found/total count, and an overall "found / total (%)". A grid of entries (scrolls with the wheel when long; wide cells for guns and monsters) beside a detail panel: the picture on a dark plate (monsters **animated live**), the name, rarity (or Boss) and "Collected / Taken / Slain xN", the description and stats (guns: damage, chambers, fire delay, reload, spread, slots; monsters: health, damage, gold). Undiscovered entries are dark silhouettes named "???". Bosses have red frames; items their rarity's colour.
- **Adding content later needs nothing here:** the catalogue is built from `guns.defs`, `items.defs`, `perks.defs` and `enemies.defs` at start-up. Each module's order list (`guns.archetypes()`, `items.order`, `perks.order`, `enemies.order`) sets where an entry is listed; anything missing from it is listed after, by name. A gun's compendium text is its `desc` (or the DESCS table in `src/guns.lua`); a monster's name and notes come from the LORE table in `src/enemies.lua` (bosses keep their own `name`), and `compendium = false` keeps a kind out (the DPS dummy). Recording is by category and id, so old save files simply show new entries as undiscovered.
- **Menu sound** (`src/audio.lua`): on the title screens the world falls silent and **the void** plays instead — a deep, slowly beating hum (36 / 36.5 Hz) under a low roar of falling air with a thin glassy whistle drifting in and out — and a **menu theme** in the area themes' recipe: a slow, cold D-minor drift (Dm, Bb, Gm, A at 50 bpm) with soft pads, a deep sub, sparse sine plucks and a glassy pulse-wave bell line falling into a long echo. Both fade in on the title and out when a run starts. UI sounds: a tick on moving, a two-tone select, a softer falling "back", a page-turn click on tabs, the discovery chime, and the swallow sigh.

## 9d. Death recap & save names (implemented; `src/deaths.lua`, `src/menu.lua`)
- **Every save file has a name.** Choosing a slot with no name (a new one, or an old file from before names) opens **Name Your Hunter**: a text box (letters, digits, spaces, hyphens and apostrophes; up to 14 characters; Enter or Confirm, Esc or Back) before the run starts. The name shows on the save card, on Continue and in the pause menu, and the recap calls it back.
- **What killed him.** Everything that hurts the hunter names itself (`Player:hurt` / `hurtOverTime` take a source id): an enemy's kind (contact, a worm's body, a spitter's or the Queen's acid glob), "dynamite" (a miner's stick), "keg" (an exploding barrel), "selfblast" (his own explosive rounds), "gas", "fire" and "water" (drowning); anything else is "the Unforgiving Dark". The last thing to hurt him is the killer.
- **The death fade:** there is no separate "You Died" screen; after the hunter has fallen the world fades gradually darker (from 0.3 s to 1.5 s after death, to a dark wine tint at 80%), and the recap takes over with the same darkness, the world still showing behind it.
- **The recap** appears 1.5 s after death, once the fade has finished. The middle of the screen is one centred group: on the left a smallish **wanted poster** (tilted parchment with nails: "WANTED", a ruled picture box with the killer **printed straight onto the paper in brown ink**, like a woodcut, from a picture of the monster as it looked in the game the moment he died, and its name; the picture comes from the killer itself with `enemies.photo`, or a posed specimen for a worm, a spitter's glob or a split Queen; a killer that isn't a monster (gas, flames, water, a blast) gets a question mark), and beside it, centred on the poster, **You Died** with "**<Name> met his end by the <adjective> <killer>.**" (the adjective is picked at random from a list per monster: Starving Ghoul, Screeching Cave Bat, Toothy Piranha, Dynamite-Happy Skeleton Miner; bosses use their own name with Mighty, Merciless, Terrible or Dreaded; Choking Gas, Roaring Flames, Cold Black Water, Short-Fused Stick of Dynamite...) and a random **western quip** in quotes ("The buzzards will be along by sundown.", "Boots on, hat on, and not a soul to bury him."...). **The poster slams in:** the page is dark for 0.3 s, then the poster flies in from close to the screen (3.2x, spinning, accelerating) and **hits at 0.5 s** with a heavy thud, the whole page shaking and a puff of dust (no flash), with a little rebound; the rest of the page fades in as it lands. Buttons ignore presses for the first 0.9 s (the hunter's trigger finger). Just above the buttons: **New in the compendium**, one row per group that gained entries this run (Weapons, Ammo, Attachments, Perks, Bestiary): the group's title, then just the sprites, with no names ("Nothing new in the compendium this run." if none). Buttons: **New run** and **Quit to Menu**. New monsters get their name from `enemies.defs` (adjectives are added in `src/deaths.lua`, with general ones as the fallback).
- **Recap music** (`audio.setRecap`): a very slow, sad E-minor synth piece (Em, C, G, D at 42 bpm): soft pads, a deep sub, a lonely sine lead with a slow vibrato, a few distant bells and a long echo. It fades in with the recap and out when a run starts or the title returns.

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

## 11a. Direction after Milestone 1: runs, the camp and the compendium

*Agreed 2026-10-14. A plan, not yet built. Everything here is **[Later]** until a step below is started.*

### 11a-i. What a run is

- **Length:** a normal finish takes about **30 minutes**: a minute at camp, then roughly 4-5 minutes of main path per area, a couple of minutes for the Queen, and the rest in optional detours (vaults, events, elites) for players who want them.
- **Short runs still count.** Dying early must never feel wasted: compendium discoveries, quest progress, rescued NPCs and marks (below) are banked as they happen, not at the end.
- **Everything permanent is mostly sideways.** Permanent upgrades add *options and convenience* (more choices, new tools, a map, starting loadouts, new recipes) with only small stat bumps, so a first run and a fiftieth run still feel like roguelite runs.

### 11a-ii. World expansion (step 0: do this before anything else)

**Status (2026-10-14): the foundation is built.** Layout table, a world three times as wide (8640 px, extending *east* so the camp and the mine keep their places at the west end instead of moving to the middle), and the first side branch, **The Old Quarry**. What exists now:

- **Layout table** (`LAYOUT` in `scenes/catacombs.lua`): each area is `{ x, y, w, h, tier }` (plus `parent`/`side` for shop hatches, `entry` for a surface crevice, `rank` for the "deepest reached" record). `levelAt` is a rectangle lookup (the nearest area for points in gaps), `catacombs.layoutSize()` gives the extent and `catacombs.entries()` the surface crevices. Areas can be any size.
- **The world is 8640 px wide.** The main road is still the first 2880 px (`catacombs.SPINE_W`); everything east of it is open desert on the surface (mesas, boulders, ruined pillars, trees, a chest atop each far mesa, pots and crates) over unexplored rock for the branches to be carved from, with bedrock at the far east and bottom edges. The east is painted lazily (`World.lazyX`: a tile there is painted from the cells when it is first drawn or touched), so building the world costs about the same as before, and `World:fillFast` fills big plain regions row by row.
- **The Old Quarry** (area 6, `THEMES[6]`): a side branch 2880 px wide and only 2300 px tall at x 2880-5759, entered by a **crevice in the east desert at x 4300** (stone lip, lamp posts, plank-lined shaft) that drops into its entrance chamber. Pale cut sandstone and spoil, amber crystals and lamps, miners, rollers, worms and a lot of TNT; it counts as tier 2 for difficulty and rank 2 for the record, and borrows the Catacombs' music, far scenery and sounds (`theme.track`, `theme.parallax`). It is generated in the background after the main road, or at once when the hunter comes within 1500 px of the crevice (`catacombs.ensure(py, px)`). Its shop is a dead end for now.
- **Still to do for this step:** more branches (a west-side entrance is not possible with the camp at the west edge; branches go east, and a second column can be added by widening further), cross-cuts joining the branches to the main road, a vault or reward at the end of each branch, and varied depths for the main areas.

The world is 2880 px wide with every area the same size, stacked in rows (§3, §7). That is too small a stage for a hub that grows, side branches and quests. The plan:

- **Wider world.** Three times as wide (about **8640 px**, three columns of the current 2880), with the overworld a real, explorable desert across all of it. The main mine stays in the middle and the camp near it. The two flanks get their own **entrances**: a dry well or crypt in the west badlands, a canyon crevice or rail depot in the east.
- **A spine and branches, not a grid.** The main spine keeps its run: Catacombs → Sunken Hollows → Sulfur Vents → the Queen → Cinder Warrens or Drowned Halls. The side columns hold **branch areas** with their own themes, monsters and rewards, entered from their own surface entrances or from cross-cuts off the spine. (Names and themes for the branches are open, see §12.)
- **Depth does not have to match.** An area is a rectangle with its own width and height, not a cell in a row. Branches can be shorter (about 1800-2400 px) or longer than the spine's 3100 px, so the bottoms of the world are ragged: a quarry branch ends at a dead end with a vault, a flooded crypt keeps going. Areas can also be taller or wider than today's where it helps (a cavern-heavy area, a long narrow mine).
- **Cross-cuts.** Horizontal tunnels, collapsed passages and diggable seams join the spine to the branches at set depths, so a hunter can wander sideways and find a branch from below, and the world feels one piece. Some are hidden (dig or blast in).
- **Technical work this needs** (no design questions in it):
  - `catacombs.lua` finds an area by row from the top (`levelAt`, `levelHeight`) and builds each area's rectangle from the one above. Replace that with a **layout table**: each area has an `x0, y0, x1, y1`, a theme, and links (which shop hatch or cross-cut leads where). `levelAt(y, x)` becomes a rectangle lookup.
  - `overworld.lua` has `WIDTH` and `HEIGHT` as constants (`HEIGHT = CAVE_TOP + AREAS * CAVE_HEIGHT`); both come from the layout instead. The camp, headframe, ruins and so on keep their positions relative to the middle column.
  - Generation stays background-driven and in order, but now follows the layout's links (a branch is generated when the hunter nears a link to it, as the next area is today).
  - Memory: cells are one byte each in an FFI array (the unified world is ~38 MB now, ~115 MB at three times the width) and tiles allocate lazily, so this is affordable; fluids, lighting and enemies already work in a region around the hunter.
  - Save "deepest reached" and the compendium's area names key off area ids, not rows.
- **Pacing check:** a wider world must not lengthen the main path; the spine's path is unchanged and branches are optional. The 30-minute target is measured on the spine.

**Built so far from the revised layout (2026-10-14):**

- **The world is 11520 px wide, x -2880 to 8639.** `World.new(width, height, left, top)` takes an origin, so x and y may be negative (the sky dungeon will use negative y). Cells are stored per 256x256 tile, allocated when something is written in it; a tile filled whole (unexplored rock) is one id with no storage. `World:fillFast`, `markLazy` and `claim` paint unexplored regions on demand and let an area claim its own rectangle when it generates. Memory after generating every area is about 135 MB of Lua, and the world no longer needs bytes for ground nobody has seen.
- **Fixed:** the fluid grid's key stride (2048 cells) overflowed above x 4096 and could not hold negative x; it is now 16384 with an offset (`K`, `KOFF` in `src/fluids.lua`). Physics terrain chunks work at negative coordinates, and `World:get` floors fractional coordinates.
- **The west desert** (x -2880 to -1): mesas, boulders, ruined pillars, trees, chests and pots, and a shaft at x -700 (stone lip, lamp posts, plank lining) down to the flooded works.
- **The Flooded Caverns** (area 8, x -2800 to -401, 2400 x 2600): caverns under a **lake** in the west desert (a bowl about 760 px wide at x -900 that narrows to a neck dropping into the top of the cave, all of it water; no pit or shaft). `area.flood = { level }` floods every open cell below that depth (runs of 2-px cells made by `cavegen`, filled by `fluids` a slice per frame; shop rooms stay dry, `dry` in `fluids.lua`); piranhas through the water. Without the **Diving Helm** (`perks.defs.diving_helm`, `fx.diving`) the hunter drowns, which is the lock.
- **The Deep** (area 9, x -2800 to -401, 2400 x 1800): a flooded boss chamber under the galleries (arena 1730 x 1000), with the Matron as a placeholder boss. No braziers in a flooded arena.
- **The Foreman's Hall** (area 7, under the Quarry, 2880 x 800): a standalone boss arena the Queen's size (`arenaFrac`, `arenaH`, `arenaWidth` in the area spec), with the Warden as a placeholder boss. **It always drops the Diving Helm** (`bossReward`).
- **Water drawing** is now a shader that cuts rock out of whole runs of cells using the terrain mask, with the runs cached per grid row, so a flooded screen costs about the same as a dry one (it was 14 ms a frame, now well under 1). The old pixel-exact path is the fallback.
- **Generation dependencies:** `catacombs.generate(i)` completes an area and only the areas whose hatches lead to it; side branches entered from the surface need nothing, and are generated when the hunter comes within 1500 px of their shaft.
- **The Needle** (area 10, x 5800-8599, y -2900 to 1099): the vertical mountain at the east end. The desert ground rises on a long ramp (x 5350-5870, 120 px up) to a doorway in the mountain's face, with a lamp post. Inside is a deep cave whose routes **climb**: vertical shafts of 200-420 px with **ladders of one-way platforms** (a platform every 28 px, alternating sides; `info.platforms`, registered in `world.platforms` like the arena's), joined by level corridors. `area.climb`, `area.profile` (the silhouette: rows outside it stay sky) and `area.arenaCx` in `src/cavegen.lua`; it is dark inside although it stands above ground (`catacombs.indoors`). A summit arena (the Queen's size) holds a placeholder Dreadbat; killing it opens a gate in the roof and an exit shaft with a ladder up through the summit cap.
- **The Cloud Reaches** (area 11, x 0-8599, y -4300 to -2901): the sky dungeon above the mountain, entered by a hole through its floor where the exit shaft arrives. `area.open`: no caves, floating islands (flat-topped, tapering below) and spires over a 200 px floor, a shop at the far west end, the dusk sky behind. **Low gravity** (`theme.gravity = 0.35`; `config.gravity` is live, scaled by `catacombs.update`, and physics gravity follows).
- The world's top is now y -4400, with the sky and the mountain above the surface.
- **Still to build:** a real aquatic boss, the Quarry's real boss, a real mountain-top boss, the hub's buildings, clouds and scenery for the sky, and individuality for each dungeon. (The vertical mountain and the sky dungeon are built, with placeholders.)

#### Revised world layout (from the map sketch, 2026-10-14)

The sketch replaces the "everything extends east" stopgap above. The Barrens, the camp and the mine keep their coordinates (x 0-2879, shaft at x 1660, surface at y ~510); everything else is arranged round them:

```
                         SKY DUNGEON  (very open, low gravity)
                  ┌────────────────────────────────────────────┐
                  │                                            │
                  └─────────────────────────────────┬──────────┤
                                                    │ VERTICAL │
                                                    │ MOUNTAIN │
 ═════════════ the Barrens (overworld, the surface) ═══╪══════════╪═══════
   WATER    ┌─ hub / camp ─┐  ┌ main road ┐          │          │
  DUNGEON   │  (NPCs)      │  │  area 1   │      ┌───┴────┐
  (flooded) └──────────────┘  │  area 2   │      │ OLD    │
 ┌────────┐                   │  area 3   │      │ QUARRY │
 │        │                   │ main boss │      ├────────┴──────┐
 ├────────┤                   │ 4 left/right     │ QUARRY BOSS   │
 │ WATER  │                   └───────────       └───────────────┘
 │ BOSS   │
 └────────┘
```

Rough placement (px, y measured as today, so the sky and mountain are at negative y; sizes are starting points to tune):

| Region | x | y | Size | How it is entered |
|---|---|---|---|---|
| Main road (areas 1-4) | 0-2879 | 760 down | as now | the mine shaft |
| Hub / camp | about -400 to 1500 | the surface | the plain either side of the camp | (it is the overworld) |
| **Water dungeon** | -2800 to -401 | 760-3359 | 2400 x 2600 | a sealed shaft on the surface at about x -700 |
| **Water boss** | -2800 to -401 | 3360-5159 | 2400 x 1800 | down from the water dungeon's shop |
| Old Quarry | 2880-5759 | 760-3059 | 2880 x 2300 | the crevice at x 4300 (built) |
| **Quarry boss arena** | 2880-6500 | 3060-4559 | 3600 x 1500 | down from the Quarry's shop |
| **Vertical mountain** | about 7000-8639 | about -2900 to 510 | 1640 x 3400 | climbs from the east end of the desert |
| **Sky dungeon** | about -200 to 8639 | about -4300 to -2900 | 8800 x 1400 | the top of the mountain |

**Biases, for now, as in the other dungeons** (individuality comes later): each is generated by `cavegen` from its own rectangle, with a shop and a boss where it has one, tiers by depth (water 3, quarry boss 3, mountain 3-4, sky 5). What is different about each is only what the sketch asks for:

- **Water dungeon.** Most of its open space is **flooded** (a flood level near the top; every open cell below it is water), so it plays as a swim. The water is mostly still: only cells touching air or open space are awake. A boss area below it is bigger, for an aquatic boss. **Locked by gear, not a door:** without a *breathing item* the hunter drowns (the breath meter is already in `fluids.lua`), so the lock is the water itself. The item (working name *Diving Helm*) is the reward for the **Quarry boss**, which gives the Quarry's boss a point beyond loot: it opens the west.
- **Vertical mountain.** Generated like the main areas but **routes climb**: the entrance is at the bottom, the goal at the top, and each route is a chain of ledges spaced within a jump (or a recoil jump), with level corridors between climbs. Everything else (monsters, loot, a shop, a boss) is as in other areas. Its top opens into the sky dungeon.
- **Sky dungeon.** *Very open*: floating islands and cloud shelves in a wide chamber, few tunnels, long sight-lines. **Low gravity** (a per-area gravity scale, roughly a third, applied to the hunter, monsters and objects), so recoil jumps carry far. Enclosed below by a cloud floor so falling out does not drop into the desert.

**Decisions (2026-10-14):**

- The **Quarry boss always drops the Diving Helm** for now (no random loot roll for it).
- The **Quarry boss arena** is sized for its boss, based on the Queen's chamber (a flat-floored boxy room about 1500 x 400 px with platforms, §7d) with a little rock round it; it is a standalone area under the Quarry and will change as the boss is designed.
- The **mountain's entrance is a walk up**, the mirror of the first area's shaft: a path or ramp climbing the mountain's flank from the desert into a deep cave that opens out and eventually climbs.
- The **sky dungeon is reached from the top of the mountain dungeon**, past a **boss** that waits there.

**What has to change in the engine first** (an invisible step; see §11a-vii):

1. **The world has to allow negative coordinates and stay cheap.** `World` takes an origin (`left`, `top`) so x and y may be negative, and stores cells **per tile, allocated when first written** (unexplored rock is one id per tile, not 11 million bytes), so a world twice as big costs only what is actually generated. The painted-on-demand tiles (`World.lazyX`) become a list of regions that areas claim when they generate.
2. **Fluids key their cells with a stride of 2048 cells** (`K`), which breaks at x 4096 and above and cannot hold negative x. That is already a bug in the east desert and the Quarry's east half (water, gas and fire could alias into the wrong row). The key packing is widened and given an offset so any x or y in the world is valid.
3. **Physics terrain chunks** skip negative chunk coordinates when terrain is dug (`cx >= 0 and cy >= 0`): fixed for the negative region.
4. **Flood fill, climbing routes and a gravity scale** are new generator and physics features, added one per branch.

### 11a-iii. Elites

Monsters can spawn **elite**: bigger health bar, a visible mark and one or two **affixes**. Elites are the targets of bounties and the source of *trophies*.

| Affix | What it does |
|---|---|
| **Armoured** | takes a fraction of damage from the front; weak to explosions and to being shot from behind |
| **Burning** | trails fire; sets gas alight; immune to fire |
| **Splitting** | breaks into two smaller copies of itself when killed |
| **Vampiric** | heals when it hurts the hunter |
| **Frenzied** | faster, with short rage windows |
| **Hexed** | casts a curse on the hunter (slower reload, dimmer light) until it dies |

- Each area spawns a few, more with depth, never in shop rooms or boss arenas. Affixes combine from the second area on.
- **Built (2026-10-15), see §11a-ix:** Armoured, Burning and Splitting. Vampiric, Frenzied and Hexed are still to do.
- An elite drops a **trophy**: marks (below) and one item from the **locked** pool (§11a-v), and can be mounted at the camp.
- Elites share the monster's own animation and behaviour; the affix is mostly data, a tint and an icon, plus a few hooks (`enemies.damage`, `die`).

### 11a-iv. The camp (the hub) and its people

The Barrens' camp (tent, campfire, lanterns, the DPS dummy) is where permanent upgrades live. It **grows by the people the hunter finds below** and the **marks** he brings back.

- **Marks** are the permanent currency: earned from elites, bosses, quests and first-time compendium discoveries. Gold stays run-only (spent in shops and lost on death).
- **NPCs are found, then they move to camp.** Each is freed or helped in the dungeon (§11a-vi); once they live at camp they offer upgrades and quests for marks.

| Person | Found | At camp |
|---|---|---|
| **Gunsmith** | a prisoner in a collapsed mine room (area 1) | weapon grades, bigger slots, new fuser recipes; unlocks guns for the pool |
| **Prospector** | trapped under a cave-in (area 1; built, §11a-xii) | banks some gold between runs; sells digging tools (pickaxe, dynamite) |
| **Bounty clerk** | a wounded hunter (area 2) | the board: bounties and quests |
| **Apothecary** | caged in the Sulfur Vents (built, §11a-xiv) | a vigor tonic and starting flasks (no chapel or preacher: the desolate tone) |
| **Cartographer** | a lost surveyor, caged in the Old Quarry (built, §11a-xiv) | the survey map |
| **Bartender** | after the first boss (built, §11a-xiv) | house rules: harder runs that pay more marks |
| **Taxidermist** | after the first elite trophy is carried back (built, §11a-xiii) | mounts trophies; each gives a small passive |

- Camp upgrades each have a few tiers, bought with marks. Tiers are mostly new options (a fourth weapon slot is the exception we'd allow).
- The camp is visibly different as it grows: a lit window in the gunsmith's shack, a bar at night, trophies on the wall.

### 11a-v. Compendium gating

The compendium (§9c) tracks two things per item, perk, monster and gun:

- **Seen:** the hunter has met it (it shows as a silhouette). Goals, not rewards.
- **Unlocked:** it can now drop, appear in shops and be fused.

Unlocking comes from the Gunsmith's tier, a quest reward, or killing a particular elite. The starting pool is deliberately small and legible; most of the 53 items and the perks begin locked, with the common ones unlocked by simply playing. Discoveries are banked immediately, even if the run ends in death.

### 11a-vi. Events and NPCs in the dungeon

Each area rolls a few **events** alongside the crates, chests and the new story scenes (§7b, `src/story.lua`):

- **Caged prisoner:** free them (kill the keeper, break the lock) and they move to camp. The main way to unlock a camp NPC.
- **Wounded hunter:** gives a quest ("bring me three silver rounds", "kill the thing in the Hollows").
- **Altar:** a curse for a boon, in the spirit of the perks.
- **Sealed vault:** needs a key, dynamite or digging; holds a weapon or a locked item.
- **Ghost merchant:** appears now and then, with odd prices.
- **Quest items:** an object to carry back to camp alive.

Quests can run across several runs ("find the three relics of the old preacher"); their progress is saved with the profile. Quests are given by the bounty clerk and by hunters met below.

### 11a-vii. Build order

*Status (2026-10-15): steps 1-5 are built at a first level (§11a-viii to §11a-xiv): marks and unlocks, the Gunsmith, elites, the bounty board, the Prospector, Taxidermist, Apothecary, Cartographer and Bartender, the dungeon events (altar, sealed vault, ghost merchant, wounded hunter and the questline of the silver bells) and two new areas. What remains is depth (more affixes, more quests and events, real areas with their own bosses).*

0. **World expansion** (§11a-ii): layout table, the wider overworld, the first side branch (*done*); then the **revised layout**: (a) world origin and sparse cells, fluid key fix, physics guard; (b) the west column: flooded water dungeon and water boss; (c) the Quarry's boss arena and the Diving Helm reward; (d) the vertical mountain; (e) the sky dungeon.
1. **Save fields and the compendium states:** marks, camp upgrades, quest progress, *seen* and *unlocked* per entry. Compendium gating wired into drops and shops.
2. **Elites:** three affixes first (armoured, burning, splitting), trophies and marks.
3. **First camp NPC:** one freeable prisoner in area 1 who appears at camp, with one purchasable upgrade.
4. **Bounty board:** a single quest type (kill a named elite), pays marks.
5. **More NPCs, events, branches and quests,** one at a time, then the rest of the camp's growth.

Work on audio (real recordings), a map, accessibility settings and a daily seed can happen alongside any of these.

### 11a-viii. Built so far: marks, unlocks and the Gunsmith (2026-10-14; `src/meta.lua`, `src/npcs.lua`)

**Save files (version 2).** A profile now also keeps `marks`, `camp` (who lives there), `upgrades` (tier bought per upgrade), `unlocked` and `seen` (per category, id = true) and `stats.marksEarned`. **Older files keep everything they had found: it counts as unlocked**, so nothing a player already had disappears from the pool. With no profile in use (the world built behind the title screen, the test room) the whole pool is open; choosing a save file rolls the shops' goods and the starting revolver again from its pool (`shop.restock`, `inventory.starterGun`).

**Marks** are banked the moment they are earned and shown on the HUD left of the gold bag (a small silver-violet sigil and the count, once a profile has any), and in the side notes: a discovery's note shows its "+1"; other earnings get a note of their own ("Marks earned: The Gunsmith freed +5").

| Earned for | Marks |
|---|---|
| anything new in the compendium | 0 (was 1; turned off 2026-10-15) |
| reaching an area for the first time | 3 |
| freeing a prisoner | 5 |
| every boss slain | 5 |
| every elite slain | 2 |

**The pool.** Weapons, ammo types and attachments are gated (perks and monsters are not, yet). **Unlocked from the start: the revolver, the double-barrel and the Broomhandle, and every common item** (fused items, made in the fuser, and levelled ones follow their base). The machine gun, the gatling and every rare and cursed item start locked: they never drop, sit in shops or come out of chests at random (`items.isAvailable`, `guns.isAvailable`, set by `meta.install`).

**Seeing locked things.** A locked thing becomes **seen** when it lies within ~110 px of the hunter or he collects it. They turn up from: **bosses** (one of their four items is always a locked one while any are left, and their weapon is a locked kind 40% of the time); **chests** (a weapon from a chest is a locked kind 30% of the time); and the Gunsmith's thank-you gift (below). They work normally for the rest of that run.

**The compendium** shows a small brass **padlock** on every locked weapon, ammo and attachment cell. A seen-but-not-collected entry is a silhouette with a faint rim, its name and "Seen". A locked entry's detail says what to do ("Locked. Teach the Gunsmith at camp to make it: 4 marks.", or, before he is freed, "...until someone who knows guns learns to make it").

**The caged Gunsmith.** Area 2, the Sunken Hollows (moved from area 1 on 2026-10-15; `theme.prisoner`, placed by `cavegen` last so the layout doesn't change) has an **iron cage** on the flattest, roomiest stretch of floor found nearest the middle of its depth, levelled and cleared so it always fits, with a candle stub beside it and **two ghouls** standing guard. Inside, the Gunsmith (stocky, grey beard, flat cap with goggles, leather apron) sits slumped; when the hunter comes within ~120 px he gets up at the bars, faces him and calls out in speech bubbles ("Hunter! Over here!", "Shoot the lock off, quick!"). **Shooting the brass padlock** (or any blast reaching it) breaks it: the door swings open, he thanks the hunter ("Bless you, hunter!", "I'll make for your camp.", "Find me by the fire. Take this."), walks out and is gone in a puff of dust after ~5 s, leaving a **gift gun** on the cage floor (a kind he doesn't make yet, if there is one). The profile records him at camp and pays 5 marks. In later runs his cage stands open and empty.

**At camp** the Gunsmith's **stall** stands east of the fire (x 1134): an awning on two posts, a workbench with a vise, a rifle being mended and a box of cartridges, long guns leaning on a post, an anvil on a stump where he hammers (sparks fly) and a hanging lantern. He turns to face the hunter and greets him with a random line when he comes near. **[E] Talk to the Gunsmith** opens his page (Esc or E closes it; the game is paused):

- **Upgrades** (cards with tier pips and a price in marks; Enter or click buys the next tier):

| Upgrade | Tiers (marks) | Effect |
|---|---|---|
| **Filed and Oiled** | 6, 12 | generated weapons' bonuses roll 15% better per tier (and their one worse stat less badly), so better grades turn up more often |
| **Bored-Out Frames** | 8, 16 | generated weapons have a 15% chance per tier of one more slot |
| **Loaded Holster** | 5 | the starting revolver always comes with a (non-cursed) ammo type or attachment fitted |

- **Teach him:** a grid of everything still locked, silhouettes until seen. Choosing a seen one asks to confirm and **unlocks it for good** for weapon 6, rare 4 or cursed 3 marks. The focused entry's name, price and description show under the grid.

**Elites** (§11a-ix) pay 2 marks, record a trophy and drop a locked item too.

**Adding the next person** needs an entry in `meta.PEOPLE`, their upgrades in `meta.UPGRADES` (with `npc = id`), a `prisoner = id` on the area theme they are caged in, their camp spot (`npcs.setCamp` in `overworld.populate`) and their drawing in `src/npcs.lua`.

### 11a-ix. Elites, as built (2026-10-15; `src/enemies.lua`)

- **Which and how many:** when an area's monsters are spawned (`catacombs.spawnProps`), `enemies.rollElites` makes a few of them elite: 3 in a tier-1 area, then 4, 5, 6, 7 by depth tier. Only ghouls, bats, spitters, hoppers, bloaters, skeleton miners and cave rollers can be elite (not worms, piranhas, swarm members, wisps, bosses or the dummy). Each gets one affix; from tier 2 on, 35% get a second.
- **Stronger:** 3x health, 1.25x damage, 2.5x gold.
- **How they look:** the sprite pulses with the affix's colour (taking turns with two affixes, through the same tint shader as frost and fire; a status tint takes over while one applies), a crest of small glowing diamonds over the head (one per affix, bobbing), a light in the affix's colour (a bigger, warmer one for Burning), and once they are fighting a **health bar edged in gold with the name over it** ("Splitting Armoured Ghoul"), thinner than a boss's.

| Affix | Colour | What it does |
|---|---|---|
| **Armoured** | steel blue | takes 35% of the damage from the front (from shots travelling into its face; sparks and a clank), full damage from behind, **150% from blasts** |
| **Burning** | orange | leaves a small flame every 0.3 s while it moves (flyers only light gas), sheds embers, sets gas alight; immune to fire and burning (`e.fireproof`) |
| **Splitting** | green | when it dies, two ordinary monsters of its kind (half the health) are flung out of it, already hunting the hunter (not for spitters) |

- **When one dies:** extra gold, an item from the **locked pool** (any item if none are left), "ELITE SLAIN", and through `enemies.onEliteKilled` (src.game) **2 marks** ("Splitting Armoured Ghoul slain +2") and a **trophy**: the profile counts elites slain per kind (`profile.trophies`, for the Taxidermist later).

### 11a-xi. The bounty board, as built (2026-10-15; `src/bounties.lua`)

- **At camp,** west of the practice range (x 762), a plank board under a little shingled roof with up to three small posters nailed to it (a taken one has a red mark). It is there from the first run (the bounty clerk, when built, can take it over). **[E] Read the bounty board** opens its page (E or Esc closes it).
- **The page:** three **wanted posters** side by side, the same parchment poster as the death recap with the monster printed in ink and the bounty's **name** ("Grey Rumble", "Old Gnasher": a title and a name per kind), and under each: what it is ("Splitting Armoured Cave Roller"), where it was last seen ("the middle Sunken Hollows": the upper, middle or lower third of an area), the reward in marks, and **Take it** / **Give it up** (asks first; nothing is paid back). **Up to two** can be taken at once ("Hands full"); a taken poster is stamped **TAKEN** in red.
- **What gets posted:** a floor-walking kind (ghoul, hopper, skeleton miner or cave roller; a kind already on the board is avoided) in an area the profile has reached (or the first two), that has that kind and isn't flooded. One affix in a rank-1 area, two deeper. Reward: 6 + 3 x the area's rank, +2 for a second affix (9-23).
- **Across runs:** the posters and which are taken are saved with the profile (`profile.bounties`). The board fills back up to three when a run starts.
- **In a run:** once a taken bounty's area exists, the monster of its kind nearest to the third it was seen in (or a fresh one on a floor spot there) becomes the **named elite**: the bounty's affixes, an elite's 3x health and half as much again, and its name in gold over its health bar (shown at once, not only once it fights). Walking into its area brings up a note ("Bounty: Grey Rumble / Somewhere in the middle part of this area"), and while it is within 700 px but off screen a **gold triangle** on the screen's edge points to it.
- **Claimed:** killing it pays the reward at once ("Bounty claimed: Grey Rumble +14", on top of the elite's own 2 marks and loot), and the poster comes down.

### 11a-xii. The Prospector and the cave-in, as built (2026-10-15)

- **The cave-in (area 1, the Catacombs):** where the Gunsmith's cage used to be placed, `cavegen` heaps a **mound of loose earth** (about 37 px wide and 21 tall, the area's dirt with one lump in eight of rock) over the levelled spot. The Prospector is buried in it: only his battered hat, whiskered face and a **waving arm** show at its top, with broken shoring sticking out and his lantern on its side beside it. Two ghouls stand guard as at the cage. Within ~120 px he calls out ("Down here! Under the rock!", "Shoot the dirt off me!"). **Shooting the dirt away** (any gun digs dirt) or blasting it frees him once three quarters of the earth over his body is gone (checked five times a second): he stands, thanks the hunter ("Air! Sweet air!", "I'll be under the arch, west of your fire."), walks off and is gone, leaving **60 gold** and **two sticks of dynamite** for the run. 5 marks, and he lives at camp from then on (later runs: just the heap).
- **His camp, under the natural arch** west of the bounty board (x 650): a bedroll, his iron-bound **strongbox**, a pick against a rock, a sack of samples and a lantern on a stake. He swirls a gold pan, and turns to the hunter with a line when he comes near. **[E] Talk to the Prospector**.
- **The strongbox** (on his page, right of the upgrades): how much gold is in it against what it holds, with a bar, what the hunter carries, **Put it in** (as much as fits) and **Take it all out**. What is in it survives death; the hunter walks back up to camp with gold to put it away and takes it out at the start of a run to spend below (`profile.bank`; deposits don't count as gold earned again).
- **Upgrades:**

| Upgrade | Tiers (marks) | Effect |
|---|---|---|
| **Bigger Strongbox** | 5, 10 | holds 100, then 250, then 600 |
| **Miner's Tithe** | 6, 12 | on death, 15% per tier of the gold carried goes into the strongbox (up to what it holds) |
| **Blasting Kit** | 5, 10 | every run starts with 2 sticks of dynamite per tier |

- **Dynamite** (a new action, **Throw dynamite, Q** by default, rebindable): throws a stick toward the mouse (faster the farther the aim, with a little lift). It arcs, bounces and goes off after 1.4 s in a blast 1.6x a miner's that **digs an 11-px crater in any rock** (not bedrock or masonry), hurting monsters and the hunter alike; shooting it in the air sets it off early. The count shows on the HUD under the gold (a red stick and "x2"); with none left, Q says "No dynamite".

### 11a-xiii. The Taxidermist (2026-10-15; `src/meta.lua` MOUNTS, `src/npcs.lua`)

- **The natural arch is gone** (the rock arch west of the board fenced in the Prospector's camp); that ground is open.
- **He needs no rescuing:** he turns up at camp (x 1196, east of the Gunsmith) once the profile has slain any elite (the trophy count, §11a-ix). His stall: planks with a row of nails for seven trophy plaques (a plaque appears on its nail once mounted), a work table with a half-stuffed shape, jars on a shelf; he stitches away until the hunter comes near. **[E] Talk to the Taxidermist**.
- **His page:** a row per kind of elite (ghoul, cave bat, spitter, mire hopper, bloater, skeleton miner, cave roller): elites of that kind slain, the bonus, and **Mount** for 3 marks (needs one slain). A mount is permanent for the profile. Bonuses (`perks.extraFx`, summed with the run's perks):

| Mounted | Bonus |
|---|---|
| Ghoul | +10 max health |
| Cave bat | +4% movement speed |
| Spitter | reloads 5% faster |
| Mire hopper | +5% jump height |
| Bloater | take 4% less damage |
| Skeleton miner | +6% gold from everything |
| Cave roller | kicks hit 20% harder |

### 11a-xiv. The rest of the roster, the dungeon events and the new areas (2026-10-15)

**Camp people** (`src/people.lua` draws them, `src/meta.lua` holds their data):

| Person | Found | Stall (x) | What they do |
|---|---|---|---|
| **Apothecary** | caged in area 3 (the Sulfur Vents), gives a flask | west end, 520 | **Vigor Tonic** (5, 10 marks): +12 max health per tier. **Pocket Flask** (6, 12): start each run with a flask per tier; **H** drinks one for 35% of max health (HUD: a green bottle and a count) |
| **Cartographer** | caged in area 6 (the Old Quarry) | 706, between the Prospector and the board | **Survey Map** (6, 10): **M** opens a map of everywhere walked this run (zoomed to the charted ground, cells of 16 px charted within ~96 px of the hunter); tier 2 marks shops (cyan), chests (gold) and bounty quarries (red) on charted ground |
| **Bartender** | arrives once the profile has slain a boss | a bar between the tent and the fire, 984 | **House rules**, chosen for the next run (switches; they apply at a run's start, and no boss is affected): **Rotgut** monsters +40% health, marks +35%; **Powder Keg** monsters hit +30% harder, marks +30%; **Lean Times** shops and healing cost +30%, marks +20%. Marks earned in a run are multiplied by all that are on |

**Events** (`src/events.lua`; `cavegen` places them last, in every area with monsters except arenas and the sky):

- **Altar** (1 in areas of rank 1-2, 2 deeper): a stone plinth with a violet flame. **[E] Make an offering** once: a **rare perk and a cursed perk** you don't have (a curse for a boon).
- **Sealed vault** (one an area): a stone-brick room carved in solid rock with a narrow corridor out to the nearest cave, closed by an **iron door** (the iron can't be broken; its keyhole glints). Open it with a **key** (the room is wrapped in iron: it can't be dug or blasted into). The key is carried by **the area's first elite** (it drops when it dies and is picked up by walking over it; the HUD counts keys), or lies on a ledge if there is none. Inside, a **reliquary chest**: a weapon (likely a locked kind, well fitted), a locked item and 60-110 gold (x depth).
- **Ghost merchant:** once a run (60%), between 40 and 110 s in, a pale hooded ghost with a lantern appears near the hunter for ~110 s. **[E]** opens his page: three items (any, locked ones too) at **odd prices** paid in gold (9-217 and never round), **health** (7-24) or **marks** (2-6).
- **Wounded hunter** (area 2, until the quest is done): lying bandaged against the wall. **[E]** starts the questline of **the old preacher's three silver bells**, saved with the profile. A bell then lies hidden in each of the first three areas; walking over one carries it (HUD), and dying loses it. **[E] at the bounty board** delivers what is carried: 4 marks each; all three: 15 marks and a locked item. (Delivered bells are not placed again.)

**New areas:** the two post-Queen paths each go on: **The Ember Foundry** (under the Cinder Warrens: more lava, wisps, miners and rollers, hotter light) and **The Silt Vaults** (under the Drowned Halls: even more water, hoppers and bloaters). Their paths' last shops now have hatches (area 5, tier 5; `LAYOUT` indices 12 and 13, themes derived from the areas above).

### 11a-xv. The town (2026-10-15; `src/town.lua`)

The hub grows from the hunter's camp into a western town as people move in. **Everyone always stands in the same place**: the street has eight fixed **lots**, each with a raised wooden **porch** (8 px up, 56 wide) and **three steps** on its left end, real terrain built with the world (`town.build`), so the ground plan never changes and the steps are always walkable (no step is taller than the player's 5 px limit, even where the ground dips). The person stands on their porch at the lot's centre.

| Lot (x) | Who |
|---|---|
| 520, 586, 652, 718 | Apothecary, Cartographer, Prospector, Taxidermist |
| 784 | the bounty board |
| (the hunter's tent, the practice dummy and the campfire stay in the middle, around x 830-1040) | |
| 1100, 1166 | Gunsmith, Bartender |
| 1232 | the **town hall**, a spare lot for the next building (bounty clerk, sheriff...) |

**Three stages**, from how many of the six people are at camp (`town.stage`):

1. **Camp (0-3 people):** the stalls as they were (awnings, tables, bars) on their porches.
2. **Settlement (4-5, more than half):** every occupied lot gets a **plank shack**: board walls in the person's colour, a three-course shingle roof, a porch roof on two posts, two small windows, hanging lanterns and a lettered sign standing on the ridge. The stall's own awning is dropped (`s.bare`). Windows and lanterns glow and light the street.
3. **Town (all six):** every lot becomes a **false-front building**: a two-storey painted facade (clapboard, cream trim, two lit windows), a cornice, a raised parapet with the name in letters (APOTHECARY, SURVEYS, ASSAY, TAXIDERMY, GUNS, SALOON), a striped scalloped awning on posts, a shaded side wall. The **town hall** is finished (a tower with a clock and a red flag, double doors, shuttered windows; closed for now). A **GUNNUG** welcome sign stands at the west end and **telegraph poles** carry a wire, sagging, across the whole street.

**Nothing marks an empty lot** (revised the same day: the first version had survey stakes, FOR SALE boards and timber frames, which gave the plan away). A lot is bare desert until its person arrives: then the porch and steps rise out of the ground under them (a puff of dust and a thump; `town.sync`, checked every frame, and run while the world is built so a returning save file's town is already there) and the stall or building appears. Switching to a save file with fewer people takes porches away again. The town hall lot is built only when all six are in. The bounty board's lot is there from the start.

Each building's colour is the lot's `accent`, its lettering `sign`, so a new lot is one entry in `town.LOTS` and, for a person, one stall drawer. Things moved to make room: the natural arch and two trees (earlier), the bones east of the pond (x 1396), a crate, an urn. The porches are wood, so they can be shot to pieces like any wood; the next run rebuilds them.

### 11a-xvi. Controls and fixes after playtesting (2026-10-15)

- **Restart is a hold:** hold **R** (rebindable) for 2 s: after 0.5 s the screen fades to black over the remaining 1.5 s and the run restarts; letting go brings the picture back. The key must be released after a restart before it counts again.
- **Survey map:** **+ and - buttons** in the top-right of the map's border, the **mouse wheel** (about the cursor), **+/-** keys and **0** (back to the fitted view) zoom; a **right-button drag**, the arrows or WASD move it. **Left-click** puts a **teal X** (with its distance from the hunter in metres, 8 px each) anywhere on the map; **right-click an X** takes it down. Marks last for the run.
- **Vaults are sealed in iron:** the room is wrapped in a 3-px iron shell (like the door), so it cannot be dug or blasted into: the only way in is the key. The corridor out to the cave stays ordinary rock.
- **Water glints off** along with the reflections (the streaks of lamplight under a water surface read as reflections).
- **Controls page** rows shrink to fit above the buttons however many actions there are.
- **Speech bubbles** never overlap (a later one goes above) and the camp's people greet one at a time. The HUD's right-hand column stacks gold, marks, then a row per carried item (dynamite, flasks, keys, bells), centred under the sack.

### 11a-xvii. Progression pacing, the way home, and more (2026-10-15)

- **Camp pacing** (`meta.lua`): the first run has nothing but the camp site: no elites, no cages. After one death elites spawn and the Gunsmith and Prospector can be found; after two the Apothecary and Cartographer. Slay an elite and die and the bounty board goes up (`p.board`) and the Taxidermist, now caged in the Cinder Warrens (area 4 left path), can be found. The Bartender still comes with the first boss. Cages are placed when an area's props are (`meta.canFind`).
- **Taxidermist mounts have levels.** First mount 5 marks with 1 elite slain; each upgrade needs 5 more of that kind and costs 1.2x the last (5, 6, 7, 8, 9, 10...), up to level 8. Each level adds half the previous one's bonus (ghoul: +10, +15, +17, +19 health), so mounts taper off. Older saves' `true` counts as level 1.
- **Gatling gun**: never a random or locked drop until a boss has been slain; the first boss ever slain always drops it. Boss weapons are never worse than grade A.
- **Fuser** needs 12 ether (was 20). The Apothecary's flask and the Prospector's dynamite are given at the moment the upgrade is bought.
- **Lava flows** like water at a fifth of the speed (`fluids.lua`, `lavaFlow`); the Cinder Warrens have no water pools. The vault no longer claims digging opens it.
- **The way home**: under each post-boss shop is a brick room (reached by a shaft with two one-way ledges to climb out) holding a teleport pad. Two presses of interact take the hunter back to camp for 80% of his gold and 80% of his max health (he dies if he has no more than that).
- **Saloon**: two bottles on the back shelf glow in a rule's colour for each house rule switched on.
- **Crosshair** (Settings > Crosshair): style (plus, circle, dot, X), colour, opacity, line thickness, length, gap and outline, with a preview.

### 11a-xviii. Boss arenas, the Queen and the Marble Colossus (2026-10-15)

- **The pedestal.** An arena's boss is not there until the hunter presses interact at the pedestal in the middle of the floor. It reads "Defy the <X>" (the area's `defy`: Caverns for the Sulfur Queen, Stone for the Colossus, Depths for the Matron, Heights for the Dreadbat). Pressing it seals the tunnels into the arena with iron plugs (`a.plugs`, removed with the gates when the boss dies), clears out every other monster in the arena (`enemies.vanish`), and brings the boss. A boss area's boss is a `lv.boss` record in `scenes/catacombs.lua`.
- **Camera.** During a fight the view pulls out to 1.35x (`render.setZoom`, in 0.05 steps: the virtual screen grows, the interface keeps its size) and looks between the hunter and the nearest piece of the boss (`camera.setFocus`).
- **The Sulfur Queen** splits like a slime: below 33% health she splits in two, and each piece splits again below half of its own, three times over (up to eight pieces). She is drawn as a wobbling, breathing blob with eyes that follow the hunter and a mouth that gapes when she spits. Her gas no longer catches fire: no brazier fires in her arena and her minions are bloaters, never wisps.
- **The Marble Colossus** (the Quarry's boss, `enemies.defs.golem`): lumbers slowly; swipe (close), thrown stones (1/2/3 by stage), a stomp that sends a stone wave along the floor (both ways from stage 2) and an eye beam that sweeps an arc. At two thirds and a third of its health it kneels in a crystal shell, invulnerable, while little golems (`minigolem`) walk in from both sides of the arena; once they are all dead the shell breaks and it is open to attack (x1.5 damage) for a moment.

**Boss ideas still to build** (so we can come back to them):

- *The Deep (Mire Matron's flooded hall, "Defy the Depths"):* an anglerfish-like leviathan or a drowned kraken in the arena's lake. Tentacles reach up through the water to grab and drag the hunter under (a drowning timer); a lure-light drifts through the dark and the true body only shows when it lunges; phases raise and drain the water level (platforms appear and sink), and it calls shoals of piranhas. Weak point: the lure's eye when it bites.
- *The Summit (the Dreadbat's peak, "Defy the Heights"):* a storm roc / thunder drake at the mountain top. Dives, wing gusts that push the hunter toward the edge, lightning that strikes marked spots (telegraphed circles), and a phase where it lands on the summit's spire and calls a storm whose strikes are the only way to break its charged shield (lure a strike onto it).
- *The Sky (above the gate, "Defy the Heavens"):* a clockwork or star warden on floating platforms. The arena is a ring of islands; it rotates a beam like a clock hand, drops gravity wells that pull the hunter's bullets, and splits into three constellations that must be shot in the order they light up.

### 11a-x. Performance notes (2026-10-15)

Measured with a scripted profiler (8 ghouls, a burst of three shots every 5 frames): plain hits cost under 0.1 ms a frame; the lag around fights came from what hits set off.

- **Bullets tested every monster in the world** at every pixel they moved (~1000 monsters once all areas exist). `enemies.hitTest` now uses a list of the monsters within 1000 px of the hunter, rebuilt every frame (new spawns join it at once).
- **Blasts re-traced the terrain's physics outlines on every dig** (each explosive round digs several times and a volley digs the same chunks over and over: 20-40 ms frames). `physics.rebuildRegion` now queues the chunks, and `physics.flush` re-traces each once just before the next physics step.
- **Smoke** made a fresh table for every smoke pixel drawn every frame; the tables are now reused.
- **Water reflections are off** (`fluids.reflector` is no longer set): they drew every creature a second time near water.
- **Hub and first-area lag (2026-10-15):** the areas below the surface are generated in the background, and that took a 10 ms slice of every 16.7 ms frame for the first ~minute of play (hub frames ~15.7 ms, ~7 ms once everything was built; it faded as the hunter went deeper because generation had finished). In play the budget is now 2.5 ms (6 ms until the first area exists, which is ready after ~8 s, about when the hunter reaches the shaft); with a menu, the weapon panel or the compare prompt open, or on the title screen, it is still 10 ms. Hub frames: ~7 ms. Still to do: when an area finishes, placing its props costs one 30-50 ms hitch (`fluids.add`, the physics outlines).
- **Tumbleweeds** are twig balls: a ragged outline with crossing sprigs over a dark inside, three variants per size, rolling and turning (before, a spoked wheel).
- Explosive volleys went from ~33 ms to ~24 ms a frame on average and the worst frames from 131 ms to about 50-75 ms. Left: the game makes several hundred KB of garbage a frame, blasts still repaint and flood-fill terrain (~1-2 ms each), and fire and smoke drawing grows with the fire.

## 12. Open Questions
- Overworld size and contents for the long-term version.
- **World layout (§11a-ii):** names, themes and monsters for the side-branch areas; how many branches; how long the spine and branches should be; where the cross-cuts sit.
- **Camp (§11a-iv):** whether the camp stays on the surface or also gets an underground annex; how many tiers each upgrade has; what the first Taxidermist passives are.
- **Quests (§11a-vi):** how many quests can be active at once; whether failed quests (a dead NPC, a lost item) can be retried.
- **Elites (§11a-iii):** whether affixes should be visible on the compendium before the first kill.
- **Revised layout (§11a-ii):** the Quarry boss and the aquatic boss (kinds, arenas, what they drop); whether the Diving Helm is the only way into the water or a second route (a drain, a pump) should exist; how the mountain and the sky dungeon join (a hatch, an updraft); what stops a fall out of the sky.
