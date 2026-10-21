# Camp people and weapon unlocks (as built, 2026-10-21)

Everything is per save profile (`src/meta.lua`). "Deaths" = `stats.deaths`; a new run starts after each one.

## When and where each person is found

"Resets" = runs begun after another (a restart, or a new run after a death), counted per save (`stats.resets`; older saves start from their deaths).

| Person | Where | Opens up when | How they are freed |
|---|---|---|---|
| Gunsmith | Sunken Hollows (area 2), in a cage | after 1 reset | shoot the padlock |
| Apothecary | Sulfur Vents (area 3), in a cage | after 1 reset | shoot the padlock |
| Cartographer | The Quarry, in a cage | after 1 reset | shoot the padlock; she drops the flare gun |
| Bartender | Oasis pond at camp, drinking | after 1 reset | talk to him (E); he stays put, and the saloon goes up once neither the pond nor his lot is on screen |
| Prospector | Old Mine, buried under rubble | after 3 resets | dig the rubble off him (his Perk Shelf is an upgrade) |
| Taxidermist | Cinder Warrens, in a cage | the bounty board is up (an elite slain, then a death) | shoot the padlock |
| Sawbone | Flooded Caverns, floating near the lake's right edge | always | press E to wake him; he drops the crossbow |

## Bartender (new)

- Drinks cost marks and are drunk when bought. Each lasts 5 min of underground time (A Stiffer Pour adds 50% per tier); buying again resets the timer. Nothing carries to the next run.
- Drinks sit on two shelves (3 to a shelf); only stocked ones show. Click a bottle to buy it (a gulp plays). Another of the same stacks its buff, not its time. Past 3 drinks in you the aim and view wander (worse each drink); at 10 you pass out and the run resets. Active drinks show beside the perk badges under the hotbar.
- On the shelf at the start: Redeye Whiskey (+15% damage, 1 mark), Cold Lager (1 hp per 2.5 s, 1).
- Back-Room Stock I (4 marks): Black Stout (+25 max health, 2), Quickshot Gin (+15% fire rate, 2).
- Back-Room Stock II (8 marks): Hopper's Cider (+20% jump, +10% speed, 2), Gold Rush Mead (+30% gold, 3).
- House Rules (6 marks, one tier) unlocks the old debuff switches (Rotgut, Powder Keg, Lean Times) that pay extra marks. The section only appears once bought.

## How weapons reach the drop pool

The pool starts as revolver, shotgun and semiauto. Every other gun (automatic, gatling, crossbow, flare) is locked: it cannot drop, sit in a shop or come out of a chest as a normal roll. To unlock one:

1. **See it.** Pick one up, or leave one lying within about 110 x 80 px of the hunter (`game.lua`, every 0.25 s). The Gunsmith's page shows only seen guns.
2. **Teach it.** At the Gunsmith's camp page, pay 6 marks to have him craft it. It then joins the pool for every run on the profile.

Ways a locked gun shows up to be seen:

- Weapon chests: 20% of chests hold a weapon, and 30% of those are a locked kind (so about 6% of chests).
- Vault chests: always one locked gun.
- Bosses: 40% chance the prize weapon is a locked kind (never worse than grade A).
- Freeing a prisoner (not the Prospector): a gift gun of a locked kind on the cage floor.
- Special cases (never in random drops): the Gunsmith's first rescue gifts the **automatic**; the Sawbone, when woken, the **crossbow**; the Cartographer, when freed, the **flare gun**; the Queen of the Sulfur Vents drops the **gatling** until it is crafted. Having freed the giver also lets the Gunsmith craft theirs.

Ammo types and attachments are gated the same way (see, then teach). Teach costs: weapon 6, common 2, cursed 3, rare 4, epic 8 marks. Fused and common items are free from the start.

Knobs to adjust later: `STARTER_WEAPONS`, `TEACH_COST`, `SPECIAL_GUNS` and `canFind` in `meta.lua`; `GOLD_CHANCE` and `LOCKED_CHANCE` in `chests.lua`; the 0.4 locked-gun roll in `enemies.lua` (boss prize).

## Gunsmith's stock (new)

Unlocked guns can be bought from the Gunsmith for gold, one per run, always B-grade: shotgun 50, semiauto 80, flare 100, automatic 200, crossbow 200, gatling 300 (`meta.GUN_PRICES`). A freed person's cage no longer returns in later runs.
