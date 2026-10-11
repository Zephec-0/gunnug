# Gunnug — Design Document

> Living document. Sections marked **[Later]** are intentionally deferred; we'll revisit them once the current milestone is playable.

## 1. Concept

A 2D roguelite dungeon crawler built on the bones of **Noita**: pixel-simulated, destructible terrain and a deep, buildable weapon system. Noita's wizard, wands, and spells are replaced with a gunslinger, firearms, and ammunition/attachments drawn from the **Western era up to (but not including) WW1**.

- **Engine:** LÖVE 11.5 (via the bootstrap-love2d-project template)
- **Controls:** Mouse aim + WASD
- **Platforms:** Windows first; template supports others later

## 2. Art Direction

- Pixel art in the spirit of Noita, but **more vibrant** — saturated palette, strong contrast between terrain materials, punchy muzzle flashes and impacts.
- **Rendering:** the game draws to a low-resolution canvas of **400×225** (zoomed in 20% from the original 480×270) that fills the window. Non-whole-number scales (e.g. 4.8× at 1920×1080) use "sharp bilinear" scaling: a crisp whole-number upscale followed by a smooth fit, so every pixel stays the same size. One game pixel = one terrain pixel.
- **Camera:** keeps the player centred (leaning slightly toward the aim) and is not clamped to the level; past a level's edge, the edge terrain continues.
- **Character:** a lanky gunslinger (hat, poncho, jeans) drawn as 1-pixel limbs on a procedural skeleton rather than sprite frames: legs walk via inverse kinematics, both hands grip the gun and follow the aim, the gun kicks on firing, legs tuck when rising and dangle when falling, the kick extends a leg, and landings dip the body.

## 3. Game Structure

```
Overworld (hand-built, same every run)
   └─► Dungeon entrance
          └─► Area 1 (randomly generated) ─► Shop room ─► Area 2 ─► Shop ─► ...
```

- **Overworld:** hand-crafted, consistent across runs. Eventually large and explorable; for now a walkable area that leads to the dungeon entrance.
- **Areas:** each is randomly generated and ends at a **shop room**, which then leads into the next area (as in Noita).
- **Shop room:** for now, simply the endpoint of an area's generation — an empty room that exists. No items or purchasing yet.

## 4. Player

### 4.1 Movement
Modelled on Noita: walk, jump, air control, gravity, collision against pixel terrain (including walking up small slopes/steps). The player's hitbox is 5×12 px, and the player feels **80% of world gravity** (its own gravity scale, like physics objects have) with strong air control, so it stays manoeuvrable in the air.

**Levitation is replaced by recoil jumping.** Firing a weapon pushes the player in the direction opposite the shot. Firing downward launches the player upward; this is the primary means of gaining height and crossing gaps. Each weapon has its own recoil strength, so weapon choice affects mobility (e.g. the shotgun is a strong "jump" gun).

- Recoil pushes in **all directions** opposite the shot, but is **mainly an airborne mechanic**: while standing on the ground, recoil is significantly reduced.
- Recoil jumping has **no extra limit** — it is bounded only by the gun's chambers and reload time.

### 4.2 Kick
Kept from Noita. A short-range kick (**F**) that shoves loose objects (and later enemies) in the facing direction.

### 4.3 Health
- Same model as Noita, displayed as a number. Player starts with **100 HP**.
- **Current milestone:** HP is static at 100 — no damage is taken. **[Later]** damage sources, death, healing, max-HP upgrades.

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
- Every gun fires its **default round** with its own base damage and behaviour. Ammo types and attachments fitted in the gun's slots will later alter how shots behave (exact rules to be designed — see §5.5).
- Every gun has an **impact force**: the impulse a bullet applies to physics objects where it hits. Deliberately larger than realistic (a crate shot should skip across the room), and a stat that ammo types/attachments can modify later (e.g. heavy slugs).

### 5.3 Base weapon archetypes
Starting tuning values — to be adjusted by feel.

| Archetype | Example | Chambers | Fire delay | Reload | Spread | Damage / shot | Recoil | Notes |
|---|---|---|---|---|---|---|---|---|
| **Revolver** | Single-action revolver | 6 | 0.25 s | 1.2 s | 2° | 10 | Medium | **Current milestone focus** |
| Shotgun | Double-barrel | 2 | 0.35 s | 1.5 s | 15° (cone) | 6 × 7 pellets | High | Best recoil jumper |
| Semi-auto | Broomhandle-style pistol | 10 | 0.15 s | 1.6 s | 3° | 7 | Low | Fast follow-ups |
| Automatic | Hand-cranked / early machine gun | 40 | 0.06 s | 3.0 s | 6° | 4 | Low per shot, sustained | Long reload |

### 5.4 Era scope
Weapons from the Western period up to pre-WW1 (e.g. revolvers, lever-action rifles, double-barrel shotguns, derringers, Gatling and Maxim guns). No modern firearms. Specific weapon roster **[Later]**.

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
- **Terrain collision:** the pixel terrain is traced into collision outlines, split into chunks, so destroying terrain only rebuilds the outlines of the chunks it touched.
- **Forces on objects:** bullets apply their gun's impact force at the exact hit point; kicks apply a fixed impulse. Heavier objects move less from the same force.
- **Player interaction:** the player stays on precise pixel movement (not a physics body), but:
  - can **stand** on objects, and is carried along by them,
  - **pushes** objects by walking into them (heavier objects push slower),
  - **kicks** them,
  - blocks objects falling onto them.

### 6b. Destruction rules
- A bullet digs a small crater (revolver: radius 2.5 px, power 1). Each pixel in range is removed with probability *power / hardness*: dirt and sand (1) break readily, sandstone and wood (2) take a couple of hits, rock (3) chips slowly. Bedrock and brick never break.
- Terrain that gets cut loose (no longer connected to bedrock/brick) **falls as physics debris**: it becomes a rigid body carrying its own pixels, with mass from its materials. Tiny pieces (< 6 px) crumble to particles; loose pieces larger than 400 px stay put (keeps large floating landmasses stable and the check cheap). Up to 60 debris bodies exist at once.

## 7. Procedural Generation
- Each area is generated at the start of the run/area: caves and tunnels carved through terrain, a guaranteed traversable path from the entrance to the **shop room** at the end.
- The path must be reachable with walking + jumping + recoil jumping.
- **Area 1 ("The Old Mine")**: 512×1152 px, a **descending** cave. Dirt pockets in rock (more dirt near the top), organic caves (cellular automata), a main tunnel that winds downward but never climbs, a timber-ledged entrance chamber at the top, and the brick shop room at the bottom. Every generated area is checked with a reachability search; failures retry with a new seed, and as a last resort a straight tunnel is carved, so generation can never fail. Seeds are shown on the area banner.

### 7a. Overworld ("The Badlands")
Hand-built desert canyon, same every run: dunes of sand over banded sandstone, canyon walls at each end, two mesas and a natural arch (recoil-jump targets), cacti, a sky with a sun and parallax mesa silhouettes, and a small shooting range at the start. The **old mine** on the right is a timber headframe over a shaft; dropping to the bottom of the shaft enters the dungeon.

## 8. Targets & Enemies
- **Current milestone:** no enemies. **Test dummies / targets** are placed for checking damage numbers and hit detection.
- **[Later]** enemies, AI, loot drops.

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

After Milestone 1, add the shotgun, semi-auto, and automatic archetypes, then start designing ammo types and attachments.

## 11. Open Questions
- Overworld size and contents for the long-term version.
