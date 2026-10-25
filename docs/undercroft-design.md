# The Undercroft, secrets and hat rules (design draft, 2026-10-24)

Nothing here is built yet. Names are placeholders. It follows the sky dungeon's tone: **found, not told**. No signs, no quest log; the game only ever hints.

The sky route ends with the Champion and the eclipse. The Undercroft is the second ending, a **descent** below the Deep.

## 1. How the Undercroft opens

The Big Fish does not open it. A sealed floor under the Deep's last shop only opens to a **Relic** (working name: the Sunken Key). The Relic does nothing in a normal run, so it can't be mistaken for loot. It is carried to the Deep, put in the floor and turned.

The Relic comes from the **Buried Vault**, which is reached by digging (§2). So the chain is:

1. Find the Buried Vault's mountain.
2. Gather the items that open its door.
3. Take the Relic from inside.
4. Carry it to the Deep and open the floor.

The Relic is an attachment slot item, so it can be lost on death and has to be recovered or re-earned each run until it is **spent**. **Decided:** once the Undercroft is opened it **stays open on the profile for later runs**. The Relic is spent on the first opening.

## 2. The Buried Vault

- **Location.** Inside solid rock, under a mountain or a wall of hard rock away from any route. Everything around it and the entrance is **hard rock** that ordinary rounds barely scratch.
- **Digging gate.** The rock round the vault and its entrance is **vault rock**: undamaged by anything except the ammo and attachments in §2a. It needs a hard threshold (a minimum dig power), not the usual chance-based chipping, because ordinary hardness only changes how long digging takes and never stops it. Everything else, including explosives, leaves it untouched.
- **A collectible hidden under it.** One of the items for the door sits under the mountain, in a pocket only the same digging reaches. The player never sees a marker. The only hints are an odd lump in the terrain and the compendium.
- **The door.** Locked by **fused items**: a door of slots, like the fuser, that takes specific fused items rather than loose ones. It checks for a fused result, not individual ammo, so it also tells the player the fuser matters. The recipe is not printed anywhere. Fragments of it sit on cave walls, in NPC lines and in the compendium's fusion pages once the player has seen each ingredient.
- **Inside.** A short, quiet vault with no monsters. The Relic sits on a pedestal. This place is a reward, not a fight.

### 2a. What can dig vault rock

Dig works by chance: a bullet's `digPower` against a material's `hardness` (dirt 1, sandstone 2, rock 3; guns start at power 1, the chance per pixel is power / hardness; `math.huge` is indestructible). Items that bite terrain today (audited from `items.lua` and `items_batch2.lua`):

| Item | Dig effect | Opens vault rock? |
|---|---|---|
| Auger Rounds | radius +3, power +2 (reaches hard rock) | yes |
| Corkscrew Rounds | radius +3, power +2, boomerangs and digs again | yes |
| Acid Rounds | radius +1 ("eats rock a little") | yes (flagged) |
| Blight Rounds | radius +1 (poison and acid, same rock bite) | yes (flagged) |
| Piercing Rounds | power +1 | no |
| Brass Jackets | radius +1, power +1 | no |
| Prospector's Pick | radius +1, power +1 | yes (flagged) |
| Treasure Hunter's Barrel | power +1 | yes (flagged) |
| Explosive, Unstable, Demolition Sleeve, Phoenix | a blast bite, power 1.5 | no |
| The hunter's thrown dynamite, kegs, a miner's dynamite | blasts, up to crater 33 / power 3.5 | no |
| Enemy digging (claws, worms) | power up to 40 | no |

Phase Rounds (bullets fly through terrain and never dig) are excluded.

Notes:

- The unflagged mild diggers (Piercing, Brass) still add up with the base gun, and flagging is explicit rather than by power, which is why a power threshold was rejected in favour of the flag. The Pick and the Barrel are flagged too, so the two gold-hunting attachments are a way in as well.
- Acid and Blight raise the dig radius but not the power, so the flag is what lets them work on vault rock, without changing how they behave on soft ground.
- **Decided (final):** **no explosion digs vault rock**: not explosive ammo, Unstable Rounds, the hunter's dynamite, kegs or a miner's sticks. Blasts are the easy way through ordinary rock, so the vault is the one place they do not work.
- **Decided:** a `vaultDig` flag, set on Auger, Corkscrew, Acid, Blight, Prospector's Pick and Treasure Hunter's Barrel only. Stacking mild diggers does not count. Only the flag opens vault rock; dig power and blasts never do. A new item opens it only if it is given the flag.

