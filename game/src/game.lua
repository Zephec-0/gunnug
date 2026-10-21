-- Top-level game state: owns the current scene, world, player and systems,
-- and wires them into LÖVE's callbacks (called from main.lua).
--
-- A scene module provides:
--   title, subtitle               banner shown on entry
--   build(opts) -> world, spawnX, spawnY
--   populate(world)               place targets/props (after physics exists)
-- and optionally:
--   update(dt, player, game, effects)  triggers, ambient effects
--   background()                  work that keeps going even while paused
--                                 (menus, the weapon panel), such as generation
--   ambient                       light level colour (default: fully lit)
--   addLights(lighting, camX, camY) light sources (lanterns, candles, moon)
--   drawFront(camX, camY)         world-space layer in front of the player (lit)
--   drawEmissive(camX, camY)      world-space glows drawn after the lighting
--   drawBackground(camX, camY)    on the low-res canvas, behind everything
--   drawDecor(camX, camY)         world-space decorations behind the player
--   drawScreen(toScreen, font)    full-resolution text such as signs
local audio = require("src.audio")
local bullets = require("src.bullets")
local camera = require("src.camera")
local juice = require("src.juice")
local fluids = require("src.fluids")
local ambience = require("src.ambience")
local critters = require("src.critters")
local weather = require("src.weather")
local bake = require("src.bake")
local chests = require("src.chests")
local compare = require("src.compare")
local visuals = require("src.visuals")
local devpanel = require("src.devpanel")
local config = require("src.config")
local effects = require("src.effects")
local deaths = require("src.deaths")
local enemies = require("src.enemies")
local fuser = require("src.fuser")
local guns = require("src.guns")
local hud = require("src.hud")
local input = require("src.input")
local inventory = require("src.inventory")
local items = require("src.items")
local itembar = require("src.itembar")
local lighting = require("src.lighting")
local menu = require("src.menu")
local menubg = require("src.menubg")
local meta = require("src.meta")
local bounties = require("src.bounties")
local events = require("src.events")
local surveymap = require("src.surveymap")
local npcs = require("src.npcs")
local perks = require("src.perks")
local fog = require("src.fog")
local physics = require("src.physics")
local pickups = require("src.pickups")
local Player = require("src.player")
local props = require("src.props")
local render = require("src.render")
local save = require("src.save")
local settings = require("src.settings")
local shop = require("src.shop")
local targets = require("src.targets")
local toasts = require("src.toasts")

-- The overworld scene is the whole world (surface and catacombs); the test
-- room is a separate tuning ground
local scenes = {
  overworld = require("src.scenes.overworld"),
  testroom = require("src.scenes.testroom"),
}

local game = {}

local scene, world, player
local inv -- the run's inventory; survives area changes, reset on restart
local pending -- { name, opts } of a scene to load on the next update
local fade = 0 -- black overlay alpha, fades out after entering a scene
local restartLatched = false
local restartHeld, restartFade = 0, 0 -- holding the restart key: seconds held, and the fade to black it brings on
local RESTART_FADE_AT, RESTART_TIME = 0.5, 2 -- the screen starts to fade after this long, the run restarts after this
local mouseVX, mouseVY = 0, 0
local showPhysics = false

