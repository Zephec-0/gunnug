# Gunnug — Design Document

> Living document. Sections marked **[Later]** are intentionally deferred; we'll revisit them once the current milestone is playable.

## 1. Concept

A **dark fantasy** 2D roguelite dungeon crawler built on the bones of **Noita**: pixel-simulated, destructible terrain and a deep, buildable weapon system. Noita's wizard, wands, and spells are replaced with a **monster hunter** in the mould of Van Helsing, wielding firearms (and later other weapons) with ammunition and attachments, spanning **old designs up to roughly WW2-era**. Tone: the grim gothic world of *Warhammer: Vermintide*, rendered in the art style of *Dead Cells*.

- **Engine:** LÖVE 11.5 (via the bootstrap-love2d-project template)
- **Controls:** Mouse aim + WASD
- **Platforms:** Windows first; template supports others later

## 2. Art Direction

- **Dark fantasy, Dead Cells-style pixel art — desolate rather than gothic:** muted, weathered bases (dusty sand, red sandstone, slate, dark earth) that stay readable rather than pitch dark, with a few **vivid accents** — glowing eyes, lantern and campfire flames, teal cave fungus, silver fittings — and punchy, glowing muzzle flashes and sparks. No vampire/graveyard imagery.
- **Lighting:** each scene has an ambient light level; a light map with soft radial lights (the hunter's own light, candles, lanterns, the moon, muzzle flashes, bullets, glowing fungus) is multiplied over the scene. Flames, eyes, sparks and bullets are drawn afterwards as **emissive** so they glow even in darkness.
- **Terrain shading:** terrain is at full brightness at its edges and darkens with distance from open air (lit rims around dark masses); digging re-shades automatically.
- **Rendering:** the terrain image is split into 256×256 tiles (only changed tiles are re-uploaded, only visible ones drawn). The game draws to a low-resolution canvas of **640×360**, which maps exactly **3:1 onto 1920×1080** — every game pixel is a crisp 3×3 block, with no blurring of moving objects. (The view shows the same amount of world as the earlier 400×225 zoom, at 1.6× the pixel density.) Other window sizes that aren't a whole multiple use "sharp bilinear" scaling: a crisp whole-number upscale followed by a smooth fit. Moving props are drawn at whole-pixel positions so they step cleanly instead of resampling. One game pixel = one terrain pixel. Screen-space UI (HUD, item bar, text) has its own scale and is unaffected by pixel density.
- **Rescaling rule:** all world values are in game pixels. To change pixel density again, multiply lengths, speeds, accelerations and forces by the factor; masses and times stay the same; pixel-count limits scale by the factor squared. The Box2D metre scales too, so physics behaves identically.
- **Camera:** keeps the player centred (leaning slightly toward the aim) and is not clamped to the level; past a level's edge, the edge terrain continues.
- **Character:** a lanky, slim **Van Helsing-style hunter**, drawn as pixel limbs on a procedural skeleton rather than sprite frames. His head is mostly a tall, wide-brimmed hat worn low, the brim pulled down to two glowing eyes peering from the shadow beneath; he wears a slim long dark coat with a crimson lining and a **light-grey shoulder mantle** (part of the coat, its loose end trailing in the wind), dark trousers and buckled boots, and carries an engraved dark-steel revolver. Legs walk via inverse kinematics, both hands grip the gun and follow the aim, the gun kicks on firing, legs tuck when rising and dangle when falling, the kick extends a leg, landings dip the body, and he has crouch and slide poses. The coat tails and mantle tail follow the motion with simple secondary physics.

## 3. Game Structure

```
Overworld (hand-built, same every run)
   └─► Dungeon entrance
          └─► Area 1 (randomly generated) ─► Shop room ─► Area 2 ─► Shop ─► ...
```

- **One seamless world, no loading screens** (as in Noita): the overworld and the areas below it are a single continuous level. The whole world is there from the start of a run — you walk to the mine shaft and drop straight down into Area 1, and could dig down from anywhere. Areas are stacked vertically under the overworld.
- **Overworld:** hand-crafted, consistent across runs. Eventually large and explorable; for now a walkable area that leads to the dungeon entrance.
- **Areas:** each is randomly generated and ends at a **shop room**, which then leads into the next area (as in Noita).
- **Background generation:** a new run builds the overworld at once (~0.25 s) and generates Area 1 a few milliseconds per frame while the hunter is still on the surface (~3.5 s, finished long before anyone can walk to the shaft). If the hunter gets underground first, the rest is generated immediately.
- **Shop room:** for now, simply the endpoint of an area's generation — an empty room that exists. No items or purchasing yet.

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

### 5.5 Ammo types & attachments **[Later]**
Placeholder — to be designed once the base guns feel right. Each gun has its own number of slots for them (revolver: 4), separate from its chamber count.

### 5.6 Item bar & weapon panel
Noita-style, along the top-left of the screen:
- **3 weapon slots** (keys **1–3** or the mouse wheel select one; the selected slot is outlined in gold), followed by **7 slots** for loose ammo types and attachments.
- **Tab** opens the weapon panel in the middle of the screen and **pauses the game**. Each carried weapon gets a card with its stats and its own ammo/attachment slots. Anything in a slot can be dragged to another slot (dropping on a full slot swaps them); weapons only go in weapon slots, ammo/attachments everywhere else. Hovering shows the name. Tab or Escape closes it.
- The inventory belongs to the run: it carries over between areas and resets on restart. All carried guns keep reloading, held or not.

## 6. World & Terrain

- **Pixel terrain, destructible, static materials.** Bullets and explosions carve holes in terrain. Detached chunks/debris may fall. No fluids, gases, or fire spreading in this milestone.
- Built so a full falling-sand simulation (sand, liquids, fire, gas) can be added later without a rewrite.
- **Materials (initial):** e.g. dirt (easy to destroy), rock (harder), bedrock (indestructible, used for area bounds).

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
- Terrain that gets cut loose (no longer connected to bedrock/brick) **falls as physics debris**: it becomes a rigid body carrying its own pixels, with mass from its materials. Tiny pieces (< 15 px) crumble to particles; loose pieces larger than 1024 px stay put (keeps large floating landmasses stable and the check cheap). Up to 60 debris bodies exist at once.

## 7. Procedural Generation
- Each area is generated at the start of the run/area: caves and tunnels carved through terrain, a guaranteed traversable path from the entrance to the **shop room** at the end.
- The path must be reachable with walking + jumping + recoil jumping.
- **Area 1 ("The Catacombs")**: 1920×3680 px (the full width of the world, directly under the overworld), a **descending** cave. Dirt pockets in rock (more dirt near the top), organic caves (cellular automata, with rounded ceilings near the top), **6–8 large open caverns** spread down its depth (up to ~640×380 px; ragged edges, flatter floors, 3–6 rock ledges each), a timber-ledged entrance chamber at the top under the mine shaft, and the brick shop room at the bottom.
- **Multiple intertwining routes:** three routes (one wide, two narrower) lead from the entrance down to the shop, each built from **vertical drops** (220–480 px, now and then a slanting one) alternating with **level corridors** (300–1000 px) that only wander gently up and down — so a route never climbs and is easy to walk and fall through. Extra corridors and drops scattered across the cave (10 and 6) cut through the routes, so they cross into each other and you can switch between them.
- **Never fails:** the finished area is checked with a reachability search (a coarse 4×4-px grid); if no route is found a straight emergency tunnel is carved. Seeds are shown on the area banner.

### 7a. Overworld ("The Barrens")
Hand-built and the same every run: a **desolate desert at dusk** — dusty sand over banded red sandstone, canyon walls at each end, a violet-to-ember evening sky with a low setting sun, a few early stars, drifting dust haze, and parallax mesa silhouettes. Along the way: a practice range, dead trees, **crumbling ancient ruins** (broken stone pillars, a lintel fragment, a low wall remnant, a fallen column) around a smoking **campfire**, a mesa and a natural sandstone arch. On the right a weathered timber **mine headframe** with a hanging lantern stands over the shaft, which runs straight down (timber-lined, open all the way) into the catacombs' entrance chamber. The headframe's left leg and brace are background scenery, so the hunter walks straight in from the left without having to shoot through anything; the right leg and the crossbeam are solid timber. The ruins use breakable stone brick. Warm evening ambient light, not night.

### 7b. The Catacombs
The generated area (above) under the dark-fantasy palette: the light blends from the warm surface ambient to dim but readable cave light as the hunter goes underground (the sunlight fades with it), and the backdrop behind the rock gets gloomier with depth. Entering it shows the "The Catacombs" banner; clusters of glowing teal fungus scattered across the cave floors (they light the way), and a candlelit stone shop room with wall sconces and candles on the counter.

## 8. Targets & Enemies
- **Test dummies / targets** on the surface practice range and in the test room, for checking damage numbers and hit detection.
- **Enemies** (first batch), all pixel-collision creatures like the hunter: they collide with terrain **and physics objects** (crates, fallen debris) — standing on them, and ghouls shove crates in their way (and hop over them when chasing). While active, each has a kinematic physics stand-in, so falling crates and debris land on them; acid globs splash on objects and nudge them. Bullets hurt them (with knockback from the gun's impact force), kicks hurt and shove them, and being shot wakes them and sets them on the hunter. They notice the hunter only with a clear line of sight. Bullets start at the hunter's shoulder, so a monster pressed against him (closer than the muzzle) can still be shot.

| Enemy | HP | Behaviour | Damage |
|---|---|---|---|
| **Ghoul** | 30 | Hunched, ash-pale scavenger with red eyes. Shuffles about when idle; on sight (280 px) chases at 62 px/s (slower than the hunter), hops up ledges, and lunges when close. Gives up beyond 460 px. | 12 on contact |
| **Cave bat** | 8 | Hangs asleep from ceilings; on sight (210 px) flutters at the hunter, bites, veers off for 0.8 s, and comes back. | 6 on contact |
| **Spitter** | 20 | Fleshy sac clinging to a ceiling. On sight (300 px) swells up (0.45 s tell) and lobs an acid glob in an arc that lands on the hunter, every 2.4 s. Globs can be dodged or shot down. Falls if its rock is shot away. | 10 per glob |

- **Placement:** each generated area places its monsters at generation: none near the entrance or in the shop, at least 48 px apart, and **more and tougher deeper down** (spawn chance 35% at the top to 100% at the bottom; HP up to ×1.6). About 70 per area. Only monsters within ~520 px of the hunter are active.
- **[Later]** more types (e.g. a heavy brute), loot drops, respawning.

## 9. Economy & Shop **[Later]**
Gold, buying weapons and ammo/attachments, shop inventory generation.

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

## 11. Open Questions
- Overworld size and contents for the long-term version.