## 3. The Hollow King (the Undercroft's final boss)

It **mimics the others**: it opens each phase with an attack lifted from an earlier boss, so players who learned the game recognise them (the Queen's globs, the Golem's slams, the Big Fish's lunges, the Champion's light). But it keeps its own identity so it isn't a rematch:

- **Its own look.** It is not a monster in a hole. It is the *thing under the world*: a hollow, vaguely crowned figure assembled from the debris of the descent (bone, rubble, fossil, cooled magma), with its faces swapping as it borrows a boss's move.
- **Its own rule.** The fight is about **terrain**. The Undercroft is made of diggable rock and the King collapses, floods and re-forms the arena. The player is tested on digging, recoil jumping and holding ground, not just dodging.
- **Its own tell.** Every borrowed attack is **slower and more telegraphed**, so it is readable, and then it fuses two of them in the last phase.
- **Its own reward.** **Decided:** destroying the core turns the world to **dust and volcanic ash**: the overworld darkens to ash and the Undercroft's heat breaks out, mirroring the eclipse for the sky.

Reuse: the hunter and boss music hooks in `audio.lua` (add a `king` track), and the existing arena sealing in the catacombs scene.

## 4. The Descent

Three or four zones, each shorter and heavier than the sky: fossil beds, a magma sea, a buried city, then the core. The rule is the sky's opposite: **pressure, heat and no sky**. Light is the scarce resource (the lighting shader already makes this strong), and gravity is normal or heavier where the sky's is low.

## 5. Secrets

Each secret is a small, real discovery with a concrete reward. All are per profile unlocks and show in the compendium once found, but never before.

- **Ace of Spades.** In the high-low card game, win the Ace of Spades and drag it to the toolbar. It becomes a **unique attachment/ammo type** (an item that exists nowhere else).
- **One of each drink.** Drink every bartender drink type in a single run to get a **unique perk**.
- **Speed.** Reaching a certain speed (a long slide, a recoil chain, a fall) unlocks a specific ammo type the first time it happens.
- **The vault chain.** The Buried Vault itself (§2).

Rule for new secrets: it is built from something the game already does, it never needs a menu, and it never punishes a player who doesn't find it.

## 6. Hats: rules for a run

The hat the hunter wears (the crown and brim are already drawn apart for swapping) sets a **rule for the run**, chosen at the start. Each hat makes the run harder or stranger and **completing it (defeating a boss) unlocks something**.

**Decided:** the Bartender's House Rules debuffs (Rotgut, Powder Keg, Lean Times) are **disabled during an altered run**, so hat rules never stack with them.

Candidate rules, each a switch in the existing run setup:

| Hat | Rule |
|---|---|
| Plain hat | No change (the normal run) |
| 10 HP hat | Start and stay at 10 max health |
| One-slot hat | One weapon slot only |
| Manual-reload hat | Reloads are manual, no auto reload |

More can be added in the same way. Open points:

1. **What completing a run unlocks.** Each hat's win unlocks something *specific to it* (a cosmetic, a weapon, an ammo type, a bartender drink), so the hats are goals and not just handicaps.
2. **How it is chosen.** A hat stand at camp, not a menu, in keeping with the rest of the camp.
3. ~~How it combines with the House Rules debuffs~~ Decided: disabled.

## 7. Open questions

- Decided: the Undercroft stays open across runs once opened; the Hollow King turns the world to dust and ash; House Rules are off in hat runs. The vault-rock rule is decided too (§2a). Nothing is open except the details of building it.
- Should the Undercroft count as its own ending in the death recap and the compendium?

## 8. Build order

Each step is playable or screenshot-testable on its own, and later steps only depend on earlier ones. Where I name a file it is the one that owns that system today; I haven't opened them all to plan the edits, so treat the file hints as starting points.