-- Recording into the save slot (src.save): every weapon, ammo type and
-- attachment that reaches the inventory is counted once (the same object
-- picked up again isn't counted twice), and so is every perk taken in a run
local counted = setmetatable({}, { __mode = "k" })
local runPerks = {}
local lastGold = 0
local deathCounted
local playing = false -- a run is under way (not on the title screen)
local discoveries = {} -- this run's first-time compendium entries: { category, id }
local deadTime = 0 -- seconds the hunter has been dead (the recap follows the death animation)
local deathPhoto -- the killer, photographed the moment he died (false: nothing to photograph)
local RECAP_DELAY = 1.5
local DEATH_FADE_START = 0.3 -- the fade to the recap starts this long after the fall

-- Queues a scene change (a new run, or the test room). Loading happens next
-- update, after one blank frame.
-- Dev panel: teleports. The camp, areas and arenas live in the overworld, so
-- from anywhere else a fresh overworld is loaded first and the jump is made
-- once it is up.
local devQueue
function game.devTeleport(spec)
  if spec.kind == "test" then
    game.enter("testroom")
    return
  end
  local function go()
    scene.devTeleport(player, spec)
    camera.snap(player:center())
  end
  if scene == scenes.overworld and not pending and player then
    go()
  else
    game.enter("overworld", { atCave = true })
    devQueue = go
  end
end

function game.enter(name, opts)
  pending = { name = name, opts = opts }
end

local function load(name, opts)
  scene = assert(scenes[name], "unknown scene: " .. tostring(name))
  bullets.clear()
  effects.clear()
  enemies.clear()
  fog.clear()
  fuser.clear()
  pickups.clear()
  chests.clear()
  shop.clear()
  npcs.clear()
  events.clear()
  bounties.reset()
  compare.close()
  local spawnX, spawnY
  camera.setTop(nil) -- (a scene with a roof sets it as it builds)
  world, spawnX, spawnY = scene.build(opts)
  physics.init(world)
  surveymap.reset(world)
  scene.populate(world)
  player = Player.new(spawnX, spawnY, world, inv)
  bullets.player = player
  camera.snap(player:center())
  hud.showBanner(scene.title, scene.subtitle)
  fade = 1
  if devQueue then
    local go = devQueue
    devQueue = nil
    go()
  end
end

-- Saving and resuming a run ("Save and quit", src.save's saved runs) ------------
--
-- Restored: the seed (the world's areas grow from it, so the caves are laid out
-- exactly as before), where the hunter stood, his health, gold, guns (with their
-- rolls, fitted ammo/attachments and chambers), loose items, the fuser, perks,
-- glyphs, flasks, dynamite, keys and relics.
-- Not restored: changes made to the world (dug rock, spilled water, fires,
-- opened chests, broken props, bought shop stock), enemies (they spawn afresh,
-- slain bosses included), pickups on the ground, map chart and random events
-- under way. The hunter is moved to open ground if the rock he stood in was
-- one of his own holes.

local function itemData(item)
  return { id = item.id, level = item.level or 0 }
end

local function itemFrom(d)
  if type(d) ~= "table" or not items.defs[d.id] then
    return nil
  end
  local level = math.max(0, math.min(items.MAX_LEVEL, math.floor(tonumber(d.level) or 0)))
  return items.new(d.id, level)
end

local function gunData(g)
  local d = {
    id = g.id,
    name = g.name,
    slotCount = g.slotCount,
    chambers = g.chambers,
    spent = g.spent,
    generated = g.generated or false,
    tinkerRolls = g.tinkerRolls,
    rolls = g.rolls,
    slots = {},
  }
  for i = 1, g.slotCount do
    if g.slots[i] then
      d.slots[i] = itemData(g.slots[i])
    end
  end
  return d
end

local function gunFrom(d)
  if type(d) ~= "table" or not guns.defs[d.id] then
    return nil
  end
  local g = guns.new(d.id, math.max(1, math.min(8, math.floor(tonumber(d.slotCount) or guns.defs[d.id].slots))))
  if type(d.name) == "string" then
    g.name = d.name
  end
  if type(d.rolls) == "table" then
    g.rolls = {}
    for k, v in pairs(d.rolls) do
      if type(k) == "string" and type(v) == "number" then
        g.rolls[k] = v
      end
    end
  end
  g.generated = d.generated == true
  g.tinkerRolls = tonumber(d.tinkerRolls)
  g.spent = tonumber(d.spent) or 0
  g.chambers = math.max(0, math.min(99, math.floor(tonumber(d.chambers) or g.chambers))) -- (limited to the gun's size once the perks are back)
  if type(d.slots) == "table" then
    for i = 1, g.slotCount do
      g.slots[i] = itemFrom(d.slots[i])
    end
  end
  return g
end

-- Whether "Save and quit" is on offer: a living hunter in the overworld
function game.canSaveRun()
  return playing and not pending and player ~= nil and not player.dead and scene == scenes.overworld and save.activeSlot() ~= nil
end

-- What leaving a run saves
local function snapshotRun()
  local cat = require("src.scenes.catacombs")
  local b = player.body
  local run = {
    seed = cat.seed(),
    x = b.x,
    y = b.y,
    hp = player.hp,
    time = os.time(),
    inv = {
      gold = inv.gold,
      dynamite = inv.dynamite or 0,
      flasks = inv.flasks or 0,
      keys = inv.keys or 0,
      selected = inv.selected,
      secondWindUsed = inv.secondWindUsed or false,
      weapons = {},
      items = {},
      perks = {},
      glyphs = {},
      relics = {},
      fuse = { locked = inv.fuse.locked or false, ether = inv.fuse.ether or 0, slots = {} },
    },
  }
  local r = run.inv
  for i = 1, inventory.WEAPON_SLOTS do
    r.weapons[i] = inv.weapons[i] and gunData(inv.weapons[i]) or nil
  end
  for i = 1, inventory.ITEM_SLOTS do
    r.items[i] = inv.items[i] and itemData(inv.items[i]) or nil
  end
  for i = 1, 2 do
    r.fuse.slots[i] = inv.fuse.slots[i] and itemData(inv.fuse.slots[i]) or nil
  end
  for i, id in ipairs(inv.perks) do
    r.perks[i] = id
  end
  for id in pairs(inv.glyphs) do
    r.glyphs[id] = true
  end
  for idx in pairs(inv.relics or {}) do
    r.relics[idx] = true
  end
  local area = cat.levelAt(player:center())
  run.area = area or 0
  run.areaName = area and cat.areaName(area) or nil
  return run
end

-- Leaving the run (quit to title or desktop, closing the window): a living
-- hunter in the overworld is saved to be continued, anything else clears the saved run
local function keepRun()
  if not playing then
    return
  end
  if not (game.canSaveRun() and save.writeRun(save.activeSlot(), snapshotRun())) then
    save.clearRun(save.activeSlot())
  end
end

-- A saved run's inventory, rebuilt (bad entries are dropped, not fatal)
local function inventoryFrom(run)
  local r = run.inv
  local new = inventory.new() -- (binds perks and glyphs to itself)
  new.weapons = {}
  for i = 1, inventory.WEAPON_SLOTS do
    new.weapons[i] = gunFrom(r.weapons[i])
    if new.weapons[i] then
      counted[new.weapons[i]] = true -- (already in the compendium from the first time)
    end
  end
  new.items = {}
  for i = 1, inventory.ITEM_SLOTS do
    new.items[i] = itemFrom(r.items[i])
  end
  if type(r.fuse) == "table" then
    for i = 1, 2 do
      new.fuse.slots[i] = itemFrom(r.fuse.slots and r.fuse.slots[i])
    end
    new.fuse.locked = r.fuse.locked == true and new.fuse.slots[1] ~= nil and new.fuse.slots[2] ~= nil
    new.fuse.ether = tonumber(r.fuse.ether) or 0
  end
  for _, id in ipairs(r.perks or {}) do
    if perks.defs[id] then
      new.perks[#new.perks + 1] = id
      runPerks[id] = true
    end
  end
  perks.version = perks.version + 1
  for _, g in pairs(new.weapons) do
    g.chambers = math.min(g.chambers, g:maxChambers())
  end
  for id in pairs(r.glyphs or {}) do
    if require("src.glyphs").defs[id] then
      new.glyphs[id] = true
    end
  end
  for idx in pairs(r.relics or {}) do
    new.relics = new.relics or {}
    new.relics[idx] = true
  end
  new.gold = math.max(0, math.floor(tonumber(r.gold) or 0))
  new.dynamite = tonumber(r.dynamite) or 0
  new.flasks = tonumber(r.flasks) or 0
  new.keys = tonumber(r.keys) or 0
  new.secondWindUsed = r.secondWindUsed == true
  new.selected = math.max(1, math.min(inventory.weaponSlots(), math.floor(tonumber(r.selected) or 1)))
  -- (items the fuser holds, loose items and guns' attachments count too)
  for _, list in ipairs({ new.items, new.fuse.slots }) do
    for _, it in pairs(list) do
      counted[it] = true
    end
  end
  for _, g in pairs(new.weapons) do
    for _, it in pairs(g.slots) do
      counted[it] = true
    end
  end
  return new
end

-- Where the hunter stands again: his saved spot, or the nearest open ground to it
local function freeSpot(x, y)
  local Body = require("src.body")
  local cfg = config.player
  local function free(px, py)
    return not Body.terrainOverlaps(world, px, py, cfg.width, cfg.height)
  end
  if free(x, y) then
    return x, y
  end
  for dist = 2, 160, 2 do
    for _, d in ipairs({ { 0, -dist }, { -dist, 0 }, { dist, 0 }, { 0, dist }, { -dist, -dist }, { dist, -dist } }) do
      if free(x + d[1], y + d[2]) then
        return x + d[1], y + d[2]
      end
    end
  end
  return nil
end

-- Once the scene is built: the areas the hunter was in exist again, and he is
-- put back in them
local function placeHunter(run)
  local cat = require("src.scenes.catacombs")
  local x, y = math.floor(run.x), math.floor(run.y)
  local area = run.area and run.area > 0 and cat.levelAt(y + config.player.height / 2, x + config.player.width / 2) or nil
  if area then
    if area > 1 then
      cat.ensure(y, x) -- (with a "Building ..." screen if it takes a while)
    end
    cat.generate(area)
  end
  local px, py = freeSpot(x, y)
  if not px then
    local info = area and cat.info(area)
    px, py = info and info.spawnX or x, info and info.spawnY or y
  end
  local b = player.body
  b.x, b.y, b.vx, b.vy = px, py, 0, 0
  player.physBody:setPosition(b.x + b.w / 2, b.y + b.h / 2)
  player:refreshMaxHp()
  player.hp = math.max(1, math.min(player.maxHp, run.hp))
  camera.snap(player:center())
  hud.showBanner("Run Resumed", area and cat.areaName(area) or scene.title)
end

-- Starts a fresh run in the overworld
local function newRun()
  if playing then
    save.clearRun(save.activeSlot())
  end
  inv = inventory.new()
  runPerks, lastGold = {}, 0
  discoveries, deadTime, deathPhoto = {}, 0, nil
  audio.setRecap(false)
  if itembar.isOpen() then
    itembar.toggle()
  end
  game.enter("overworld")
  if playing then
    save.stat("runs")
    bounties.refresh()
    meta.beginRun()
    inv.flasks = meta.startFlasks()
    inv.dynamite = meta.startDynamite()
  end
end

local function note(thing, category, id)
  if thing and not counted[thing] then
    counted[thing] = true
    save.record(category, id)
  end
end

local seenTimer = 0

-- Logs what the run has collected into the profile (cheap: a few slots a frame)
local function track(area)
  if not save.profile() or not inv then
    return
  end
  for i = 1, inventory.WEAPON_SLOTS do
    local gun = inv.weapons[i]
    if gun then
      note(gun, "weapon", gun.id)
      for s = 1, gun.slotCount do
        local item = gun.slots[s]
        if item then
          note(item, item.kind, items.key(item.id, item.level))
        end
      end
    end
  end
  for i = 1, inventory.ITEM_SLOTS do
    local item = inv.items[i]
    if item then
      note(item, item.kind, items.key(item.id, item.level))
    end
  end
  for i = 1, 2 do
    local item = inv.fuse.slots[i]
    if item then
      note(item, item.kind, items.key(item.id, item.level))
    end
  end
  for _, id in ipairs(inv.perks) do
    if not runPerks[id] then
      runPerks[id] = true
      save.record("perk", id)
    end
  end
  if inv.gold > lastGold then
    save.stat("gold", inv.gold - lastGold)
  end
  lastGold = inv.gold
  if area then
    save.statMax("deepest", require("src.scenes.catacombs").rank(area))
    -- Marks for reaching an area for the first time
    if not meta.isSeen("area", area) then
      meta.see("area", area)
      meta.earn(meta.EARN.area, "area")
    end
  end
  -- Locked things lying near the hunter count as seen (goals for the Gunsmith)
  seenTimer = seenTimer - 1 / 60
  if seenTimer <= 0 and player and not player.dead then
    seenTimer = 0.25
    local px, py = player:center()
    for _, p in ipairs(pickups.all()) do
      if (p.item or p.gun) and math.abs(p.x - px) < 110 and math.abs(p.y - py) < 80 then
        if p.item and not meta.isUnlocked(p.item.kind, p.item.id) then
          meta.see(p.item.kind, p.item.id)
        elseif p.gun and not meta.isUnlocked("weapon", p.gun.id) then
          meta.see("weapon", p.gun.id)
        end
      end
    end
  end
  if player.dead and deathCounted ~= player then
    deathCounted = player
    save.clearRun(save.activeSlot()) -- (no saved run to go back to)
    meta.tithe(inv.gold) -- (the Miner's Tithe banks a share of what he carried)
    save.stat("deaths")
    meta.onDeath()
    save.flush()
  end
end

function game.load()
  audio.load()
  render.load()
  lighting.load()
  -- (Water reflections, fluids.reflector, are off: drawing every creature a
  -- second time cost too much frame time)
  settings.load()
  -- A first discovery pops up a note at the side of the screen
  save.onDiscover = function(category, id)
    if playing then
      toasts.discover(category, id, meta.EARN.discover)
      discoveries[#discoveries + 1] = { category, id }
      meta.earn(meta.EARN.discover, "discover")
    end
  end
  -- The rest of the profile's meta-progression (src.meta): unlock gating in
  -- the generators, marks shown as they are earned, the camp's people
  meta.install()
  meta.onEarn = function(amount, reason)
    if reason ~= "discover" then -- (a discovery's note already shows its mark)
      toasts.marks(amount, reason)
    end
  end
  events.onGhost = function()
    menu.open("ghost")
  end
  npcs.onTalk = function(id)
    menu.open(id == "board" and "board" or "camp", id)
  end
  -- Akimbo taken: the third weapon slot goes (its gun moves over, or drops)
  perks.onAdd = function(id)
    if id ~= "akimbo" or not inv then
      return
    end
    local spare = inv:foldThirdSlot()
    if spare and player then
      local px, py = player:center()
      pickups.dropWeapon(px + player.facing * 6, py, spare, player.facing * 70, -50)
    end
  end
  -- A freed prisoner's gift for this run (the Prospector: dynamite)
  npcs.onFreed = function(id)
    if id == "prospector" and inv then
      inv.dynamite = (inv.dynamite or 0) + 2
    elseif id == "apothecary" and inv then
      inv.flasks = (inv.flasks or 0) + 1
    end
  end
  -- The Prospector's strongbox, from his page
  menu.runGold = function()
    return inv and inv.gold or 0
  end
  menu.runPerks = function()
    return inv and inv.perks or {}
  end
  menu.canSaveRun = game.canSaveRun
  bounties.onNotice = function(title, label)
    toasts.notice(title, label)
  end
  -- An elite's death: its trophy and its marks
  enemies.onEliteKilled = function(e)
    meta.trophy(e.kind)
    meta.earn(meta.EARN.elite, enemies.eliteName(e))
    if e.bounty then
      bounties.claim(e)
    end
  end
  menu.onAction = function(action, arg)
    game.menuAction(action, arg)
  end
  love.mouse.setVisible(false)
  require("src.cursors").apply()
  inv = inventory.new()
  -- A replaced weapon drops at the hunter's feet
  compare.onChoose = function(index, newGun, pickup)
    local old = inv.weapons[index]
    inv.weapons[index] = newGun
    if pickup.shop then
      shop.take(pickup, inv) -- bought: pay now that a weapon to replace was chosen
    else
      pickups.remove(pickup)
    end
    local px, py = player:center()
    pickups.dropWeapon(px + player.facing * 6, py, old, player.facing * 70, -50)
    effects.weaponCard(px, py - 22, newGun)
  end
  -- The fuser's tooltip names a result only once the save file has found it
  itembar.isKnown = function(category, id)
    return save.count(category, id) > 0
  end
  -- The fuser's lock, from its button on the item bar
  itembar.onFuseToggle = function()
    if player and not player.dead then
      fuser.toggle(inv, player)
    end
  end
  -- With all weapon slots full, picking up a weapon asks which to replace
  pickups.onWeaponFull = function(p)
    compare.open(p.gun, p)
  end
  -- So do weapons dragged off the bar
  itembar.onDropWeapon = function(gun)
    local px, py = player:center()
    pickups.dropWeapon(px + player.facing * 6, py, gun, player.facing * 70, -50)
  end
  -- Items dragged out of the inventory land on the ground by the hunter's feet
  itembar.onDrop = function(item)
    local px, py = player:center()
    pickups.dropItem(px + player.facing * 6, py, item, player.facing * 70, -50)
  end
  -- Kills: heal, momentum and refills for the hunter, and Death Burst
  -- The way home from the shop after a boss: the trip costs most of the gold
  -- and of the max health (and can kill, if he has not healed up first)
  shop.onReturn = function(player)
    if not inv or not scene.toCamp then
      return
    end
    inv.gold = math.floor(inv.gold * (1 - shop.RETURN_GOLD) + 0.5)
    if player:drainHealth(math.ceil(player.maxHp * shop.RETURN_HEALTH), "portal") then
      scene.toCamp(player)
      camera.snap(player:center())
      audio.play("heal")
      local cx = player:center()
      effects.popup(cx, player.body.y - 14, "Home", { 0.7, 0.95, 1 })
    end
  end
  -- A flask or dynamite upgrade is handed over the moment it is bought
  meta.onBought = function(id)
    if inv and id == "flask" then
      inv.flasks = (inv.flasks or 0) + 1
    elseif inv and id == "blasting" then
      inv.dynamite = (inv.dynamite or 0) + 2
    end
  end
  enemies.onKill = function(e, fx)
    if player then
      player:onKill(e, fx)
    end
    -- Its ether charges a locked fuser
    if inv and not e.def.noEther then
      local b = e.body
      fuser.onKill(inv, b.x + b.w / 2, b.y + b.h / 2, e.def.boss and not (e.group and e.group.alive > 1))
    end
    -- Into the bestiary (a split Queen counts once, when the last of her falls)
    if not (e.group and e.group.alive > 1) then
      save.record("enemy", e.kind)
      if e.kind == "darkhunter" then
        save.record("enemy", "crowrider") -- (his second form falls with him)
      end
      save.stat("kills")
      if e.def.boss then
        save.stat("bosses")
        meta.earn(meta.EARN.boss, e.def.name or "boss")
      end
    else
      save.stat("kills")
    end
    if perks.has("death_burst") then
      local b = e.body
      local x, y = b.x + b.w / 2, b.y + b.h / 2
      effects.explosion(x, y, 22)
      audio.play("explosion", 0.6)
      enemies.damageArea(x, y, 22, 12, 180)
    end
  end
  load("overworld") -- the first world is built behind the title screen
  menu.open("title")
  audio.setMenu(true)
end

-- Carries out what a menu chose (src.menu calls this)
function game.menuAction(action, arg)
  if action == "play" then
    -- Into a run with the chosen save slot (the world behind the title is fresh)
    save.use(arg)
    save.clearRun(arg) -- (a new run replaces a saved one)
    settings.set("lastSlot", arg)
    playing = true
    save.stat("runs")
    runPerks, lastGold, deathCounted = {}, inv and inv.gold or 0, nil
    discoveries, deadTime, deathPhoto = {}, 0, nil
    menu.close()
    audio.setMenu(false)
    toasts.clear()
    -- The world was built behind the title before this profile was known: roll
    -- the shops and the starting revolver again from its unlocked pool
    shop.restock()
    bounties.refresh()
    meta.beginRun()
    if inv then
      inv.dynamite = meta.startDynamite()
      inv.flasks = meta.startFlasks()
    end
    if player then
      player:refreshMaxHp() -- (mounted trophies belong to the profile just chosen)
      player.hp = player.maxHp
    end
    if inv and inv.weapons[1] and not inv.weapons[2] then
      inv.weapons[1] = inventory.starterGun()
    end
    hud.showBanner(scene.title, scene.subtitle)
  elseif action == "continue" then
    -- Back into a saved run of slot arg: the world is rebuilt from its seed and the hunter put back
    local run = save.peekRun(arg)
    if not run then
      return
    end
    save.use(arg)
    settings.set("lastSlot", arg)
    playing = true
    runPerks, deathCounted = {}, nil
    discoveries, deadTime, deathPhoto = {}, 0, nil
    menu.close()
    audio.setMenu(false)
    audio.setRecap(false)
    toasts.clear()
    if itembar.isOpen() then
      itembar.toggle()
    end
    meta.beginRun()
    inv = inventoryFrom(run)
    lastGold = inv.gold
    save.clearRun(arg) -- (used up: the run is saved again by saving and quitting again)
    game.enter("overworld", { seed = math.floor(run.seed) })
    devQueue = function()
      placeHunter(run)
    end
  elseif action == "ghostbuy" then
    local ok, why = events.buy(arg, player)
    if not ok then
      local px, py = player:center()
      effects.popup(px, py - 14, why or "Can't pay that", { 0.9, 0.5, 0.5 })
      audio.play("deny")
    end
  elseif action == "refresh" then
    if player then
      player:refreshMaxHp() -- (a mounted trophy may have changed it)
    end
  elseif action == "deposit" then
    local put = meta.deposit(inv.gold)
    inv.gold = inv.gold - put
    lastGold = inv.gold -- (not earned again when it comes back out)
    save.flush()
  elseif action == "withdraw" then
    inv.gold = inv.gold + meta.withdraw()
    lastGold = inv.gold
  elseif action == "perkstore" then
    -- The perk leaves the run for the Prospector's shelf (its health and other effects go with it)
    if meta.shelvePerk(arg) then
      for i, id in ipairs(inv.perks) do
        if id == arg then
          table.remove(inv.perks, i)
          break
        end
      end
      perks.version = perks.version + 1
      if player then
        player:refreshMaxHp()
      end
    end
  elseif action == "perktake" then
    local id = meta.bankedPerk()
    if id and not perks.has(id) then
      meta.unshelvePerk()
      perks.add(id)
      if player then
        player:refreshMaxHp()
      end
    end
  elseif action == "resume" then
    menu.close()
  elseif action == "restart" then
    newRun()
    menu.close()
  elseif action == "title" then
    keepRun()
    save.flush()
    playing = false
    newRun()
    menu.open("title")
    audio.setMenu(true)
  elseif action == "quit" then
    keepRun()
    save.flush()
    love.event.quit()
  end
end

-- Typed text, for the name entry (main.lua passes love.textinput on)
function game.textinput(text)
  menu.textinput(text)
end

-- Saves on the way out (main.lua calls this from love.quit)
function game.quit()
  keepRun()
  save.flush()
end

-- The window lost focus: pause, if the setting says so
function game.focus(focused)
  if not focused and playing and not menu.isOpen() and settings.get("pauseOnFocusLoss") then
    menu.open("pause")
  end
end

local spaceTimer = 0

-- How roomy the place around (x, y) is: rays out in 12 directions, the
-- average distance to rock mapped to -1 (open air above ground) .. 0 (tight
-- tunnel) .. 1 (a big cavern)
function game.measureSpace(x, y, underground)
  local total = 0
  local n = 12
  for i = 0, n - 1 do
    local a = i / n * math.pi * 2
    local dx, dy = math.cos(a), math.sin(a)
    local d = 0
    while d < 240 and not world:isSolid(math.floor(x + dx * d), math.floor(y + dy * d)) do
      d = d + 8
    end
    total = total + d
  end
  local avg = total / n
  local roomy = math.max(0, math.min(1, (avg - 24) / 150))
  return roomy * underground - (1 - underground)
end

-- How long the last frame's own work took (update and draw, without the
-- background generation), so generation can have what is left of the frame
-- The frame the game aims for: about 80% of one refresh of the display with vsync on, or of 1/120 s
-- with it off (the rest is headroom for the GC, the driver and presenting), kept between 5.5 and 11 ms.
-- A fixed 11 ms let the generation fill every frame to 11 ms, which held a fast display to ~80 fps.
local FRAME_TARGET = 0.011
local targetCheck = 0
local function frameTarget(dt)
  targetCheck = targetCheck - dt
  if targetCheck > 0 then
    return FRAME_TARGET
  end
  targetCheck = 1 -- (the display or the vsync setting may change: looked at again every second)
  local refresh = 120
  if love.window.getVSync() ~= 0 then
    local _, _, mode = love.window.getMode()
    if mode and mode.refreshrate and mode.refreshrate > 0 then
      refresh = mode.refreshrate
    end
  end
  FRAME_TARGET = math.max(0.0055, math.min(0.011, 0.8 / refresh))
  return FRAME_TARGET
end
local frameT0, genSpent, lastWork = 0, 0, 0.008

function game.update(dt)
  audio.setHearing(meta.limbOn("ear") and 0.45 or 1)
  frameT0 = love.timer.getTime()
  genSpent = 0
  local target = frameTarget(dt)
  dt = math.min(dt, 1 / 30) -- avoid huge steps after hitches

  if pending then
    if pending.drawn then
      local p = pending
      pending = nil
      load(p.name, p.opts)
    end
    return
  end

  render.layout()
  local underground, area, inShop = 0, nil, false
  if scene.undergroundFactor and not menu.isOpen() then
    underground = scene.undergroundFactor(player:center())
    if scene.audioInfo then
      area, inShop = scene.audioInfo(player:center())
    end
  end
  -- Where the hunter is listening from, how big the space around him is
  -- (reverb) and how hard the monsters are pressing him (music tension)
  if playing and not menu.isFrontEnd() then
    local lx, ly = player:center()
    audio.setListener(lx, ly)
    spaceTimer = spaceTimer - dt
    if spaceTimer <= 0 then
      spaceTimer = 0.25
      audio.setSpace(game.measureSpace(lx, ly, underground))
      audio.setTension(enemies.threat(lx, ly) + (player.hurtFlash > 0.3 and 0.2 or 0))
    end
  end
  -- (with the weapon panel open the area's sound plays on, but muffled; under water too)
  local dlg = menu.state() == "dialog" and menu.dialogState()
  audio.setTable(dlg and dlg.music == "table")
  audio.update(dt, underground, menu.isOpen(), area, inShop, itembar.isOpen() or (playing and player.submerged))
  -- The weapon panel and the menus pause the game, like Noita's inventory
  love.mouse.setVisible(itembar.isOpen() or menu.isOpen() or compare.isOpen() or visuals.isOpen() or require("src.devpanel").isOpen())
  require("src.cursors").update() -- (tilts while the button is held)
  visuals.update()
  menu.update(dt)
  if menu.isFrontEnd() then
    menubg.update(dt)
  end
  save.update(dt, playing and not (itembar.isOpen() or menu.isOpen() or compare.isOpen()))
  toasts.update(dt)
  compare.update()
  if scene.background then
    -- (a bigger share of the frame goes to generating areas while nobody is playing)
    local px, py
    if player then
      px, py = player:center()
    end
    local g0 = love.timer.getTime()
    scene.background(menu.isOpen() or itembar.isOpen() or compare.isOpen(), px, py, target - lastWork)
    genSpent = love.timer.getTime() - g0
  end
  if playing then
    track(area)
    bounties.update(player, area)
    if not player.dead then
      surveymap.update(dt, player:center())
    end
    -- A death: once the hunter has finished falling, the recap
    if player.dead and not menu.isOpen() then
      if deathPhoto == nil then
        -- The picture for the wanted poster, taken as he falls
        local source = player.lastSource
        deathPhoto = enemies.defs[source] and enemies.photo(player.lastEnemy, source) or false
      end
      deadTime = deadTime + dt
      if deadTime >= RECAP_DELAY then
        local profile = save.profile()
        local recap = deaths.recap(profile and profile.name, player.lastSource)
        recap.discoveries = discoveries
        recap.photo = deathPhoto or nil
        recap.slot = save.activeSlot()
        toasts.clear()
        menu.open("recap", recap)
        audio.setRecap(true)
      end
    elseif not player.dead then
      deadTime, deathPhoto = 0, nil
    end
  end
  if itembar.isOpen() or menu.isOpen() or compare.isOpen() then
    restartHeld, restartFade = 0, 0
    return
  end

  -- Restarting the run takes the key held down for 2 s: after half a second
  -- the screen fades to black over the rest of it, and letting go brings it back
  if restartLatched and not input.down("restart") then
    restartLatched = false -- (let go of it after a restart before it counts again)
  end
  if playing and input.down("restart") and not restartLatched then
    restartHeld = restartHeld + dt
    restartFade = restartHeld > RESTART_FADE_AT and math.min(1, (restartHeld - RESTART_FADE_AT) / (RESTART_TIME - RESTART_FADE_AT)) or 0
    if restartHeld >= RESTART_TIME then
      restartHeld, restartFade = 0, 0
      restartLatched = true
      newRun()
      return
    end
  else
    restartHeld = 0
    restartFade = math.max(0, restartFade - dt * 4)
  end

  fade = math.max(0, fade - dt * 2)
  mouseVX, mouseVY = render.toVirtual(love.mouse.getPosition())
  local camX, camY = camera.baseOffset()
  local aimX, aimY = mouseVX + camX, mouseVY + camY

  -- A dead hunter stays where he fell until the run is restarted (R)
  if not player.dead then
    local ob = player.body
    local ox, oy = ob.x, ob.y
    player:update(dt, aimX, aimY)
    require("src.dev").flyStep(player, dt, ox, oy)
  end
  player:updateHurt(dt)
  player:syncPhysics(dt)
  enemies.syncPhysics(dt)
  props.snapshotVelocities()
  physics.update(dt, player:center())
  if not player.dead then
    player:ride(dt)
  end

  targets.update(dt)
  props.update(dt)
  chests.update(dt)
  shop.update(dt, player)
  npcs.update(dt, player)
  -- random events happen in ordinary areas only: never in a boss arena, a shop or the overworld
  local eventArea = playing and area or nil
  if eventArea then
    local ex, ey = player:center()
    local cat = require("src.scenes.catacombs")
    if inShop or cat.inArena(ex, ey) or cat.inShop(ex, ey) then
      eventArea = nil
    end
  end
  events.update(dt, player, eventArea)
  bullets.update(dt, world)
  enemies.update(dt, world, player)
  fog.update(dt, world, player, enemies.nearby(), bullets)
  pickups.update(dt, world, player)
  fuser.update(dt, world, player, inv)
  effects.update(dt, world)
  world:flushRepaints()
  world:refresh()
  hud.update(dt)

  if scene.update then
    scene.update(dt, player, game, effects)
  end
  do
    -- Air, creatures and weather
    local view = { x = camX, y = camY, w = config.VIRTUAL_W, h = config.VIRTUAL_H }
    local areaNow, shopNow = nil, false
    local under = 0
    if scene.undergroundFactor then
      under = scene.undergroundFactor(player:center())
      if scene.audioInfo then
        areaNow, shopNow = scene.audioInfo(player:center())
      end
    end
    if shopNow then
      areaNow = nil
    end
    ambience.update(dt, world, player, areaNow, under, view)
    critters.update(dt, world, player, areaNow, under, view)
    weather.update(dt, 1 - under)
  end

  local px, py = player:center()
  camera.update(dt, px, py, aimX, aimY)
  -- the terrain just outside the view, readied a little each frame
  world:prewarm(camX, camY, config.VIRTUAL_W, config.VIRTUAL_H)
end

local function drawLoading()
  love.graphics.clear(0, 0, 0)
  pending.drawn = true
end

-- The title screen: the black hole, with the menu over it
local MENU_FX = { aberr = 1.1, vig = 0.45, contrast = 0.34 }
local function drawFrontEnd()
  menubg.prepare()
  render.setMood(MENU_FX, 0, 0, 0)
  render.beginWorld()
  menubg.draw()
  menu.drawWorldLayer()
  render.endWorld()
  menu.draw(render.uiScale())
  love.graphics.setColor(1, 1, 1)
end

local drawFrame

function game.draw()
  drawFrame()
  lastWork = love.timer.getTime() - frameT0 - genSpent
end

drawFrame = function()
  if menu.isFrontEnd() then
    -- (a world being built behind the title doesn't blank the screen)
    if pending then
      pending.drawn = true
    end
    drawFrontEnd()
    return
  end
  if pending then
    drawLoading()
    return
  end
  local camX, camY = camera.offset()

  -- Light map for this frame (scene ambient + every light source)
  local view = { x = camX, y = camY, w = config.VIRTUAL_W, h = config.VIRTUAL_H }
  lighting.begin(scene.ambient)
  player:addLights(lighting)
  enemies.addLights(lighting, view)
  pickups.addLights(lighting, view)
  props.addLights(lighting, view)
  chests.addLights(lighting, view)
  shop.addLights(lighting, view)
  npcs.addLights(lighting, view)
  events.addLights(lighting, view)
  bullets.addLights(lighting)
  effects.addLights(lighting)
  fuser.addLights(lighting)
  critters.addLights(lighting, view)
  if scene.addLights then
    scene.addLights(lighting, camX, camY)
  end
  lighting.render(camX, camY, function()
    world:draw(camX, camY, config.VIRTUAL_W, config.VIRTUAL_H)
  end, function()
    -- Monsters block light a little, so they throw soft moving shadows (a
    -- light inside a monster's own body ignores that monster)
    love.graphics.setColor(1, 1, 1, 0.7)
    enemies.drawOccluders(view)
    if lighting.objectShadows then
      -- The things that stand in the world throw shadows too (their cached pieces drawn the plain way:
      -- a cached piece is blitted with its own blend mode, which would wipe the rock out of the mask).
      local baked = bake.enabled.minedecor
      bake.enabled.minedecor = false
      lighting.occluderScale(lighting.OBJECT_SHADOW)
      props.draw(view)
      chests.draw(view)
      npcs.draw(view, player)
      events.draw(view)
      targets.draw()
      if scene.drawLitDecor then
        scene.drawLitDecor(view, true) -- (without the mine's timber frames)
      end
      -- (the hunter as his body's box: his hat and gun stick out, and would shade his own light)
      if not player.dead then
        local b = player.body
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", b.x + 1, b.y + 1, math.max(1, b.w - 2), math.max(1, b.h - 2))
      end
      lighting.occluderScale(1)
      bake.enabled.minedecor = baked
      love.graphics.setColor(1, 1, 1, 1)
    end
  end)
  render.setLamps(lighting.lamps(camX, camY, 4))

  -- The look of the frame: the area's mood, bent by the hunter's health and hits
  local lowhp = player.dead and 0 or math.max(0, math.min(1, (0.4 - player.hp / player.maxHp) / 0.3))
  render.setMood(scene.fx, player.hurtFlash, lowhp, player.dead and math.min(1, deadTime / 2) or 0)
  if meta.limbOn("eye") then
    render.eyeBlur() -- (one eye gone: a heavy, smeared vignette)
  end
  render.beginWorld()
  if scene.drawBackground then
    scene.drawBackground(camX, camY)
  end
  love.graphics.push()
  love.graphics.translate(-camX, -camY)
  if scene.drawDecor then
    scene.drawDecor(camX, camY)
  end
  world:draw(camX, camY, config.VIRTUAL_W, config.VIRTUAL_H, lighting.terrainShader())
  targets.draw()
  props.draw(view)
  chests.draw(view)
  shop.draw(view)
  npcs.draw(view, player)
  events.draw(view)
  enemies.draw(view)
  player:draw()
  effects.drawWorld()
  critters.draw(view)
  if scene.drawFront then
    scene.drawFront(camX, camY)
  end
  love.graphics.pop()

  lighting.drawMotes(camX, camY)
  local worldEnts
  if lighting.litSprites then
    -- (the lit sprites test: what stands in the world is drawn once more, for its silhouette)
    worldEnts = lighting.entityMask(function()
      love.graphics.translate(-camX, -camY)
      props.draw(view)
      chests.draw(view)
      shop.draw(view)
      npcs.draw(view, player)
      events.draw(view)
      targets.draw()
      if scene.drawLitDecor then
        scene.drawLitDecor(view) -- (the scene's own things: the mine's shoring, carts and lamps, the story's props)
      end
      enemies.draw(view, true)
      player:draw()
    end)
  end
  lighting.apply(worldEnts)

  -- Emissive pass: glows that ignore the darkness
  love.graphics.push()
  love.graphics.translate(-camX, -camY)
  if scene.drawEmissive then
    scene.drawEmissive(camX, camY)
  end
  critters.drawEmissive(view)
  player:drawEmissive()
  enemies.drawEmissive(view)
  props.drawEmissive(view)
  pickups.drawEmissive(view)
  chests.drawEmissive(view)
  shop.drawEmissive(view)
  npcs.drawEmissive(view)
  events.drawEmissive(view)
  bullets.draw()
  effects.drawEmissive()
  fog.draw(view) -- (after every light and glow: it hides them all)
  fuser.drawEmissive()
  if showPhysics then
    physics.drawDebug()
  end
  love.graphics.pop()
  weather.drawScreen(love.timer.getDelta())
  -- A red flash when the hunter is hurt
  if player.hurtFlash > 0 then
    love.graphics.setColor(0.7, 0.05, 0.05, 0.28 * player.hurtFlash)
    love.graphics.rectangle("fill", 0, 0, config.VIRTUAL_W, config.VIRTUAL_H)
  end
  if fade > 0 then
    love.graphics.setColor(0, 0, 0, fade)
    love.graphics.rectangle("fill", 0, 0, config.VIRTUAL_W, config.VIRTUAL_H)
  end
  render.endWorld()

  -- The crosshair goes on after the finished frame, so the bloom can't make it glow
  if not itembar.isOpen() and not menu.isOpen() and not compare.isOpen() and not player.dead then
    local sx, sy = render.toScreen(mouseVX, mouseVY)
    love.graphics.push()
    love.graphics.translate(sx, sy)
    love.graphics.scale(render.scale, render.scale)
    hud.drawCrosshair(0, 0)
    love.graphics.pop()
  end

  -- Full-resolution overlays
  local function toScreen(x, y)
    return render.toScreen(x - camX, y - camY)
  end
  local font = hud.font(render.uiScale())
  if scene.drawScreen then
    scene.drawScreen(toScreen, font, player)
  end
  effects.drawScreen(toScreen, font)
  enemies.drawScreen(toScreen, font)
  if not shop.nearPedestal(player) then
    pickups.drawScreen(toScreen, font, player) -- (a pedestal's prompt takes the key, see game.keypressed)
  end
  chests.drawScreen(toScreen, font, player)
  shop.drawScreen(toScreen, font, player)
  npcs.drawScreen(toScreen, font, player)
  events.drawScreen(toScreen, font, player)
  -- Hovering the mouse over a weapon lying about, or on a shop pedestal, shows
  -- what it is before you take it
  if not (itembar.isOpen() or menu.isOpen() or compare.isOpen()) then
    local wx, wy = mouseVX + camX, mouseVY + camY
    local gun, gx, gy = pickups.weaponAt(wx, wy)
    if not gun then
      gun, gx, gy = shop.weaponAt(wx, wy)
    end
    if gun then
      local sx, sy = toScreen(gx, gy)
      effects.drawWeaponCard(sx, sy, gun, font)
    end
  end
  -- The title screen stands alone; a pause menu keeps the HUD but hides the
  -- area banner, which would show through it
  if menu.state() ~= "title" and menu.state() ~= "recap" then
    hud.hideBanner = menu.isOpen() or compare.isOpen()
    hud.draw(player, render.uiScale())
    itembar.draw(inv, render.uiScale())
  end
  -- Dying: once he has fallen, the world fades darker toward the recap (which
  -- picks up with the same darkness, the world still showing behind it)
  if playing and player.dead and not menu.isOpen() and deadTime > DEATH_FADE_START then
    local ww, wh = love.graphics.getDimensions()
    local k = math.min(1, (deadTime - DEATH_FADE_START) / (RECAP_DELAY - DEATH_FADE_START))
    love.graphics.setColor(0.05, 0.01, 0.02, 0.8 * k)
    love.graphics.rectangle("fill", 0, 0, ww, wh)
  end
  if restartFade > 0 then
    local ww, wh = love.graphics.getDimensions()
    love.graphics.setColor(0, 0, 0, restartFade)
    love.graphics.rectangle("fill", 0, 0, ww, wh)
  end
  compare.draw(inv, render.uiScale())
  visuals.draw(render.uiScale())
  devpanel.draw(render.uiScale())
  toasts.draw(render.uiScale())
  menu.draw(render.uiScale())
  love.graphics.setColor(1, 1, 1)
end

-- Returns true if the key was handled (main.lua uses this so Escape closes
-- the weapon panel or opens the pause menu instead of quitting)
function game.keypressed(key)
  if devpanel.isOpen() and devpanel.keypressed(key) then
    return true
  end
  if key == "f2" then
    if playing and not menu.isOpen() then
      require("src.dev").toggle()
    end
    return true
  end
  if key == "f4" and not menu.isOpen() then
    visuals.toggle()
    return true
  end
  if visuals.isOpen() then
    visuals.keypressed(key)
    return true
  end
  if key == "f11" then
    settings.set("fullscreen", not settings.get("fullscreen"))
    return true
  end
  if menu.isOpen() then
    menu.keypressed(key)
    return true -- a menu swallows every key
  end
  if pending then
    return false
  end
  if compare.isOpen() then
    compare.keypressed(key)
    return true -- and so does the compare prompt
  end
  if input.is("fuse", key) and not player.dead then
    fuser.toggle(inv, player)
    return true
  end
  if input.is("inventory", key) or (key == "escape" and itembar.isOpen()) then
    itembar.toggle()
    return true
  elseif key == "escape" then
    menu.open("pause")
    return true
  elseif input.is("weapon1", key) or input.is("weapon2", key) or input.is("weapon3", key) then
    inv:select(input.is("weapon1", key) and 1 or (input.is("weapon2", key) and 2 or 3))
    return true
  end
  if itembar.isOpen() then
    return false -- everything else waits until the panel is closed
  end
  if input.is("jump", key) and not player.dead then
    player:pressJump()
  elseif input.is("kick", key) and not player.dead then
    player:kick()
  elseif input.is("map", key) and not player.dead then
    if meta.tier("survey") > 0 then
      menu.open("map")
    else
      local px, py = player:center()
      effects.popup(px, py - 14, "No survey map", { 0.8, 0.8, 0.85 })
    end
  elseif input.is("heal", key) and not player.dead then
    if (inv.flasks or 0) > 0 and player.hp < player.maxHp then
      inv.flasks = inv.flasks - 1
      player:heal(math.ceil(player.maxHp * 0.35))
      audio.play("buy")
      local px, py = player:center()
      effects.popup(px, py - 14, "Flask", { 0.6, 1, 0.7 })
      for _ = 1, 8 do
        effects.particle(px + (love.math.random() - 0.5) * 6, py, (love.math.random() - 0.5) * 30, -20 - love.math.random() * 40, 0.6, { 0.6, 1, 0.7 }, -20, true)
      end
    elseif (inv.flasks or 0) <= 0 then
      local px, py = player:center()
      effects.popup(px, py - 14, "No flasks", { 0.8, 0.8, 0.85 })
    end
  elseif input.is("throw", key) and not player.dead then
    if (inv.dynamite or 0) > 0 then
      inv.dynamite = inv.dynamite - 1
      local mx, my = render.toVirtual(love.mouse.getPosition())
      local camX, camY = camera.baseOffset()
      local sx, sy = player:shoulder()
      enemies.throwStick(sx, sy, mx + camX, my + camY)
    else
      local px, py = player:center()
      effects.popup(px, py - 14, "No dynamite", { 0.8, 0.8, 0.85 })
      audio.play("deny")
    end
  elseif input.is("roll", key) and not player.dead then
    player:pressRoll()
  elseif input.is("interact", key) and not player.dead then
    if not npcs.interact(player) and not events.interact(player) and not (scene.interact and scene.interact(player)) and not chests.interact(player) and not shop.interact(player) then
      pickups.interact(player)
    end
  elseif key == "f6" and not player.dead then
    -- Debug: swaps the held weapon for a randomly generated one
    local gun = guns.generate()
    inv.weapons[inv.selected] = gun
    local px, py = player:center()
    effects.weaponCard(px, py - 22, gun)
  elseif input.is("restart", key) then
    -- (held, not pressed: see game.update)
  elseif key == "f9" then
    game.enter("testroom")
  elseif key == "f10" then
    game.enter("overworld", { atCave = true }) -- a fresh world, starting at the catacombs' entrance
  elseif key == "f8" and scene.toArena and not player.dead then
    -- Testing: straight to the Sulfur Queen's arena
    scene.toArena(player)
    camera.snap(player:center())
  else
    return false
  end
  return true
end

function game.mousepressed(x, y, button)
  if devpanel.isOpen() and devpanel.mousepressed(x, y, button, game) then
    return
  end
  if visuals.isOpen() then
    visuals.mousepressed(x, y, button)
    return
  end
  if menu.isOpen() then
    menu.mousepressed(x, y, button)
    return
  end
  if compare.isOpen() then
    return
  end
  if itembar.mousepressed(inv, x, y, button) or pending or itembar.isOpen() then
    return
  end
  if button == 2 and inv:selectedGun() then
    local started = inv:selectedGun():reload()
    if inv:offhandGun() and inv:offhandGun():reload() then
      started = true -- (Akimbo: both guns reload together)
    end
    if started then
      audio.play("reload")
    end
  end
end

function game.mousereleased(x, y, button)
  if visuals.isOpen() then
    visuals.mousereleased()
    return
  end
  if menu.isOpen() then
    menu.mousereleased(x, y, button)
    return
  end
  if compare.isOpen() then
    compare.mousereleased(x, y, button)
    return
  end
  itembar.mousereleased(inv, x, y, button)
end

function game.wheelmoved(dx, dy)
  if devpanel.isOpen() and devpanel.wheelmoved(dy) then
    return
  end
  if menu.isOpen() then
    menu.wheelmoved(dx, dy)
    return
  end
  if dy ~= 0 and not itembar.isOpen() and not menu.isOpen() and not compare.isOpen() then
    inv:cycle(dy > 0 and -1 or 1)
  end
end

-- For tests and future pickups
function game.inventory()
  return inv
end

function game.player()
  return player
end

-- What the survey map marks on its second tier: { x, y, color, always }
function game.mapMarks()
  local out = {}
  local cat = require("src.scenes.catacombs")
  for i = 1, cat.count() do
    local info = cat.info(i)
    if info then
      for _, room in ipairs(info.shops or {}) do
        out[#out + 1] = { x = room.x + room.w / 2, y = room.y + room.h / 2, color = { 0.4, 0.9, 1 } }
      end
      for _, c in ipairs(info.chests or {}) do
        out[#out + 1] = { x = c[1], y = c[2], color = { 1, 0.85, 0.3 } }
      end
    end
  end
  for _, b in ipairs(bounties.list()) do
    local e = b.taken and bounties.placed(b.id)
    if e and not e.dead then
      out[#out + 1] = { x = e.body.x, y = e.body.y, color = { 1, 0.3, 0.25 }, always = true }
    end
  end
  return out
end

return game