1. **(Built 2026-10-24, headless-tested, not played.) Vault rock and the `vaultDig` flag** (`materials.lua`, `destruction.lua`, `bullets.lua`, `items.lua`, `items_batch2.lua`). A new indestructible-unless-flagged material. `vaultDig` is added to the six items in §2a, carried from the item mods onto the shot, and checked in `destruction.dig`. Test: in the test room, shoot a patch of vault rock with each item and with an unflagged gun and explosive.
2. **(Built 2026-10-24, headless-tested, not played.) Save flags** (`meta.lua`, `save.lua`). Per profile: `undercroft = { open, beaten }`, `secrets` (id to true) and `hatWins` (hat id to true), with `meta.undercroftOpen/openUndercroft/undercroftBeaten/beatUndercroft/secretFound/findSecret/hatWon/winHat`. Old saves are repaired on load. The Relic itself is an item, not a flag. Save and load must keep them across runs and old saves must still load.
3. **(Built 2026-10-24, headless-tested, not played.) The Buried Vault** (`buriedvault.lua`, called from `scenes/overworld.lua`). Decided: it sits **under the Needle**, in the plain's rock just below the mountain's box (x 6780 to 7220, y 1100 to 1380). The Needle's lowest caves reach y 1082 to 1085 there, so the way in is to dig down a short way from them. The block is solid vault rock, hollowed into an antechamber, a brick divider where the door goes (step 4) and a room behind it for the Relic, plus a small sealed pocket for the first door item. Coordinates are in `buriedvault.info`. Not yet done: the door, the item in the pocket, any visual tell (it currently looks like ordinary rock).
   Original plan: Generate it in solid rock in one existing area: hard-rock shell, the buried pocket for the first door item, the door. Needs step 1.
4. **(Built 2026-10-24, headless-tested with screenshots, not played.) The fused-item door** (`relicdoor.lua`, hooked through `events.lua`). The recipe is **Thermal Shock Rounds (incendiary + frost), Sungold Rounds (gilded + glowing) and Shrapnel Rounds (ricochet + splitting)**, all fused from common items so no unlocking is in the way. The sealed pocket holds a Sungold Round, so one key can be found instead of fused. Press E at the door from the antechamber with a matching item in your loose items or an unlocked fuser slot: it is spent and its socket lights in the item's colour. With all three set the wall between the rooms opens. The sockets show the items' two-letter codes (TH, SG, SR), and the key prompt appears only when you carry a matching item. The door resets each run. Not done: the hints elsewhere in the world, and a proper door art pass.
   Original plan: A door that takes specific fused items and opens when it holds the recipe. Place the fused items' fragments of the recipe (cave walls, NPC lines, compendium fusion pages).
5. **(Built 2026-10-24, headless-tested with screenshots, not played.) The Relic** (`items.lua`, id `sunkenkey`, name "The Sunken Key"). A loose item (no mods, rarity `relic`) resting on a brick pedestal in the Relic's room. It never generates, never appears in shops, the compendium or the Gunsmith's pages, and cannot be sold on the mat. Picking it up and carrying it is all it does; it is lost if you die with it, and a new vault is built each run. Saves restore it by id. The first Undercroft opening is permanent (step 2), so later runs do not need it again.
   Original plan: An attachment-slot item that does nothing in play, found on the pedestal inside the vault, and carried to the Deep. Needs steps 2 to 4.
6. **(Built 2026-10-24, headless-tested with a screenshot, not played.) The sealed floor under the Deep** (`deepseal.lua`; `secrets.lua` now gathers the hidden-thing hooks that `events.lua` calls). The Deep has two shops; the way is under the **right-hand** one, in the small room under its floor with the teleport pad: an iron plate with a keyhole, a faint amber glint and no text. With the Sunken Key, E turns it: the Key is spent, the plate gives, a 26-wide shaft opens (60 px deep for now, ending in rock) and `meta.openUndercroft()` makes it permanent. On a save that has already opened it, the shaft is open from the start. The prompt `[E]` only shows when you carry the Key. Step 7 builds the first zone at the foot of the shaft (`deepseal.shaft()` gives its coordinates).
   Original plan: A floor that takes the Relic, spends it, sets "Undercroft open" and opens the way.
7. **(First pass built 2026-10-24; see test notes below.) The Undercroft's first zone, the Fossil Beds** (layout entry 14 in `scenes/catacombs.lua`, x -2800 to -401, y 5160 to 8259, tier 5, theme derived from the Quarry's, the Quarry's music via `AREA_TRACK`). It is dormant: nothing builds it until the Sunken Key has turned the sealed floor, and it builds itself as soon as that happens. The Deep now builds **one shop** (theme flag `oneShop`), at its right-hand corner, so the sealed floor sits under the only shop. Pixel art, fossil dressing and a shop of its own are the polish still to do.
   Original plan: (`cavegen.lua`, `scenes/catacombs.lua`, area themes in `visuals.lua`). One descent zone (fossil beds) built like the other areas: theme, lighting, monsters, shop. Prove the descent works before building the rest.
8. **(Built and rethemed 2026-10-24; see test notes.) The other three zones** (layout entries 15 to 17 in `scenes/catacombs.lua`, each through the hatch of the one above): **The Greywacke** (hard grey rock with a green-brown cast over red clay, y 8260 to 11059; clay-red strata, scree and lichen), **The Buried City** (old grey slate over clay, dust lying in drifts, y 11060 to 13659) and **The Core** (dark brown and grey rock, soot and seams of magma, with the Hollow King's hall and the one shop). The Fossil Beds and the Greywacke reuse the Quarry's and the Needle's creatures; the Buried City and the Core add two of their own (`undermobs.lua`): the **Slagback**, a crawling heap of slag that leaves molten pools and spits lava, and the **Ash Shade**, a drifting column of volcanic ash that breathes out a fan of stinging ash. Their music borrows the Foundry's, the Silt Vaults' and the Deep's tracks until they get their own. They count their own numbers as "deepest reached" (14 to 17), so a save file's "Deepest" names them. Magma Sea and Buried City's own fixes, new monsters and art are polish still to do.
   Original plan: (magma sea, buried city, core). Each with its own theme, monsters and music (`audio.lua` TRACKS). Check every one for the missing-music gap noted earlier.
9. **(First pass built 2026-10-24; see test notes.) The Hollow King** (`hollowking.lua`; his own theme in `audio.lua`). He floats in the Core's boss hall and wears the Queen's, the Golem's and the Fish's face in turn (health lines at 75, 50 and 25 percent): lava globs, then a slam that sends a wave of rock along the floor each way with stones off the roof, then a marked lunge. From the third turn the roof comes down (a column of dust warns where, then a stone falls), and the last turn is all of it. He cannot be hurt while he changes face. When he falls the core goes out: `meta.beatUndercroft()` is set (the dust-and-ash change to the world is step 10).
   Original plan: (a new `hollowking.lua`, modelled on `starwarden.lua` and `darkhunter.lua`; `audio.lua` BOSS_TRACKS; `compendium.lua`). First the arena and the terrain-collapse rule, then one borrowed attack per phase, then the fused last phase and its art.
10. **(Built 2026-10-24, headless-tested with screenshots, not played.) The ash ending** (`weather.lua`, `scenes/overworld.lua`). Once the Hollow King has fallen on a save (`meta.undercroftBeaten()`), the surface changes for good: the sky is smoke (grey and brown, bands of ash cloud, bruised red at the horizon, the sun a dull red disc, no stars), a far volcano with a glowing crater and a plume stands among the distant mountains and the far scenery is darker; the day is dull and hazy (less colour, sun shafts smothered, a little more wind) and ash flakes drift down over the whole surface. It fades in over a few seconds when it first happens. Not done: dusty ground on the surface rock, the title screen, camp people's lines, and a check that the volcano is easy to see from the camp.
   Original plan: (`weather.lua`, `visuals.lua`, `town.lua`). Dust and volcanic ash across the overworld after the core falls, and the title screen if the sky route's eclipse has one.
11. **(Built 2026-10-25, headless-tested with screenshots, not played.) Hats and the altered-run rules** (`meta.lua` HATS, `npcs.lua`, `menu.lua` PAGES.hats). A hat stand stands by the camp's tent (E: Change hats) with a menu page listing four hats. **The Old Hat** (no rule), **Glass Hat** (ten health, nothing raises it: `perks.maxHp`), **Lone Hat** (one weapon slot: `inventory.weaponSlots`) and **Reloader's Hat** (guns never reload themselves: `guns.manualReload`; right click still reloads by hand). The hat worn is the profile's choice (`p.hat`); it is fixed when a run begins (`meta.beginRun`), changes the band on the hunter's hat, and turns the Bartender's house rules off for that run. Beating any boss in a run under a hat for the first time (`meta.hatBossKilled`, called from the boss-killed hook) unlocks that hat's reward for good: Glass Barrel, Holster Loader or Overclock taught for free, plus 10 marks. Not done: the Undercroft's own unlocks per hat, more hats, and a visible crown/shape for each hat (only the band colour differs).
   Original plan: (`menu.lua`, `game.lua`, `player.lua`, `inventory.lua`, `bartender` code in `npcs.lua`). The hat stand at camp, the rule switches (10 HP, one slot, manual reload), the House Rules debuffs disabled, and the per-hat unlock on a boss win. Independent of steps 3 to 10, so it can be built any time after step 2.
12. **(Built 2026-10-25, headless-tested with a screenshot, not played.) Secrets.** Three, none listed in the compendium until found. **The Ace of Spades** (`items.lua` `aceofspades`, `eventui.lua`): when the Ace of Spades lies on top of the pile at the High-Low table it can be picked up and dragged onto the item bar; it becomes a unique ammo (critical hits +40% likely, far worse, plain hits 10% weaker; never sold or found). **The House Regular** (`perks.lua` `regular`, `meta.buyDrink`): drinking one of each of the Bartender's six drinks in a single run gives an epic perk (+30 max health, 10% less damage, never drunk or passed out); it needs both Back-Room Stock tiers. **Redline Rounds** (`items.lua` `redline`, `meta.speedFeat`): moving at 500 px/s or faster for a moment (the cap is 576, so only stacked recoil gets there) unlocks Redline Rounds (bullets 50% faster, 15% harder, more kick) for good; the compendium lists them after the next start. Each marks `meta.findSecret`. Not done: hints for any of them, and a way to show them once found.
   Original plan: (`items.lua`, `perks.lua`, the card table scene, the bartender code, `player.lua`). Ace of Spades attachment, the one-of-each-drink perk, the speed ammo unlock. Each is independent of the others, so they can be added one at a time.
13. **Polish and docs.** Compendium entries, death recap lines for the Undercroft ending, sounds, pixel art for the vault and the King, and the design doc's sections updated from this draft into the as-built notes.

Two things to settle at the start:

- **Where the vault's area is.** Which existing area the vault sits in (it should be one the player has to dig through to reach, not a corridor).
- **What the fused-item recipe is.** The two or three fused items the door needs have to exist in `items.fusions` and be reachable in a normal run.

## 9. The Hollow King's hall and look (redesign built 2026-10-25, headless-tested with screenshots, not played)

The first pass (step 9) is a crowned figure in a flat hall. The direction for the redesign:

- **The hall.** A large open chamber you **fall into** from above, not an arena you walk into.
- **The core.** In the middle hangs the **core**, a sphere-like shape with a **metallic look** made with the graphics engine (shaders), a prism-like shell. It is inert until it is **shot**: shooting it starts the fight.
- **The start.** The camera **zooms out and pulls to the core**, and shakes as the core **disintegrates into particles** outside of the prism shell.
- **The King.** Free-flowing: a **hive of particles** that moves like a swarm and takes the form of the other bosses in turn (the Queen, the Golem, the Fish), rather than a drawn figure. The turns, attacks and falling roof from the first pass can carry over.
- **Open questions.** How the particle swarm is hit and how its health works (a hitbox that follows the densest part of the swarm, or the core as the weak point); how many particles the game can draw; whether the fall-in replaces the pedestal.

As built: the Core is a hall 2160 wide and 1100 high that starts right under the way in, so the hunter falls into it (`arenaFrac` 0.06, no platforms). The core hangs 150 px over the floor in the middle, a faceted sphere of metal drawn by a shader (`hollowking.lua`, flat steps of colour to stay pixel art). The first shot wakes it (`e.woken`; no pedestal, no proximity trigger): the camera zooms out to 1.9 and shakes for 3.8 s while the sphere shrinks and flies off as about 380 bits, leaving a small metal prism at the heart. The bits flow on springs with a little noise toward the shape of each turn (the Queen's disc and crown, the Golem's blocky figure, the Fish, then a spiral hive), change colour per shape, and scatter when hit. The attacks, the falling roof and the death are as in the first pass, and he now drifts over the hunter. Still open: the hive's hit area is one box on its middle (not the prism or the densest cluster), no sound of its own for the metal, and the hall and the core look dark in play.
